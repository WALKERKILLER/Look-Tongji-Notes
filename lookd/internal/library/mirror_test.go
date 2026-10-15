package library

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"lookstudio/lookd/internal/store"
)

// pendingActivity starts a mirrored write of activity.json and stops before
// the index commits, as a crash would.
func pendingActivity(t *testing.T, l *Library, seconds int64) *mirrorTx {
	t.Helper()
	m := l.beginMirror()
	if _, err := m.replace(filepath.Join(l.Root, "activity.json"), map[string]any{"rows": []store.ActivityRow{{Day: "2026-10-13", Kind: "watch", Seconds: seconds}}}); err != nil {
		t.Fatal(err)
	}
	return m
}

func journals(t *testing.T, l *Library) int {
	t.Helper()
	ents, _ := os.ReadDir(filepath.Join(l.Root, journalDir))
	return len(ents)
}

func TestMirrorFailedCommitRestoresFile(t *testing.T) {
	ctx := context.Background()
	l, _ := openLib(t)
	path := filepath.Join(l.Root, "activity.json")
	if err := l.AddActivity(ctx, "", "2026-10-13", "watch", "", "", 300, 0); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(path)
	m := pendingActivity(t, l, 999)
	m.finish(ctx, errors.New("disk I/O error")) // its token never committed
	if after, _ := os.ReadFile(path); string(after) != string(before) {
		t.Fatalf("previous file not restored:\n%s", after)
	}
	if n := journals(t, l); n != 0 {
		t.Fatalf("%d journal(s) left", n)
	}
}

func TestMirrorRecoveryAfterCrash(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	path := filepath.Join(l.Root, "activity.json")
	if err := l.AddActivity(ctx, "", "2026-10-13", "watch", "", "", 300, 0); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(path)

	// Crash before the commit: reopening restores the previous file.
	pendingActivity(t, l, 999)
	if _, err := Open(l.Root, st); err != nil {
		t.Fatal(err)
	}
	if after, _ := os.ReadFile(path); string(after) != string(before) {
		t.Fatalf("uncommitted file kept:\n%s", after)
	}

	// Crash after the commit: the new file stays and the token is dropped.
	m := pendingActivity(t, l, 777)
	if _, err := st.DB.Exec(`INSERT INTO mirror_commits(token, at) VALUES(?, ?)`, m.token(), time.Now().Unix()); err != nil {
		t.Fatal(err)
	}
	committed, _ := os.ReadFile(path)
	if _, err := Open(l.Root, st); err != nil {
		t.Fatal(err)
	}
	if after, _ := os.ReadFile(path); string(after) != string(committed) {
		t.Fatalf("committed file replaced:\n%s", after)
	}
	if ok, _ := st.MirrorCommitted(ctx, m.token()); ok || journals(t, l) != 0 {
		t.Fatalf("journal or token left after recovery")
	}
}

func TestReindexIgnoresUnfinishedMirror(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	if err := l.AddActivity(ctx, "", "2026-10-13", "watch", "", "", 300, 0); err != nil {
		t.Fatal(err)
	}
	pendingActivity(t, l, 999) // left by a crash; the index never saw it
	st.DB.Exec(`DELETE FROM activity`)
	if _, err := l.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	if rows, _ := st.ActivityRows(ctx); len(rows) != 1 || rows[0].Seconds != 300 {
		t.Fatalf("rows = %+v", rows)
	}
}

func TestReindexWaitsForMirroredWrites(t *testing.T) {
	ctx := context.Background()
	l, _ := openLib(t)
	l.mirrorMu.Lock() // a write in progress
	done := make(chan struct{})
	go func() {
		l.Reindex(ctx)
		close(done)
	}()
	select {
	case <-done:
		t.Fatal("Reindex ran during a mirrored write")
	case <-time.After(50 * time.Millisecond):
	}
	l.mirrorMu.Unlock()
	<-done
}
