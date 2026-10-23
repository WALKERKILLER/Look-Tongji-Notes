package jobs

import (
	"context"
	"errors"
	"io"
	"net"
	"net/url"
	"syscall"
	"time"

	"lookstudio/lookd/internal/dl"
)

// A job that fails for a transient reason (the network dropped, the server
// hiccuped) goes back to the queue after a growing delay instead of failing,
// so a batch carries on by itself once the connection returns; downloads
// continue from their checkpoint. Other failures (no video, no ffmpeg, a
// full disk) fail at once.
var retryDelays = []time.Duration{15 * time.Second, 30 * time.Second, time.Minute, 2 * time.Minute, 5 * time.Minute, 10 * time.Minute}

type retryState struct {
	n  int       // automatic retries so far
	at time.Time // not before
}

func transient(err error) bool {
	if err == nil || errors.Is(err, context.Canceled) {
		return false
	}
	if code := dl.Status(err); code != 0 {
		return code == 408 || code == 429 || code >= 500
	}
	// Network failures surface as these types; syscall.Errno also has
	// net.Error's methods, so that interface would match a full disk too.
	var ue *url.Error
	var oe *net.OpError
	var de *net.DNSError
	if errors.As(err, &ue) || errors.As(err, &oe) || errors.As(err, &de) || dl.Stalled(err) || errors.Is(err, context.DeadlineExceeded) || errors.Is(err, io.ErrUnexpectedEOF) {
		return true
	}
	for _, e := range []error{syscall.ECONNRESET, syscall.ECONNREFUSED, syscall.ECONNABORTED, syscall.ETIMEDOUT, syscall.EHOSTUNREACH, syscall.ENETUNREACH, syscall.ENETDOWN, syscall.EPIPE} {
		if errors.Is(err, e) {
			return true
		}
	}
	return false
}

// nextRetry returns when a job that failed with err after n automatic
// retries runs again, or false when it should fail.
func nextRetry(err error, n int, now time.Time) (time.Time, bool) {
	if !transient(err) || n >= len(retryDelays) {
		return time.Time{}, false
	}
	return now.Add(retryDelays[n]), true
}
