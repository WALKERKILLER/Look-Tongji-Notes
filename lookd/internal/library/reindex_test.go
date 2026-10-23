package library

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"lookstudio/lookd/internal/store"
)

// A rebuilt index must keep notes that belong to no course (top-level notes/).
func TestReindexKeepsLooseNotes(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	lib, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	n, err := lib.SaveNote(ctx, store.Note{Title: "随手记", Body: "不属于任何课程"})
	if err != nil {
		t.Fatal(err)
	}

	// Fresh index over the same files, as after deleting library.db.
	st2, err := store.Open(filepath.Join(t.TempDir(), "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st2.Close()
	lib2, err := Open(root, st2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := lib2.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	got, err := st2.Note(ctx, n.ID)
	if err != nil {
		t.Fatalf("loose note lost after reindex: %v", err)
	}
	if got.Path != n.Path || got.Body != "不属于任何课程" {
		t.Fatalf("reindexed note = %+v, want path %s", got, n.Path)
	}
}

// A library copied to another device shows its lectures as downloaded.
func TestReindexAdoptsCopiedLectures(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	lib, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(st.UpsertCourse(ctx, store.Course{ID: "C1", Title: "海洋声学"}))
	must(st.UpsertLectures(ctx, []store.Lecture{{ID: "L1", CourseID: "C1", Title: "第一讲", Date: "2026-09-14"}}))
	must(lib.SaveTranscript(ctx, "L1", []store.Segment{{StartMs: 0, EndMs: 1000, Text: "声速剖面"}}, "test"))
	lec, _ := st.Lecture(ctx, "L1")
	must(os.MkdirAll(lib.Abs(lec.Dir+"/slides"), 0o755))
	must(os.WriteFile(lib.Abs(lec.Dir+"/slides/0001_t00-00-05.jpg"), []byte("jpg"), 0o644))
	must(os.WriteFile(lib.Abs(lec.Dir+"/slides/index.json"),
		[]byte(`{"items":[{"idx":1,"t_sec":5,"file":"0001_t00-00-05.jpg","is_key":true}]}`), 0o644))
	must(st.PutAsset(ctx, store.Asset{LectureID: "L1", Kind: "slides", Path: lec.Dir + "/slides", Bytes: 3}))
	must(lib.WriteLectureJSON(ctx, "L1"))

	st2, err := store.Open(filepath.Join(t.TempDir(), "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st2.Close()
	lib2, err := Open(root, st2)
	must(err)
	_, err = lib2.Reindex(ctx)
	must(err)
	got, err := st2.Lecture(ctx, "L1")
	must(err)
	if got.Dir != lec.Dir || len(got.Assets) != 2 || got.Segments != 1 {
		t.Fatalf("adopted lecture = %+v, want dir %s with 2 kinds and 1 segment", got, lec.Dir)
	}
	slides, _ := st2.Slides(ctx, "L1")
	if len(slides) != 1 || slides[0].TSec != 5 || slides[0].Path != lec.Dir+"/slides/0001_t00-00-05.jpg" {
		t.Fatalf("slides = %+v", slides)
	}
	if c, _ := st2.Course(ctx, "C1"); c.Title != "海洋声学" || c.Dir == "" {
		t.Fatalf("course = %+v", c)
	}
}

// A note whose file was deleted on another device leaves the index.
func TestReindexDropsDeletedNotes(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	lib, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	n, err := lib.SaveNote(ctx, store.Note{Title: "要删的", Body: "x"})
	if err != nil {
		t.Fatal(err)
	}
	os.Remove(lib.Abs(n.Path))
	if _, err := lib.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := st.Note(ctx, n.ID); err == nil {
		t.Fatal("note without a file stayed in the index")
	}
}
