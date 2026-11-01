package library

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path"
	"regexp"
	"sort"
	"strings"
)

// CatalogItem identifies a local file without relocating it or reading its body.
type CatalogItem struct {
	Path      string `json:"path"`
	Name      string `json:"name"`
	CourseID  string `json:"course_id"`
	Course    string `json:"course"`
	LectureID string `json:"lecture_id,omitempty"`
	Lecture   string `json:"lecture,omitempty"`
	Pinned    bool   `json:"pinned"`
	NoteID    string `json:"note_id,omitempty"`
	Category  string `json:"category"`
	FileType  string `json:"file_type"`
	Bytes     int64  `json:"bytes"`
	Modified  int64  `json:"modified"`
}

var labName = regexp.MustCompile(`(?i)(^|[^a-z])(lab(\s*\d+|[^a-z]|$)|实验|實驗)`)
var coursewareName = regexp.MustCompile(`(?i)(^|[^a-z])(chp\d|chapter|lecture\d|slides?|ppt)`)

func catalogCategory(name, rel string, note bool) string {
	n := strings.ToLower(name)
	p := strings.ToLower(rel)
	switch {
	case labName.MatchString(n) || labName.MatchString(path.Dir(p)):
		return "lab"
	case strings.Contains(n, "作业") || strings.Contains(n, "homework") || strings.Contains(n, "assignment") || strings.Contains(p, "/homework/") || strings.Contains(path.Dir(p), "作业"):
		return "homework"
	case strings.HasPrefix(n, "transcript."):
		return "transcript"
	case strings.Contains(p, "/slides/"):
		return "slides"
	case strings.Contains(n, "参考") || strings.Contains(n, "reference") || strings.Contains(n, "book") || strings.Contains(n, "教材"):
		return "reference"
	case note:
		return "notes"
	case strings.Contains(p, "/courseware/") || strings.Contains(n, "课件") || coursewareName.MatchString(n):
		return "courseware"
	case strings.HasSuffix(n, ".mp4") || strings.HasSuffix(n, ".mkv") || strings.HasSuffix(n, ".mov") || strings.HasSuffix(n, ".webm"):
		return "video"
	default:
		return "other"
	}
}

// Catalog walks only indexed course folders. Metadata, caches and links are
// omitted; os.Root also confines all filesystem access during a directory swap.
func (l *Library) Catalog(ctx context.Context) ([]CatalogItem, error) {
	return l.CourseCatalog(ctx, "")
}

func (l *Library) CourseCatalog(ctx context.Context, courseID string) ([]CatalogItem, error) {
	courses, err := l.Store.Courses(ctx)
	if err != nil {
		return nil, err
	}
	notes, err := l.Store.Notes(ctx, "", "")
	if err != nil {
		return nil, err
	}
	noteByPath := map[string]int{}
	for i, n := range notes {
		noteByPath[n.Path] = i
	}
	root, err := os.OpenRoot(l.Root)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	out := []CatalogItem{}
	allowed := map[string]bool{"pdf": true, "ppt": true, "pptx": true, "doc": true, "docx": true, "xls": true, "xlsx": true, "csv": true, "md": true, "txt": true, "srt": true, "vtt": true, "mp4": true, "mkv": true, "mov": true, "webm": true, "mp3": true, "wav": true, "m4a": true, "jpg": true, "jpeg": true, "png": true, "webp": true, "zip": true, "7z": true, "tar": true, "gz": true, "c": true, "h": true, "py": true, "ipynb": true}
	for _, c := range courses {
		if c.Dir == "" || (courseID != "" && c.ID != courseID) {
			continue
		}
		if path.Clean(c.Dir) != c.Dir || !strings.HasPrefix(c.Dir, "courses/") {
			return nil, fmt.Errorf("invalid indexed course directory")
		}
		info, e := root.Lstat(c.Dir)
		if os.IsNotExist(e) {
			continue
		}
		if e != nil {
			return nil, e
		}
		if info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		lectures, e := l.Store.Lectures(ctx, c.ID)
		if e != nil {
			return nil, e
		}
		err = fs.WalkDir(root.FS(), c.Dir, func(rel string, d fs.DirEntry, walkErr error) error {
			if e := ctx.Err(); e != nil {
				return e
			}
			if walkErr != nil {
				return walkErr
			}
			if d.Type()&os.ModeSymlink != 0 {
				return nil
			}
			name := d.Name()
			if d.IsDir() {
				if strings.HasPrefix(name, ".") || strings.HasSuffix(name, ".parsed") || name == "cache" || name == "node_modules" {
					return fs.SkipDir
				}
				return nil
			}
			if strings.HasPrefix(name, ".") {
				return nil
			}
			ext := strings.TrimPrefix(strings.ToLower(path.Ext(name)), ".")
			if !allowed[ext] {
				return nil
			}
			info, e := d.Info()
			if e != nil {
				return e
			}
			if !info.Mode().IsRegular() {
				return nil
			}
			it := CatalogItem{Path: rel, Name: name, CourseID: c.ID, Course: c.Title, FileType: ext, Bytes: info.Size(), Modified: info.ModTime().Unix()}
			for _, lec := range lectures {
				if lec.Dir != "" && strings.HasPrefix(rel, lec.Dir+"/") {
					it.LectureID = lec.ID
					it.Lecture = lec.Title
					break
				}
			}
			ni, isNote := noteByPath[rel]
			if isNote {
				it.NoteID = notes[ni].ID
				it.Pinned = notes[ni].Pinned
				it.Name = notes[ni].Title
			}
			it.Category = catalogCategory(it.Name, rel, isNote)
			out = append(out, it)
			if len(out) > 20000 {
				return fmt.Errorf("资料超过 20000 项，请缩小课程库后重试")
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if a.Course != b.Course {
			return a.Course < b.Course
		}
		if a.Category != b.Category {
			return a.Category < b.Category
		}
		if a.Pinned != b.Pinned {
			return a.Pinned
		}
		return a.Path < b.Path
	})
	return out, nil
}
