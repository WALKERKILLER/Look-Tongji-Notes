package library

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"

	"lookstudio/lookd/internal/store"
)

// A library copied from another device (backup restore, WebDAV sync) brings
// its files but not the index rows that point at them. reindexLectures
// adopts courses, lectures, their folders, local files and slides from
// course.json, lecture.json and slides/index.json, so the lectures show as
// downloaded. Rows the index already has keep their fields.

type courseMeta struct {
	ID       string          `json:"id"`
	Title    string          `json:"title"`
	Alias    string          `json:"alias"`
	Teacher  string          `json:"teacher"`
	Teachers json.RawMessage `json:"teachers"`
	College  string          `json:"college"`
	Term     string          `json:"term"`
}

type lectureMeta struct {
	ID        string `json:"id"`
	CourseID  string `json:"course_id"`
	Title     string `json:"title"`
	Date      string `json:"date"`
	BeginAt   string `json:"begin_at"`
	EndAt     string `json:"end_at"`
	Lecturer  string `json:"lecturer"`
	Room      string `json:"room"`
	DurationS int64  `json:"duration_seconds"`
	Files     []struct {
		Kind  string          `json:"kind"`
		Path  string          `json:"path"`
		Bytes int64           `json:"bytes"`
		Meta  json.RawMessage `json:"meta"`
	} `json:"files"`
}

func isoUnix(s string) int64 {
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t.Unix()
	}
	return 0
}

func readMeta(p string, v any) bool {
	b, err := os.ReadFile(p)
	return err == nil && json.Unmarshal(b, v) == nil
}

func (l *Library) reindexLectures(ctx context.Context) int {
	count := 0
	courses, _ := filepath.Glob(filepath.Join(l.Abs("courses"), "*", "course.json"))
	for _, cp := range courses {
		var cm courseMeta
		if !readMeta(cp, &cm) || cm.ID == "" {
			continue
		}
		cdir := l.Rel(filepath.Dir(cp))
		if l.Store.AdoptCourse(ctx, store.Course{ID: cm.ID, Title: cm.Title, Alias: cm.Alias, Teacher: cm.Teacher,
			Teachers: cm.Teachers, College: cm.College, Term: cm.Term, Dir: cdir}) != nil {
			continue
		}
		lectures, _ := filepath.Glob(filepath.Join(filepath.Dir(cp), "*", "lecture.json"))
		for _, lp := range lectures {
			var lm lectureMeta
			if !readMeta(lp, &lm) || lm.ID == "" || lm.CourseID != cm.ID {
				continue
			}
			dir := l.Rel(filepath.Dir(lp))
			if l.Store.AdoptLecture(ctx, store.Lecture{ID: lm.ID, CourseID: lm.CourseID, Title: lm.Title, Date: lm.Date,
				BeginAt: isoUnix(lm.BeginAt), EndAt: isoUnix(lm.EndAt), Lecturer: lm.Lecturer, Room: lm.Room,
				HasPlayback: lm.DurationS > 0, DurationS: lm.DurationS, Dir: dir}) != nil {
				continue
			}
			if lec, err := l.Store.Lecture(ctx, lm.ID); err != nil || lec.Dir != dir {
				continue // the index keeps this lecture in another folder
			}
			for _, f := range lm.Files {
				p := filepath.Join(filepath.Dir(lp), filepath.FromSlash(f.Path))
				fi, err := os.Stat(p)
				if err != nil || strings.Contains(f.Path, "..") {
					continue
				}
				a := store.Asset{LectureID: lm.ID, Kind: f.Kind, Path: dir + "/" + f.Path, Bytes: f.Bytes, Meta: f.Meta}
				if !fi.IsDir() {
					a.Bytes = fi.Size()
				}
				if l.Store.PutAsset(ctx, a) == nil {
					count++
				}
				if f.Kind == "slides" {
					l.adoptSlides(ctx, lm.ID, dir+"/"+f.Path)
				}
			}
		}
	}
	return count
}

func (l *Library) adoptSlides(ctx context.Context, lectureID, rel string) {
	if have, err := l.Store.Slides(ctx, lectureID); err != nil || len(have) > 0 {
		return
	}
	var idx struct {
		Items []struct {
			Idx   int    `json:"idx"`
			TSec  int64  `json:"t_sec"`
			File  string `json:"file"`
			IsKey bool   `json:"is_key"`
		} `json:"items"`
	}
	if !readMeta(filepath.Join(l.Abs(rel), "index.json"), &idx) {
		return
	}
	var slides []store.Slide
	for _, it := range idx.Items {
		if it.File == "" || filepath.Base(it.File) != it.File {
			continue
		}
		if _, err := os.Stat(filepath.Join(l.Abs(rel), it.File)); err == nil {
			slides = append(slides, store.Slide{Idx: it.Idx, TSec: it.TSec, IsKey: it.IsKey, Path: rel + "/" + it.File})
		}
	}
	if len(slides) > 0 {
		l.Store.ReplaceSlides(ctx, lectureID, slides)
	}
}

// pruneNotes drops indexed notes whose file is gone.
func (l *Library) pruneNotes(ctx context.Context) {
	notes, err := l.Store.Notes(ctx, "", "")
	if err != nil {
		return
	}
	for _, n := range notes {
		if n.Path == "" {
			continue
		}
		if _, err := os.Stat(l.Abs(n.Path)); os.IsNotExist(err) {
			l.Store.DeleteNote(ctx, n.ID)
		}
	}
}
