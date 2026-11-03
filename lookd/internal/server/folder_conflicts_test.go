package server

import (
	"context"
	"encoding/json"
	"lookstudio/lookd/internal/datasync"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFolderConflictCanBeReadAndAcknowledgedWithoutDeletingCopy(t *testing.T) {
	root := t.TempDir()
	data := t.TempDir()
	st, e := store.Open(filepath.Join(root, "library.db"))
	if e != nil {
		t.Fatal(e)
	}
	defer st.Close()
	lib, e := library.Open(root, st)
	if e != nil {
		t.Fatal(e)
	}
	s := &Server{St: st, Lib: lib, Data: &datasync.Service{Roots: datasync.Roots{Library: root, Data: data}}, Bus: events.New(), Ctx: context.Background()}
	p := filepath.Join(root, datasync.ConflictDir, "folder-test", "library", "courses", "速成", "note.md")
	os.MkdirAll(filepath.Dir(p), 0700)
	os.WriteFile(p, []byte("kept draft"), 0600)
	rows, e := s.folderConflicts(nil, httptest.NewRequest("GET", "/", nil))
	if e != nil {
		t.Fatal(e)
	}
	list := rows.([]map[string]any)
	if len(list) != 1 {
		t.Fatal(list)
	}
	id := list[0]["id"].(string)
	req := httptest.NewRequest("GET", "/", nil)
	req.SetPathValue("conflict", id)
	v, e := s.folderConflict(nil, req)
	if e != nil {
		t.Fatal(e)
	}
	if v.(map[string]any)["body"] != "kept draft" {
		t.Fatal(v)
	}
	body, _ := json.Marshal(map[string]string{"action": "keep", "expected_hash": ""})
	req = httptest.NewRequest("POST", "/", strings.NewReader(string(body)))
	req.SetPathValue("conflict", id)
	if _, e = s.folderConflict(nil, req); e != nil {
		t.Fatal(e)
	}
	rows, e = s.folderConflicts(nil, req)
	if e != nil || len(rows.([]map[string]any)) != 0 {
		t.Fatal(rows, e)
	}
	if _, e = os.Stat(p); e != nil {
		t.Fatal("acknowledgement deleted recovery copy")
	}
}

func TestCanvasReplacementRecoveryDoesNotRequireConflictChoice(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	st.UpsertCourse(ctx, store.Course{ID: "c", Title: "速成"})
	st.UpsertLectures(ctx, []store.Lecture{{ID: "l", CourseID: "c", Title: "第一课"}})
	lib, err := library.Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = lib.StudyCanvas(ctx, "l"); err != nil {
		t.Fatal(err)
	}
	s := &Server{Token: "fixture", St: st, Lib: lib, Bus: events.New(), Ctx: ctx}
	body := `{"version":3,"revision":4,"strokes":[]}`
	r := httptest.NewRequest("POST", "/api/lectures/l/study-canvas/draft", strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer fixture")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	found := false
	err = filepath.WalkDir(filepath.Join(root, datasync.TrashDir), func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() {
			b, e := os.ReadFile(p)
			if e != nil {
				return e
			}
			found = found || string(b) == body
		}
		return nil
	})
	if err != nil || !found {
		t.Fatal("replacement has no byte-identical recovery copy", err)
	}
	rows, err := s.folderConflicts(nil, r)
	if err != nil || len(rows.([]map[string]any)) != 0 {
		t.Fatal("recovery incorrectly requires a conflict choice", rows, err)
	}
}
