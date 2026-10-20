package library

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"

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
	file := filepath.Join(dir, day[:4]+".json")
	if err := realActivityPath(dir, file); err != nil {
		return err
	}
	m := l.beginMirror()
	err := l.Store.AddActivityMirrored(ctx, m.token(), reportID, day, kind, courseID, lectureID, seconds, count, func(rows []store.ActivityRow) (func(), error) {
		return m.replace(file, map[string]any{"schema": "look-studio/activity@1", "year": day[:4], "rows": rows})
	})
	m.finish(ctx, err)
	return err
}

// realActivityPath refuses an activity directory or year file that is a
// symlink (or not a plain directory and file), so a report never writes
// outside the library.
func realActivityPath(dir, file string) error {
	if fi, err := os.Lstat(dir); err != nil || !fi.IsDir() {
		return fmt.Errorf("%s 不是课程库里的普通目录", activityDir)
	}
	if fi, err := os.Lstat(file); err == nil && !fi.Mode().IsRegular() {
		return fmt.Errorf("%s 不是普通文件", filepath.Join(activityDir, filepath.Base(file)))
	}
	return nil
}

// reindexActivity restores every year file, and activity.json, the single
// file earlier versions wrote. Symlinked files are skipped. Each day keeps
// at most MaxDayBuckets buckets; when a file holds more, the largest are kept
// (then the first in key order), so a rebuild is deterministic.
func (l *Library) reindexActivity(ctx context.Context) int {
	dir := filepath.Join(l.Root, activityDir)
	files := []string{filepath.Join(l.Root, "activity.json")}
	if fi, err := os.Lstat(dir); err == nil && fi.IsDir() {
		if ents, err := os.ReadDir(dir); err == nil {
			for _, e := range ents {
				if e.Type().IsRegular() && activityYearFile.MatchString(e.Name()) {
					files = append(files, filepath.Join(dir, e.Name()))
				}
			}
		}
	}
	var rows []store.ActivityRow
	for _, path := range files {
		if fi, err := os.Lstat(path); err != nil || !fi.Mode().IsRegular() {
			continue
		}
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
			if store.CheckActivityRow(r) == nil {
				rows = append(rows, r)
			}
		}
	}
	slices.SortStableFunc(rows, func(a, b store.ActivityRow) int {
		return cmp.Or(cmp.Compare(a.Day, b.Day), cmp.Compare(b.Seconds, a.Seconds), cmp.Compare(b.Count, a.Count),
			cmp.Compare(a.Kind, b.Kind), cmp.Compare(a.CourseID, b.CourseID), cmp.Compare(a.LectureID, b.LectureID))
	})
	n := 0
	for _, r := range rows {
		if l.Store.PutActivity(ctx, r) == nil {
			n++
		}
	}
	return n
}
