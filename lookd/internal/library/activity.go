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

// AddActivity records a report (once per reportID) and rewrites
// activity.json with it: if the file cannot be written the report is not
// kept, and if the index then does not commit the previous file returns
// (see mirror.go).
func (l *Library) AddActivity(ctx context.Context, reportID, day, kind, courseID, lectureID string, seconds, count int64) error {
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	m := l.beginMirror()
	err := l.Store.AddActivityMirrored(ctx, m.token(), reportID, day, kind, courseID, lectureID, seconds, count, func(rows []store.ActivityRow) (func(), error) {
		return m.replace(filepath.Join(l.Root, "activity.json"), map[string]any{"schema": "look-studio/activity@1", "rows": rows})
	})
	m.finish(ctx, err)
	return err
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
		// Rows that a report could not have produced are skipped.
		if store.CheckActivityRow(r) == nil && l.Store.PutActivity(ctx, r) == nil {
			n++
		}
	}
	return n
}
