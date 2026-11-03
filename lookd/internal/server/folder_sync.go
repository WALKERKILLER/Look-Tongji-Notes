package server

import (
	"context"
	"encoding/json"
	"fmt"
	"lookstudio/lookd/internal/datasync"
	"lookstudio/lookd/internal/store"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type coursePortableState struct {
	User     store.UserState     `json:"user"`
	Activity []store.ActivityRow `json:"activity"`
}

func (s *Server) courseLectureIDs(ctx context.Context, ids []string) (map[string]bool, map[string]string, error) {
	courses := map[string]bool{}
	lectures := map[string]string{}
	for _, id := range ids {
		courses[id] = true
		rows, e := s.St.Lectures(ctx, id)
		if e != nil {
			return nil, nil, e
		}
		for _, l := range rows {
			lectures[l.ID] = id
		}
	}
	return courses, lectures, nil
}
func (s *Server) CourseState(ctx context.Context, ids []string) ([]byte, error) {
	courses, lectures, e := s.courseLectureIDs(ctx, ids)
	if e != nil {
		return nil, e
	}
	user, e := s.St.ExportUserState(ctx)
	if e != nil {
		return nil, e
	}
	for id := range user.Playback {
		if lectures[id] == "" {
			delete(user.Playback, id)
		}
	}
	bs := []store.Bookmark{}
	for _, b := range user.Bookmarks {
		if lectures[b.LectureID] != "" {
			bs = append(bs, b)
		}
	}
	user.Bookmarks = bs
	activity, e := s.St.ActivityRows(ctx)
	if e != nil {
		return nil, e
	}
	kept := []store.ActivityRow{}
	for _, v := range activity {
		if courses[v.CourseID] {
			kept = append(kept, v)
		}
	}
	return json.Marshal(coursePortableState{user, kept})
}
func (s *Server) MergeCourseState(ctx context.Context, ids []string, b []byte) (bool, error) {
	courses, lectures, e := s.courseLectureIDs(ctx, ids)
	if e != nil {
		return false, e
	}
	var st coursePortableState
	if e = json.Unmarshal(b, &st); e != nil {
		return false, e
	}
	for id := range st.User.Playback {
		if lectures[id] == "" {
			delete(st.User.Playback, id)
		}
	}
	bs := []store.Bookmark{}
	for _, v := range st.User.Bookmarks {
		if lectures[v.LectureID] != "" {
			bs = append(bs, v)
		}
	}
	st.User.Bookmarks = bs
	activity := []store.ActivityRow{}
	for _, v := range st.Activity {
		if !courses[v.CourseID] {
			continue
		}
		if v.LectureID != "" && lectures[v.LectureID] != v.CourseID {
			return false, fmt.Errorf("同步学习记录的课次不属于对应课程：%s", v.LectureID)
		}
		activity = append(activity, v)
	}
	return s.St.MergeLearningState(ctx, st.User, activity)
}
func (s *Server) folderPreview(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in datasync.Settings
	if e := decode(r, &in); e != nil {
		return nil, e
	}
	v, e := s.Data.FolderPreview(r.Context(), in)
	return v, dataErr(e)
}

func (s *Server) mergeFolderSessionMetadata() error {
	if s.Data == nil || s.Data.Status().Kind != "folder" {
		return nil
	}
	wanted := map[string]bool{}
	for _, id := range s.Data.Status().CourseIDs {
		wanted[id] = true
	}
	dest := filepath.Join(s.Data.Roots.Data, "agent", "sessions-meta.json")
	meta := map[string]map[string]any{}
	if b, e := os.ReadFile(dest); e == nil {
		if e = json.Unmarshal(b, &meta); e != nil {
			return e
		}
	}
	paths, _ := filepath.Glob(filepath.Join(s.Data.Roots.Data, "agent", "course-sessions", "*.json"))
	for _, p := range paths {
		course := strings.TrimSuffix(filepath.Base(p), ".json")
		if !wanted[course] {
			continue
		}
		b, e := os.ReadFile(p)
		if e != nil {
			return e
		}
		var entries map[string]map[string]any
		if e = json.Unmarshal(b, &entries); e != nil {
			return e
		}
		for id, v := range entries {
			// A cache must not undo a local reassignment or claim an ordinary chat.
			if old, exists := meta[id]; exists && old["course_id"] != course {
				continue
			}
			if v["course_id"] == course {
				meta[id] = v
			}
		}
	}
	b, e := json.Marshal(meta)
	if e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(dest), 0700); e != nil {
		return e
	}
	return os.WriteFile(dest, b, 0600)
}
