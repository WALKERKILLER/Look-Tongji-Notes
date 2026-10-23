package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"lookstudio/lookd/internal/datasync"
	"lookstudio/lookd/internal/store"
)

// Data moving between devices (backups, WebDAV sync) and the storage
// overview with its cleanup.
// Contract: docs/specs/0014-data-sync-and-backup.md

func dataErr(err error) error {
	var he *datasync.HTTPError
	switch {
	case errors.Is(err, datasync.ErrBusy), errors.Is(err, datasync.ErrNotConfigured):
		return apiError{http.StatusConflict, err.Error()}
	case errors.Is(err, datasync.ErrNotBackup), errors.Is(err, os.ErrNotExist):
		return apiError{http.StatusBadRequest, orMsg(err, "备份已失效，请重新选择文件")}
	case errors.As(err, &he):
		if he.Status == http.StatusUnauthorized {
			return apiError{http.StatusUnauthorized, err.Error()}
		}
		return apiError{http.StatusBadGateway, err.Error()}
	}
	return err
}

func orMsg(err error, msg string) string {
	if errors.Is(err, os.ErrNotExist) {
		return msg
	}
	return err.Error()
}

// UserState and MergeUserState adapt the index's personal state for the
// datasync service.
func (s *Server) UserState(ctx context.Context) ([]byte, error) {
	st, err := s.St.ExportUserState(ctx)
	if err != nil {
		return nil, err
	}
	return json.Marshal(st)
}

func (s *Server) MergeUserState(ctx context.Context, b []byte) (bool, error) {
	var st store.UserState
	if err := json.Unmarshal(b, &st); err != nil {
		return false, nil // an unreadable state is skipped, not fatal
	}
	return s.St.MergeUserState(ctx, st)
}

// DataArrived refreshes what reads files that came from another device.
func (s *Server) DataArrived(ctx context.Context, library, data bool) {
	if library {
		if _, err := s.Lib.Reindex(ctx); err != nil {
			slog.Warn("reindex after sync", "err", err)
		}
		// The events the pages already reload on.
		for _, kind := range []string{"courses_changed", "lecture_changed", "notes_changed", "schedule_changed",
			"activity_changed", "quizzes_changed"} {
			s.Bus.Publish(kind, map[string]string{"reason": "sync"})
		}
	}
	if data && s.Agent != nil {
		s.Agent.Restart("") // the assistant reads its sessions and tasks at start
	}
}

func (s *Server) dataExport(w http.ResponseWriter, r *http.Request) {
	media := r.URL.Query().Get("media") == "1"
	name := fmt.Sprintf("LookStudio-备份-%s.zip", time.Now().Format("20060102-1504"))
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", "attachment; filename*=UTF-8''"+url.PathEscape(name))
	if err := s.Data.Export(r.Context(), w, media); err != nil {
		slog.Warn("export backup", "err", err) // headers are gone; the client sees a broken zip
	}
}

func (s *Server) dataImport(_ http.ResponseWriter, r *http.Request) (any, error) {
	pv, err := s.Data.Receive(r.Context(), r.Body)
	if err != nil {
		return nil, dataErr(err)
	}
	return pv, nil
}

func (s *Server) dataRestore(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Mode string `json:"mode"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	res, err := s.Data.Restore(r.Context(), r.PathValue("id"), in.Mode)
	if err != nil {
		return nil, dataErr(err)
	}
	return res, nil
}

func (s *Server) syncConfigure(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in datasync.Settings
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	st, err := s.Data.Configure(r.Context(), in)
	if err != nil {
		return nil, dataErr(err)
	}
	return st, nil
}

func (s *Server) syncRun(http.ResponseWriter, *http.Request) (any, error) {
	st := s.Data.Status()
	switch {
	case !st.Configured:
		return nil, dataErr(datasync.ErrNotConfigured)
	case st.Running:
		return st, nil
	}
	go func() {
		ctx, cancel := context.WithTimeout(s.Ctx, 2*time.Hour)
		defer cancel()
		if _, err := s.Data.Sync(ctx); err != nil && !errors.Is(err, datasync.ErrBusy) {
			slog.Warn("webdav sync", "err", err)
		}
	}()
	st.Running = true
	return st, nil
}

// ---- storage ----

type storageCategory struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Bytes int64  `json:"bytes"`
	Files int    `json:"files"`
}

type storageReport struct {
	Library    string            `json:"library"`
	Categories []storageCategory `json:"categories"`
	Total      int64             `json:"total"`
	// Cleanable is what POST /api/storage/clean may free.
	Cleanable map[string]int64 `json:"cleanable"`
	Models    int64            `json:"models"`
	Assistant int64            `json:"assistant"`
	Runtime   int64            `json:"runtime"`
}

func dirSize(root string) int64 {
	var n int64
	filepath.WalkDir(root, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && d.Type().IsRegular() {
			if fi, err := d.Info(); err == nil {
				n += fi.Size()
			}
		}
		return nil
	})
	return n
}

// cacheEntries lists the transcription scratch files no job still needs.
func (s *Server) cacheEntries(ctx context.Context) (all, stale []string, err error) {
	active, err := s.St.Jobs(ctx, "queued", "running", "paused")
	if err != nil {
		return nil, nil, err
	}
	busy := map[string]bool{}
	transcribing := false
	for _, j := range active {
		busy[j.LectureID] = true
		if j.Kind == "transcript" && j.State == "running" {
			transcribing = true
		}
	}
	dir := s.Lib.Abs(".cache")
	ents, _ := os.ReadDir(dir)
	for _, e := range ents {
		p := filepath.Join(dir, e.Name())
		all = append(all, p)
		if strings.HasPrefix(e.Name(), "chunks-") {
			// Audio chunks of a transcription in progress; not named after it.
			if fi, err := e.Info(); err == nil && (!transcribing || time.Since(fi.ModTime()) > 6*time.Hour) {
				stale = append(stale, p)
			}
			continue
		}
		id, _, _ := strings.Cut(e.Name(), ".")
		if !busy[id] {
			stale = append(stale, p)
		}
	}
	return all, stale, nil
}

func (s *Server) storage(_ http.ResponseWriter, r *http.Request) (any, error) {
	rep := storageReport{Library: s.Lib.Root, Cleanable: map[string]int64{}}
	cats := map[string]*storageCategory{}
	order := []storageCategory{
		{Key: "video", Label: "视频与录音"}, {Key: "slides", Label: "PPT 截图"}, {Key: "courseware", Label: "课件"},
		{Key: "text", Label: "转写稿、笔记与题目"}, {Key: "index", Label: "索引"}, {Key: "cache", Label: "转写缓存与未完成下载"},
		{Key: "sync", Label: "同步冲突与回收站"}, {Key: "other", Label: "其他"},
	}
	for i := range order {
		cats[order[i].Key] = &order[i]
	}
	root := filepath.Clean(s.Lib.Root)
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || !d.Type().IsRegular() {
			return nil
		}
		fi, err := d.Info()
		if err != nil {
			return nil
		}
		rel := filepath.ToSlash(strings.TrimPrefix(p, root+string(filepath.Separator)))
		key := "other"
		switch {
		case strings.HasPrefix(rel, ".cache/"):
			key = "cache"
		case strings.HasPrefix(rel, datasync.ConflictDir+"/"), strings.HasPrefix(rel, datasync.TrashDir+"/"):
			key = "sync"
		case strings.HasPrefix(rel, "library.db"):
			key = "index"
		case strings.HasSuffix(rel, ".part"), strings.HasSuffix(rel, ".part.json"):
			key = "cache"
		case datasync.IsMedia(rel):
			key = "video"
		case strings.Contains(rel, "/slides/"):
			key = "slides"
		case strings.Contains(rel, "/courseware/"):
			key = "courseware"
		case strings.HasSuffix(rel, ".md"), strings.HasSuffix(rel, ".srt"), strings.HasSuffix(rel, ".txt"), strings.HasSuffix(rel, ".json"):
			key = "text"
		}
		c := cats[key]
		c.Bytes += fi.Size()
		c.Files++
		rep.Total += fi.Size()
		return nil
	})
	rep.Categories = order
	_, stale, err := s.cacheEntries(r.Context())
	if err != nil {
		return nil, err
	}
	for _, p := range stale {
		rep.Cleanable["cache"] += dirSize(p)
	}
	rep.Cleanable["sync"] = cats["sync"].Bytes
	if wal, err := os.Stat(s.Lib.Abs("library.db-wal")); err == nil {
		rep.Cleanable["index"] = wal.Size() // at least; VACUUM may free more
	}
	if s.Local != nil {
		rep.Models = s.Local.Status().Location.Used
	}
	if s.Data != nil {
		rep.Assistant = dirSize(filepath.Join(s.Data.Roots.Data, "agent"))
	}
	if s.Runtime != nil {
		rep.Runtime = dirSize(s.Runtime.Dir)
	}
	return rep, nil
}

func (s *Server) storageClean(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Cache   bool `json:"cache"`
		Sync    bool `json:"sync"`
		Compact bool `json:"compact"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	var freed int64
	if in.Cache {
		_, stale, err := s.cacheEntries(r.Context())
		if err != nil {
			return nil, err
		}
		for _, p := range stale {
			n := dirSize(p)
			if os.RemoveAll(p) == nil {
				freed += n
			}
		}
	}
	if in.Sync {
		for _, d := range []string{datasync.ConflictDir, datasync.TrashDir} {
			p := s.Lib.Abs(d)
			n := dirSize(p)
			if os.RemoveAll(p) == nil {
				freed += n
			}
		}
	}
	if in.Compact {
		size := func() int64 {
			var n int64
			for _, f := range []string{"library.db", "library.db-wal"} {
				if fi, err := os.Stat(s.Lib.Abs(f)); err == nil {
					n += fi.Size()
				}
			}
			return n
		}
		before := size()
		if err := s.St.Compact(r.Context()); err != nil {
			return nil, err
		}
		if d := before - size(); d > 0 {
			freed += d
		}
	}
	return map[string]int64{"freed": freed}, nil
}
