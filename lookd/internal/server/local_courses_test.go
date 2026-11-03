package server

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"lookstudio/lookd/internal/agent"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
	"lookstudio/lookd/internal/tongji"
)

func TestLocalCourseImportPlaybackAndRecovery(t *testing.T) {
	if _, err := exec.LookPath("ffprobe"); err != nil {
		t.Skip("ffprobe required for real-video integration")
	}
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg required to generate video fixture")
	}
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	lib, err := library.Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	sess := tongji.NewSession("", nil)
	s := &Server{Token: "test", St: st, Lib: lib, Sess: sess, Bus: events.New(), Agent: &agent.Supervisor{}, lastCourse: time.Now()}
	h := s.Handler()
	call := func(method, path string, body []byte, token string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, path, bytes.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := call("POST", "/api/local-courses", []byte(`{"title":"本地课程"}`), "wrong"); w.Code != 401 {
		t.Fatal(w.Code)
	}
	if w := call("POST", "/api/local-courses", []byte(`{"title":"  "}`), "test"); w.Code != 400 {
		t.Fatal(w.Code, w.Body.String())
	}
	w := call("POST", "/api/local-courses", []byte(`{"title":"操作系统期末速成","teacher":"数学建模老哥"}`), "test")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var course store.Course
	if err := json.Unmarshal(w.Body.Bytes(), &course); err != nil || !store.IsLocalCourse(course.ID) || course.Term != "local" {
		t.Fatal(course, err)
	}
	if current(course, time.Now()) {
		t.Fatal("local course entered recording poller")
	}
	// A nil campus client makes any unintended remote access fail this test.
	w = call("GET", "/api/courses/"+course.ID+"/lectures?sync=1", nil, "test")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	video := filepath.Join(t.TempDir(), "source.mp4")
	cmd := exec.Command("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=2:d=1", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", video)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatal(err, string(out))
	}
	data, err := os.ReadFile(video)
	if err != nil {
		t.Fatal(err)
	}
	var lessons []store.Lecture
	for _, name := range []string{"01.mp4", "02.mp4"} {
		w = call("POST", "/api/courses/"+course.ID+"/local-videos?name="+name, data, "test")
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		var lec store.Lecture
		if err := json.Unmarshal(w.Body.Bytes(), &lec); err != nil || !lec.HasPlayback || lec.DurationS <= 0 {
			t.Fatal(lec, err)
		}
		lessons = append(lessons, lec)
	}
	if lessons[0].ID >= lessons[1].ID {
		t.Fatal("import order lost")
	}
	w = call("POST", "/api/courses/"+course.ID+"/local-videos?name=01.mp4", data, "test")
	var retried store.Lecture
	json.Unmarshal(w.Body.Bytes(), &retried)
	if w.Code != 200 || retried.ID != lessons[0].ID {
		t.Fatal("retry duplicated a lesson", w.Code, w.Body.String())
	}
	w = call("GET", "/api/lectures/"+lessons[0].ID+"/media", nil, "test")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var media struct {
		Streams []tongji.Stream `json:"streams"`
	}
	json.Unmarshal(w.Body.Bytes(), &media)
	if len(media.Streams) != 1 || !strings.Contains(media.Streams[0].URL, "/files/") {
		t.Fatal(w.Body.String())
	}
	r := httptest.NewRequest("GET", media.Streams[0].URL, nil)
	r.Header.Set("Range", "bytes=0-15")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 206 || !bytes.Equal(w.Body.Bytes(), data[:16]) {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := call("GET", "/api/lectures/"+lessons[0].ID+"/slides", nil, "test"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	for _, filename := range []string{"../escape.mp4", "bad.txt", "bad.mp4"} {
		w = call("POST", "/api/courses/"+course.ID+"/local-videos?name="+filename, []byte("invalid video"), "test")
		if w.Code != 400 {
			t.Fatal(filename, w.Code, w.Body.String())
		}
	}
	if err := st.UpsertCourse(ctx, store.Course{ID: "school", Title: "学校课程", Term: "20261"}); err != nil {
		t.Fatal(err)
	}
	if w := call("POST", "/api/courses/school/local-videos?name=a.mp4", data, "test"); w.Code != 400 {
		t.Fatal(w.Code)
	}
	r = httptest.NewRequest("POST", "/api/courses/"+course.ID+"/local-videos?name=large.mp4", nil)
	r.Header.Set("Authorization", "Bearer test")
	r.ContentLength = library.LocalVideoLimit + 1
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 413 {
		t.Fatal(w.Code, w.Body.String())
	}
	if tmp, _ := filepath.Glob(filepath.Join(root, ".local-upload-*")); len(tmp) != 0 {
		t.Fatal("failed upload leaked files", tmp)
	}
	if cs, _ := st.Course(ctx, course.ID); cs.LectureTotal != 2 {
		t.Fatal("incorrect course total", cs.LectureTotal)
	}
	// A failed school refresh still serves both school and local courses.
	s.Cl = &tongji.Client{S: sess}
	w = call("GET", "/api/courses?sync=1", nil, "test")
	if w.Code != 200 || !strings.Contains(w.Body.String(), course.ID) || !strings.Contains(w.Body.String(), `"id":"school"`) {
		t.Fatal(w.Code, w.Body.String())
	}
	st2, err := store.Open(filepath.Join(t.TempDir(), "fresh.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st2.Close()
	lib2, err := library.Open(root, st2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := lib2.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	for _, lec := range lessons {
		recovered, err := st2.Lecture(ctx, lec.ID)
		assets, _ := st2.Assets(ctx, lec.ID)
		if err != nil || recovered.Title != lec.Title || recovered.DurationS != lec.DurationS || len(assets) != 1 {
			t.Fatal("recovery failed", recovered, assets, err)
		}
		content, err := os.ReadFile(lib2.Abs(assets[0].Path))
		if err != nil || !bytes.Equal(content, data) {
			t.Fatal("imported bytes changed", err)
		}
	}
	if cs, _ := st2.Course(ctx, course.ID); cs.LectureTotal != 2 || cs.Term != "local" {
		t.Fatal("course recovery failed", cs)
	}
	// A redirected destination must not receive an upload.
	outside := t.TempDir()
	if err := os.Rename(lib.Abs(course.Dir), lib.Abs(course.Dir)+".saved"); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, lib.Abs(course.Dir)); err != nil {
		t.Fatal(err)
	}
	if _, err := lib.ImportLocalVideo(ctx, course.ID, "03.mp4", bytes.NewReader(data)); err == nil {
		t.Fatal("accepted symlink destination")
	}
	if entries, _ := os.ReadDir(outside); len(entries) != 0 {
		t.Fatal("upload escaped library")
	}
}
