package dl

import (
	"bytes"
	"context"
	"crypto/rand"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

func TestSegmentedRefreshAndResume(t *testing.T) {
	data := make([]byte, 9<<20+12345)
	rand.Read(data)
	var rejected atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("sig") != "good" {
			rejected.Add(1)
			w.WriteHeader(403)
			return
		}
		http.ServeContent(w, r, "v.mp4", time.Unix(0, 0), bytes.NewReader(data))
	}))
	defer srv.Close()

	e := New(http.DefaultTransport, Options{MaxConns: 6, MinChunk: 1 << 20})
	dest := filepath.Join(t.TempDir(), "out.bin")
	req := Request{URL: srv.URL + "/v.mp4?sig=stale", Dest: dest,
		Refresh: func(context.Context) (string, error) { return srv.URL + "/v.mp4?sig=good", nil }}

	// Cancel early to leave a partial download behind.
	ctx, cancel := context.WithCancel(context.Background())
	e.SetRateLimit(4 << 20)
	go func() { time.Sleep(600 * time.Millisecond); cancel() }()
	if err := e.Fetch(ctx, req, nil); err == nil {
		t.Fatal("expected cancellation")
	}
	if _, err := os.Stat(dest + ".part.json"); err != nil {
		t.Fatalf("no checkpoint: %v", err)
	}
	e.SetRateLimit(0)
	var last Progress
	if err := e.Fetch(context.Background(), req, func(p Progress) { last = p }); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(dest)
	if !bytes.Equal(got, data) {
		t.Fatal("content mismatch")
	}
	if last.Done != int64(len(data)) {
		t.Fatalf("progress %+v", last)
	}
	if rejected.Load() == 0 {
		t.Fatal("refresh path not exercised")
	}
	if _, err := os.Stat(dest + ".part.json"); !os.IsNotExist(err) {
		t.Fatal("checkpoint not cleaned")
	}
}

func TestStalledConnectionIsRedialled(t *testing.T) {
	data := make([]byte, 6<<20)
	rand.Read(data)
	var ranged, stalled atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Range") != "bytes=0-0" && ranged.Add(1) <= 2 {
			// Trickle a few bytes, then hang like a degraded connection.
			stalled.Add(1)
			var start int64
			fmt.Sscanf(r.Header.Get("Range"), "bytes=%d-", &start)
			w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, len(data)-1, len(data)))
			w.WriteHeader(http.StatusPartialContent)
			w.Write(data[start : start+1024])
			w.(http.Flusher).Flush()
			<-r.Context().Done()
			return
		}
		http.ServeContent(w, r, "v.mp4", time.Unix(0, 0), bytes.NewReader(data))
	}))
	defer srv.Close()

	e := New(http.DefaultTransport.(*http.Transport).Clone(), Options{MaxConns: 3, MinChunk: 1 << 20, StallWindow: 600 * time.Millisecond, StallRate: 1 << 20})
	dest := filepath.Join(t.TempDir(), "out.bin")
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := e.Fetch(ctx, Request{URL: srv.URL + "/v.mp4", Dest: dest}, nil); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(dest); !bytes.Equal(got, data) {
		t.Fatal("content mismatch")
	}
	if stalled.Load() != 2 {
		t.Fatalf("stalled handlers = %d", stalled.Load())
	}
}
