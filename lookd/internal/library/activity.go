package library

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"

	"lookstudio/lookd/internal/store"
)

// Study activity lives in the index and is mirrored to one file per year,
// activity/<year>.json, like the schedule, so that rebuilding the index from
// files keeps it and a report rewrites only its own year.
const activityDir = "activity"

var activityYearFile = regexp.MustCompile(`^\d{4}\.json$`)

// AddActivity records a report (once per reportID) and rewrites its year's
// file with it: if the file cannot be written the report is not kept, and
// if the index then does not commit the previous file returns (see
// mirror.go).
func (l *Library) AddActivity(ctx context.Context, reportID, day, kind, courseID, lectureID string, seconds, count int64) error {
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	dir := filepath.Join(l.Root, activityDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	m := l.beginMirror()
	err := l.Store.AddActivityMirrored(ctx, m.token(), reportID, day, kind, courseID, lectureID, seconds, count, func(rows []store.ActivityRow) (func(), error) {
		return m.replace(filepath.Join(dir, day[:4]+".json"), map[string]any{"schema": "look-studio/activity@1", "year": day[:4], "rows": rows})
	})
	m.finish(ctx, err)
	return err
}

// reindexActivity restores every year file, and activity.json, the single
// file earlier versions wrote.
func (l *Library) reindexActivity(ctx context.Context) int {
	files := []string{filepath.Join(l.Root, "activity.json")}
	if ents, err := os.ReadDir(filepath.Join(l.Root, activityDir)); err == nil {
		for _, e := range ents {
			if !e.IsDir() && activityYearFile.MatchString(e.Name()) {
				files = append(files, filepath.Join(l.Root, activityDir, e.Name()))
			}
		}
	}
	n := 0
	for _, path := range files {
		b, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		var f struct {
			Rows []store.ActivityRow `json:"rows"`
		}
		if json.Unmarshal(b, &f) != nil {
			continue
		}
		for _, r := range f.Rows {
			// Rows that a report could not have produced are skipped.
			if store.CheckActivityRow(r) == nil && l.Store.PutActivity(ctx, r) == nil {
				n++
			}
		}
	}
	return n
}
