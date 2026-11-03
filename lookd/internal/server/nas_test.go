package server

import (
	"context"
	"encoding/json"
	"lookstudio/lookd/internal/nasbridge"
	"lookstudio/lookd/internal/store"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestNASReportsUseManifestAndAvailableIndex(t *testing.T) {
	root := t.TempDir()
	os.WriteFile(filepath.Join(root, "自动做作业状态.md"), []byte("| 课程 | 作业 | 状态 | 成果 |\n| C | Lab3 | ready | [[C/4.课程作业/Lab3/报告.md\\|报告]] [[C/4.课程作业/Lab3/报告.pdf]] |"), 0600)
	original := map[string]any{"course": "C", "name": "Lab3", "generation_state": "ready", "submission_state": "unconfirmed"}
	d := map[string]any{"jobs": []any{original}}
	attachNASReports(d, []nasbridge.File{{ID: "report", Path: "C/4.课程作业/Lab3/报告.md"}}, root)
	j := d["jobs"].([]any)[0].(map[string]any)
	refs := j["reports"].([]map[string]any)
	if len(refs) != 2 || refs[0]["available"] != true || refs[1]["available"] != false {
		t.Fatal(refs)
	}
	if original["reports"] != nil || j["submission_state"] != "unconfirmed" {
		t.Fatal("mutated cached snapshot or submission")
	}
	outside := t.TempDir()
	os.WriteFile(filepath.Join(outside, "manifest.md"), []byte("| C | Lab3 | ready | [[secret.md]] |"), 0600)
	os.Remove(filepath.Join(root, "自动做作业状态.md"))
	os.Symlink(filepath.Join(outside, "manifest.md"), filepath.Join(root, "自动做作业状态.md"))
	clean := map[string]any{"jobs": []any{original}}
	attachNASReports(clean, nil, root)
	if clean["jobs"].([]any)[0].(map[string]any)["reports"] != nil {
		t.Fatal("outside manifest read")
	}
}

func TestNASHTMLIsInertAndUnknownFileDenied(t *testing.T) {
	root := t.TempDir()
	rel := "C/3.课程资料/page.html"
	os.MkdirAll(filepath.Join(root, "C/3.课程资料"), 0700)
	os.WriteFile(filepath.Join(root, rel), []byte("<script>fetch('/studio/bootstrap')</script>"), 0600)
	s := &Server{}
	s.nasOnce.Do(func() { s.nasClient = &nasbridge.Bridge{Root: root} })
	r := httptest.NewRequest("GET", "/api/nas/files/id", nil)
	r.SetPathValue("id", nasbridge.FileID(rel))
	w := httptest.NewRecorder()
	if _, err := s.nasFile(w, r); err != nil {
		t.Fatal(err)
	}
	if w.Header().Get("Content-Type") != "text/plain; charset=utf-8" || w.Header().Get("Content-Security-Policy") != "sandbox; default-src 'none'" {
		t.Fatal(w.Header())
	}
	r.SetPathValue("id", "../../.ssh/id_rsa")
	if _, err := s.nasFile(httptest.NewRecorder(), r); err == nil {
		t.Fatal("outside file accepted")
	}
}

func TestNASCalendarDeduplicatesAndPreservesMidnight(t *testing.T) {
	t.Setenv("LOOK_PLATFORM", "fudan")
	root := t.TempDir()
	st, err := store.Open(filepath.Join(t.TempDir(), "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	st.PutSettings(context.Background(), map[string]json.RawMessage{"nas.course_links": json.RawMessage(`{"CS OS":"40309"}`)})
	event := "---\ntitle: \"HW\"\ncourse: \"CS OS\"\ndue: \"2026-10-26T00:00:00+08:00\"\ncompleted: false\ngenerated_key: abc\n---\nhttps://elearning.fudan.edu.cn/courses/123/assignments/456\n"
	os.WriteFile(filepath.Join(root, "a.md"), []byte(event), 0600)
	os.WriteFile(filepath.Join(root, "duplicate.md"), []byte(event), 0600)
	s := &Server{St: st, Sess: nativeFudanFixture(t)}
	s.nasOnce.Do(func() { s.nasClient = &nasbridge.Bridge{Calendar: root} })
	q := store.ScheduleQuery{CourseID: "40309", From: "2026-10-26", To: "2026-10-26"}
	out := s.nasSchedule(context.Background(), q, nil)
	if len(out) != 1 || out[0].DueTime != "00:00" || out[0].DueDate != "2026-10-26" {
		t.Fatal(out)
	}
	out = s.nasSchedule(context.Background(), q, []store.ScheduleItem{{ID: "canvas:456", Source: "canvas"}})
	if len(out) != 1 || out[0].Source != "canvas" {
		t.Fatal("duplicated Canvas", out)
	}
	q.CourseID = "another"
	if len(s.nasSchedule(context.Background(), q, nil)) != 0 {
		t.Fatal("course scope lost")
	}
	for _, method := range []string{"PATCH", "DELETE"} {
		r := httptest.NewRequest(method, "/api/schedule/nas:abc", nil)
		r.SetPathValue("id", "nas:abc")
		var err error
		if method == "PATCH" {
			_, err = s.patchSchedule(httptest.NewRecorder(), r)
		} else {
			_, err = s.deleteSchedule(httptest.NewRecorder(), r)
		}
		if err == nil {
			t.Fatal("NAS calendar writable")
		}
	}
}
