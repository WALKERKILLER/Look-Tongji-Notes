package server

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"lookstudio/lookd/internal/tongji"
)

// The relay passes range requests through with the daemon's headers (the
// WebVPN cookie), which the player never sees.
func TestRelayStreamPassesRanges(t *testing.T) {
	var cookie string
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie = r.Header.Get("Cookie")
		http.ServeContent(w, r, "v.mp4", time.Time{}, bytes.NewReader([]byte("0123456789")))
	}))
	defer up.Close()
	s := &Server{}
	s.relayed.put("L1", &tongji.Media{
		Streams: []tongji.Stream{{URL: up.URL + "/https/abc/v.mp4"}},
		Headers: http.Header{"Cookie": {"wengine_vpn_ticket=V1"}},
	})
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/lectures/{id}/streams/{n}", s.relayStream)

	req := httptest.NewRequest(http.MethodGet, "/api/lectures/L1/streams/0", nil)
	req.Header.Set("Range", "bytes=3-5")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	body, _ := io.ReadAll(rec.Body)
	if rec.Code != http.StatusPartialContent || string(body) != "345" || rec.Header().Get("Content-Range") != "bytes 3-5/10" {
		t.Fatalf("%d %q %v", rec.Code, body, rec.Header())
	}
	if cookie != "wengine_vpn_ticket=V1" || rec.Header().Get("Set-Cookie") != "" {
		t.Fatalf("upstream cookie %q", cookie)
	}

	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/lectures/L1/streams/1", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("missing stream: %d", rec.Code)
	}
}
