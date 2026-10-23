package notify

import (
	"path/filepath"
	"testing"
)

func TestFeedDedupesPersistsAndMarksRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "n.json")
	var got []Item
	f := Open(path, func(it Item) { got = append(got, it) })
	if !f.Add(Item{ID: "a", Kind: "lecture_ready", Title: "A", At: 10}) || !f.Add(Item{ID: "b", Title: "B", At: 20}) {
		t.Fatal("new items rejected")
	}
	if f.Add(Item{ID: "a", Title: "again"}) {
		t.Fatal("duplicate accepted")
	}
	if len(got) != 2 {
		t.Fatalf("published %d", len(got))
	}
	items, unread := Open(path, nil).List()
	if len(items) != 2 || unread != 2 || items[0].ID != "b" {
		t.Fatalf("reload: %+v %d", items, unread)
	}
	f.MarkRead([]string{"a"})
	if _, unread := f.List(); unread != 1 {
		t.Fatalf("unread %d", unread)
	}
	f.MarkRead(nil)
	if _, unread := Open(path, nil).List(); unread != 0 {
		t.Fatalf("unread after all %d", unread)
	}
	for i := 0; i < keep+5; i++ {
		f.Add(Item{ID: string(rune('A'+i%26)) + string(rune(i)), At: int64(100 + i)})
	}
	if items, _ := f.List(); len(items) != keep {
		t.Fatalf("kept %d", len(items))
	}
}
