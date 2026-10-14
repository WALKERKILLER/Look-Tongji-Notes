package library

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"

	"lookstudio/lookd/internal/store"
)

// Study activity lives in the index and is mirrored to activity.json, like
// the schedule, so that rebuilding the index from files keeps it.

func (l *Library) WriteActivity(ctx context.Context) error {
	l.actMu.Lock()
	defer l.actMu.Unlock()
	rows, err := l.Store.ActivityRows(ctx)
	if err != nil {
		return err
	}
	return writeJSON(filepath.Join(l.Root, "activity.json"), map[string]any{"schema": "look-studio/activity@1", "rows": rows})
}

func (l *Library) reindexActivity(ctx context.Context) int {
	b, err := os.ReadFile(filepath.Join(l.Root, "activity.json"))
	if err != nil {
		return 0
	}
	var f struct {
		Rows []store.ActivityRow `json:"rows"`
	}
	if json.Unmarshal(b, &f) != nil {
		return 0
	}
	n := 0
	for _, r := range f.Rows {
		if r.Day != "" && r.Kind != "" && l.Store.PutActivity(ctx, r) == nil {
			n++
		}
	}
	return n
}
