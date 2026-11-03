package server

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"lookstudio/lookd/internal/datasync"
)

func TestFolderSessionCacheCannotUndoLocalReassignment(t *testing.T) {
	root, data := t.TempDir(), t.TempDir()
	sync := &datasync.Service{Roots: datasync.Roots{Library: root, Data: data}}
	if _, err := sync.Configure(context.Background(), datasync.Settings{Kind: "folder", LocalFolder: t.TempDir(), CourseIDs: []string{"old"}}); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(data, "agent", "course-sessions")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	global := filepath.Join(data, "agent", "sessions-meta.json")
	if err := os.WriteFile(global, []byte(`{"moved":{"course_id":"new","kind":"course"},"ordinary":{"kind":"chat"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "old.json"), []byte(`{"moved":{"course_id":"old"},"ordinary":{"course_id":"old"},"received":{"course_id":"old","kind":"course"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	s := &Server{Data: sync}
	if err := s.mergeFolderSessionMetadata(); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(global)
	if err != nil {
		t.Fatal(err)
	}
	var meta map[string]map[string]string
	if err := json.Unmarshal(b, &meta); err != nil {
		t.Fatal(err)
	}
	if meta["moved"]["course_id"] != "new" || meta["ordinary"]["kind"] != "chat" || meta["ordinary"]["course_id"] != "" || meta["received"]["course_id"] != "old" {
		t.Fatalf("wrong merged metadata: %s", b)
	}
}
