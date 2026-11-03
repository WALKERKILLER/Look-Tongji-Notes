package library

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"lookstudio/lookd/internal/store"
)

func TestCatalogSeparatesCategoryFromFormatAndOmitsUnsafeEntries(t *testing.T) {
	lib, _ := reviewFixture(t)
	ctx := context.Background()
	lec, _ := lib.Store.Lecture(ctx, "one")
	files := map[string]string{"courseware/Lab 4.pdf": "lab", "courseware/第一次作业.pdf": "homework", "courseware/Chp3 VM.pptx": "courseware", "courseware/reference-book.pdf": "reference", "slides/1.jpg": "slides", "courseware/unknown.zip": "courseware"}
	for rel := range files {
		p := lib.Abs(lec.Dir + "/" + rel)
		os.MkdirAll(filepath.Dir(p), 0700)
		if e := os.WriteFile(p, []byte("evidence"), 0600); e != nil {
			t.Fatal(e)
		}
	}
	n, e := lib.SaveNote(ctx, store.Note{ID: "n", CourseID: "os", LectureID: "one", Title: "Lab 4 实验要求", Source: "user", Body: "原笔记"})
	if e != nil {
		t.Fatal(e)
	}
	outside := t.TempDir()
	os.WriteFile(filepath.Join(outside, "private.pdf"), []byte("private"), 0600)
	os.Symlink(filepath.Join(outside, "private.pdf"), lib.Abs(lec.Dir+"/courseware/link.pdf"))
	os.Symlink(outside, lib.Abs(lec.Dir+"/linked"))
	os.MkdirAll(lib.Abs(lec.Dir+"/courseware/a.pdf.parsed"), 0700)
	os.WriteFile(lib.Abs(lec.Dir+"/courseware/a.pdf.parsed/full.md"), []byte("cache"), 0600)
	items, e := lib.Catalog(ctx)
	if e != nil {
		t.Fatal(e)
	}
	seen := map[string]CatalogItem{}
	for _, it := range items {
		if _, ok := seen[it.Path]; ok {
			t.Fatal("duplicate path")
		}
		seen[it.Path] = it
		if it.CourseID != "os" {
			t.Fatal(it)
		}
	}
	for rel, cat := range files {
		it, ok := seen[lec.Dir+"/"+rel]
		if !ok || it.Category != cat || it.LectureID != "one" {
			t.Fatal(rel, it)
		}
	}
	if seen[n.Path].NoteID != "n" || seen[n.Path].Category != "lab" {
		t.Fatal("note identity/category lost", seen[n.Path])
	}
	for _, rel := range []string{"lecture.json", "courseware/link.pdf", "linked/private.pdf", "courseware/a.pdf.parsed/full.md"} {
		if _, ok := seen[lec.Dir+"/"+rel]; ok {
			t.Fatal("unsafe/metadata entry exposed", rel)
		}
	}
	if seen[lec.Dir+"/courseware/Lab 4.pdf"].FileType != "pdf" {
		t.Fatal("category used as format")
	}
}
