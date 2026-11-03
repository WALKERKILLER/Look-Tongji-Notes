package server

import (
	"context"
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
	resolved, e := s.resolvedFolderConflicts()
	if e != nil {
		return nil, e
	}
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
func fileDigest(p string) (string, error) {
	f, err := os.Open(p)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
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
		if e != nil {
			return nil, e
		}
		hash, e := fileDigest(target)
		return map[string]any{"body": string(b), "current_hash": hash}, e
	}
	var in struct {
		Action       string `json:"action"`
		ExpectedHash string `json:"expected_hash"`
	}
	if e := decode(r, &in); e != nil {
		return nil, e
	}
	if in.Action != "keep" && in.Action != "restore" {
		return nil, badRequest("无效的处理方式")
	}
	// Serialize restore with local saves and received-file application. Check the
	// expected revision and ownership inside the same lock as the replacement.
	restored := false
	e = s.Lib.ApplySyncFiles(func() error {
		if err := r.Context().Err(); err != nil {
			return err
		}
		if err := guardConflictTarget(targetRoot, target); err != nil {
			return err
		}
		current, err := fileDigest(target)
		if err != nil {
			return err
		}
		if in.ExpectedHash != current {
			return apiError{409, "当前版本已改变，请重新查看"}
		}
		if in.Action == "keep" {
			return s.markFolderConflict(r.PathValue("conflict"))
		}
		folderCopy := parts[1] == "library" || parts[1] == "course-data" || strings.HasPrefix(parts[0], "folder-")
		if folderCopy && (s.Data == nil || s.Data.Status().Kind != "folder") {
			return badRequest("请先接入同步文件夹并选择此课程，再恢复副本")
		}
		if s.Data != nil && s.Data.Status().Kind == "folder" {
			logical := filepath.ToSlash(filepath.Join(parts[1:]...))
			if parts[1] != "library" && parts[1] != "course-data" {
				logical = "library/" + filepath.ToSlash(relative)
			}
			if err := s.Data.ValidateFolderRestore(r.Context(), logical, p); err != nil {
				return err
			}
		}
		// Validate the acknowledgement index before replacing any working file.
		if _, err := s.resolvedFolderConflicts(); err != nil {
			return err
		}
		if current != "" {
			backup := filepath.Join(s.Lib.Root, datasync.ConflictDir, "manual-"+time.Now().Format("20060102-150405.000000000"), filepath.Join(parts[1:]...))
			if err := guardConflictTarget(s.Lib.Root, backup); err != nil {
				return err
			}
			if err := copyConflict(target, backup); err != nil {
				return err
			}
		}
		if err := copyConflict(p, target); err != nil {
			return err
		}
		restored = true
		return s.markFolderConflict(r.PathValue("conflict"))
	})
	// The working file is installed even if recording its acknowledgement fails.
	// Refresh it after releasing the library lock, including on client disconnect.
	if restored {
		refreshCtx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 30*time.Second)
		s.DataArrived(refreshCtx, true, dataChanged)
		cancel()
		if s.Data != nil {
			s.Data.Soon(s.Ctx)
		}
	}
	if e != nil {
		return nil, e
	}
	return ok(), nil
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
	if closeErr := w.Close(); e == nil {
		e = closeErr
	}
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

func (s *Server) resolvedFolderConflicts() (map[string]bool, error) {
	out := map[string]bool{}
	if s.Data == nil {
		return out, nil
	}
	err := datasync.ReadFolderIndex(filepath.Join(s.Data.Roots.Data, "folder-conflicts-resolved.json"), &out)
	if errors.Is(err, os.ErrNotExist) {
		return out, nil
	}
	return out, err
}
func (s *Server) markFolderConflict(id string) error {
	if s.Data == nil {
		return nil
	}
	out, err := s.resolvedFolderConflicts()
	if err != nil {
		return err
	}
	out[id] = true
	return writeFolderIndex(filepath.Join(s.Data.Roots.Data, "folder-conflicts-resolved.json"), out)
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
