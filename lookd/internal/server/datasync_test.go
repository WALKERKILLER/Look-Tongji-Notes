package server

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
)

// Cleaning the cache keeps what queued, running and paused jobs resume from.
func TestStaleCacheSparesActiveJobs(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	lib, err := library.Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	st.UpsertCourse(ctx, store.Course{ID: "C", Title: "c"})
	st.UpsertLectures(ctx, []store.Lecture{{ID: "111", CourseID: "C"}, {ID: "222", CourseID: "C"}})
	st.PutJob(ctx, store.Job{ID: "111-transcript", LectureID: "111", Kind: "transcript", State: "paused"})
	st.PutJob(ctx, store.Job{ID: "222-transcript", LectureID: "222", Kind: "transcript", State: "failed"})
	cache := lib.Abs(".cache")
	os.MkdirAll(filepath.Join(cache, "chunks-1"), 0o755)
	for _, f := range []string{"111.mp4.part", "111.mp4.part.json", "222.mp4.part", "222.mp3", "chunks-1/000.mp3"} {
		os.WriteFile(filepath.Join(cache, f), []byte("x"), 0o644)
	}
	s := &Server{St: st, Lib: lib}
	all, stale, err := s.cacheEntries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, p := range stale {
		got[filepath.Base(p)] = true
	}
	if len(all) != 5 || len(stale) != 3 || !got["222.mp4.part"] || !got["222.mp3"] || !got["chunks-1"] {
		t.Fatalf("stale = %v of %d", stale, len(all))
	}
}
