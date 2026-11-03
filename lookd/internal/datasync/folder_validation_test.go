package datasync

import (
	"context"
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func editFolderManifest(t *testing.T, remote, device string, edit func(*folderManifest)) {
	t.Helper()
	p := filepath.Join(remote, "devices", device+".json")
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	var m folderManifest
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	edit(&m)
	b, err = json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, b, 0600); err != nil {
		t.Fatal(err)
	}
}
func assertFolderBytes(t *testing.T, root, path, want string) {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, path))
	if err != nil || string(b) != want {
		t.Fatalf("%s changed: %q, %v", path, b, err)
	}
}
func TestFolderRejectsSharedDestinationOwnership(t *testing.T) {
	for _, kind := range []string{"quiz", "chat", "unclassified-chat", "metadata", "delete-quiz", "delete-chat"} {
		t.Run(kind, func(t *testing.T) {
			remote := t.TempDir()
			a, ar := folderFixture(t)
			b, br := folderFixture(t)
			writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			destRoot, dest, original := br, "quizzes/shared.json", `{"quiz":{"course_id":"other"},"attempts":[]}`
			if strings.Contains(kind, "quiz") {
				writeFolderTest(t, ar, dest, `{"quiz":{"course_id":"local-pilot"},"attempts":[]}`)
			} else {
				destRoot, dest, original = b.Roots.Data, "agent/sessions/shared.jsonl", "{\"type\":\"session\",\"id\":\"shared\"}\n{\"id\":\"old\"}\n"
				writeFolderTest(t, a.Roots.Data, "agent/sessions-meta.json", `{"shared":{"course_id":"local-pilot","kind":"course"}}`)
				writeFolderTest(t, a.Roots.Data, "agent/sessions/shared.jsonl", "{\"type\":\"session\",\"id\":\"shared\"}\n{\"id\":\"new\"}\n")
				if kind != "unclassified-chat" {
					writeFolderTest(t, b.Roots.Data, "agent/sessions-meta.json", `{"shared":{"course_id":"other","kind":"course"}}`)
				}
			}
			writeFolderTest(t, destRoot, dest, original)
			configureTest(t, a, remote)
			configureTest(t, b, remote)
			runFolderTest(t, a)
			if strings.HasPrefix(kind, "delete-") || kind == "metadata" {
				editFolderManifest(t, remote, a.cfg.DeviceID, func(m *folderManifest) {
					for p, v := range m.Files {
						if strings.Contains(p, "/quizzes/") || strings.Contains(p, "/assistant/") {
							if kind == "metadata" {
								delete(m.Files, p)
							} else {
								v.Hash = ""
								v.Size = 0
								v.Deleted = 1
								m.Files[p] = v
							}
						}
					}
				})
			}
			if _, err := b.Sync(context.Background()); err == nil {
				t.Fatal("accepted another course's global destination")
			}
			assertFolderBytes(t, destRoot, dest, original)
			if _, err := os.Stat(filepath.Join(br, "courses/pilot/course.json")); !os.IsNotExist(err) {
				t.Fatal("partial import before ownership rejection")
			}
			if kind != "quiz" && kind != "delete-quiz" && kind != "unclassified-chat" {
				assertFolderBytes(t, b.Roots.Data, "agent/sessions-meta.json", `{"shared":{"course_id":"other","kind":"course"}}`)
			}
		})
	}
}
func TestFolderRejectsCourseDirectoryTakeover(t *testing.T) {
	for _, body := range []string{`{"id":"other"}`, `invalid`} {
		t.Run(body, func(t *testing.T) {
			remote := t.TempDir()
			a, ar := folderFixture(t)
			b, br := folderFixture(t)
			writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			writeFolderTest(t, ar, "courses/pilot/note.md", "remote")
			writeFolderTest(t, br, "courses/pilot/course.json", body)
			writeFolderTest(t, br, "courses/pilot/note.md", "keep")
			configureTest(t, a, remote)
			configureTest(t, b, remote)
			runFolderTest(t, a)
			if _, err := b.Sync(context.Background()); err == nil {
				t.Fatal("accepted another course directory")
			}
			assertFolderBytes(t, br, "courses/pilot/course.json", body)
			assertFolderBytes(t, br, "courses/pilot/note.md", "keep")
		})
	}
}
func TestFolderRejectsOversizedGenerationBeforeObjectRead(t *testing.T) {
	for _, tc := range []struct {
		name        string
		sizes       []int64
		alternative bool
	}{
		{"negative", []int64{-1}, false}, {"overflow", []int64{math.MaxInt64}, false}, {"object", []int64{(4 << 30) + 1}, false}, {"total", []int64{4 << 30, 4 << 30, 1}, false}, {"alternative", []int64{(4 << 30) + 1}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			remote := t.TempDir()
			a, ar := folderFixture(t)
			b, br := folderFixture(t)
			writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			configureTest(t, a, remote)
			configureTest(t, b, remote)
			runFolderTest(t, a)
			editFolderManifest(t, remote, a.cfg.DeviceID, func(m *folderManifest) {
				for i, size := range tc.sizes {
					e := Entry{Hash: strings.Repeat(string(rune('a'+i)), 64), Size: size}
					p := "library/courses/pilot/video" + string(rune('a'+i)) + ".mp4"
					if tc.alternative {
						v := m.Files["library/courses/pilot/course.json"]
						v.Alternatives = []Entry{e}
						m.Files["library/courses/pilot/course.json"] = v
					} else {
						m.Files[p] = folderEntry{Entry: e, Clock: map[string]uint64{"remote": 1}}
					}
				}
			})
			_, err := b.Sync(context.Background())
			if err == nil || (!strings.Contains(err.Error(), "大小") && !strings.Contains(err.Error(), "暂存")) {
				t.Fatalf("must reject budget before opening missing object, got %v", err)
			}
			if _, err := os.Stat(filepath.Join(br, "courses/pilot/course.json")); !os.IsNotExist(err) {
				t.Fatal("partial generation installed")
			}
			staging, _ := filepath.Glob(filepath.Join(b.Roots.Data, "folder-stage-*"))
			if len(staging) != 0 {
				t.Fatal("staging leaked")
			}
		})
	}
}
func TestFolderCourseRecordsRoundTrip(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	quiz := `{"quiz":{"course_id":"local-pilot"},"attempts":[]}`
	chat := "{\"type\":\"session\",\"id\":\"shared\"}\n{\"id\":\"first\"}\n"
	writeFolderTest(t, ar, "quizzes/shared.json", quiz)
	writeFolderTest(t, a.Roots.Data, "agent/sessions-meta.json", `{"shared":{"course_id":"local-pilot","kind":"course"}}`)
	writeFolderTest(t, a.Roots.Data, "agent/sessions/shared.jsonl", chat)
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	runFolderTest(t, b)
	assertFolderBytes(t, br, "quizzes/shared.json", quiz)
	assertFolderBytes(t, b.Roots.Data, "agent/sessions/shared.jsonl", chat)
	writeFolderTest(t, a.Roots.Data, "agent/sessions/shared-other.jsonl", "{\"type\":\"session\",\"id\":\"other\"}\n")
	runFolderTest(t, a)
	runFolderTest(t, b)
	if _, err := os.Stat(filepath.Join(b.Roots.Data, "agent/sessions/shared-other.jsonl")); !os.IsNotExist(err) {
		t.Fatal("filename substring exported another chat")
	}
}

func TestFolderScanFailureDoesNotPublishDeletion(t *testing.T) {
	for _, blockedKind := range []string{"directory", "file"} {
		t.Run(blockedKind, func(t *testing.T) {
			remote := t.TempDir()
			a, ar := folderFixture(t)
			b, br := folderFixture(t)
			writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			writeFolderTest(t, ar, "courses/pilot/notes/note.md", "keep")
			configureTest(t, a, remote)
			configureTest(t, b, remote)
			runFolderTest(t, a)
			runFolderTest(t, b)
			manifest := filepath.Join(remote, "devices", a.cfg.DeviceID+".json")
			before, err := os.ReadFile(manifest)
			if err != nil {
				t.Fatal(err)
			}
			blocked := filepath.Join(ar, "courses/pilot/notes")
			if blockedKind == "file" {
				blocked = filepath.Join(blocked, "note.md")
				writeFolderTest(t, ar, "courses/pilot/notes/note.md", "new size forces rehash")
			}
			if err := os.Chmod(blocked, 0000); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { os.Chmod(blocked, 0700) })
			if blockedKind == "directory" {
				if _, err := os.ReadDir(blocked); err == nil {
					t.Skip("filesystem/user does not enforce directory read permissions")
				}
			} else if f, err := os.Open(blocked); err == nil {
				f.Close()
				t.Skip("filesystem/user does not enforce file read permissions")
			}
			if _, err := a.Sync(context.Background()); err == nil {
				t.Fatal("incomplete scan published as deletions")
			}
			after, err := os.ReadFile(manifest)
			if err != nil || string(before) != string(after) {
				t.Fatal("failed scan changed published manifest", err)
			}
			runFolderTest(t, b)
			assertFolderBytes(t, br, "courses/pilot/notes/note.md", "keep")
		})
	}
}

func TestFolderTransferBudgetBoundaries(t *testing.T) {
	a := Entry{Hash: strings.Repeat("a", 64), Size: 4 << 30}
	b := Entry{Hash: strings.Repeat("b", 64), Size: 4 << 30}
	entries := map[string]folderEntry{"a": {Entry: a}, "b": {Entry: b}, "alias": {Entry: a, Alternatives: []Entry{a}}}
	if err := validateFolderTransfer(entries, nil); err != nil {
		t.Fatal("exact budget or shared hash rejected", err)
	}
	entries["extra"] = folderEntry{Entry: Entry{Hash: strings.Repeat("c", 64), Size: 1}}
	if err := validateFolderTransfer(entries, nil); err == nil {
		t.Fatal("one byte beyond budget accepted")
	}
	if err := validateFolderTransfer(entries, map[string]string{"b": b.Hash}); err != nil {
		t.Fatal("already-local object consumed staging budget", err)
	}
	entries["alias"] = folderEntry{Entry: Entry{Hash: a.Hash, Size: 1}}
	if err := validateFolderTransfer(entries, nil); err == nil {
		t.Fatal("hash aliases disagreed on size")
	}
}

func TestFolderRecordMergeBoundsAllVersions(t *testing.T) {
	root, err := os.OpenRoot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	a := Entry{Hash: strings.Repeat("a", 64), Size: 20 << 20}
	b := Entry{Hash: strings.Repeat("b", 64), Size: 20 << 20}
	entries := map[string]folderEntry{"course-data/pilot/quizzes/q.json": {Entry: a, Alternatives: []Entry{b}}}
	if err := (&Service{}).mergeFolderRecords(context.Background(), &folderStorage{root: root}, entries); err != nil {
		t.Fatal("oversized merge opened objects before checking total", err)
	}
	if len(entries["course-data/pilot/quizzes/q.json"].Alternatives) != 1 {
		t.Fatal("oversized merge dropped conflict versions")
	}
}
