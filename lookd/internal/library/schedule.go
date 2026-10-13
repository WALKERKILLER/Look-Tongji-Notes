package library

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"

	"lookstudio/lookd/internal/store"
)

// The schedule lives in the index and is mirrored to schedule.json so that
// rebuilding the index from files keeps it.

func (l *Library) WriteSchedule(ctx context.Context) error {
	items, err := l.Store.Schedule(ctx, store.ScheduleQuery{})
	if err != nil {
		return err
	}
	return writeJSON(filepath.Join(l.Root, "schedule.json"), map[string]any{"schema": "look-studio/schedule@1", "items": items})
}

func (l *Library) reindexSchedule(ctx context.Context) int {
	b, err := os.ReadFile(filepath.Join(l.Root, "schedule.json"))
	if err != nil {
		return 0
	}
	var f struct {
		Items []store.ScheduleItem `json:"items"`
	}
	if json.Unmarshal(b, &f) != nil {
		return 0
	}
	n := 0
	for _, it := range f.Items {
		if it.ID != "" && it.DueDate != "" && l.Store.PutScheduleItem(ctx, it) == nil {
			n++
		}
	}
	return n
}
