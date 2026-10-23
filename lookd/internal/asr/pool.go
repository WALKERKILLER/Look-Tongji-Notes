package asr

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Engine is one transcription channel: a free cloud service or a local model.
type Engine interface {
	Transcribe(ctx context.Context, audio string, onStage Stage) ([]Utterance, error)
}

const (
	quotaWindow = 12 * time.Hour
	quotaAudio  = 6 * time.Hour // courtesy cap per channel, as VideoCaptioner does
	chunkSec    = 1200          // 20 min: few enough requests to stay under rate limits
	overlapSec  = 15
	// starveLimit fails a transcription when no channel could take a chunk
	// for this long (all cooling, disabled or over quota).
	starveLimit = 20 * time.Minute
	maxEvents   = 40
)

// PoolConfig is the user-facing transcription setup.
type PoolConfig struct {
	Disabled    []string `json:"disabled"`
	Strategy    string   `json:"strategy"` // "balance" or a channel id to prefer
	Concurrency int      `json:"concurrency"`
}

type use struct {
	At   int64   `json:"at"`
	Secs float64 `json:"secs"`
}

// Event is one chunk attempt, kept for diagnosis.
type Event struct {
	At      int64   `json:"at"`
	Channel string  `json:"channel"`
	Chunk   string  `json:"chunk"` // "3/5"
	Secs    float64 `json:"secs"`
	Took    float64 `json:"took"`
	OK      bool    `json:"ok"`
	Error   string  `json:"error,omitempty"`
}

type channel struct {
	id, name, note string
	eng            Engine
	slots          int  // chunks in flight at most
	local          bool // runs on this machine: no quota, audio never leaves

	inflight  int
	coolUntil time.Time
	backoff   time.Duration
	OK        int    `json:"ok"`
	Fail      int    `json:"fail"`
	LastErr   string `json:"last_error"`
	LastUsed  int64  `json:"last_used"`
	Usage     []use  `json:"usage"`
}

// LocalID is the channel id of the on-device recogniser.
const LocalID = "local"

// ChannelStatus is what the UI shows per channel.
type ChannelStatus struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Note      string  `json:"note"`
	Local     bool    `json:"local"`
	Enabled   bool    `json:"enabled"`
	State     string  `json:"state"` // ready | busy | cooling | quota | disabled
	Busy      int     `json:"busy"`
	Slots     int     `json:"slots"`
	CoolUntil int64   `json:"cool_until,omitempty"`
	UsedSecs  float64 `json:"used_secs"`
	QuotaSecs float64 `json:"quota_secs"`
	OK        int     `json:"ok"`
	Fail      int     `json:"fail"`
	LastError string  `json:"last_error,omitempty"`
	LastUsed  int64   `json:"last_used,omitempty"`
}

type cached struct {
	at time.Time
	us []Utterance
	by string
}

// Pool spreads transcription over the free channels: long audio is cut into
// overlapping chunks, each chunk goes to a healthy channel with a free slot,
// and a failing channel cools down while others take over. Finished chunks
// are remembered, so a retried job only redoes what is missing.
type Pool struct {
	mu     sync.Mutex
	wake   chan struct{}
	chans  []*channel
	cfg    PoolConfig
	state  string
	cache  map[string]cached
	events []Event
	saved  map[string]*channel // persisted counters, for channels added later
}

func NewPool(statePath string) *Pool {
	p := newPool(statePath, []*channel{
		{id: "bcut", name: "必剪", slots: 2, note: "哔哩哔哩必剪的免费云端识别", eng: New(nil)},
		{id: "jianying", name: "剪映", slots: 1, note: "字节跳动剪映的免费云端识别；请求签名由 VideoCaptioner 的公共服务提供（只发送接口路径与时间戳，不含音频）", eng: NewJianYing(nil)},
	})
	p.load()
	return p
}

func newPool(statePath string, chans []*channel) *Pool {
	return &Pool{wake: make(chan struct{}), state: statePath, chans: chans, cache: map[string]cached{},
		cfg: PoolConfig{Strategy: "balance", Concurrency: 2}}
}

func (p *Pool) SetConfig(c PoolConfig) {
	if c.Concurrency <= 0 || c.Concurrency > 6 {
		c.Concurrency = 2
	}
	if c.Strategy == "" {
		c.Strategy = "balance"
	}
	p.mu.Lock()
	p.cfg = c
	p.mu.Unlock()
	p.signal()
}

// SetLocal adds, replaces or (with a nil engine) removes the local channel.
func (p *Pool) SetLocal(name, note string, eng Engine) {
	p.mu.Lock()
	idx := -1
	for i, c := range p.chans {
		if c.id == LocalID {
			idx = i
		}
	}
	switch {
	case eng == nil && idx >= 0:
		p.chans = append(p.chans[:idx:idx], p.chans[idx+1:]...)
	case eng != nil && idx >= 0:
		c := p.chans[idx]
		c.name, c.note, c.eng = name, note, eng
	case eng != nil:
		c := &channel{id: LocalID, name: name, note: note, eng: eng, slots: 1, local: true}
		if s := p.saved[LocalID]; s != nil {
			c.OK, c.Fail, c.LastErr, c.LastUsed = s.OK, s.Fail, s.LastErr, s.LastUsed
		}
		p.chans = append([]*channel{c}, p.chans...)
	}
	p.mu.Unlock()
	p.signal()
}

// TakeLocal removes the local channel unless it is transcribing, and
// reports whether the local models are now unused.
func (p *Pool) TakeLocal() bool {
	p.mu.Lock()
	for i, c := range p.chans {
		if c.id == LocalID {
			if c.inflight > 0 {
				p.mu.Unlock()
				return false
			}
			p.chans = append(p.chans[:i:i], p.chans[i+1:]...)
			break
		}
	}
	p.mu.Unlock()
	p.signal()
	return true
}

func (p *Pool) signal() {
	p.mu.Lock()
	close(p.wake)
	p.wake = make(chan struct{})
	p.mu.Unlock()
}

func (p *Pool) enabledLocked(c *channel) bool {
	for _, d := range p.cfg.Disabled {
		if d == c.id {
			return false
		}
	}
	return true
}

func (c *channel) usedLocked(now time.Time) float64 {
	var s float64
	keep := c.Usage[:0]
	for _, u := range c.Usage {
		if now.Sub(time.Unix(u.At, 0)) < quotaWindow {
			keep = append(keep, u)
			s += u.Secs
		}
	}
	c.Usage = keep
	return s
}

func (p *Pool) Status() (PoolConfig, []ChannelStatus, []Event) {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := time.Now()
	out := make([]ChannelStatus, 0, len(p.chans))
	for _, c := range p.chans {
		st := ChannelStatus{ID: c.id, Name: c.name, Note: c.note, Local: c.local, Enabled: p.enabledLocked(c), Busy: c.inflight, Slots: c.slots,
			UsedSecs: c.usedLocked(now), QuotaSecs: quotaAudio.Seconds(), OK: c.OK, Fail: c.Fail, LastError: c.LastErr, LastUsed: c.LastUsed}
		if c.local {
			st.QuotaSecs = 0
		}
		switch {
		case !st.Enabled:
			st.State = "disabled"
		case now.Before(c.coolUntil):
			st.State, st.CoolUntil = "cooling", c.coolUntil.Unix()
		case !c.local && st.UsedSecs >= st.QuotaSecs:
			st.State = "quota"
		case c.inflight > 0:
			st.State = "busy"
		default:
			st.State = "ready"
		}
		out = append(out, st)
	}
	ev := make([]Event, len(p.events))
	for i, e := range p.events {
		ev[len(ev)-1-i] = e // newest first
	}
	return p.cfg, out, ev
}

// pick reserves a channel for a chunk of secs seconds, preferring channels
// not yet tried for it. With nothing free it returns when to look again.
func (p *Pool) pick(secs float64, tried map[string]bool) (c *channel, wake <-chan struct{}, retryAt time.Time, err error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := time.Now()
	var cands []*channel
	enabled, overQuota := 0, 0
	for _, c := range p.chans {
		if !p.enabledLocked(c) {
			continue
		}
		enabled++
		if !c.local && c.usedLocked(now)+secs > quotaAudio.Seconds() {
			overQuota++
			continue
		}
		if now.Before(c.coolUntil) {
			if retryAt.IsZero() || c.coolUntil.Before(retryAt) {
				retryAt = c.coolUntil
			}
			continue
		}
		if c.inflight >= c.slots {
			continue
		}
		cands = append(cands, c)
	}
	if enabled == 0 {
		return nil, nil, time.Time{}, errors.New("没有启用的转写渠道，请在 设置 → 转写 中开启至少一个")
	}
	if overQuota == enabled {
		return nil, nil, time.Time{}, errors.New("所有转写渠道的免费额度（每渠道 12 小时内 6 小时音频）已用完，请稍后再试")
	}
	if len(cands) == 0 {
		for _, c := range p.chans {
			if c.inflight > 0 {
				// A busy channel will free a slot and signal; that is
				// ordinary queueing, not an outage.
				return nil, p.wake, time.Time{}, nil
			}
		}
		return nil, p.wake, retryAt, nil
	}
	pref := p.cfg.Strategy
	sort.SliceStable(cands, func(i, j int) bool {
		a, b := cands[i], cands[j]
		if tried[a.id] != tried[b.id] {
			return !tried[a.id]
		}
		if pref != "balance" && (a.id == pref) != (b.id == pref) {
			return a.id == pref
		}
		// Least loaded relative to capacity, then least used recently.
		la, lb := float64(a.inflight)/float64(a.slots), float64(b.inflight)/float64(b.slots)
		if la != lb {
			return la < lb
		}
		return a.usedLocked(now) < b.usedLocked(now)
	})
	c = cands[0]
	c.inflight++
	return c, nil, time.Time{}, nil
}

// release frees a reservation without recording an outcome.
func (p *Pool) release(c *channel) {
	p.mu.Lock()
	c.inflight--
	p.mu.Unlock()
	p.signal()
}

func (p *Pool) done(c *channel, ev Event, err error) {
	p.mu.Lock()
	c.inflight--
	now := time.Now()
	c.LastUsed = now.Unix()
	if err == nil {
		c.OK++
		c.backoff = 0
		c.LastErr = ""
		c.Usage = append(c.Usage, use{At: now.Unix(), Secs: ev.Secs})
	} else {
		c.Fail++
		c.LastErr = err.Error()
		if transient(err) {
			// Rate limited: back off 1, 2, 4 … 15 minutes.
			c.backoff = min(max(c.backoff*2, time.Minute), 15*time.Minute)
		} else {
			c.backoff = 5 * time.Minute
		}
		c.coolUntil = now.Add(c.backoff)
		ev.Error = err.Error()
	}
	ev.OK = err == nil
	p.events = append(p.events, ev)
	if len(p.events) > maxEvents {
		p.events = p.events[len(p.events)-maxEvents:]
	}
	p.mu.Unlock()
	p.save()
	p.signal()
}

type chunk struct {
	key        string
	path       string
	start, end float64 // seconds covered by the chunk file
	lo, hi     float64 // seconds this chunk is responsible for
	secs       float64
}

// Transcribe splits audio into chunks and recognises them across channels.
// It also returns the ids of the channels that contributed, e.g. "bcut+jianying".
func (p *Pool) Transcribe(ctx context.Context, audio string, onStage Stage) ([]Utterance, string, error) {
	fi, err := os.Stat(audio)
	if err != nil {
		return nil, "", err
	}
	// Re-extracting the same lecture gives the same file, so a rerun job
	// still finds the chunks an earlier run finished.
	ident := fmt.Sprintf("%s|%d", audio, fi.Size())
	total := probeSeconds(ctx, audio)
	var chunks []chunk
	if total <= 0 || total <= chunkSec+120 {
		chunks = []chunk{{key: ident + "|all", path: audio, lo: -1, hi: 1e12, secs: max(total, 1)}}
	} else {
		for lo := 0.0; lo < total; lo += chunkSec {
			hi := min(lo+chunkSec, total)
			start, end := max(0, lo-overlapSec), min(total, hi+overlapSec)
			chunks = append(chunks, chunk{key: fmt.Sprintf("%s|%d", ident, int(lo)), start: start, end: end, lo: lo, hi: hi, secs: end - start})
		}
		chunks[0].lo, chunks[len(chunks)-1].hi = -1, 1e12
	}

	results := make([][]Utterance, len(chunks))
	used := make([]string, len(chunks))
	var mu sync.Mutex
	finished := 0
	note := ""
	p.mu.Lock()
	for i, ck := range chunks {
		if c, ok := p.cache[ck.key]; ok {
			results[i], used[i] = c.us, c.by
			finished++
		}
	}
	conc := p.cfg.Concurrency
	p.mu.Unlock()

	report := func() {
		if onStage == nil {
			return
		}
		mu.Lock()
		n := map[string]int{}
		for _, u := range used {
			if u != "" {
				n[u]++
			}
		}
		var parts []string
		for _, c := range p.chans {
			if n[c.id] > 0 {
				parts = append(parts, fmt.Sprintf("%s %d", c.name, n[c.id]))
			}
		}
		label := fmt.Sprintf("识别 %d/%d 段", finished, len(chunks))
		if len(parts) > 0 {
			label += "（" + strings.Join(parts, " · ") + "）"
		}
		if note != "" {
			label += " · " + note
		}
		frac := float64(finished) / float64(len(chunks))
		mu.Unlock()
		onStage(label, frac)
	}
	setNote := func(s string) {
		mu.Lock()
		changed := note != s
		note = s
		mu.Unlock()
		if changed {
			report()
		}
	}
	report()

	var dir string
	if len(chunks) > 1 {
		if dir, err = os.MkdirTemp(filepath.Dir(audio), "chunks-"); err != nil {
			return nil, "", err
		}
		defer os.RemoveAll(dir)
	}

	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	for i := range chunks {
		if results[i] != nil || used[i] != "" {
			continue // recovered from an earlier attempt
		}
		select {
		case sem <- struct{}{}:
		case <-ctx.Done():
		}
		if ctx.Err() != nil {
			break
		}
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			defer func() { <-sem }()
			ck := &chunks[i]
			if ck.path == "" {
				ck.path = filepath.Join(dir, fmt.Sprintf("%03d.mp3", i))
				if err := cut(ctx, audio, ck.path, ck.start, ck.end); err != nil {
					cancel(err)
					return
				}
			}
			label := fmt.Sprintf("%d/%d", i+1, len(chunks))
			tried := map[string]bool{}
			var lastErr error
			starved := time.Time{}
			for attempt := 0; attempt < 6; {
				c, wake, retryAt, err := p.pick(ck.secs, tried)
				if err != nil {
					cancel(err)
					return
				}
				if c == nil && retryAt.IsZero() {
					starved = time.Time{}
					select {
					case <-ctx.Done():
						return
					case <-wake:
					case <-time.After(30 * time.Second):
					}
					continue
				}
				if c == nil {
					if starved.IsZero() {
						starved = time.Now()
					}
					if time.Since(starved) > starveLimit {
						cancel(fmt.Errorf("免费转写渠道持续不可用（第 %s 段等待超过 %d 分钟）: %v", label, int(starveLimit.Minutes()), lastErr))
						return
					}
					setNote("渠道冷却中，" + retryAt.Format("15:04") + " 后继续")
					wait := min(30*time.Second, time.Until(retryAt)+time.Second)
					select {
					case <-ctx.Done():
						return
					case <-wake:
					case <-time.After(wait):
					}
					continue
				}
				starved = time.Time{}
				setNote("")
				attempt++
				tried[c.id] = true
				t0 := time.Now()
				u, err := c.eng.Transcribe(ctx, ck.path, nil)
				if ctx.Err() != nil {
					p.release(c)
					return
				}
				if errors.Is(err, errEmpty) {
					u, err = []Utterance{}, nil // silence is a valid result
				}
				p.done(c, Event{At: t0.Unix(), Channel: c.name, Chunk: label, Secs: ck.secs, Took: time.Since(t0).Seconds()}, err)
				if err == nil {
					mu.Lock()
					results[i], used[i] = u, c.id
					finished++
					mu.Unlock()
					p.mu.Lock()
					p.cache[ck.key] = cached{at: time.Now(), us: u, by: c.id}
					p.mu.Unlock()
					report()
					return
				}
				lastErr = fmt.Errorf("%s: %w", c.name, err)
			}
			cancel(fmt.Errorf("第 %s 段多次识别失败: %w", label, lastErr))
		}(i)
	}
	wg.Wait()
	if err := context.Cause(ctx); err != nil && !errors.Is(err, context.Canceled) {
		return nil, "", err
	}
	if ctx.Err() != nil {
		return nil, "", ctx.Err()
	}

	// Each utterance belongs to the chunk holding its midpoint, so overlap
	// regions contribute exactly once.
	var out []Utterance
	for i, us := range results {
		ck := chunks[i]
		off := int64(ck.start * 1000)
		for _, u := range us {
			u.StartMs += off
			u.EndMs += off
			mid := float64(u.StartMs+u.EndMs) / 2000
			if mid >= ck.lo && mid < ck.hi {
				out = append(out, u)
			}
		}
	}
	sort.SliceStable(out, func(a, b int) bool { return out[a].StartMs < out[b].StartMs })
	p.mu.Lock()
	for _, ck := range chunks {
		delete(p.cache, ck.key)
	}
	for k, c := range p.cache {
		if time.Since(c.at) > 6*time.Hour {
			delete(p.cache, k)
		}
	}
	p.mu.Unlock()
	if len(out) == 0 {
		return nil, "", errors.New("识别结果为空")
	}
	var ids []string
	for _, c := range p.chans {
		for _, u := range used {
			if u == c.id {
				ids = append(ids, c.id)
				break
			}
		}
	}
	return out, strings.Join(ids, "+"), nil
}

func cut(ctx context.Context, src, dst string, start, end float64) error {
	cmd := exec.CommandContext(ctx, "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
		"-ss", strconv.FormatFloat(start, 'f', 3, 64), "-t", strconv.FormatFloat(end-start, 'f', 3, 64),
		"-i", src, "-c", "copy", "-y", dst)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("切分音频: %v %s", err, bytes.TrimSpace(out))
	}
	return nil
}

func probeSeconds(ctx context.Context, path string) float64 {
	out, err := exec.CommandContext(ctx, "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path).Output()
	if err != nil {
		return 0
	}
	f, _ := strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
	return f
}

type savedState struct {
	Channels map[string]*channel `json:"channels"`
	Events   []Event             `json:"events"`
}

func (p *Pool) load() {
	b, err := os.ReadFile(p.state)
	if err != nil {
		return
	}
	var st savedState
	if json.Unmarshal(b, &st) != nil || st.Channels == nil {
		// Older format: a bare map of channels.
		st = savedState{}
		if json.Unmarshal(b, &st.Channels) != nil {
			return
		}
	}
	for _, c := range p.chans {
		if s := st.Channels[c.id]; s != nil {
			c.OK, c.Fail, c.LastErr, c.LastUsed, c.Usage = s.OK, s.Fail, s.LastErr, s.LastUsed, s.Usage
		}
	}
	p.saved = st.Channels
	p.events = st.Events
}

func (p *Pool) save() {
	if p.state == "" {
		return
	}
	p.mu.Lock()
	st := savedState{Channels: map[string]*channel{}, Events: append([]Event(nil), p.events...)}
	now := time.Now()
	for _, c := range p.chans {
		c.usedLocked(now)
		st.Channels[c.id] = &channel{OK: c.OK, Fail: c.Fail, LastErr: c.LastErr, LastUsed: c.LastUsed, Usage: append([]use(nil), c.Usage...)}
	}
	p.mu.Unlock()
	b, _ := json.Marshal(st)
	tmp := p.state + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, p.state)
	}
}
