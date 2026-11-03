package datasync

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func folderFixture(t *testing.T) (*Service, string) {
	t.Helper()
	root := t.TempDir()
	data := t.TempDir()
	s := &Service{Roots: Roots{Library: root, Data: data}}
	return s, root
}
func writeFolderTest(t *testing.T, root, name, body string) {
	t.Helper()
	p := filepath.Join(root, filepath.FromSlash(name))
	if e := os.MkdirAll(filepath.Dir(p), 0700); e != nil {
		t.Fatal(e)
	}
	if e := os.WriteFile(p, []byte(body), 0600); e != nil {
		t.Fatal(e)
	}
}
func configureTest(t *testing.T, s *Service, folder string) {
	t.Helper()
	_, e := s.Configure(context.Background(), Settings{Kind: "folder", LocalFolder: folder, CourseIDs: []string{"local-pilot"}, Media: true})
	if e != nil {
		t.Fatal(e)
	}
}
func runFolderTest(t *testing.T, s *Service) Result {
	t.Helper()
	r, e := s.Sync(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	return r
}
func TestFolderSyncPreservesCourseAndConcurrentEdits(t *testing.T) {
	ctx := context.Background()
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	writeFolderTest(t, ar, "courses/速成/course.json", `{"id":"local-pilot","title":"速成"}`)
	writeFolderTest(t, ar, "courses/速成/video.mp4", "video")
	writeFolderTest(t, ar, "courses/速成/note.md", "initial")
	writeFolderTest(t, ar, "courses/别的课/course.json", `{"id":"other"}`)
	writeFolderTest(t, a.Roots.Data, "seal.key", "never exported")
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	if got, e := os.ReadFile(filepath.Join(br, "courses/速成/video.mp4")); e != nil || string(got) != "video" {
		t.Fatalf("media %q %v", got, e)
	}
	if _, e := os.Stat(filepath.Join(br, "courses/别的课")); !os.IsNotExist(e) {
		t.Fatal("unselected course escaped")
	}
	runFolderTest(t, a)
	writeFolderTest(t, ar, "courses/速成/note.md", "edited a")
	writeFolderTest(t, br, "courses/速成/note.md", "edited b")
	runFolderTest(t, a)
	r := runFolderTest(t, b)
	runFolderTest(t, a)
	if r.Conflicts == 0 {
		t.Fatal("independent edits not retained")
	}
	aa, _ := os.ReadFile(filepath.Join(ar, "courses/速成/note.md"))
	bb, _ := os.ReadFile(filepath.Join(br, "courses/速成/note.md"))
	if string(aa) != string(bb) {
		t.Fatal("did not converge")
	}
	os.Remove(filepath.Join(ar, "courses/速成/video.mp4"))
	runFolderTest(t, a)
	runFolderTest(t, b)
	if _, e := os.Stat(filepath.Join(br, "courses/速成/video.mp4")); !os.IsNotExist(e) {
		t.Fatal("deletion did not propagate")
	}
	// No model, credential or index files appear in published logical paths.
	devices, _ := os.ReadDir(filepath.Join(remote, "devices"))
	for _, d := range devices {
		raw, _ := os.ReadFile(filepath.Join(remote, "devices", d.Name()))
		if strings.Contains(string(raw), "seal.key") || strings.Contains(string(raw), "library.db") {
			t.Fatal("private data published")
		}
	}
	_, _ = ctx, br
}
func TestFolderIncompleteObjectsLeaveWorkingFilesIntact(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	writeFolderTest(t, ar, "courses/test/course.json", `{"id":"local-pilot"}`)
	writeFolderTest(t, ar, "courses/test/note.md", "one")
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	writeFolderTest(t, ar, "courses/test/note.md", "two")
	runFolderTest(t, a)
	h, _ := hashFile(filepath.Join(ar, "courses/test/note.md"))
	object := filepath.Join(remote, "objects", h)
	saved, _ := os.ReadFile(object)
	os.Remove(object)
	if _, e := b.Sync(context.Background()); e == nil {
		t.Fatal("accepted missing object")
	}
	v, _ := os.ReadFile(filepath.Join(br, "courses/test/note.md"))
	if string(v) != "one" {
		t.Fatal("incomplete generation changed library")
	}
	os.WriteFile(object, []byte("bad"), 0600)
	if _, e := b.Sync(context.Background()); e == nil {
		t.Fatal("accepted corrupt object")
	}
	os.WriteFile(object, saved, 0600)
	runFolderTest(t, b)
	v, _ = os.ReadFile(filepath.Join(br, "courses/test/note.md"))
	if string(v) != "two" {
		t.Fatal("retry did not finish")
	}
}
func TestFolderRejectsUnknownVersionsAndSymlinkTarget(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	writeFolderTest(t, ar, "courses/test/course.json", `{"id":"local-pilot"}`)
	configureTest(t, a, remote)
	runFolderTest(t, a)
	b, br := folderFixture(t)
	configureTest(t, b, remote)
	outside := t.TempDir()
	os.MkdirAll(filepath.Join(br, "courses"), 0700)
	os.Symlink(outside, filepath.Join(br, "courses/test"))
	if _, e := b.Sync(context.Background()); e == nil {
		t.Fatal("followed local symlink")
	}
	raw, _ := os.ReadFile(filepath.Join(remote, "library.json"))
	var m map[string]any
	json.Unmarshal(raw, &m)
	m["version"] = 99
	raw, _ = json.Marshal(m)
	os.WriteFile(filepath.Join(remote, "library.json"), raw, 0600)
	if _, e := a.Sync(context.Background()); e == nil {
		t.Fatal("accepted new format")
	}
}

func TestFolderPreviewListsRemoteCoursesWithoutLocalLibrary(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	writeFolderTest(t, ar, "courses/速成/course.json", `{"id":"local-pilot","title":"速成"}`)
	configureTest(t, a, remote)
	runFolderTest(t, a)
	b, _ := folderFixture(t)
	preview, e := b.FolderPreview(context.Background(), Settings{Kind: "folder", LocalFolder: remote})
	if e != nil {
		t.Fatal(e)
	}
	courses := preview["courses"].(map[string]string)
	if courses["local-pilot"] == "" {
		t.Fatal("new device cannot discover course")
	}
}
func TestRecordMergeKeepsBothAttemptsAndRejectsChangedIDs(t *testing.T) {
	rows, ok := mergeIdentified([][]json.RawMessage{{json.RawMessage(`{"id":"a","v":1}`)}, {json.RawMessage(`{"id":"a","v":1}`), json.RawMessage(`{"id":"b","v":2}`)}})
	if !ok || len(rows) != 2 {
		t.Fatal("lost unique records")
	}
	_, ok = mergeIdentified([][]json.RawMessage{{json.RawMessage(`{"id":"a","v":1}`)}, {json.RawMessage(`{"id":"a","v":2}`)}})
	if ok {
		t.Fatal("silently replaced conflicting record")
	}
}

func TestFolderRejectsOutOfScopeIndexBeforeApplyingFiles(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	writeFolderTest(t, ar, "courses/pilot/course.json", `{"id":"local-pilot"}`)
	writeFolderTest(t, ar, "courses/pilot/one/lecture.json", `{"id":"lecture","course_id":"other"}`)
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	if _, err := b.Sync(context.Background()); err == nil {
		t.Fatal("accepted an unselected lecture")
	}
	if _, err := os.Stat(filepath.Join(br, "courses/pilot/course.json")); !os.IsNotExist(err) {
		t.Fatal("partial import before scope validation")
	}
}

func TestFolderCanvasLatestSaveWinsWithoutBlockingConflict(t *testing.T) {
	remote := t.TempDir()
	a, ar := folderFixture(t)
	b, br := folderFixture(t)
	rel := "courses/速成/study-canvas.json"
	writeFolderTest(t, ar, "courses/速成/course.json", `{"id":"local-pilot"}`)
	writeFolderTest(t, ar, rel, `{"version":3,"revision":1,"strokes":[]}`)
	configureTest(t, a, remote)
	configureTest(t, b, remote)
	runFolderTest(t, a)
	runFolderTest(t, b)
	runFolderTest(t, a)
	earlier := `{"version":3,"revision":2,"strokes":[{"id":"earlier"}]}`
	latest := `{"version":3,"revision":2,"strokes":[{"id":"latest"}]}`
	writeFolderTest(t, ar, rel, earlier)
	writeFolderTest(t, br, rel, latest)
	at := time.Now()
	if err := os.Chtimes(filepath.Join(ar, rel), at.Add(-time.Second), at.Add(-time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(filepath.Join(br, rel), at, at); err != nil {
		t.Fatal(err)
	}
	runFolderTest(t, a)
	result := runFolderTest(t, b)
	runFolderTest(t, a)
	runFolderTest(t, b)
	if result.Conflicts != 0 {
		t.Fatal("canvas blocked on manual conflict", result)
	}
	for _, root := range []string{ar, br} {
		got, err := os.ReadFile(filepath.Join(root, rel))
		if err != nil || string(got) != latest {
			t.Fatalf("latest canvas not selected: %q %v", got, err)
		}
		found := false
		filepath.WalkDir(filepath.Join(root, TrashDir), func(p string, d os.DirEntry, err error) error {
			if err == nil && !d.IsDir() {
				raw, _ := os.ReadFile(p)
				found = found || string(raw) == earlier
			}
			return nil
		})
		if !found {
			t.Fatal("superseded canvas has no recovery copy")
		}
	}
}
