package library

import (
	"context"
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
