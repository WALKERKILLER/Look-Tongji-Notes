package datasync

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Non-course-tree files are namespaced by course in the exchange directory.
// Their working locations remain compatible with the existing app and agent.
func (s *Service) folderAbs(p string) (string, bool) {
	if strings.HasPrefix(p, "library/") {
		return s.Roots.Abs(p)
	}
	if !validFolderPath(p) {
		return "", false
	}
	parts := strings.Split(p, "/")
	if len(parts) == 3 && parts[0] == "course-data" && parts[2] == "metadata.json" {
		return filepath.Join(s.Roots.Data, "agent", "course-sessions", parts[1]+".json"), true
	}
	if len(parts) != 4 || parts[0] != "course-data" {
		return "", false
	}
	switch parts[2] {
	case "quizzes":
		if strings.HasSuffix(parts[3], ".json") {
			return filepath.Join(s.Roots.Library, "quizzes", parts[3]), true
		}
	case "assistant":
		if strings.HasSuffix(parts[3], ".jsonl") {
			return filepath.Join(s.Roots.Data, "agent", "sessions", parts[3]), true
		}
	}
	return "", false
}
func (s *Service) folderExtras(ctx context.Context, ids []string) ([]File, error) {
	wanted := map[string]bool{}
	for _, id := range ids {
		wanted[id] = true
	}
	var out []File
	add := func(p, abs string) {
		if fi, e := os.Lstat(abs); e == nil && fi.Mode().IsRegular() {
			out = append(out, File{Path: p, Abs: abs, Size: fi.Size(), ModTime: fi.ModTime()})
		}
	}
	quizzes, _ := filepath.Glob(filepath.Join(s.Roots.Library, "quizzes", "*.json"))
	for _, abs := range quizzes {
		var v struct {
			Quiz struct {
				CourseID string `json:"course_id"`
			} `json:"quiz"`
		}
		if err := readFolderJSON(abs, &v); err != nil {
			return nil, err
		}
		if wanted[v.Quiz.CourseID] {
			add("course-data/"+v.Quiz.CourseID+"/quizzes/"+filepath.Base(abs), abs)
		}
	}
	meta := map[string]map[string]any{}
	if err := readFolderJSON(filepath.Join(s.Roots.Data, "agent", "sessions-meta.json"), &meta); err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	for _, course := range ids {
		selected := map[string]map[string]any{}
		for id, v := range meta {
			if v["course_id"] == course {
				selected[id] = v
			}
		}
		generated := filepath.Join(s.Roots.Data, "agent", "course-sessions", course+".json")
		if len(selected) > 0 {
			b, _ := json.Marshal(selected)
			if e := writeFile(generated, time.Time{}, func(f *os.File) error { _, e := f.Write(b); return e }); e != nil {
				return nil, e
			}
			add("course-data/"+course+"/metadata.json", generated)
		}
		if len(selected) == 0 {
			continue
		}
		sessions, _ := filepath.Glob(filepath.Join(s.Roots.Data, "agent", "sessions", "*.jsonl"))
		for _, abs := range sessions {
			id, err := folderSessionID(abs)
			if err != nil {
				return nil, err
			}
			if _, ok := selected[id]; ok {
				add("course-data/"+course+"/assistant/"+filepath.Base(abs), abs)
			}
		}
	}
	return out, ctx.Err()
}

func safeWorkingPath(abs, root string) error {
	rel, e := filepath.Rel(root, abs)
	if e != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return errors.New("文件超出工作目录")
	}
	cur := root
	for _, part := range strings.Split(rel, string(filepath.Separator)) {
		cur = filepath.Join(cur, part)
		st, e := os.Lstat(cur)
		if os.IsNotExist(e) {
			continue
		}
		if e != nil {
			return e
		}
		if st.Mode()&os.ModeSymlink != 0 {
			return errors.New("同步目标不可包含符号链接")
		}
	}
	return nil
}

// Validate index-bearing documents before any generation is materialized. A
// valid hash proves transfer integrity, but not that the document is in scope.
func validateFolderDocument(p, staged string, dirs map[string]string) error {
	course := ""
	for id, dir := range dirs {
		if p == "library/"+dir+"/course.json" || strings.HasPrefix(p, "library/"+dir+"/") {
			course = id
			break
		}
	}
	if strings.HasPrefix(p, "course-data/") {
		course = strings.Split(p, "/")[1]
	}
	name := filepath.Base(p)
	if name != "course.json" && name != "lecture.json" && !strings.Contains(p, "/quizzes/") {
		return nil
	}
	var v struct {
		ID       string `json:"id"`
		CourseID string `json:"course_id"`
		Quiz     struct {
			CourseID string `json:"course_id"`
		} `json:"quiz"`
	}
	if err := readFolderJSON(staged, &v); err != nil {
		return errors.New("同步索引文档格式无效或超过 32 MiB")
	}
	if name == "course.json" {
		if v.ID != course {
			return errors.New("同步课程标识与接入范围不一致")
		}
	} else if name == "lecture.json" {
		if v.CourseID != course {
			return errors.New("同步课次不属于所选课程")
		}
	} else if v.Quiz.CourseID != course {
		return errors.New("同步练习不属于所选课程")
	}
	return nil
}
