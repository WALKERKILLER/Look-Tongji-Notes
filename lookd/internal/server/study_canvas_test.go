package server

import (
	"context"
	"encoding/json"
	"lookstudio/lookd/internal/agent"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestStudyCanvasAuthenticatedRoutes(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, e := store.Open(filepath.Join(root, "library.db"))
	if e != nil {
		t.Fatal(e)
	}
	defer st.Close()
	st.UpsertCourse(ctx, store.Course{ID: "c", Title: "演示"})
	st.UpsertLectures(ctx, []store.Lecture{{ID: "l", CourseID: "c", Title: "第一课"}, {ID: "other", CourseID: "c", Title: "另一课"}})
	lib, e := library.Open(root, st)
	if e != nil {
		t.Fatal(e)
	}
	s := &Server{Token: "fixture", St: st, Lib: lib, Bus: events.New(), Agent: &agent.Supervisor{}}
	h := s.Handler()
	call := func(method, p, body, token string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, p, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	p := "/api/lectures/l/study-canvas"
	if w := call("GET", p, "", "wrong"); w.Code != 401 {
		t.Fatal(w.Code)
	}
	w := call("GET", p, "", "fixture")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var d library.StudyDocument
	if e = json.Unmarshal(w.Body.Bytes(), &d); e != nil {
		t.Fatal(e)
	}
	w = call("POST", p+"/assets?name=notes.md", "# study\nlocal text", "fixture")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var imported library.StudyImport
	json.Unmarshal(w.Body.Bytes(), &imported)
	d.Objects = append(d.Objects, imported.Objects...)
	b, _ := json.Marshal(d)
	if w = call("PUT", p, string(b), "fixture"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	q, _ := json.Marshal(library.StudyContextRequest{Revision: 1, Objects: []string{imported.Objects[0].ID}, Selection: library.StudySelection{ObjectID: imported.Objects[0].ID, Start: 8, End: 13}})
	if w = call("POST", p+"/context", string(q), "wrong"); w.Code != 401 {
		t.Fatal("context auth", w.Code)
	}
	w = call("POST", p+"/context", string(q), "fixture")
	var scope library.StudyContext
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &scope) != nil || len(scope.Sources) != 1 || scope.Sources[0].Text != "local" {
		t.Fatal("actual selection", w.Code, w.Body.String())
	}
	if w = call("POST", "/api/lectures/other/study-canvas/context", string(q), "fixture"); w.Code != 409 {
		t.Fatal("cross-lecture context", w.Code)
	}
	if w = call("POST", p+"/context", `{"revision":0}`, "fixture"); w.Code != 409 {
		t.Fatal("stale context", w.Code)
	}
	if w = call("PUT", p, string(b), "fixture"); w.Code != 409 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = call("PUT", p, `{"broken":`, "fixture"); w.Code != 400 {
		t.Fatal(w.Code)
	}
	if w = call("POST", p+"/assets?path=../../outside", "", "fixture"); w.Code != 400 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = call("POST", "/api/lectures/other/study-canvas/assets?path="+imported.Objects[0].Source, "", "fixture"); w.Code != 400 {
		t.Fatal("cross-lecture asset accepted", w.Code, w.Body.String())
	}
	if w = call("GET", "/api/lectures/missing/study-canvas", "", "fixture"); w.Code != 404 {
		t.Fatal(w.Code)
	}

	conversation := p + "/conversations/chat"
	if w = call("GET", conversation, "", "wrong"); w.Code != 401 {
		t.Fatal("chat auth", w.Code)
	}
	if w = call("PUT", conversation, `{"version":1,"id":"chat","revision":0,"draft":"my draft","query":{"objects":[]},"turns":[{"id":"one","question":"q","answer":"a","state":"done","context_key":"scope"}]}`, "fixture"); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w = call("GET", conversation, "", "fixture"); w.Code != 200 || !strings.Contains(w.Body.String(), "my draft") {
		t.Fatal("chat restore", w.Body.String())
	}
	if w = call("GET", "/api/lectures/other/study-canvas/conversations/chat", "", "fixture"); w.Code != 200 || strings.Contains(w.Body.String(), "my draft") {
		t.Fatal("chat scope", w.Body.String())
	}
	if w = call("POST", p+"/media", `{"object_id":"lecture","from_ms":0,"to_ms":180001}`, "fixture"); w.Code != 400 {
		t.Fatal("unbounded media request", w.Code)
	}
	w = call("GET", "/api/lectures/other/study-canvas", "", "fixture")
	if w.Code != 200 || strings.Contains(w.Body.String(), "local text") {
		t.Fatal("lecture state leaked", w.Code, w.Body.String())
	}
}
