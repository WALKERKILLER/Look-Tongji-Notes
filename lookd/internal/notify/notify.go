// Package notify keeps the in-app notification feed: new lectures, replays
// that became available, Canvas assignments and announcements. Items are
// deduplicated by ID, kept in a small JSON file and announced on the bus.
// Contract: docs/specs/0010-live-refresh.md
package notify

import (
	"encoding/json"
	"os"
	"sort"
	"sync"
	"time"
)

const keep = 200

type Item struct {
	ID        string `json:"id"`   // stable key, e.g. "lecture_ready:<lecture id>"
	Kind      string `json:"kind"` // lecture_added | lecture_ready | assignment_new | assignment_due | announcement
	Title     string `json:"title"`
	Body      string `json:"body,omitempty"`
	CourseID  string `json:"course_id,omitempty"`
	LectureID string `json:"lecture_id,omitempty"`
	URL       string `json:"url,omitempty"` // web page to open, e.g. on Canvas
	At        int64  `json:"at"`
	Read      bool   `json:"read"`
}

type Feed struct {
	path    string
	publish func(Item)

	mu    sync.Mutex
	items []Item
}

// Open loads the feed from path ("" keeps it in memory).
func Open(path string, publish func(Item)) *Feed {
	f := &Feed{path: path, publish: publish}
	if b, err := os.ReadFile(path); err == nil {
		json.Unmarshal(b, &f.items)
	}
	return f
}

// Add records a new item and announces it; an ID seen before is ignored.
func (f *Feed) Add(it Item) bool {
	if it.At == 0 {
		it.At = time.Now().Unix()
	}
	f.mu.Lock()
	for _, x := range f.items {
		if x.ID == it.ID {
			f.mu.Unlock()
			return false
		}
	}
	f.items = append(f.items, it)
	sort.SliceStable(f.items, func(i, j int) bool { return f.items[i].At > f.items[j].At })
	if len(f.items) > keep {
		f.items = f.items[:keep]
	}
	f.saveLocked()
	f.mu.Unlock()
	if f.publish != nil {
		f.publish(it)
	}
	return true
}

// Seen reports whether an item with this ID was ever recorded (and kept).
func (f *Feed) Seen(id string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, x := range f.items {
		if x.ID == id {
			return true
		}
	}
	return false
}

// List returns the items, newest first, and the unread count.
func (f *Feed) List() ([]Item, int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := append([]Item{}, f.items...)
	unread := 0
	for _, x := range out {
		if !x.Read {
			unread++
		}
	}
	return out, unread
}

// MarkRead marks the given items, or all with ids == nil.
func (f *Feed) MarkRead(ids []string) {
	want := map[string]bool{}
	for _, id := range ids {
		want[id] = true
	}
	f.mu.Lock()
	for i := range f.items {
		if ids == nil || want[f.items[i].ID] {
			f.items[i].Read = true
		}
	}
	f.saveLocked()
	f.mu.Unlock()
}

func (f *Feed) saveLocked() {
	if f.path == "" {
		return
	}
	b, _ := json.Marshal(f.items)
	tmp := f.path + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, f.path)
	}
}
