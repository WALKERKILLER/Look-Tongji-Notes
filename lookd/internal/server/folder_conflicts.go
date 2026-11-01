package server

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"lookstudio/lookd/internal/datasync"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func (s *Server) folderConflictPaths() (map[string]string, error) {
	paths := map[string]string{}
	root := filepath.Join(s.Lib.Root, datasync.ConflictDir)
	err := filepath.WalkDir(root, func(p string, d os.DirEntry, e error) error {
		if os.IsNotExist(e) {
			return nil
		}
		if e != nil {
			return e
		}
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(root, p)
		sum := sha256.Sum256([]byte(filepath.ToSlash(rel)))
		paths[hex.EncodeToString(sum[:])] = p
		return nil
	})
	return paths, err
}
func (s *Server) folderConflicts(_ http.ResponseWriter, r *http.Request) (any, error) {
	paths, e := s.folderConflictPaths()
	if e != nil {
		return nil, e
	}
	resolved := s.resolvedFolderConflicts()
	out := []map[string]any{}
	for id, p := range paths {
		if resolved[id] {
			continue
		}
		st, e := os.Stat(p)
		if e != nil {
			continue
		}
		rel, _ := filepath.Rel(filepath.Join(s.Lib.Root, datasync.ConflictDir), p)
		out = append(out, map[string]any{"id": id, "path": filepath.ToSlash(rel), "bytes": st.Size()})
	}
	return out, nil
}
func fileDigest(p string) string {
	f, e := os.Open(p)
	if e != nil {
		return ""
	}
	defer f.Close()
	h := sha256.New()
	io.Copy(h, f)
	return hex.EncodeToString(h.Sum(nil))
}
func (s *Server) folderConflict(_ http.ResponseWriter, r *http.Request) (any, error) {
	paths, e := s.folderConflictPaths()
	if e != nil {
		return nil, e
	}
	p := paths[r.PathValue("conflict")]
	if p == "" {
		return nil, apiError{404, "冲突副本不存在"}
	}
	rel, _ := filepath.Rel(filepath.Join(s.Lib.Root, datasync.ConflictDir), p)
	parts := strings.Split(filepath.ToSlash(rel), "/")

	if len(parts) < 3 {
		return nil, badRequest("冲突路径无效")
	}
	targetRoot := s.Lib.Root
	dataChanged := false
	relative := ""
	switch parts[1] {
	case "library":
		relative = filepath.Join(parts[2:]...)
	case "courses", "quizzes", "notes":
		relative = filepath.Join(parts[1:]...)
	case "course-data":
		if len(parts) < 4 || s.Data == nil {
			return nil, badRequest("冲突路径无效")
		}
		selected := false
		for _, id := range s.Data.Status().CourseIDs {
			if id == parts[2] {
				selected = true
			}
		}
		if !selected {
			return nil, badRequest("此课程未启用同步")
		}
		if parts[3] == "quizzes" && len(parts) == 5 {
			relative = filepath.Join("quizzes", parts[4])
		} else {
			targetRoot = s.Data.Roots.Data
			dataChanged = true
			if parts[3] == "metadata.json" && len(parts) == 4 {
				relative = filepath.Join("agent", "course-sessions", parts[2]+".json")
			} else if parts[3] == "assistant" && len(parts) == 5 {
				relative = filepath.Join("agent", "sessions", parts[4])
			} else {
				return nil, badRequest("冲突路径无效")
			}
		}
	default:
		return nil, badRequest("此副本需要在本机文件夹中处理")
	}
	target := filepath.Join(targetRoot, relative)
	if e := guardConflictTarget(targetRoot, target); e != nil {
		return nil, e
	}

	if r.Method == "GET" {
		f, e := os.Open(p)
		if e != nil {
			return nil, e
		}
		defer f.Close()
		b, e := io.ReadAll(io.LimitReader(f, 1<<20))
		return map[string]any{"body": string(b), "current_hash": fileDigest(target)}, e
	}
	var in struct {
		Action       string `json:"action"`
		ExpectedHash string `json:"expected_hash"`
	}
	if e := decode(r, &in); e != nil {
		return nil, e
	}
	if in.ExpectedHash != fileDigest(target) {
		return nil, apiError{409, "当前版本已改变，请重新查看"}
	}
	if in.Action == "keep" {
		return ok(), s.markFolderConflict(r.PathValue("conflict"))
	}
	if in.Action != "restore" {
		return nil, badRequest("无效的处理方式")
	}
	if st, e := os.Stat(target); e == nil && st.Mode().IsRegular() {
		backup := filepath.Join(s.Lib.Root, datasync.ConflictDir, "manual-"+time.Now().Format("20060102-150405.000"), filepath.Join(parts[1:]...))
		os.MkdirAll(filepath.Dir(backup), 0700)
		if e = copyConflict(target, backup); e != nil {
			return nil, e
		}
	}
	if e = copyConflict(p, target); e != nil {
		return nil, e
	}
	s.DataArrived(r.Context(), true, dataChanged)
	if s.Data != nil {
		s.Data.Soon(s.Ctx)
	}
	return ok(), s.markFolderConflict(r.PathValue("conflict"))
}
func copyConflict(src, dst string) error {
	if src == dst {
		return errors.New("路径相同")
	}
	r, e := os.Open(src)
	if e != nil {
		return e
	}
	defer r.Close()
	if e = os.MkdirAll(filepath.Dir(dst), 0700); e != nil {
		return e
	}
	w, e := os.CreateTemp(filepath.Dir(dst), ".conflict-*")
	if e != nil {
		return e
	}
	defer os.Remove(w.Name())
	_, e = io.Copy(w, r)
	w.Close()
	if e != nil {
		return e
	}
	return os.Rename(w.Name(), dst)
}

func (s *Server) folderDraft(_ http.ResponseWriter, r *http.Request) (any, error) {
	lec, err := s.St.Lecture(r.Context(), r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	if lec.Dir == "" {
		return nil, badRequest("课次尚未建立本地目录")
	}
	b, err := io.ReadAll(io.LimitReader(r.Body, 32<<20+1))
	if err != nil {
		return nil, err
	}
	if len(b) > 32<<20 || !json.Valid(b) {
		return nil, badRequest("草稿格式无效或超过限制")
	}
	sum := sha256.Sum256(b)
	dest := filepath.Join(s.Lib.Root, datasync.TrashDir, "canvas-draft-"+hex.EncodeToString(sum[:]), "library", filepath.FromSlash(lec.Dir), "study-canvas.json")
	if err = guardConflictTarget(s.Lib.Root, dest); err != nil {
		return nil, err
	}
	if err = os.MkdirAll(filepath.Dir(dest), 0700); err != nil {
		return nil, err
	}
	if err = os.WriteFile(dest, b, 0600); err != nil {
		return nil, err
	}
	return ok(), nil
}

func (s *Server) resolvedFolderConflicts() map[string]bool {
	out := map[string]bool{}
	if s.Data == nil {
		return out
	}
	b, e := os.ReadFile(filepath.Join(s.Data.Roots.Data, "folder-conflicts-resolved.json"))
	if e == nil {
		json.Unmarshal(b, &out)
	}
	return out
}
func (s *Server) markFolderConflict(id string) error {
	if s.Data == nil {
		return nil
	}
	out := s.resolvedFolderConflicts()
	out[id] = true
	b, e := json.Marshal(out)
	if e != nil {
		return e
	}
	return os.WriteFile(filepath.Join(s.Data.Roots.Data, "folder-conflicts-resolved.json"), b, 0600)
}
func guardConflictTarget(root, p string) error {
	rel, e := filepath.Rel(root, p)
	if e != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return errors.New("冲突路径无效")
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
			return errors.New("冲突路径含有符号链接")
		}
	}
	return nil
}
