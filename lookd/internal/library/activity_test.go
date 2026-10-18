package library

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"lookstudio/lookd/internal/store"
)

func openLib(t *testing.T) (*Library, *store.Store) {
	t.Helper()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	l, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	return l, st
}

func TestActivitySurvivesReindex(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	if err := l.AddActivity(ctx, "", "2026-10-13", "watch", "C1", "L1", 300, 0); err != nil {
		t.Fatal(err)
	}
	if err := l.AddActivity(ctx, "", "2026-10-14", "ask", "", "", 0, 2); err != nil {
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

	// An older file copy never lowers newer totals.
	st.AddActivity(ctx, "2026-10-13", "watch", "C1", "L1", 60, 0)
	l.Reindex(ctx)
	if got, _ := st.ActivityRows(ctx); got[0].Seconds != 360 {
		t.Fatalf("reindex lowered totals: %+v", got)
	}
}

func TestActivityNotKeptWhenMirrorFails(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	// A directory where the file should be makes the write fail.
	if err := os.MkdirAll(filepath.Join(l.Root, "activity", "2026.json"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := l.AddActivity(ctx, "", "2026-10-13", "watch", "", "", 300, 0); err == nil {
		t.Fatal("mirror failure was not reported")
	}
	if rows, _ := st.ActivityRows(ctx); len(rows) != 0 {
		t.Fatalf("report kept without its mirror: %+v", rows)
	}
}

func TestActivityMirroredPerYear(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	for _, day := range []string{"2025-12-31", "2026-01-01"} {
		if err := l.AddActivity(ctx, "", day, "watch", "", "", 300, 0); err != nil {
			t.Fatal(err)
		}
	}
	old := filepath.Join(l.Root, "activity", "2025.json")
	past := time.Now().Add(-time.Hour).Truncate(time.Second)
	os.Chtimes(old, past, past)
	if err := l.AddActivity(ctx, "", "2026-01-02", "read", "", "", 60, 0); err != nil {
		t.Fatal(err)
	}
	if fi, err := os.Stat(old); err != nil || !fi.ModTime().Equal(past) {
		t.Fatalf("a 2026 report rewrote 2025.json: %v", err)
	}
	var f struct{ Rows []store.ActivityRow }
	b, _ := os.ReadFile(filepath.Join(l.Root, "activity", "2026.json"))
	if json.Unmarshal(b, &f) != nil || len(f.Rows) != 2 {
		t.Fatalf("2026.json rows = %+v", f.Rows)
	}

	// Reindex restores every year and the single file earlier versions wrote.
	writeJSON(filepath.Join(l.Root, "activity.json"), map[string]any{"rows": []store.ActivityRow{{Day: "2024-05-01", Kind: "ask", Count: 3}}})
	st.DB.Exec(`DELETE FROM activity`)
	if _, err := l.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	if rows, _ := st.ActivityRows(ctx); len(rows) != 4 {
		t.Fatalf("rows after reindex = %+v", rows)
	}
}

func TestActivityReindexSkipsInvalidRows(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	writeJSON(filepath.Join(l.Root, "activity.json"), map[string]any{"rows": []store.ActivityRow{
		{Day: "2026-10-13", Kind: "watch", Seconds: 300},
		{Day: "2026-02-30", Kind: "watch", Seconds: 300},
		{Day: "0001-01-01", Kind: "read", Seconds: 60},
		{Day: "2026-10-13", Kind: "nap", Seconds: 60},
		{Day: "2026-10-13", Kind: "read", Seconds: -100},
	}})
	if _, err := l.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	rows, _ := st.ActivityRows(ctx)
	if len(rows) != 1 || rows[0].Seconds != 300 {
		t.Fatalf("rows = %+v", rows)
	}
	if _, err := st.ActivityStreak(ctx, time.Now()); err != nil {
		t.Fatalf("streak after reindex: %v", err)
	}
}
