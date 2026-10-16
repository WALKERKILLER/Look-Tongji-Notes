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
	lecDir := filepath.Join(out, "海洋地质学", "2026-09-10 第一讲")

	gotNote := readFile(t, filepath.Join(lecDir, "notes", "板块构造.md"))
	for _, want := range []string{
		`look_note_id: "` + note.ID + `"`,
		"[12:03](lookstudio://lecture/L1?t=723)",
		`$v=\frac{d}{t}$`,
		"![PPT 12](../slides/0012_t00-12-03.jpg)",
	} {
		if !strings.Contains(gotNote, want) {
			t.Errorf("note lacks %q:\n%s", want, gotNote)
		}
	}
	if strings.Contains(gotNote, "look://") {
		t.Errorf("note still has look:// links:\n%s", gotNote)
	}
	if readFile(t, filepath.Join(lecDir, "slides", "0012_t00-12-03.jpg")) != "jpg" {
		t.Error("linked slide not copied")
	}
	lecPage := readFile(t, filepath.Join(lecDir, "2026-09-10 第一讲.md"))
	for _, want := range []string{"[板块构造](notes/板块构造.md)", "[转写稿](transcript.md)", "[海洋地质学](../海洋地质学.md)"} {
		if !strings.Contains(lecPage, want) {
			t.Errorf("lecture page lacks %q:\n%s", want, lecPage)
		}
	}
	if !strings.Contains(readFile(t, filepath.Join(lecDir, "transcript.md")), "lookstudio://lecture/L1?t=0") {
		t.Error("transcript timestamps not linked")
	}
	if !strings.Contains(readFile(t, filepath.Join(out, "课程库.md")), "(未归类笔记/随手记.md)") {
		t.Error("index lacks the loose note:\n" + readFile(t, filepath.Join(out, "课程库.md")))
	}

	// Unchanged library: nothing is rewritten.
	res, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if res.Written != 0 || res.Removed != 0 {
		t.Fatalf("second export rewrote files: %+v", res)
	}

	// A note edited in the vault is kept; the new version goes beside it.
	edited := filepath.Join(lecDir, "notes", "板块构造.md")
	must(os.WriteFile(edited, []byte("我在 Obsidian 里改过"), 0o644))
	note.Body += "\n补充一句\n"
	_, err = lib.SaveNote(ctx, note)
	must(err)
	res, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if len(res.Conflicts) != 1 || readFile(t, edited) != "我在 Obsidian 里改过" {
		t.Fatalf("edited note not protected: %+v", res)
	}
	if !strings.Contains(readFile(t, filepath.Join(lecDir, "notes", "板块构造 (Look Studio).md")), "补充一句") {
		t.Error("new version not written beside the edited note")
	}

	// The "(Look Studio)" copy is protected the same way once edited.
	copyPath := filepath.Join(lecDir, "notes", "板块构造 (Look Studio).md")
	must(os.WriteFile(copyPath, []byte("副本也改了"), 0o644))
	note.Body += "\n再补一句\n"
	_, err = lib.SaveNote(ctx, note)
	must(err)
	_, err = lib.ExportObsidian(ctx, vault, "")
	must(err)
	if readFile(t, copyPath) != "副本也改了" || !strings.Contains(readFile(t, filepath.Join(lecDir, "notes", "板块构造 (Look Studio 2).md")), "再补一句") {
		t.Fatal("edited conflict copy was overwritten")
	}

	// Attachments are copies: editing one in the vault leaves the library
	// alone, and later exports keep the edit.
	slide := filepath.Join(lecDir, "slides", "0012_t00-12-03.jpg")
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
