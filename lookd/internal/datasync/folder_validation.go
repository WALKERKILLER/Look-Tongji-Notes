package datasync

import (
	"bufio"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	folderObjectLimit int64 = 4 << 30
	folderStageLimit  int64 = 8 << 30
	folderRecordLimit int64 = 32 << 20
)

// Bound the complete incoming generation, including conflict backups, before
// opening objects. Hash aliases must agree on size and count only once.
func validateFolderTransfer(entries map[string]folderEntry, local map[string]string) error {
	sizes := map[string]int64{}
	counted := map[string]bool{}
	var total int64
	add := func(e Entry, needed bool, limit int64) error {
		if e.Size < 0 || e.Size > limit {
			return fmt.Errorf("同步对象大小无效或超过 %d MiB，请缩小同步范围", limit>>20)
		}
		if len(e.Hash) != 64 {
			return errors.New("文件哈希无效")
		}
		if _, err := hex.DecodeString(e.Hash); err != nil {
			return errors.New("文件哈希无效")
		}
		if old, ok := sizes[e.Hash]; ok {
			if old != e.Size {
				return errors.New("相同同步对象的大小不一致")
			}
		}
		sizes[e.Hash] = e.Size
		if needed && !counted[e.Hash] {
			if e.Size > folderStageLimit-total {
				return errors.New("本轮同步暂存量超过 8 GiB，请缩小同步范围或关闭媒体同步")
			}
			total += e.Size
			counted[e.Hash] = true
		}
		return nil
	}
	for p, v := range entries {
		limit := folderObjectLimit
		name := filepath.Base(p)
		if name == "course.json" || name == "lecture.json" || name == "metadata.json" || strings.Contains(p, "/quizzes/") {
			limit = folderRecordLimit
		}
		if v.Deleted == 0 {
			if err := add(v.Entry, v.Hash != local[p], limit); err != nil {
				return err
			}
		}
		for _, a := range v.Alternatives {
			if err := add(a, true, limit); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Service) validateFolderCourseDir(id, dir string, dirs map[string]string) error {
	for other, target := range dirs {
		if other != id && target == dir {
			return errors.New("同步课程目录已被其他课程使用")
		}
	}
	abs := filepath.Join(s.Roots.Library, filepath.FromSlash(dir))
	if err := safeWorkingPath(filepath.Join(abs, "course.json"), s.Roots.Library); err != nil {
		return err
	}
	if _, err := os.Stat(abs); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	var c struct {
		ID string `json:"id"`
	}
	if err := readFolderJSON(filepath.Join(abs, "course.json"), &c); err != nil {
		return fmt.Errorf("无法确认同步目标课程归属：%w", err)
	}
	if c.ID != id {
		return errors.New("同步目标目录属于其他课程，已停止导入")
	}
	return nil
}

func readFolderJSON(p string, v any) (err error) {
	defer func() {
		if err != nil {
			err = fmt.Errorf("读取同步索引 %s：%w", p, err)
		}
	}()
	f, err := os.Open(p)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, folderRecordLimit+1))
	if err != nil {
		return err
	}
	if int64(len(b)) > folderRecordLimit {
		return errors.New("同步索引文档超过 32 MiB")
	}
	return json.Unmarshal(b, v)
}

func folderSessionID(p string) (id string, err error) {
	defer func() {
		if err != nil {
			err = fmt.Errorf("读取助手会话 %s：%w", p, err)
		}
	}()
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	scan := bufio.NewScanner(f)
	scan.Buffer(make([]byte, 4096), 1<<20)
	var h struct {
		Type string `json:"type"`
		ID   string `json:"id"`
	}
	if !scan.Scan() || json.Unmarshal(scan.Bytes(), &h) != nil || h.Type != "session" || h.ID == "" {
		return "", errors.New("助手会话头无效，无法确认归属")
	}
	return h.ID, nil
}

type folderSessionMeta map[string]struct {
	CourseID string `json:"course_id"`
}

// Global quiz/session destinations and session IDs must retain their owner.
// Run the full preflight inside ApplyFiles, before any file can be installed.
func (s *Service) validateFolderTargets(ctx context.Context, entries map[string]folderEntry, staged map[string]string, released map[string]bool) error {
	hasExtras := false
	for p := range entries {
		abs, ok := s.folderAbs(p)
		if !ok {
			return errors.New("同步文件路径无效")
		}
		root := s.Roots.Library
		if folderPrivateData(p) {
			root = s.Roots.Data
		}
		if err := safeWorkingPath(abs, root); err != nil {
			return err
		}
		if strings.HasPrefix(p, "course-data/") {
			hasExtras = true
		}
	}
	if !hasExtras {
		return nil
	}
	current := folderSessionMeta{}
	if err := readFolderJSON(filepath.Join(s.Roots.Data, "agent", "sessions-meta.json"), &current); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	owners := map[string]string{}
	for id, m := range current {
		owners[id] = m.CourseID
	}
	// The global index is authoritative. Selected import caches only supply
	// missing IDs while a newly received session awaits server indexing.
	for p, v := range entries {
		if !strings.HasPrefix(p, "course-data/") || !strings.HasSuffix(p, "/metadata.json") || v.Deleted != 0 {
			continue
		}
		abs, _ := s.folderAbs(p)
		var meta folderSessionMeta
		if err := readFolderJSON(abs, &meta); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return err
		}
		course := strings.Split(p, "/")[1]
		for id, m := range meta {
			if _, ok := current[id]; ok {
				continue
			}
			if m.CourseID != course {
				return fmt.Errorf("本机会话索引归属无效：%s", abs)
			}
			if old, ok := owners[id]; ok && old != course {
				return fmt.Errorf("本机会话索引归属冲突：%s", abs)
			}
			owners[id] = course
		}
	}
	headers, _, err := s.folderSessionHeaders(ctx)
	if err != nil {
		return err
	}
	sessionPaths := map[string][]string{}
	for p, id := range headers {
		sessionPaths[id] = append(sessionPaths[id], p)
		if _, ok := owners[id]; !ok {
			owners[id] = ""
		}
	}
	source := func(p string, v folderEntry) string {
		if staged[v.Hash] != "" {
			return staged[v.Hash]
		}
		abs, _ := s.folderAbs(p)
		return abs
	}
	for p, v := range entries {
		if !strings.HasPrefix(p, "course-data/") || !strings.HasSuffix(p, "/metadata.json") || v.Deleted != 0 {
			continue
		}
		course := strings.Split(p, "/")[1]
		var meta folderSessionMeta
		if err := readFolderJSON(source(p, v), &meta); err != nil {
			return err
		}
		for id, m := range meta {
			if id == "" || m.CourseID != course {
				return errors.New("同步会话索引不属于所选课程")
			}
			if owner, ok := owners[id]; ok && owner != course {
				return errors.New("同步会话标识已属于其他课程或普通聊天")
			}
			owners[id] = course
		}
	}
	targets := map[string]string{}
	incomingSessions := map[string]string{}
	for p, v := range entries {
		if !strings.HasPrefix(p, "course-data/") {
			continue
		}
		if v.Deleted != 0 && released[p] {
			continue
		}
		abs, ok := s.folderAbs(p)
		if !ok {
			return errors.New("同步文件路径无效")
		}
		course := strings.Split(p, "/")[1]
		if owner, ok := targets[abs]; ok && owner != course {
			return errors.New("多个课程指向同一同步目标")
		}
		targets[abs] = course
		root := s.Roots.Data
		if strings.Contains(p, "/quizzes/") {
			root = s.Roots.Library
		}
		if err := safeWorkingPath(abs, root); err != nil {
			return err
		}
		_, err := os.Stat(abs)
		exists := err == nil
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if strings.Contains(p, "/quizzes/") && exists {
			var doc struct {
				Quiz struct {
					CourseID string `json:"course_id"`
				} `json:"quiz"`
			}
			if err := readFolderJSON(abs, &doc); err != nil {
				return err
			}
			if doc.Quiz.CourseID != course {
				return errors.New("同步练习目标属于其他课程")
			}
		}
		if !strings.Contains(p, "/assistant/") {
			continue
		}
		localID := ""
		if exists {
			localID, err = folderSessionID(abs)
			if err != nil {
				return err
			}
			if owners[localID] != course {
				return errors.New("同步会话目标属于其他课程或普通聊天")
			}
		}
		if v.Deleted != 0 {
			continue
		}
		id, err := folderSessionID(source(p, v))
		if err != nil {
			return err
		}
		if owners[id] != course || (exists && localID != id) {
			return errors.New("同步会话正文与课程归属不一致")
		}
		if old, ok := incomingSessions[id]; ok && old != abs {
			return fmt.Errorf("同步会话重复：%s 与 %s", old, abs)
		}
		incomingSessions[id] = abs
		for _, old := range sessionPaths[id] {
			if old == abs {
				continue
			}
			oldPath := "course-data/" + course + "/assistant/" + filepath.Base(old)
			tombstone, ok := entries[oldPath]
			if !ok || tombstone.Deleted == 0 {
				return fmt.Errorf("同步会话标识已使用其他文件名：%s；改名需同时删除旧路径", old)
			}
		}
	}
	return nil
}
