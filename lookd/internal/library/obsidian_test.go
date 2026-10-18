package library

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"lookstudio/lookd/internal/store"
)

func newTestLibrary(t *testing.T) (*Library, context.Context) {
	t.Helper()
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	lib, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	return lib, ctx
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestExportObsidian(t *testing.T) {
	lib, ctx := newTestLibrary(t)
	st := lib.Store
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(st.UpsertCourse(ctx, store.Course{ID: "C1", Title: "海洋地质学", Teacher: "张三"}))
	must(st.UpsertLectures(ctx, []store.Lecture{{ID: "L1", CourseID: "C1", Title: "第一讲", Date: "2026-09-10"}}))
	_, _, dir, err := lib.EnsureLecture(ctx, "L1")
	must(err)
	must(os.MkdirAll(lib.Abs(dir+"/slides"), 0o755))
	must(os.WriteFile(lib.Abs(dir+"/slides/0012_t00-12-03.jpg"), []byte("jpg"), 0o644))
	must(st.ReplaceSlides(ctx, "L1", []store.Slide{{Idx: 12, TSec: 723, Path: dir + "/slides/0012_t00-12-03.jpg"}}))
	must(lib.SaveTranscript(ctx, "L1", []store.Segment{{Idx: 0, StartMs: 0, EndMs: 5000, Text: "今天讲板块构造"}}, "test"))
	note, err := lib.SaveNote(ctx, store.Note{LectureID: "L1", Title: "板块构造", Source: "agent",
		Body: "# 板块构造\n\n[12:03] 洋中脊 \\(v=\\frac{d}{t}\\)\n\n![PPT 12](look://slide/L1/12)\n"})
	must(err)
	loose, err := lib.SaveNote(ctx, store.Note{Title: "随手记", Body: "不属于课程"})
	must(err)

	vault := t.TempDir()
	must(os.Mkdir(filepath.Join(vault, ".obsidian"), 0o755))
	res, err := lib.ExportObsidian(ctx, vault, "")
	must(err)
	if !res.Vault || res.Written == 0 || len(res.Conflicts) != 0 {
		t.Fatalf("first export: %+v", res)
	}
	out := filepath.Join(vault, ObsidianFolder)
	courseDir := filepath.Join(out, "海洋地质学")
	notesDir := filepath.Join(courseDir, "笔记", "2026-09-10 第一讲")
	filesDir := filepath.Join(notesDir, "附件")

	gotNote := readFile(t, filepath.Join(notesDir, "板块构造.md"))
	for _, want := range []string{
		`look_note_id: "` + note.ID + `"`,
		"[12:03](lookstudio://lecture/L1?t=723)",
		`$v=\frac{d}{t}$`,
		"![PPT 12](附件/slides/0012_t00-12-03.jpg)",
	} {
		if !strings.Contains(gotNote, want) {
			t.Errorf("note lacks %q:\n%s", want, gotNote)
		}
	}
	if strings.Contains(gotNote, "look://") {
		t.Errorf("note still has look:// links:\n%s", gotNote)
	}
	if readFile(t, filepath.Join(filesDir, "slides", "0012_t00-12-03.jpg")) != "jpg" {
		t.Error("linked slide not copied")
	}
	transcript := readFile(t, filepath.Join(courseDir, "转写稿", "2026-09-10 第一讲.md"))
	for _, want := range []string{"[板块构造](../笔记/2026-09-10%20第一讲/板块构造.md)", "[课程库](../../课程库.md)", "lookstudio://lecture/L1?t=0", "tags:\n  - look-studio/transcript"} {
		if !strings.Contains(transcript, want) {
			t.Errorf("transcript page lacks %q:\n%s", want, transcript)
		}
	}
	if strings.Contains(transcript, "look-studio/transcript@1") {
		t.Errorf("library front matter leaked into the transcript page:\n%s", transcript)
	}
	index := readFile(t, filepath.Join(out, "课程库.md"))
	for _, want := range []string{"## 海洋地质学", "(海洋地质学/转写稿/2026-09-10%20第一讲.md)", "(海洋地质学/笔记/2026-09-10%20第一讲/板块构造.md)", "(未归类笔记/随手记.md)"} {
		if !strings.Contains(index, want) {
			t.Errorf("index lacks %q:\n%s", want, index)
		}
	}
	// Only the index and folders at the top; the course folder holds just
	// notes and transcripts.
	for dir, want := range map[string]string{out: ".lookstudio-export.json 未归类笔记 海洋地质学 课程库.md", courseDir: "笔记 转写稿", filepath.Dir(notesDir): "2026-09-10 第一讲"} {
		ents, err := os.ReadDir(dir)
		must(err)
		var names []string
		for _, e := range ents {
			names = append(names, e.Name())
		}
		if got := strings.Join(names, " "); got != want {
			t.Errorf("%s holds %q, want %q", dir, got, want)
		}
	}

	// Unchanged library: nothing is rewritten.
	res, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if res.Written != 0 || res.Removed != 0 {
		t.Fatalf("second export rewrote files: %+v", res)
	}

	// A note edited in the vault is kept; the new version goes beside it.
	edited := filepath.Join(notesDir, "板块构造.md")
	must(os.WriteFile(edited, []byte("我在 Obsidian 里改过"), 0o644))
	note.Body += "\n补充一句\n"
	_, err = lib.SaveNote(ctx, note)
	must(err)
	res, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if len(res.Conflicts) != 1 || readFile(t, edited) != "我在 Obsidian 里改过" {
		t.Fatalf("edited note not protected: %+v", res)
	}
	if !strings.Contains(readFile(t, filepath.Join(notesDir, "板块构造 (Look Studio).md")), "补充一句") {
		t.Error("new version not written beside the edited note")
	}

	// The "(Look Studio)" copy is protected the same way once edited.
	copyPath := filepath.Join(notesDir, "板块构造 (Look Studio).md")
	must(os.WriteFile(copyPath, []byte("副本也改了"), 0o644))
	note.Body += "\n再补一句\n"
	_, err = lib.SaveNote(ctx, note)
	must(err)
	_, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if readFile(t, copyPath) != "副本也改了" || !strings.Contains(readFile(t, filepath.Join(notesDir, "板块构造 (Look Studio 2).md")), "再补一句") {
		t.Fatal("edited conflict copy was overwritten")
	}

	// Attachments are copies: editing one in the vault leaves the library
	// alone, and later exports keep the edit.
	slide := filepath.Join(filesDir, "slides", "0012_t00-12-03.jpg")
	must(os.WriteFile(slide, []byte("annotated"), 0o644))
	if readFile(t, lib.Abs(dir+"/slides/0012_t00-12-03.jpg")) != "jpg" {
		t.Fatal("editing the exported slide changed the library")
	}
	res, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if readFile(t, slide) != "annotated" {
		t.Fatalf("edited attachment overwritten: %+v", res)
	}
	// Ownership is decided by content, not size and time: an edit that keeps
	// both is still the user's.
	fi, err := os.Stat(slide)
	must(err)
	must(os.WriteFile(slide, []byte("ANNOTATED"), 0o644))
	must(os.Chtimes(slide, fi.ModTime(), fi.ModTime()))
	_, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if readFile(t, slide) != "ANNOTATED" {
		t.Fatal("same-size edit with restored mtime was overwritten")
	}

	// A note deleted in the app disappears from the vault.
	must(lib.DeleteNote(ctx, loose.ID))
	res, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if _, err := os.Stat(filepath.Join(out, "未归类笔记")); !os.IsNotExist(err) || res.Removed != 1 {
		t.Fatalf("deleted note not cleaned up: %+v %v", res, err)
	}
}

func TestObsidianRootRejectsOverlap(t *testing.T) {
	lib, _ := newTestLibrary(t)
	vault := t.TempDir()
	for _, c := range []struct{ vault, folder string }{
		{"relative/path", ""},
		{vault, "../escape"},
		{vault, "/abs"},
		{vault, "."},
		{lib.Root, "x"}, // export inside the library
		{filepath.Dir(lib.Root), filepath.Base(lib.Root)}, // export is the library
	} {
		if _, err := lib.ObsidianRoot(c.vault, c.folder); err == nil {
			t.Errorf("ObsidianRoot(%q, %q) accepted", c.vault, c.folder)
		}
	}
	if _, err := lib.ObsidianRoot(vault, "课程/LookStudio"); err != nil {
		t.Errorf("nested folder rejected: %v", err)
	}
	// An export folder that is a symbolic link into the library.
	if err := os.Symlink(lib.Root, filepath.Join(vault, "link")); err != nil {
		t.Fatal(err)
	}
	if _, err := lib.ObsidianRoot(vault, "link"); err == nil {
		t.Error("symlink into the library accepted")
	}
	if _, err := lib.ObsidianRoot(vault, "link/sub"); err == nil {
		t.Error("folder below a symlink into the library accepted")
	}
}

// A symbolic link inside an existing export stops the export instead of
// writing through it.
func TestExportObsidianStopsAtSymlink(t *testing.T) {
	lib, ctx := newTestLibrary(t)
	if _, err := lib.SaveNote(ctx, store.Note{Title: "随手记", Body: "x"}); err != nil {
		t.Fatal(err)
	}
	vault, elsewhere := t.TempDir(), t.TempDir()
	out := filepath.Join(vault, ObsidianFolder)
	if err := os.MkdirAll(out, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(elsewhere, filepath.Join(out, "未归类笔记")); err != nil {
		t.Fatal(err)
	}
	if _, err := lib.ExportObsidian(ctx, vault, ""); err == nil {
		t.Fatal("export wrote through a symlink")
	}
	if ents, _ := os.ReadDir(elsewhere); len(ents) != 0 {
		t.Fatalf("files written outside the export: %v", ents)
	}
}

func TestObsidianPlaces(t *testing.T) {
	for _, c := range []struct{ got, want string }{
		{noteFolder("courses/物化/2026-10-16第3-4节/notes/a-1.md"), "物化/笔记/2026-10-16第3-4节"},
		{noteFolder("courses/物化/notes/a-1.md"), "物化/笔记/课程笔记"},
		{noteFolder("notes/a-1.md"), "未归类笔记"},
		{placeInExport("courses/物化/2026-10-16第3-4节/slides/0001.jpg"), "物化/笔记/2026-10-16第3-4节/附件/slides/0001.jpg"},
		{placeInExport("courses/物化/2026-10-16第3-4节/courseware/讲义.pdf.parsed/images/a.jpg"), "物化/笔记/2026-10-16第3-4节/附件/courseware/讲义.pdf.parsed/images/a.jpg"},
	} {
		if c.got != c.want {
			t.Errorf("got %q, want %q", c.got, c.want)
		}
	}
}

// A folder replaced by a symbolic link after the checks (a sync tool, another
// process) still cannot take writes or deletions out of the export folder:
// they go through the os.Root handle, not through re-resolved paths.
func TestObsidianWritesStayInsideAfterSwap(t *testing.T) {
	vault, elsewhere := t.TempDir(), t.TempDir()
	out := filepath.Join(vault, ObsidianFolder)
	victim := filepath.Join(elsewhere, "keep.md")
	if err := os.WriteFile(victim, []byte("outside"), 0o644); err != nil {
		t.Fatal(err)
	}
	dir, err := openExportRoot(vault, out)
	if err != nil {
		t.Fatal(err)
	}
	defer dir.Close()
	// The swap: what was checked as a folder is now a link out of the export.
	if err := os.Symlink(elsewhere, filepath.Join(out, "笔记")); err != nil {
		t.Fatal(err)
	}
	if err := writeAtomic(dir, filepath.Join("笔记", "keep.md"), strings.NewReader("x")); err == nil {
		t.Error("write followed a swapped-in symlink")
	}
	if err := writeAtomic(dir, filepath.Join("笔记", "new.md"), strings.NewReader("x")); err == nil {
		t.Error("create followed a swapped-in symlink")
	}
	if err := dir.Remove(filepath.Join("笔记", "keep.md")); err == nil {
		t.Error("remove followed a swapped-in symlink")
	}
	if got := readFile(t, victim); got != "outside" {
		t.Fatalf("file outside the export changed: %q", got)
	}
	if ents, _ := os.ReadDir(elsewhere); len(ents) != 1 {
		t.Fatalf("files created outside the export: %v", ents)
	}
}

// The export folder itself replaced by a link between the check and the
// export is refused.
func TestOpenExportRootRefusesSwappedFolder(t *testing.T) {
	base := t.TempDir()
	real := filepath.Join(base, "real")
	if err := os.Mkdir(real, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(base, "LookStudio")
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}
	if dir, err := openExportRoot(base, link); err == nil {
		dir.Close()
		t.Fatal("opened an export folder that is a symbolic link")
	}
}

// A parent of a not-yet-existing export folder swapped for a link out of the
// vault after the check: creating the folder must not follow it.
func TestOpenExportRootCreatesInsideVault(t *testing.T) {
	vault, elsewhere := t.TempDir(), t.TempDir()
	lib, _ := newTestLibrary(t)
	root, err := lib.ObsidianRoot(vault, "课程/LookStudio")
	if err != nil {
		t.Fatal(err)
	}
	// The swap, after ObsidianRoot and before the export creates the folder.
	if err := os.Symlink(elsewhere, filepath.Join(vault, "课程")); err != nil {
		t.Fatal(err)
	}
	if dir, err := openExportRoot(vault, root); err == nil {
		dir.Close()
		t.Fatal("created the export folder through a swapped-in symlink")
	}
	if ents, _ := os.ReadDir(elsewhere); len(ents) != 0 {
		t.Fatalf("folder created outside the vault: %v", ents)
	}
}

// Audit of #18: with the library inside the vault, a component swapped for a
// link to the library (still inside the vault) must not get a folder
// created in the library.
func TestOpenExportRootNoCreateInLibraryInsideVault(t *testing.T) {
	vault := t.TempDir()
	library := filepath.Join(vault, "library")
	if err := os.Mkdir(library, 0o755); err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(vault, "export", "new") // as checked, before the swap
	if err := os.Symlink("library", filepath.Join(vault, "export")); err != nil {
		t.Fatal(err)
	}
	if dir, err := openExportRoot(vault, root); err == nil {
		dir.Close()
		t.Fatal("opened an export folder through a link into the library")
	}
	if ents, _ := os.ReadDir(library); len(ents) != 0 {
		t.Fatalf("created in the library: %v", ents)
	}
}

// A file in the library that is a symbolic link to something outside it is
// not copied into the vault.
func TestExportObsidianSkipsLibrarySymlinks(t *testing.T) {
	lib, ctx := newTestLibrary(t)
	secret := filepath.Join(t.TempDir(), "secret.txt")
	if err := os.WriteFile(secret, []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(secret, lib.Abs("leak.txt")); err != nil {
		t.Fatal(err)
	}
	if _, err := lib.SaveNote(ctx, store.Note{Title: "n", Body: "[x](look://file/leak.txt)"}); err != nil {
		t.Fatal(err)
	}
	vault := t.TempDir()
	if _, err := lib.ExportObsidian(ctx, vault, ""); err != nil {
		t.Fatal(err)
	}
	filepath.WalkDir(vault, func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if b, _ := os.ReadFile(p); string(b) == "secret" {
				t.Errorf("file outside the library copied to %s", p)
			}
		}
		return nil
	})
}
