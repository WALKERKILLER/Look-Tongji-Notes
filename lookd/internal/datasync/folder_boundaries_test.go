package datasync

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFolderReenabledScopeKeepsLocalEdits(t *testing.T) {
	for _, mode := range []string{"media", "course"} {
		t.Run(mode, func(t *testing.T) {
			remote := t.TempDir()
			a, ar := folderFixture(t)
			b, br := folderFixture(t)
			rel := "courses/pilot/video.mp4"
			writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			writeFolderTest(t, ar, "courses/other/course.json", `{"id":"other"}`)
			writeFolderTest(t, ar, rel, "first")
			configureTest(t, a, remote)
			configureTest(t, b, remote)
			runFolderTest(t, a)
			runFolderTest(t, b)
			writeFolderTest(t, ar, rel, "second")
			runFolderTest(t, a)
			runFolderTest(t, b)
			settings := Settings{Kind: "folder", LocalFolder: remote, CourseIDs: []string{"local-pilot"}, Media: true}
			if mode == "media" {
				settings.Media = false
			} else {
				settings.CourseIDs = []string{"other"}
			}
			if _, err := a.Configure(context.Background(), settings); err != nil {
				t.Fatal(err)
			}
			runFolderTest(t, a)
			writeFolderTest(t, ar, rel, "offline edit while excluded")
			configureTest(t, a, remote)
			runFolderTest(t, a)
			runFolderTest(t, b)
			runFolderTest(t, a)
			assertFolderBytes(t, ar, rel, "offline edit while excluded")
			assertFolderBytes(t, br, rel, "offline edit while excluded")
		})
	}
}

func TestFolderLibraryNamesDoNotChangeTheirRoot(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	for _, rel := range []string{"courses/pilot/metadata.json", "courses/pilot/assistant/notes.md"} {
		writeFolderTest(t, ar, rel, `{"text":"ordinary material"}`)
	}
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	for _, rel := range []string{"courses/pilot/metadata.json", "courses/pilot/assistant/notes.md"} {
		assertFolderBytes(t, br, rel, `{"text":"ordinary material"}`)
	}
}

func TestFolderApplyRejectsChangedRootsAndCancellation(t *testing.T) {
	for _, mode := range []string{"missing-library", "replaced-library", "replaced-data", "cancel"} {
		t.Run(mode, func(t *testing.T) {
			remote := t.TempDir()
			a, ar := folderFixture(t)
			b, br := folderFixture(t)
			writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			writeFolderTest(t, ar, "courses/pilot/note.md", "incoming")
			configureTest(t, a, remote)
			configureTest(t, b, remote)
			runFolderTest(t, a)
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			root := br
			if mode == "replaced-data" {
				root = b.Roots.Data
			}
			b.ApplyFiles = func(apply func() error) error {
				if mode == "cancel" {
					cancel()
				} else {
					if err := os.Rename(root, root+"-offline"); err != nil {
						t.Fatal(err)
					}
					if strings.HasPrefix(mode, "replaced") {
						if err := os.Mkdir(root, 0700); err != nil {
							t.Fatal(err)
						}
					}
				}
				return apply()
			}
			_, err := b.Sync(ctx)
			if err == nil {
				t.Fatal("unsafe apply succeeded")
			}
			if mode == "cancel" && !errors.Is(err, context.Canceled) {
				t.Fatal(err)
			}
			if _, err := os.Stat(filepath.Join(br, "courses/pilot/note.md")); !os.IsNotExist(err) {
				t.Fatal("incoming file installed after root change/cancel")
			}
			if mode == "missing-library" {
				if _, err := os.Stat(root); !os.IsNotExist(err) {
					t.Fatal("missing root recreated")
				}
			}
			if mode == "replaced-data" {
				entries, err := os.ReadDir(root)
				if err != nil || len(entries) != 0 {
					t.Fatalf("wrote into replacement data root: %v %v", entries, err)
				}
			}
		})
	}
}

func TestFolderLateEditPreflightsWholeBatch(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	for _, name := range []string{"aaa.md", "zzz.md"} {
		writeFolderTest(t, ar, "courses/pilot/"+name, "initial")
	}
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	runFolderTest(t, a)
	for _, name := range []string{"aaa.md", "zzz.md"} {
		writeFolderTest(t, ar, "courses/pilot/"+name, "incoming")
	}
	runFolderTest(t, a)
	b.ApplyFiles = func(apply func() error) error {
		writeFolderTest(t, br, "courses/pilot/zzz.md", "unsynced local save")
		return apply()
	}
	if _, err := b.Sync(context.Background()); err == nil {
		t.Fatal("late edit accepted")
	}
	assertFolderBytes(t, br, "courses/pilot/aaa.md", "initial")
	assertFolderBytes(t, br, "courses/pilot/zzz.md", "unsynced local save")
}

func TestFolderUnreadableBaseDoesNotResetHistory(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	configureTest(t, a, remote)
	runFolderTest(t, a)
	paths, err := filepath.Glob(filepath.Join(a.Roots.Data, "folder-base-*.json"))
	if err != nil || len(paths) != 1 {
		t.Fatal(paths, err)
	}
	if err := os.Remove(paths[0]); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(paths[0], 0700); err != nil {
		t.Fatal(err)
	}
	writeFolderTest(t, ar, "courses/pilot/new.md", "must not publish")
	manifest := filepath.Join(remote, "devices", a.cfg.DeviceID+".json")
	before, _ := os.ReadFile(manifest)
	if _, err := a.Sync(context.Background()); err == nil {
		t.Fatal("unreadable base accepted")
	}
	after, _ := os.ReadFile(manifest)
	if string(before) != string(after) {
		t.Fatal("history read failure still published manifest")
	}
}

func TestFolderConcurrentNewChatsKeepBothSessions(t *testing.T) {
	a, b, _, _, _ := folderChatFixture(t)
	for i, s := range []*Service{a, b} {
		id := []string{"new-a", "new-b"}[i]
		meta := `{"s1":{"course_id":"local-pilot","kind":"course"},"` + id + `":{"course_id":"local-pilot","kind":"course"}}`
		writeFolderTest(t, s.Roots.Data, "agent/sessions-meta.json", meta)
		writeFolderTest(t, s.Roots.Data, "agent/sessions/"+id+".jsonl", `{"type":"session","id":"`+id+`"}`+"\n")
	}
	runFolderTest(t, a)
	runFolderTest(t, b)
	runFolderTest(t, a)
	for _, s := range []*Service{a, b} {
		for _, id := range []string{"new-a", "new-b"} {
			assertFolderBytes(t, s.Roots.Data, "agent/sessions/"+id+".jsonl", `{"type":"session","id":"`+id+`"}`+"\n")
		}
	}
}

func TestFolderManifestLimitRejectsOversizedDocument(t *testing.T) {
	root, err := os.OpenRoot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	f, err := root.Create("manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = f.WriteString("{}"); err != nil {
		t.Fatal(err)
	}
	if err = f.Truncate(folderRecordLimit + 1); err != nil {
		t.Fatal(err)
	}
	f.Close()
	if _, err = (&folderStorage{root: root}).get(context.Background(), "manifest.json"); err == nil {
		t.Fatal("oversized manifest silently truncated")
	}
}

func TestFolderEqualClocksAndConcurrentDeletesConverge(t *testing.T) {
	for _, name := range []string{"equal-clocks", "concurrent-deletes"} {
		t.Run(name, func(t *testing.T) {
			a := folderEntry{Entry: Entry{Hash: "a", MTime: 10}, Clock: map[string]uint64{"a": 1}}
			b := folderEntry{Entry: Entry{Hash: "b", MTime: 20}, Clock: map[string]uint64{"a": 1}}
			if name == "concurrent-deletes" {
				a.Hash = ""
				b.Hash = ""
				a.Deleted = 10
				b.Deleted = 20
				b.Clock = map[string]uint64{"b": 1}
			}
			ab, ba := combine(a, b), combine(b, a)
			x, _ := json.Marshal(ab)
			y, _ := json.Marshal(ba)
			if string(x) != string(y) {
				t.Fatalf("merge depends on manifest order: %s vs %s", x, y)
			}
			again, _ := json.Marshal(combine(ab, ab))
			if string(x) != string(again) {
				t.Fatalf("repeated merge changed state: %s vs %s", x, again)
			}
		})
	}
}
