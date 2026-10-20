// Package dl is a segmented, resumable HTTP downloader.
//
// Each connection writes straight into a preallocated file with WriteAt (no
// chunk merging), idle connections steal half of the largest remaining
// segment, progress is checkpointed for resume, and signed URLs are
// refreshed on 401/403/410. Every worker has its own connection pool, and
// a connection that stalls (well below a sane rate for a while) is dropped
// and redialled: long-lived HTTP/2 connections to the Look video server have
// been seen to degrade to a few KB/s while fresh ones run at full speed.
package dl

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/time/rate"
)

type Options struct {
	MaxConns  int   // per file
	MinChunk  int64 // smallest segment worth a connection
	Retries   int
	RateLimit int64 // bytes/sec across the engine, 0 = unlimited

	// A request receiving less than StallRate bytes/sec over StallWindow is
	// abandoned and retried on a fresh connection.
	StallWindow time.Duration
	StallRate   int64
}

type Engine struct {
	hc      *http.Client
	base    *http.Transport // cloned per worker for private connections
	opt     Options
	limiter atomic.Pointer[rate.Limiter]
	bufs    sync.Pool
}

func New(rt http.RoundTripper, opt Options) *Engine {
	if opt.MaxConns <= 0 {
		opt.MaxConns = 8
	}
	if opt.MinChunk <= 0 {
		opt.MinChunk = 2 << 20
	}
	if opt.Retries <= 0 {
		opt.Retries = 6
	}
	if opt.StallWindow <= 0 {
		opt.StallWindow = 15 * time.Second
	}
	if opt.StallRate <= 0 {
		opt.StallRate = 128 << 10
	}
	e := &Engine{hc: &http.Client{Transport: rt}, opt: opt}
	if t, ok := rt.(*http.Transport); ok {
		e.base = t
	}
	e.bufs.New = func() any { b := make([]byte, 256<<10); return &b }
	e.SetRateLimit(opt.RateLimit)
	return e
}

// SetRateLimit changes the shared bandwidth cap at runtime (0 = unlimited).
func (e *Engine) SetRateLimit(bps int64) {
	if bps <= 0 {
		e.limiter.Store(nil)
		return
	}
	e.limiter.Store(rate.NewLimiter(rate.Limit(bps), int(max(bps/4, 256<<10))))
}

// workerClient returns a client with its own connection pool (when the
// engine was built on an *http.Transport) and a func that closes it.
func (e *Engine) workerClient() (*http.Client, func()) {
	if e.base == nil {
		return e.hc, func() {}
	}
	t := e.base.Clone()
	t.ResponseHeaderTimeout = e.opt.StallWindow
	return &http.Client{Transport: t}, t.CloseIdleConnections
}

var errStalled = errors.New("connection stalled")

// watch cancels a request whose throughput over the stall window falls below
// the floor. The floor is relaxed while a user speed limit is in force.
func (e *Engine) watch(ctx context.Context, cancel context.CancelCauseFunc, got *atomic.Int64) {
	step := e.opt.StallWindow / 3
	t := time.NewTicker(step)
	defer t.Stop()
	hist := []int64{0}
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			hist = append(hist, got.Load())
			if len(hist) < 4 {
				continue
			}
			floor := e.opt.StallRate
			if e.limiter.Load() != nil {
				floor = min(floor, 16<<10)
			}
			if need := int64(float64(floor) * (3 * step).Seconds()); hist[len(hist)-1]-hist[len(hist)-4] < need {
				cancel(errStalled)
				return
			}
			hist = hist[len(hist)-3:]
		}
	}
}

func (e *Engine) SetMaxConns(n int) {
	if n > 0 && n <= 32 {
		e.opt.MaxConns = n
	}
}

type Request struct {
	URL    string
	Header http.Header
	Dest   string
	// Refresh returns a freshly signed URL when the old one is rejected.
	Refresh func(ctx context.Context) (string, error)
}

type Progress struct {
	Done  int64 `json:"done"`
	Total int64 `json:"total"`
	Speed int64 `json:"speed"`
	Conns int   `json:"conns"`
}

type segment struct {
	Start int64 `json:"start"`
	End   int64 `json:"end"` // inclusive
	Pos   int64 `json:"pos"` // next byte to write
}

type state struct {
	Total     int64      `json:"total"`
	Validator string     `json:"validator"`
	Segments  []*segment `json:"segments"`
}

type job struct {
	e      *Engine
	req    Request
	mu     sync.Mutex
	url    string
	urlGen int
	f      *os.File
	st     state
	owned  map[*segment]bool
	done   atomic.Int64
	active atomic.Int32
}

var errStatus = errors.New("bad status")

type statusErr struct{ code int }

func (s statusErr) Error() string { return "HTTP " + strconv.Itoa(s.code) }
func (s statusErr) Unwrap() error { return errStatus }

// Fetch downloads req.URL to req.Dest, resuming an earlier partial download.
func (e *Engine) Fetch(ctx context.Context, req Request, onProgress func(Progress)) error {
	if fi, err := os.Stat(req.Dest); err == nil && fi.Size() > 0 {
		if _, err := os.Stat(req.Dest + ".part.json"); errors.Is(err, os.ErrNotExist) {
			if onProgress != nil {
				onProgress(Progress{Done: fi.Size(), Total: fi.Size()})
			}
			return nil
		}
	}
	if err := os.MkdirAll(filepath.Dir(req.Dest), 0o755); err != nil {
		return err
	}
	j := &job{e: e, req: req, url: req.URL, owned: map[*segment]bool{}}
	total, validator, ranged, err := j.probe(ctx)
	if err != nil {
		return err
	}
	if !ranged || total <= 0 {
		return j.single(ctx, onProgress)
	}
	part := req.Dest + ".part"
	j.st = state{Total: total, Validator: validator}
	if b, err := os.ReadFile(part + ".json"); err == nil {
		var old state
		if json.Unmarshal(b, &old) == nil && old.Total == total && old.Validator == validator && len(old.Segments) > 0 {
			j.st = old
		}
	}
	if len(j.st.Segments) == 0 {
		n := int(min(int64(e.opt.MaxConns), max(1, total/e.opt.MinChunk)))
		size := total / int64(n)
		for i := 0; i < n; i++ {
			s := &segment{Start: int64(i) * size, End: int64(i+1)*size - 1}
			if i == n-1 {
				s.End = total - 1
			}
			s.Pos = s.Start
			j.st.Segments = append(j.st.Segments, s)
		}
	}
	f, err := os.OpenFile(part, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	j.f = f
	if fi, _ := f.Stat(); fi.Size() != total {
		if err := f.Truncate(total); err != nil {
			f.Close()
			return err
		}
	}
	var done int64
	for _, s := range j.st.Segments {
		done += s.Pos - s.Start
	}
	j.done.Store(done)

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	tickDone := make(chan struct{})
	go j.ticker(ctx, onProgress, tickDone)

	var wg sync.WaitGroup
	errc := make(chan error, e.opt.MaxConns+len(j.st.Segments))
	for i := 0; i < e.opt.MaxConns; i++ {
		seg := j.claim()
		if seg == nil {
			break
		}
		wg.Add(1)
		go func(seg *segment) {
			defer wg.Done()
			if err := j.worker(ctx, seg); err != nil {
				errc <- err
				cancel()
			}
		}(seg)
	}
	wg.Wait()
	cancel()
	<-tickDone
	j.checkpoint()
	close(errc)
	ferr := <-errc
	syncErr := f.Sync()
	f.Close()
	if ferr == nil && ctx.Err() != nil && j.remaining() > 0 {
		ferr = context.Canceled
	}
	if ferr != nil {
		return ferr
	}
	if j.remaining() > 0 {
		return fmt.Errorf("incomplete download: %d bytes missing", j.remaining())
	}
	if syncErr != nil {
		return syncErr
	}
	if err := os.Rename(part, req.Dest); err != nil {
		return err
	}
	os.Remove(part + ".json")
	if onProgress != nil {
		onProgress(Progress{Done: total, Total: total})
	}
	return nil
}

func (j *job) remaining() int64 {
	j.mu.Lock()
	defer j.mu.Unlock()
	var r int64
	for _, s := range j.st.Segments {
		if s.End >= s.Pos {
			r += s.End - s.Pos + 1
		}
	}
	return r
}

func (j *job) claim() *segment {
	j.mu.Lock()
	defer j.mu.Unlock()
	for _, s := range j.st.Segments {
		if s.Pos <= s.End && !j.isOwned(s) {
			j.own(s)
			return s
		}
	}
	return j.stealLocked()
}

// isOwned/own require j.mu; owned tracks segments that have a worker.
func (j *job) isOwned(s *segment) bool { return j.owned[s] }
func (j *job) own(s *segment)          { j.owned[s] = true }
func (j *job) release(s *segment) {
	j.mu.Lock()
	delete(j.owned, s)
	j.mu.Unlock()
}

// stealLocked splits the largest in-flight segment and returns its tail.
func (j *job) stealLocked() *segment {
	var best *segment
	var bestRem int64
	for _, s := range j.st.Segments {
		if rem := s.End - s.Pos + 1; rem > bestRem {
			best, bestRem = s, rem
		}
	}
	if best == nil || bestRem < 1<<20 {
		return nil
	}
	mid := best.Pos + bestRem/2
	tail := &segment{Start: mid, End: best.End, Pos: mid}
	best.End = mid - 1
	j.st.Segments = append(j.st.Segments, tail)
	j.own(tail)
	return tail
}

func (j *job) segEnd(s *segment) int64 {
	j.mu.Lock()
	defer j.mu.Unlock()
	return s.End
}

// wconn is a worker's private client; redial replaces a stalled connection.
type wconn struct {
	e     *Engine
	hc    *http.Client
	close func()
}

func (w *wconn) redial() {
	w.close()
	w.hc, w.close = w.e.workerClient()
}

func (j *job) worker(ctx context.Context, seg *segment) error {
	j.active.Add(1)
	defer j.active.Add(-1)
	w := &wconn{e: j.e}
	w.hc, w.close = j.e.workerClient()
	defer func() { w.close() }()
	for seg != nil {
		if err := j.runSegment(ctx, seg, w); err != nil {
			j.release(seg)
			return err
		}
		j.release(seg)
		seg = j.claim()
	}
	return nil
}

func (j *job) runSegment(ctx context.Context, seg *segment, w *wconn) error {
	attempt, stalls := 0, 0
	for {
		j.mu.Lock()
		pos, end := seg.Pos, seg.End
		j.mu.Unlock()
		if pos > end {
			return nil
		}
		err := j.stream(ctx, w.hc, seg, pos, end)
		if err == nil {
			continue
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		// A stall is the connection's fault, not the request's: redial and
		// carry on without using up a retry (bounded to avoid spinning).
		if errors.Is(err, errStalled) && stalls < 30 {
			stalls++
			w.redial()
			continue
		}
		attempt++
		if attempt > j.e.opt.Retries {
			return err
		}
		var se statusErr
		if errors.As(err, &se) && (se.code == 401 || se.code == 403 || se.code == 410) {
			if rerr := j.refresh(ctx); rerr != nil {
				return fmt.Errorf("%w (refresh: %v)", err, rerr)
			}
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(attempt*attempt) * 400 * time.Millisecond):
		}
	}
}

func (j *job) currentURL() (string, int) {
	j.mu.Lock()
	defer j.mu.Unlock()
	return j.url, j.urlGen
}

func (j *job) refresh(ctx context.Context) error {
	if j.req.Refresh == nil {
		return errors.New("no refresher")
	}
	_, gen := j.currentURL()
	u, err := j.req.Refresh(ctx)
	if err != nil {
		return err
	}
	j.mu.Lock()
	if j.urlGen == gen {
		j.url = u
		j.urlGen++
	}
	j.mu.Unlock()
	return nil
}

func (j *job) newReq(ctx context.Context, u string) (*http.Request, error) {
	r, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	for k, vs := range j.req.Header {
		for _, v := range vs {
			r.Header.Add(k, v)
		}
	}
	return r, nil
}

func (j *job) stream(ctx context.Context, hc *http.Client, seg *segment, pos, end int64) (err error) {
	u, _ := j.currentURL()
	rctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	defer func() {
		if err != nil && errors.Is(context.Cause(rctx), errStalled) && ctx.Err() == nil {
			err = errStalled
		}
	}()
	r, err := j.newReq(rctx, u)
	if err != nil {
		return err
	}
	r.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", pos, end))
	var got atomic.Int64
	go j.e.watch(rctx, cancel, &got)
	resp, err := hc.Do(r)
	if err != nil {
		var ne interface{ Timeout() bool }
		if errors.As(err, &ne) && ne.Timeout() && ctx.Err() == nil {
			return errStalled // no response headers within the stall window
		}
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		return statusErr{resp.StatusCode}
	}
	bp := j.e.bufs.Get().(*[]byte)
	defer j.e.bufs.Put(bp)
	buf := *bp
	for {
		n, rerr := resp.Body.Read(buf)
		got.Add(int64(n))
		if n > 0 {
			if lim := j.e.limiter.Load(); lim != nil {
				if err := lim.WaitN(ctx, min(n, lim.Burst())); err != nil {
					return err
				}
			}
			curEnd := j.segEnd(seg)
			w := int64(n)
			if pos+w-1 > curEnd {
				w = curEnd - pos + 1
			}
			if w > 0 {
				if _, err := j.f.WriteAt(buf[:w], pos); err != nil {
					return err
				}
				pos += w
				j.mu.Lock()
				seg.Pos = pos
				j.mu.Unlock()
				j.done.Add(w)
			}
			if pos > curEnd {
				return nil // segment finished (possibly shortened by a steal)
			}
		}
		if rerr == io.EOF {
			if pos <= j.segEnd(seg) {
				return io.ErrUnexpectedEOF
			}
			return nil
		}
		if rerr != nil {
			return rerr
		}
	}
}

func (j *job) probe(ctx context.Context) (total int64, validator string, ranged bool, err error) {
	for attempt := 0; attempt < 3; attempt++ {
		u, _ := j.currentURL()
		r, e := j.newReq(ctx, u)
		if e != nil {
			return 0, "", false, e
		}
		r.Header.Set("Range", "bytes=0-0")
		resp, e := j.e.hc.Do(r)
		if e != nil {
			err = e
			continue
		}
		io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
		resp.Body.Close()
		validator = resp.Header.Get("ETag") + "|" + resp.Header.Get("Last-Modified")
		switch resp.StatusCode {
		case http.StatusPartialContent:
			cr := resp.Header.Get("Content-Range") // bytes 0-0/12345
			if i := strings.LastIndexByte(cr, '/'); i >= 0 {
				total, _ = strconv.ParseInt(cr[i+1:], 10, 64)
			}
			return total, validator, total > 0, nil
		case http.StatusOK:
			return resp.ContentLength, validator, false, nil
		case 401, 403, 410:
			err = statusErr{resp.StatusCode}
			if rerr := j.refresh(ctx); rerr != nil {
				return 0, "", false, err
			}
		default:
			return 0, "", false, statusErr{resp.StatusCode}
		}
	}
	return 0, "", false, err
}

// single downloads without ranges (no resume).
func (j *job) single(ctx context.Context, onProgress func(Progress)) error {
	u, _ := j.currentURL()
	r, err := j.newReq(ctx, u)
	if err != nil {
		return err
	}
	resp, err := j.e.hc.Do(r)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return statusErr{resp.StatusCode}
	}
	part := j.req.Dest + ".part"
	f, err := os.Create(part)
	if err != nil {
		return err
	}
	j.f = f
	j.st.Total = resp.ContentLength
	ctx, cancel := context.WithCancel(ctx)
	tickDone := make(chan struct{})
	j.active.Store(1)
	go j.ticker(ctx, onProgress, tickDone)
	bp := j.e.bufs.Get().(*[]byte)
	_, err = io.CopyBuffer(writerFunc(func(p []byte) (int, error) {
		if lim := j.e.limiter.Load(); lim != nil {
			if err := lim.WaitN(ctx, min(len(p), lim.Burst())); err != nil {
				return 0, err
			}
		}
		n, err := f.Write(p)
		j.done.Add(int64(n))
		return n, err
	}), resp.Body, *bp)
	j.e.bufs.Put(bp)
	cancel()
	<-tickDone
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(part)
		return err
	}
	return os.Rename(part, j.req.Dest)
}

type writerFunc func([]byte) (int, error)

func (w writerFunc) Write(p []byte) (int, error) { return w(p) }

func (j *job) checkpoint() {
	if j.st.Segments == nil {
		return
	}
	j.mu.Lock()
	b, _ := json.Marshal(j.st)
	j.mu.Unlock()
	p := j.req.Dest + ".part.json"
	if os.WriteFile(p+".tmp", b, 0o644) == nil {
		os.Rename(p+".tmp", p)
	}
}

func (j *job) ticker(ctx context.Context, onProgress func(Progress), done chan struct{}) {
	defer close(done)
	t := time.NewTicker(250 * time.Millisecond)
	defer t.Stop()
	last, lastT := j.done.Load(), time.Now()
	var speed float64
	ticks := 0
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-t.C:
			cur := j.done.Load()
			inst := float64(cur-last) / now.Sub(lastT).Seconds()
			if speed == 0 {
				speed = inst
			} else {
				speed = 0.7*speed + 0.3*inst
			}
			last, lastT = cur, now
			if onProgress != nil {
				onProgress(Progress{Done: cur, Total: j.st.Total, Speed: int64(speed), Conns: int(j.active.Load())})
			}
			if ticks++; ticks%4 == 0 {
				j.checkpoint()
			}
		}
	}
}

// FetchSmall downloads a small file in one request with retries. It skips
// files that already exist.
func (e *Engine) FetchSmall(ctx context.Context, u string, h http.Header, dest string) (int64, error) {
	if fi, err := os.Stat(dest); err == nil && fi.Size() > 0 {
		return fi.Size(), nil
	}
	var last error
	for attempt := 0; attempt < e.opt.Retries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return 0, ctx.Err()
			case <-time.After(time.Duration(attempt) * 300 * time.Millisecond):
			}
		}
		r, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return 0, err
		}
		for k, vs := range h {
			r.Header[k] = vs
		}
		resp, err := e.hc.Do(r)
		if err != nil {
			last = err
			continue
		}
		if resp.StatusCode != 200 {
			resp.Body.Close()
			last = statusErr{resp.StatusCode}
			if resp.StatusCode == 404 {
				return 0, last
			}
			continue
		}
		os.MkdirAll(filepath.Dir(dest), 0o755)
		tmp := dest + ".part"
		f, err := os.Create(tmp)
		if err != nil {
			resp.Body.Close()
			return 0, err
		}
		bp := e.bufs.Get().(*[]byte)
		n, err := io.CopyBuffer(f, resp.Body, *bp)
		e.bufs.Put(bp)
		resp.Body.Close()
		if cerr := f.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			os.Remove(tmp)
			last = err
			continue
		}
		return n, os.Rename(tmp, dest)
	}
	return 0, last
}

// Status returns the HTTP status behind a download error, or 0.
func Status(err error) int {
	var s statusErr
	if errors.As(err, &s) {
		return s.code
	}
	return 0
}

// Stalled reports whether err is a connection that stopped delivering data.
func Stalled(err error) bool { return errors.Is(err, errStalled) }
