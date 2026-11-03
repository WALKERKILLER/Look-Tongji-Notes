package server

import (
	"context"
	"encoding/json"
	"lookstudio/lookd/internal/tongji"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"lookstudio/lookd/internal/agent"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
)

// Exercise the authenticated, registered API and embedded request JSON shape;
// persistence and source preservation have their primary evidence in library.
func TestLibraryReviewRoutes(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, e := store.Open(filepath.Join(root, "library.db"))
	if e != nil {
		t.Fatal(e)
	}
	defer st.Close()
	st.UpsertCourse(ctx, store.Course{ID: "c", Title: "操作系统"})
	st.UpsertLectures(ctx, []store.Lecture{{ID: "l", CourseID: "c", Title: "首课"}})
	lib, e := library.Open(root, st)
	if e != nil {
		t.Fatal(e)
	}
	segs := []store.Segment{{Idx: 0, StartMs: 0, EndMs: 1000, Text: "页表缓冲"}}
	lib.SaveTranscript(ctx, "l", segs, "local")
	lib.SaveNote(ctx, store.Note{ID: "ocr", CourseID: "c", LectureID: "l", Title: "课堂截图检索 · 首课", Source: "user", Body: "课堂证据 TLB"})
	s := &Server{Token: "test", St: st, Lib: lib, Bus: events.New(), Agent: &agent.Supervisor{}}
	h := s.Handler()
	call := func(method, p, body, token string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, p, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := call("GET", "/api/library/catalog", "", "wrong"); w.Code != http.StatusUnauthorized {
		t.Fatal(w.Code)
	}
	if w := call("GET", "/api/library/catalog", "", "test"); w.Code != 200 || !strings.Contains(w.Body.String(), `"category":"transcript"`) {
		t.Fatal(w.Code, w.Body.String())
	}
	w := call("GET", "/api/lectures/l/transcript-review/context", "", "test")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "课堂证据 TLB") {
		t.Fatal("lecture material body omitted", w.Body.String())
	}
	var c map[string]any
	json.Unmarshal(w.Body.Bytes(), &c)
	in := map[string]any{"run_id": "a", "fingerprint": c["fingerprint"], "state": "completed", "completed": 1, "total": 1, "model": "p/m", "suggestions": []map[string]any{{"segment": 0, "original": "页表缓冲", "guess": "TLB", "reason": "疑似术语错误", "evidence": "课堂 OCR：TLB"}}}
	b, _ := json.Marshal(in)
	w = call("PUT", "/api/lectures/l/transcript-review", string(b), "test")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var review library.TranscriptReview
	json.Unmarshal(w.Body.Bytes(), &review)
	w = call("PATCH", "/api/lectures/l/transcript-review", `{"suggestion_id":"`+review.Suggestions[0].ID+`"}`, "test")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"dismissed":true`) {
		t.Fatal(w.Code, w.Body.String())
	}
	in["fingerprint"] = "wrong"
	b, _ = json.Marshal(in)
	w = call("PUT", "/api/lectures/l/transcript-review", string(b), "test")
	if w.Code != 409 {
		t.Fatal(w.Code, w.Body.String())
	}
}

func TestExpiredCampusLoginStillServesAuthenticatedLocalVideo(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, e := store.Open(filepath.Join(root, "library.db"))
	if e != nil {
		t.Fatal(e)
	}
	defer st.Close()
	st.UpsertCourse(ctx, store.Course{ID: "c", Title: "操作系统"})
	st.UpsertLectures(ctx, []store.Lecture{{ID: "l", CourseID: "c", Title: "首课", DurationS: 100}})
	lib, e := library.Open(root, st)
	if e != nil {
		t.Fatal(e)
	}
	_, lec, _, e := lib.EnsureLecture(ctx, "l")
	if e != nil {
		t.Fatal(e)
	}
	rel := lec.Dir + "/video.mp4"
	os.WriteFile(lib.Abs(rel), []byte("0123456789"), 0600)
	st.PutAsset(ctx, store.Asset{LectureID: "l", Kind: "video", Path: rel, Bytes: 10})
	s := &Server{Token: "test", St: st, Lib: lib, Sess: nativeFudanFixture(t), Bus: events.New(), Agent: &agent.Supervisor{}}
	h := s.Handler()
	r := httptest.NewRequest("GET", "/api/lectures/l/media", nil)
	r.Header.Set("Authorization", "Bearer test")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var out struct {
		Streams []tongji.Stream `json:"streams"`
	}
	json.Unmarshal(w.Body.Bytes(), &out)
	if len(out.Streams) != 1 || !strings.Contains(out.Streams[0].URL, "/files/") || strings.Contains(w.Body.String(), root) {
		t.Fatal("missing bounded local playback", w.Body.String())
	}
	r = httptest.NewRequest("GET", out.Streams[0].URL, nil)
	r.Header.Set("Range", "bytes=2-5")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 206 || w.Body.String() != "2345" {
		t.Fatal("local seek failed", w.Code, w.Body.String())
	}
	r = httptest.NewRequest("GET", strings.Split(out.Streams[0].URL, "?")[0], nil)
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 401 {
		t.Fatal("unauthenticated media readable", w.Code)
	}
}

func nativeFudanFixture(t *testing.T) *tongji.Session {
	t.Helper()
	p := filepath.Join(t.TempDir(), "session.json")
	if err := os.WriteFile(p, []byte(`{"school":"fudan"}`), 0600); err != nil {
		t.Fatal(err)
	}
	return tongji.NewSession(p, nil)
}
