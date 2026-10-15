package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"testing"
)

func TestActivityReportCountedOnce(t *testing.T) {
	ctx := context.Background()
	s, err := Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	mirrors := 0
	mirror := func([]ActivityRow) (func(), error) { mirrors++; return func() {}, nil }
	for range 2 { // the second is a retry after a lost response
		if err := s.AddActivityMirrored(ctx, "", "report-0001", "2026-10-13", "watch", "", "", 120, 0, mirror); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.AddActivityMirrored(ctx, "", "report-0002", "2026-10-13", "watch", "", "", 30, 0, mirror); err != nil {
		t.Fatal(err)
	}
	rows, _ := s.ActivityRows(ctx)
	if len(rows) != 1 || rows[0].Seconds != 150 || mirrors != 2 {
		t.Fatalf("rows = %+v, mirrors = %d", rows, mirrors)
	}
}

func TestActivityCommitFailureUndoesMirror(t *testing.T) {
	ctx := context.Background()
	s, err := Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	orig := commitTx
	commitTx = func(tx *sql.Tx) error { tx.Rollback(); return errors.New("disk I/O error") }
	defer func() { commitTx = orig }()
	undone := false
	err = s.AddActivityMirrored(ctx, "", "report-0003", "2026-10-13", "watch", "", "", 60, 0, func([]ActivityRow) (func(), error) {
		return func() { undone = true }, nil
	})
	if err == nil || !undone {
		t.Fatalf("err = %v, undone = %v", err, undone)
	}
	commitTx = orig
	if rows, _ := s.ActivityRows(ctx); len(rows) != 0 {
		t.Fatalf("rows kept after failed commit: %+v", rows)
	}
	// The report id was rolled back too, so the retry is applied.
	if err := s.AddActivityMirrored(ctx, "", "report-0003", "2026-10-13", "watch", "", "", 60, 0, func([]ActivityRow) (func(), error) { return func() {}, nil }); err != nil {
		t.Fatal(err)
	}
	if rows, _ := s.ActivityRows(ctx); len(rows) != 1 {
		t.Fatalf("retry not applied: %+v", rows)
	}
}

func TestActivityBucketSaturatesWithinRestorableLimits(t *testing.T) {
	ctx := context.Background()
	s, err := Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err := s.AddActivity(ctx, "2026-10-13", "watch", "", "", MaxDaySeconds-100, 0); err != nil {
		t.Fatal(err)
	}
	if err := s.AddActivity(ctx, "2026-10-13", "ask", "", "", 0, MaxDayCount-10); err != nil {
		t.Fatal(err)
	}
	var mirrored []ActivityRow
	mirror := func(rows []ActivityRow) (func(), error) { mirrored = rows; return func() {}, nil }
	for i, r := range []struct {
		kind           string
		seconds, count int64
	}{{"watch", 300, 0}, {"watch", 300, 0}, {"ask", 0, 50}} {
		if err := s.AddActivityMirrored(ctx, "", fmt.Sprintf("report-%04d", i), "2026-10-13", r.kind, "", "", r.seconds, r.count, mirror); err != nil {
			t.Fatal(err)
		}
	}
	got := map[string]ActivityRow{}
	for _, r := range mirrored {
		if err := CheckActivityRow(r); err != nil {
			t.Errorf("mirrored row would be dropped on rebuild: %v", err)
		}
		got[r.Kind] = r
	}
	if got["watch"].Seconds != MaxDaySeconds || got["ask"].Count != MaxDayCount {
		t.Fatalf("rows = %+v", mirrored)
	}
}

func TestCheckActivityRow(t *testing.T) {
	ok := ActivityRow{Day: "2026-10-13", Kind: "watch", Seconds: 600}
	if err := CheckActivityRow(ok); err != nil {
		t.Fatal(err)
	}
	for _, r := range []ActivityRow{
		{Day: "2026-10-13", Kind: "sleep", Seconds: 60},
		{Day: "2026-02-30", Kind: "watch", Seconds: 60},
		{Day: "0001-01-01", Kind: "watch", Seconds: 60},
		{Day: "2999-01-01", Kind: "watch", Seconds: 60},
		{Day: "2026-10-13", Kind: "watch", Seconds: -5},
		{Day: "2026-10-13", Kind: "watch", Seconds: 90000},
		{Day: "2026-10-13", Kind: "ask", Seconds: 60, Count: 1},
		{Day: "2026-10-13", Kind: "read"},
	} {
		if CheckActivityRow(r) == nil {
			t.Errorf("accepted %+v", r)
		}
	}
}
