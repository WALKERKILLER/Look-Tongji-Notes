package server

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"lookstudio/lookd/internal/datasync"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
)

func folderIntegratedServer(t *testing.T, exchange string) *Server {
	t.Helper()
	root, data := t.TempDir(), t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	lib, err := library.Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	s := &Server{St: st, Lib: lib, Bus: events.New(), Ctx: context.Background(), Token: "fixture"}
	s.Data = &datasync.Service{Roots: datasync.Roots{Library: root, Data: data}, ApplyFiles: lib.ApplySyncFiles, CourseState: s.CourseState, MergeCourseState: s.MergeCourseState, Changed: s.DataArrived}
	if _, err := s.Data.Configure(s.Ctx, datasync.Settings{Kind: "folder", LocalFolder: exchange, CourseIDs: []string{"pilot"}}); err != nil {
		t.Fatal(err)
	}
	return s
}
func putFolderIntegration(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
}
func syncIntegrated(t *testing.T, s *Server) {
	t.Helper()
	if _, err := s.Data.Sync(s.Ctx); err != nil {
		t.Fatal(err)
	}
}
func assertIntegrationBytes(t *testing.T, root, rel, want string) {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, rel))
	if err != nil || string(b) != want {
		t.Fatalf("%s: %q %v", rel, b, err)
	}
}

func TestFolderImportReindexesFilesSessionsAndUserState(t *testing.T) {
	exchange := t.TempDir()
	a, b := folderIntegratedServer(t, exchange), folderIntegratedServer(t, exchange)
	putFolderIntegration(t, a.Lib.Root, "courses/pilot/course.json", `{"id":"pilot","title":"Pilot"}`)
	putFolderIntegration(t, a.Lib.Root, "courses/pilot/one/lecture.json", `{"id":"one","course_id":"pilot","title":"One"}`)
	putFolderIntegration(t, a.Data.Roots.Data, "agent/sessions-meta.json", `{"s1":{"kind":"course","course_id":"pilot"}}`)
	session := "{\"type\":\"session\",\"id\":\"s1\"}\n"
	putFolderIntegration(t, a.Data.Roots.Data, "agent/sessions/s1.jsonl", session)
	putFolderIntegration(t, b.Data.Roots.Data, "agent/sessions-meta.json", `{"private":{"kind":"chat"}}`)
	if _, err := a.Lib.Reindex(a.Ctx); err != nil {
		t.Fatal(err)
	}
	if err := a.St.SavePlayback(a.Ctx, "one", store.Playback{PositionMs: 1000, Speed: 1}); err != nil {
		t.Fatal(err)
	}
	if _, err := a.St.AddBookmark(a.Ctx, store.Bookmark{LectureID: "one", TMs: 500, Label: "keep"}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		syncIntegrated(t, a)
		syncIntegrated(t, b)
	}
	lecture, err := b.St.Lecture(b.Ctx, "one")
	if err != nil || lecture.CourseID != "pilot" {
		t.Fatal(lecture, err)
	}
	playback, err := b.St.Playback(b.Ctx, "one")
	if err != nil || playback.PositionMs != 1000 {
		t.Fatal(playback, err)
	}
	bookmarks, err := b.St.Bookmarks(b.Ctx, "one")
	if err != nil || len(bookmarks) != 1 {
		t.Fatal(bookmarks, err)
	}
	raw, err := os.ReadFile(filepath.Join(b.Data.Roots.Data, "agent/sessions-meta.json"))
	if err != nil {
		t.Fatal(err)
	}
	var meta map[string]map[string]string
	if err := json.Unmarshal(raw, &meta); err != nil {
		t.Fatal(err)
	}
	if meta["s1"]["course_id"] != "pilot" || meta["private"]["kind"] != "chat" {
		t.Fatalf("metadata: %s", raw)
	}
	assertIntegrationBytes(t, b.Data.Roots.Data, "agent/sessions/s1.jsonl", session)
}

func TestFolderRestoreCannotOverwriteAnotherCourseQuiz(t *testing.T) {
	s := folderIntegratedServer(t, t.TempDir())
	putFolderIntegration(t, s.Lib.Root, "courses/pilot/course.json", `{"id":"pilot"}`)
	original := `{"quiz":{"course_id":"other"},"attempts":[]}`
	putFolderIntegration(t, s.Lib.Root, "quizzes/q.json", original)
	putFolderIntegration(t, s.Lib.Root, datasync.ConflictDir+"/folder-test/course-data/pilot/quizzes/q.json", `{"quiz":{"course_id":"pilot"},"attempts":[]}`)
	rows, err := s.folderConflicts(nil, httptest.NewRequest("GET", "/", nil))
	if err != nil {
		t.Fatal(err)
	}
	id := rows.([]map[string]any)[0]["id"].(string)
	hash, err := fileDigest(filepath.Join(s.Lib.Root, "quizzes/q.json"))
	if err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]string{"action": "restore", "expected_hash": hash})
	r := httptest.NewRequest("POST", "/api/sync/folder/conflicts/"+id+"/resolve", strings.NewReader(string(body)))
	r.Header.Set("Authorization", "Bearer fixture")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	if w.Code < 400 {
		t.Fatalf("restore crossed course scope: %d %s", w.Code, w.Body.String())
	}
	assertIntegrationBytes(t, s.Lib.Root, "quizzes/q.json", original)
}

func TestFolderNullPrivateIndexesReturnErrors(t *testing.T) {
	for _, kind := range []string{"sessions", "resolutions"} {
		t.Run(kind, func(t *testing.T) {
			s := folderIntegratedServer(t, t.TempDir())
			switch kind {
			case "sessions":
				putFolderIntegration(t, s.Data.Roots.Data, "agent/sessions-meta.json", "null")
				putFolderIntegration(t, s.Data.Roots.Data, "agent/course-sessions/pilot.json", `{"s1":{"kind":"course","course_id":"pilot"}}`)
				if err := s.mergeFolderSessionMetadata(); err == nil {
					t.Fatal("null metadata accepted")
				}
			case "resolutions":
				putFolderIntegration(t, s.Data.Roots.Data, "folder-conflicts-resolved.json", "null")
				if err := s.markFolderConflict("fixture"); err == nil {
					t.Fatal("null resolution index accepted")
				}
			}
		})
	}
}

func TestFolderRestoreSelectedNoteKeepsBackupAndRejectsStalePreview(t *testing.T) {
	s := folderIntegratedServer(t, t.TempDir())
	putFolderIntegration(t, s.Lib.Root, "courses/pilot/course.json", `{"id":"pilot"}`)
	target := "courses/pilot/note.md"
	putFolderIntegration(t, s.Lib.Root, target, "current")
	recovery := datasync.ConflictDir + "/folder-test/library/" + target
	putFolderIntegration(t, s.Lib.Root, recovery, "recovered")
	rows, err := s.folderConflicts(nil, httptest.NewRequest("GET", "/", nil))
	if err != nil {
		t.Fatal(err)
	}
	id := rows.([]map[string]any)[0]["id"].(string)
	hash, err := fileDigest(filepath.Join(s.Lib.Root, target))
	if err != nil {
		t.Fatal(err)
	}
	resolve := func(hash string) int {
		raw, _ := json.Marshal(map[string]string{"action": "restore", "expected_hash": hash})
		r := httptest.NewRequest("POST", "/api/sync/folder/conflicts/"+id+"/resolve", strings.NewReader(string(raw)))
		r.Header.Set("Authorization", "Bearer fixture")
		w := httptest.NewRecorder()
		s.Handler().ServeHTTP(w, r)
		return w.Code
	}
	putFolderIntegration(t, s.Lib.Root, target, "saved after preview")
	if status := resolve(hash); status != 409 {
		t.Fatalf("stale preview: %d", status)
	}
	assertIntegrationBytes(t, s.Lib.Root, target, "saved after preview")
	hash, err = fileDigest(filepath.Join(s.Lib.Root, target))
	if err != nil {
		t.Fatal(err)
	}
	if status := resolve(hash); status != 200 {
		t.Fatalf("valid restore: %d", status)
	}
	assertIntegrationBytes(t, s.Lib.Root, target, "recovered")
	assertIntegrationBytes(t, s.Lib.Root, recovery, "recovered")
	backups, err := filepath.Glob(filepath.Join(s.Lib.Root, datasync.ConflictDir, "manual-*", "library", target))
	if err != nil || len(backups) != 1 {
		t.Fatal(backups, err)
	}
	body, err := os.ReadFile(backups[0])
	if err != nil || string(body) != "saved after preview" {
		t.Fatal(string(body), err)
	}
}

func TestFolderRestoreRefreshesInstalledFilesWhenAcknowledgementFails(t *testing.T) {
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("requires POSIX permissions and a non-root user")
	}
	s := folderIntegratedServer(t, t.TempDir())
	putFolderIntegration(t, s.Lib.Root, "courses/pilot/course.json", `{"id":"pilot"}`)
	target := "courses/pilot/note.md"
	putFolderIntegration(t, s.Lib.Root, target, "original")
	putFolderIntegration(t, s.Lib.Root, datasync.ConflictDir+"/folder-test/library/"+target, "restored")
	rows, err := s.folderConflicts(nil, httptest.NewRequest("GET", "/", nil))
	if err != nil {
		t.Fatal(err)
	}
	id := rows.([]map[string]any)[0]["id"].(string)
	hash, err := fileDigest(filepath.Join(s.Lib.Root, target))
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := json.Marshal(map[string]string{"action": "restore", "expected_hash": hash})
	if err := os.Chmod(s.Data.Roots.Data, 0500); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(s.Data.Roots.Data, 0700)
	messages, unsubscribe := s.Bus.Subscribe()
	defer unsubscribe()
	req := httptest.NewRequest("POST", "/api/sync/folder/conflicts/"+id+"/resolve", strings.NewReader(string(raw)))
	req.Header.Set("Authorization", "Bearer fixture")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, req)
	if w.Code < 400 {
		t.Fatal("acknowledgement write unexpectedly succeeded")
	}
	assertIntegrationBytes(t, s.Lib.Root, target, "restored")
	refreshed := false
	for len(messages) > 0 {
		if strings.Contains(string(<-messages), `"type":"notes_changed"`) {
			refreshed = true
		}
	}
	if !refreshed {
		t.Fatal("installed content left invisible after acknowledgement error")
	}
}

func TestFolderRestoreRequiresActiveCourseScope(t *testing.T) {
	s := folderIntegratedServer(t, t.TempDir())
	putFolderIntegration(t, s.Lib.Root, "courses/pilot/course.json", `{"id":"pilot"}`)
	target := "courses/pilot/note.md"
	putFolderIntegration(t, s.Lib.Root, target, "current")
	putFolderIntegration(t, s.Lib.Root, datasync.ConflictDir+"/folder-test/library/"+target, "recovered")
	rows, err := s.folderConflicts(nil, httptest.NewRequest("GET", "/", nil))
	if err != nil {
		t.Fatal(err)
	}
	id := rows.([]map[string]any)[0]["id"].(string)
	hash, err := fileDigest(filepath.Join(s.Lib.Root, target))
	if err != nil {
		t.Fatal(err)
	}
	s.Data.Disconnect()
	body, _ := json.Marshal(map[string]string{"action": "restore", "expected_hash": hash})
	req := httptest.NewRequest("POST", "/api/sync/folder/conflicts/"+id+"/resolve", strings.NewReader(string(body)))
	req.Header.Set("Authorization", "Bearer fixture")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, req)
	if w.Code < 400 {
		t.Fatal("disconnected scope allowed restoration")
	}
	assertIntegrationBytes(t, s.Lib.Root, target, "current")
}
