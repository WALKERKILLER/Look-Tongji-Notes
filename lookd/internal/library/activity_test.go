package library

import (
	"context"
	"path/filepath"
	"testing"

	"lookstudio/lookd/internal/store"
)

func TestActivitySurvivesReindex(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	l, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	st.AddActivity(ctx, "2026-10-13", "watch", "C1", "L1", 300, 0)
	st.AddActivity(ctx, "2026-10-14", "ask", "", "", 0, 2)
	if err := l.WriteActivity(ctx); err != nil {
		t.Fatal(err)
	}
	want, _ := st.ActivityRows(ctx)

	st.DB.Exec(`DELETE FROM activity`)
	// Reindexing twice must not double the totals.
	for range 2 {
		if _, err := l.Reindex(ctx); err != nil {
			t.Fatal(err)
		}
	}
	got, _ := st.ActivityRows(ctx)
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Fatalf("rows = %+v, want %+v", got, want)
	}
}
