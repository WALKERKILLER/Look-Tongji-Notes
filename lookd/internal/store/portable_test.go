package store

import (
	"context"
	"path/filepath"
	"testing"
)

func TestMergeUserState(t *testing.T) {
	ctx := context.Background()
	open := func() *Store {
		s, err := Open(filepath.Join(t.TempDir(), "library.db"))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { s.Close() })
		return s
	}
	a, b := open(), open()
	a.SavePlayback(ctx, "L1", Playback{PositionMs: 1000, Speed: 1})
	a.AddBookmark(ctx, Bookmark{LectureID: "L1", TMs: 500, Label: "公式"})
	b.SavePlayback(ctx, "L2", Playback{PositionMs: 2000, Speed: 1.5})
	b.DB.Exec(`UPDATE playback SET updated_at=updated_at-100`)
	b.SavePlayback(ctx, "L1", Playback{PositionMs: 9000, Speed: 1})
	b.DB.Exec(`UPDATE playback SET updated_at=updated_at-50 WHERE lecture_id='L1'`) // older than a's

	sa, err := a.ExportUserState(ctx)
	if err != nil {
		t.Fatal(err)
	}
	changed, err := b.MergeUserState(ctx, sa)
	if err != nil || !changed {
		t.Fatalf("merge = %v, %v", changed, err)
	}
	if p, _ := b.Playback(ctx, "L1"); p.PositionMs != 1000 {
		t.Fatalf("newer position not taken: %+v", p)
	}
	if p, _ := b.Playback(ctx, "L2"); p.PositionMs != 2000 {
		t.Fatalf("own position lost: %+v", p)
	}
	if bs, _ := b.Bookmarks(ctx, "L1"); len(bs) != 1 || bs[0].Label != "公式" {
		t.Fatalf("bookmarks = %+v", bs)
	}
	// Merging again changes nothing and adds no duplicate.
	if changed, _ := b.MergeUserState(ctx, sa); changed {
		t.Fatal("second merge reported a change")
	}
	if bs, _ := b.Bookmarks(ctx, "L1"); len(bs) != 1 {
		t.Fatalf("duplicate bookmark: %+v", bs)
	}
}
