package datasync

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUnavailableLibraryDoesNotPublishDeletions(t *testing.T) {
	for _, kind := range []string{"webdav", "folder"} {
		t.Run(kind, func(t *testing.T) {
			a, b := newDevice(t), newDevice(t)
			rel := "library/courses/pilot/note.md"
			a.write(t, "library/courses/pilot/course.json", `{"id":"local-pilot"}`, 0)
			a.write(t, rel, "keep on both devices", 0)
			if kind == "webdav" {
				srv := davServer(t)
				connect(t, a, srv.URL, true)
				connect(t, b, srv.URL, true)
			} else {
				remote := t.TempDir()
				configureTest(t, a.Service, remote)
				configureTest(t, b.Service, remote)
			}
			a.sync(t)
			b.sync(t)
			a.sync(t)
			root := a.Roots.Library
			if err := os.Rename(root, root+"-unmounted"); err != nil {
				t.Fatal(err)
			}
			if _, err := a.Sync(context.Background()); err == nil || !strings.Contains(err.Error(), root) {
				t.Fatalf("missing root must fail with its path: %v", err)
			}
			b.sync(t)
			if b.read(rel) != "keep on both devices" {
				t.Fatal("unmounted root deleted peer data")
			}
			if err := os.Rename(root+"-unmounted", root); err != nil {
				t.Fatal(err)
			}
			a.sync(t)
			b.sync(t)
			if a.read(rel) != b.read(rel) || a.read(rel) != "keep on both devices" {
				t.Fatal("remount did not recover")
			}
		})
	}
}

func TestScanRootsDistinguishEmptyMissingAndNonDirectory(t *testing.T) {
	for _, data := range []bool{false, true} {
		r := Roots{Library: t.TempDir(), Data: t.TempDir()}
		scan := func() error {
			if data {
				_, e := r.ScanData()
				return e
			}
			_, e := r.ScanLibrary(true)
			return e
		}
		if err := scan(); err != nil {
			t.Fatal("fresh empty root refused", err)
		}
		root := r.Library
		if data {
			root = r.Data
		}
		if err := os.Remove(root); err != nil {
			t.Fatal(err)
		}
		if err := scan(); err == nil {
			t.Fatal("missing root accepted")
		}
		if err := os.WriteFile(root, []byte("not a directory"), 0600); err != nil {
			t.Fatal(err)
		}
		if err := scan(); err == nil {
			t.Fatal("file root accepted")
		}
	}
}

func folderChatFixture(t *testing.T) (*Service, *Service, string, string, string) {
	t.Helper()
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, _ := folderFixture(t)
	body := "{\"type\":\"session\",\"id\":\"s1\"}\n{\"id\":\"message\",\"text\":\"keep\"}\n"
	writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	writeFolderTest(t, a.Roots.Data, "agent/sessions-meta.json", `{"s1":{"course_id":"local-pilot","kind":"course"}}`)
	writeFolderTest(t, a.Roots.Data, "agent/sessions/old_s1.jsonl", body)
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	// The server indexes received metadata after DataArrived; model that persisted result.
	writeFolderTest(t, b.Roots.Data, "agent/sessions-meta.json", `{"s1":{"course_id":"local-pilot","kind":"course"}}`)
	runFolderTest(t, a)
	runFolderTest(t, b)
	return a, b, remote, "agent/sessions/old_s1.jsonl", body
}

func TestFolderSessionRenameConverges(t *testing.T) {
	for _, newName := range []string{"aaa_s1.jsonl", "zzz_s1.jsonl"} {
		t.Run(newName, func(t *testing.T) {
			a, b, _, old, body := folderChatFixture(t)
			dest := "agent/sessions/" + newName
			if err := os.Rename(filepath.Join(a.Roots.Data, old), filepath.Join(a.Roots.Data, dest)); err != nil {
				t.Fatal(err)
			}
			for i := 0; i < 3; i++ {
				runFolderTest(t, a)
				runFolderTest(t, b)
			}
			for _, s := range []*Service{a, b} {
				assertFolderBytes(t, s.Roots.Data, dest, body)
				if _, err := os.Stat(filepath.Join(s.Roots.Data, old)); !os.IsNotExist(err) {
					t.Fatal("rename retained old live file")
				}
			}
		})
	}
}

func TestFolderLocalReassignmentDoesNotDeleteSessionOrBlock(t *testing.T) {
	a, b, _, old, body := folderChatFixture(t)
	moved := `{"s1":{"course_id":"other","kind":"course"}}`
	writeFolderTest(t, a.Roots.Data, "agent/sessions-meta.json", moved)
	for i := 0; i < 3; i++ {
		runFolderTest(t, a)
		runFolderTest(t, b)
	}
	assertFolderBytes(t, a.Roots.Data, old, body)
	assertFolderBytes(t, a.Roots.Data, "agent/sessions-meta.json", moved)
	if _, err := os.Stat(filepath.Join(a.Roots.Data, "agent/course-sessions/local-pilot.json")); !os.IsNotExist(err) {
		t.Fatal("empty export cache retained")
	}
	if _, err := os.Stat(filepath.Join(b.Roots.Data, old)); !os.IsNotExist(err) {
		t.Fatal("old course membership not released on peer")
	}
}

func TestFolderUnrelatedMalformedGlobalsDoNotBlock(t *testing.T) {
	a, b, _, _, body := folderChatFixture(t)
	for _, s := range []*Service{a, b} {
		writeFolderTest(t, s.Roots.Library, "quizzes/notes.json", `[]`)
		writeFolderTest(t, s.Roots.Data, "agent/sessions/broken.jsonl", "not a session")
		writeFolderTest(t, s.Roots.Data, "agent/course-sessions/unselected.json", "not json")
	}
	for i := 0; i < 2; i++ {
		runFolderTest(t, a)
		runFolderTest(t, b)
	}
	assertFolderBytes(t, b.Roots.Data, "agent/sessions/old_s1.jsonl", body)
	for _, s := range []*Service{a, b} {
		assertFolderBytes(t, s.Roots.Library, "quizzes/notes.json", `[]`)
		assertFolderBytes(t, s.Roots.Data, "agent/sessions/broken.jsonl", "not a session")
	}
}

func TestFolderMalformedTrackedFilesStopWithPath(t *testing.T) {
	for _, kind := range []string{"quiz", "session"} {
		t.Run(kind, func(t *testing.T) {
			a, b, remote, old, body := folderChatFixture(t)
			root, path, bad := a.Roots.Data, old, "broken"
			if kind == "quiz" {
				root, path, bad = a.Roots.Library, "quizzes/q.json", `[]`
				writeFolderTest(t, root, path, `{"quiz":{"course_id":"local-pilot"},"attempts":[]}`)
				runFolderTest(t, a)
				runFolderTest(t, b)
			}
			manifest := filepath.Join(remote, "devices", a.cfg.DeviceID+".json")
			before, err := os.ReadFile(manifest)
			if err != nil {
				t.Fatal(err)
			}
			writeFolderTest(t, root, path, bad)
			if _, err := a.Sync(context.Background()); err == nil || !strings.Contains(err.Error(), filepath.Join(root, path)) {
				t.Fatalf("missing actionable path: %v", err)
			}
			after, err := os.ReadFile(manifest)
			if err != nil || string(before) != string(after) {
				t.Fatal("bad tracked file published deletion")
			}
			runFolderTest(t, b)
			assertFolderBytes(t, b.Roots.Data, old, body)
		})
	}
}

func TestFolderExportsSeveralCoursesWithoutMixingSessions(t *testing.T) {
	s, root := folderFixture(t)
	meta := map[string]map[string]any{}
	var ids []string
	for _, id := range []string{"c1", "c2", "c3", "c4", "c5", "c6"} {
		ids = append(ids, id)
		meta["session-"+id] = map[string]any{"course_id": id, "kind": "course"}
		writeFolderTest(t, s.Roots.Data, "agent/sessions/"+id+".jsonl", `{"type":"session","id":"session-`+id+`"}`)
	}
	raw, _ := json.Marshal(meta)
	writeFolderTest(t, s.Roots.Data, "agent/sessions-meta.json", string(raw))
	writeFolderTest(t, root, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	// Use the public sync path and inspect the exported manifest's ownership.
	remote := t.TempDir()
	if _, err := s.Configure(context.Background(), Settings{Kind: "folder", LocalFolder: remote, CourseIDs: ids, Media: true}); err != nil {
		t.Fatal(err)
	}
	// Each course needs a stable local directory to establish scope.
	for _, id := range ids {
		writeFolderTest(t, root, "courses/"+id+"/course.json", `{"id":"`+id+`"}`)
	}
	runFolderTest(t, s)
	raw, err := os.ReadFile(filepath.Join(remote, "devices", s.cfg.DeviceID+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var m folderManifest
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	for _, id := range ids {
		if _, ok := m.Files["course-data/"+id+"/assistant/"+id+".jsonl"]; !ok {
			t.Fatal("missing course session", id)
		}
	}
}

func TestMissingPrivateRootIsNotRecreatedByFailedSync(t *testing.T) {
	a := newDevice(t)
	srv := davServer(t)
	connect(t, a, srv.URL, true)
	a.write(t, "data/agent/tasks.json", `[]`, 0)
	a.sync(t)
	root := a.Roots.Data
	if err := os.Rename(root, root+"-unmounted"); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err := a.Sync(context.Background()); err == nil {
			t.Fatal("missing private root accepted")
		}
		if _, err := os.Stat(root); !os.IsNotExist(err) {
			t.Fatal("failed sync recreated an empty root")
		}
	}
	if err := os.Rename(root+"-unmounted", root); err != nil {
		t.Fatal(err)
	}
	a.sync(t)
	if a.read("data/agent/tasks.json") != `[]` {
		t.Fatal("lost private portable data")
	}
}

func TestFolderDuplicateSessionWithoutRenameTombstoneIsRejected(t *testing.T) {
	a, b, remote, old, body := folderChatFixture(t)
	dest := "agent/sessions/new_s1.jsonl"
	if err := os.Rename(filepath.Join(a.Roots.Data, old), filepath.Join(a.Roots.Data, dest)); err != nil {
		t.Fatal(err)
	}
	runFolderTest(t, a)
	editFolderManifest(t, remote, a.cfg.DeviceID, func(m *folderManifest) { delete(m.Files, "course-data/local-pilot/assistant/old_s1.jsonl") })
	if _, err := b.Sync(context.Background()); err == nil {
		t.Fatal("duplicate ID without explicit old-path deletion accepted")
	}
	assertFolderBytes(t, b.Roots.Data, old, body)
	if _, err := os.Stat(filepath.Join(b.Roots.Data, dest)); !os.IsNotExist(err) {
		t.Fatal("partially installed ambiguous rename")
	}
}
