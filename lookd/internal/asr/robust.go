package asr

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// newTransport is a private HTTP/1.1 pool for the ASR services, kept apart
// from the Look session so a slow or degraded connection on one side cannot
// hold up the other.
func newTransport() *http.Transport {
	return &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSNextProto:          map[string]func(string, *tls.Conn) http.RoundTripper{},
		MaxIdleConnsPerHost:   8,
		IdleConnTimeout:       60 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
	}
}

type httpErr struct {
	svc, path  string
	code       int
	retryAfter time.Duration
}

func (e httpErr) Error() string { return fmt.Sprintf("%s %s: HTTP %d", e.svc, e.path, e.code) }

func statusErr(svc, path string, resp *http.Response) httpErr {
	e := httpErr{svc: svc, path: path, code: resp.StatusCode}
	if s, err := strconv.Atoi(resp.Header.Get("Retry-After")); err == nil && s > 0 {
		e.retryAfter = min(time.Duration(s)*time.Second, 2*time.Minute)
	}
	return e
}

// transient reports errors worth waiting out: rate limiting (412 is
// Bilibili's risk control, 429 the usual), 5xx and network hiccups.
func transient(err error) bool {
	if err == nil || errors.Is(err, context.Canceled) {
		return false
	}
	var he httpErr
	if errors.As(err, &he) {
		return he.code == 408 || he.code == 412 || he.code == 425 || he.code == 429 || he.code >= 500
	}
	var ae apiErr
	if errors.As(err, &ae) {
		return ae.limited()
	}
	var ne net.Error
	return errors.As(err, &ne) || errors.Is(err, io.ErrUnexpectedEOF) || errors.Is(err, io.EOF) || errors.Is(err, context.DeadlineExceeded)
}

// pacer keeps a minimum gap between requests to one service so parallel
// chunks never arrive as a burst.
type pacer struct {
	mu   sync.Mutex
	gap  time.Duration
	next time.Time
}

func (p *pacer) wait(ctx context.Context) error {
	p.mu.Lock()
	at := time.Now()
	if p.next.After(at) {
		at = p.next
	}
	p.next = at.Add(p.gap)
	p.mu.Unlock()
	return sleep(ctx, time.Until(at))
}

func sleep(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// retry runs an idempotent step, waiting out transient failures with
// growing delays (or the server's Retry-After) for up to tries attempts.
func retry(ctx context.Context, tries int, step func() error) error {
	delay := 3 * time.Second
	for i := 1; ; i++ {
		err := step()
		if err == nil || i >= tries || !transient(err) || ctx.Err() != nil {
			return err
		}
		d := delay
		var he httpErr
		if errors.As(err, &he) && he.retryAfter > 0 {
			d = he.retryAfter
		}
		if serr := sleep(ctx, d); serr != nil {
			return serr
		}
		delay = min(delay*3, 30*time.Second)
	}
}

// poller paces result queries and gives up after too many consecutive
// transient failures, so a rate-limited channel releases its chunk quickly
// instead of holding it until the deadline.
type poller struct {
	deadline time.Time
	interval time.Duration
	strikes  int
}

const maxStrikes = 4

func newPoller(limit time.Duration) *poller {
	return &poller{deadline: time.Now().Add(limit), interval: 3 * time.Second}
}

// next records the outcome of one query and waits before the following one.
// It returns a non-nil error when polling should stop.
func (p *poller) next(ctx context.Context, err error) error {
	if err != nil {
		if !transient(err) {
			return err
		}
		if p.strikes++; p.strikes >= maxStrikes {
			return err
		}
		p.interval = min(max(p.interval*2, 5*time.Second), 30*time.Second)
	} else {
		p.strikes, p.interval = 0, 3*time.Second
	}
	if time.Now().After(p.deadline) {
		return errTimeout
	}
	return sleep(ctx, p.interval)
}

var errTimeout = errors.New("识别超时")
