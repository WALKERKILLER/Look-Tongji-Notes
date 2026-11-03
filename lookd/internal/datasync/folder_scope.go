package datasync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

// Export only selected courses. A malformed previously tracked file stops the
// round; an unrelated malformed global file cannot become a deletion.
func (s *Service) folderExtras(ctx context.Context, ids []string, tracked map[string]bool) ([]File, error) {
	wanted := map[string]bool{}
	for _, id := range ids {
		wanted[id] = true
	}
	trackedAbs := map[string]bool{}
	for p := range tracked {
		if abs, ok := s.folderAbs(p); ok {
			trackedAbs[abs] = true
		}
	}
	var out []File
	add := func(p, abs string) error {
		fi, err := os.Lstat(abs)
		if err != nil {
			return err
		}
		if !fi.Mode().IsRegular() {
			return fmt.Errorf("同步文件不是普通文件：%s", abs)
		}
		out = append(out, File{Path: p, Abs: abs, Size: fi.Size(), ModTime: fi.ModTime()})
		return nil
	}
	quizzes, err := filepath.Glob(filepath.Join(s.Roots.Library, "quizzes", "*.json"))
	if err != nil {
		return nil, err
	}
	for _, abs := range quizzes {
		var v struct {
			Quiz struct {
				CourseID string `json:"course_id"`
			} `json:"quiz"`
		}
		if err := readFolderJSON(abs, &v); err != nil {
			if trackedAbs[abs] {
				return nil, err
			}
			continue
		}
		if wanted[v.Quiz.CourseID] {
			if err := add("course-data/"+v.Quiz.CourseID+"/quizzes/"+filepath.Base(abs), abs); err != nil {
				return nil, err
			}
		}
	}
	meta := map[string]map[string]any{}
	metaPath := filepath.Join(s.Roots.Data, "agent", "sessions-meta.json")
	if err := readFolderJSON(metaPath, &meta); err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
		// Recover a first import interrupted before the server indexed it.
		for _, course := range ids {
			cached := filepath.Join(s.Roots.Data, "agent", "course-sessions", course+".json")
			var entries map[string]map[string]any
			if err := readFolderJSON(cached, &entries); err != nil {
				if errors.Is(err, os.ErrNotExist) {
					continue
				}
				return nil, err
			}
			for id, v := range entries {
				if v["course_id"] != course {
					return nil, fmt.Errorf("会话索引归属无效：%s", cached)
				}
				if old, ok := meta[id]; ok && old["course_id"] != course {
					return nil, fmt.Errorf("会话索引归属冲突：%s", cached)
				}
				meta[id] = v
			}
		}
	}
	// Parse each header once, independently of the number of selected courses.
	headers, invalid, err := s.folderSessionHeaders(ctx)
	if err != nil {
		return nil, err
	}
	for abs, err := range invalid {
		selected := trackedAbs[abs]
		for id, m := range meta {
			course, _ := m["course_id"].(string)
			if wanted[course] && (filepath.Base(abs) == id+".jsonl" || strings.HasSuffix(filepath.Base(abs), "_"+id+".jsonl")) {
				selected = true
			}
		}
		if selected {
			return nil, err
		}
	}
	presentIDs := map[string]bool{}
	for _, id := range headers {
		presentIDs[id] = true
	}
	for _, course := range ids {
		selected := map[string]map[string]any{}
		for id, v := range meta {
			if v["course_id"] == course && presentIDs[id] {
				selected[id] = v
			}
		}
		generated := filepath.Join(s.Roots.Data, "agent", "course-sessions", course+".json")
		// This is an export cache, not an independent source of ownership.
		if len(selected) == 0 {
			if err := os.Remove(generated); err != nil && !errors.Is(err, os.ErrNotExist) {
				return nil, err
			}
			continue
		}
		b, _ := json.Marshal(selected)
		if err := writeFile(generated, time.Time{}, func(f *os.File) error { _, e := f.Write(b); return e }); err != nil {
			return nil, err
		}
		if err := add("course-data/"+course+"/metadata.json", generated); err != nil {
			return nil, err
		}
	}
	for abs, id := range headers {
		course, _ := meta[id]["course_id"].(string)
		if wanted[course] {
			if err := add("course-data/"+course+"/assistant/"+filepath.Base(abs), abs); err != nil {
				return nil, err
			}
		}
	}
	return out, ctx.Err()
}

// Invalid, unrelated headers are retained on disk and only block a round when
// a selected/tracked file or an incoming destination actually depends on them.
func (s *Service) folderSessionHeaders(ctx context.Context) (map[string]string, map[string]error, error) {
	paths, err := filepath.Glob(filepath.Join(s.Roots.Data, "agent", "sessions", "*.jsonl"))
	if err != nil {
		return nil, nil, err
	}
	headers, invalid := map[string]string{}, map[string]error{}
	for _, p := range paths {
		if err := ctx.Err(); err != nil {
			return nil, nil, err
		}
		id, err := folderSessionID(p)
		if err != nil {
			invalid[p] = err
		} else {
			headers[p] = id
		}
	}
	return headers, invalid, nil
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

func folderPrivateData(p string) bool {
	return strings.HasPrefix(p, "course-data/") && (strings.Contains(p, "/assistant/") || strings.HasSuffix(p, "/metadata.json"))
}
