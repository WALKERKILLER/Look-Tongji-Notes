package server

import (
	"io"
	"net/http"
	"strconv"
	"sync"
	"time"

	"lookstudio/lookd/internal/tongji"
)

// relayCache keeps each relayed lecture's resolved media for a while, so the
// player's many range requests do not resolve and sign it again each time.
type relayCache struct {
	mu sync.Mutex
	m  map[string]relayEntry
}

type relayEntry struct {
	media *tongji.Media
	at    time.Time
}

const relayFresh = 10 * time.Minute

func (c *relayCache) put(id string, m *tongji.Media) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.m == nil {
		c.m = map[string]relayEntry{}
	}
	for k, e := range c.m {
		if time.Since(e.at) > relayFresh {
			delete(c.m, k)
		}
	}
	c.m[id] = relayEntry{m, time.Now()}
}

func (c *relayCache) get(id string) *tongji.Media {
	c.mu.Lock()
	defer c.mu.Unlock()
	if e, ok := c.m[id]; ok && time.Since(e.at) <= relayFresh {
		return e.media
	}
	return nil
}

func (c *relayCache) reset() {
	c.mu.Lock()
	c.m = nil
	c.mu.Unlock()
}

// relayClient has no overall timeout: a relayed video streams for as long as
// the player reads it.
var relayClient = &http.Client{Transport: http.DefaultTransport}

// relayStream passes one stream of a lecture to the player for schools whose
// media only the daemon can reach (Fudan, through WebVPN). Range requests
// pass through; a refused signature resolves the media again once.
func (s *Server) relayStream(w http.ResponseWriter, r *http.Request) {
	ctx, id := r.Context(), r.PathValue("id")
	n, err := strconv.Atoi(r.PathValue("n"))
	if err != nil || n < 0 {
		writeErr(w, badRequest("无效的视频流序号"))
		return
	}
	for attempt := 0; attempt < 2; attempt++ {
		m := s.relayed.get(id)
		if m == nil || attempt > 0 {
			l, err := s.St.Lecture(ctx, id)
			if err != nil {
				writeErr(w, err)
				return
			}
			if m, err = s.Cl.LectureMedia(ctx, l.CourseID, id); err != nil {
				writeErr(w, err)
				return
			}
			s.relayed.put(id, m)
		}
		if n >= len(m.Streams) {
			writeErr(w, apiError{http.StatusNotFound, "没有这个视频流"})
			return
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, m.Streams[n].URL, nil)
		if err != nil {
			writeErr(w, err)
			return
		}
		req.Header = m.Headers.Clone()
		for _, k := range []string{"Range", "If-Range"} {
			if v := r.Header.Get(k); v != "" {
				req.Header.Set(k, v)
			}
		}
		res, err := relayClient.Do(req)
		if err != nil {
			writeErr(w, apiError{http.StatusBadGateway, "无法连接复旦 WebVPN"})
			return
		}
		if attempt == 0 && tongji.VPNSignedOut(res) {
			// The signature or the gateway session lapsed; resolving the media
			// again renews the session when needed.
			res.Body.Close()
			continue
		}
		defer res.Body.Close()
		for _, k := range []string{"Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag"} {
			if v := res.Header.Get(k); v != "" {
				w.Header().Set(k, v)
			}
		}
		w.WriteHeader(res.StatusCode)
		io.Copy(w, res.Body)
		return
	}
	writeErr(w, apiError{http.StatusBadGateway, "复旦 iCourse 拒绝了视频请求，请稍后重试"})
}
