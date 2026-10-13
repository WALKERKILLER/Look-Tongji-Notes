package server

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/mineru"
	"lookstudio/lookd/internal/store"
)

// ---- schedule ----

var scheduleKinds = map[string]bool{"homework": true, "exam": true, "activity": true, "deadline": true, "task": true}

func validDate(s string) bool {
	_, err := time.Parse("2006-01-02", s)
	return err == nil
}

func validTime(s string) bool {
	if s == "" {
		return true
	}
	_, err := time.Parse("15:04", s)
	return err == nil
}

func (s *Server) scheduleChanged(ctx context.Context, id string) {
	s.Lib.WriteSchedule(ctx)
	s.Bus.Publish("schedule_changed", map[string]string{"id": id})
}

func (s *Server) schedule(_ http.ResponseWriter, r *http.Request) (any, error) {
	q := r.URL.Query()
	return s.St.Schedule(r.Context(), store.ScheduleQuery{From: q.Get("from"), To: q.Get("to"), CourseID: q.Get("course_id"),
		LectureID: q.Get("lecture_id"), Open: q.Get("open") == "1"})
}

func checkItem(it *store.ScheduleItem) error {
	it.Title = strings.TrimSpace(it.Title)
	switch {
	case it.Title == "":
		return badRequest("标题不能为空")
	case utf8.RuneCountInString(it.Title) > 80:
		return badRequest("标题太长（最多 80 字）")
	case !validDate(it.DueDate):
		return badRequest("日期格式应为 YYYY-MM-DD")
	case !validTime(it.DueTime):
		return badRequest("时间格式应为 HH:MM")
	}
	if !scheduleKinds[it.Kind] {
		it.Kind = "task"
	}
	return nil
}

func normTitle(s string) string {
	return strings.Map(func(r rune) rune {
		if strings.ContainsRune(" \t,，。.、:：;；!！?？\"“”'‘’()（）《》", r) {
			return -1
		}
		return r
	}, s)
}

func (s *Server) addSchedule(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx := r.Context()
	var it store.ScheduleItem
	if err := decode(r, &it); err != nil {
		return nil, err
	}
	if err := checkItem(&it); err != nil {
		return nil, err
	}
	if it.Source != "agent" {
		it.Source = "user"
	}
	if it.LectureID != "" && it.CourseID == "" {
		if l, err := s.St.Lecture(ctx, it.LectureID); err == nil {
			it.CourseID = l.CourseID
		}
	}
	if it.Source == "agent" {
		// The assistant may mark the same thing twice; keep the first.
		same, _ := s.St.Schedule(ctx, store.ScheduleQuery{From: it.DueDate, To: it.DueDate, CourseID: it.CourseID})
		for _, x := range same {
			if normTitle(x.Title) == normTitle(it.Title) {
				return map[string]any{"item": x, "duplicate": true}, nil
			}
		}
	}
	if it.TMs == 0 && it.LectureID == "" {
		it.TMs = -1
	}
	it.ID, it.Done, it.CreatedAt = library.NewID(), false, 0
	if err := s.St.PutScheduleItem(ctx, it); err != nil {
		return nil, err
	}
	out, err := s.St.ScheduleItem(ctx, it.ID)
	s.scheduleChanged(ctx, it.ID)
	return map[string]any{"item": out, "duplicate": false}, err
}

func (s *Server) patchSchedule(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	it, err := s.St.ScheduleItem(ctx, id)
	if err != nil {
		return nil, err
	}
	var p struct {
		Kind     *string `json:"kind"`
		Title    *string `json:"title"`
		Detail   *string `json:"detail"`
		DueDate  *string `json:"due_date"`
		DueTime  *string `json:"due_time"`
		CourseID *string `json:"course_id"`
		Done     *bool   `json:"done"`
	}
	if err := decode(r, &p); err != nil {
		return nil, err
	}
	set := func(dst *string, v *string) {
		if v != nil {
			*dst = *v
		}
	}
	set(&it.Kind, p.Kind)
	set(&it.Title, p.Title)
	set(&it.Detail, p.Detail)
	set(&it.DueDate, p.DueDate)
	set(&it.DueTime, p.DueTime)
	set(&it.CourseID, p.CourseID)
	if p.Done != nil {
		it.Done = *p.Done
	}
	if err := checkItem(&it); err != nil {
		return nil, err
	}
	if err := s.St.PutScheduleItem(ctx, it); err != nil {
		return nil, err
	}
	s.scheduleChanged(ctx, id)
	return s.St.ScheduleItem(ctx, id)
}

func (s *Server) deleteSchedule(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	if err := s.St.DeleteScheduleItem(ctx, id); err != nil {
		return nil, err
	}
	s.scheduleChanged(ctx, id)
	return ok(), nil
}

// ---- timeline ----

func (s *Server) timeline(_ http.ResponseWriter, r *http.Request) (any, error) {
	return s.St.Timeline(r.Context(), r.PathValue("id"))
}

func (s *Server) putTimeline(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	var in struct {
		Chapters []store.Chapter `json:"chapters"`
		Text     string          `json:"text"` // skill format, used when chapters is empty
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	chs := in.Chapters
	if len(chs) == 0 {
		chs = library.ParseTimeline(in.Text)
	}
	out, err := s.Lib.SaveTimeline(ctx, id, chs)
	if err != nil {
		return nil, badRequest(err.Error())
	}
	s.publishLecture(ctx, id, "timeline")
	return out, nil
}

func (s *Server) deleteTimeline(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	if err := s.Lib.DeleteTimeline(ctx, id); err != nil {
		return nil, err
	}
	s.publishLecture(ctx, id, "timeline")
	return ok(), nil
}

func (s *Server) publishLecture(ctx context.Context, id, what string) {
	l, _ := s.St.Lecture(ctx, id)
	s.Bus.Publish("lecture_changed", map[string]string{"lecture_id": id, "course_id": l.CourseID, "what": what})
}

// ---- courseware ----

type coursewareView struct {
	Path      string             `json:"path"`
	Name      string             `json:"name"`
	Bytes     int64              `json:"bytes"`
	CreatedAt int64              `json:"created_at"`
	Uploaded  bool               `json:"uploaded"`
	Parse     *library.ParseInfo `json:"parse"`
}

func (s *Server) courseware(_ http.ResponseWriter, r *http.Request) (any, error) {
	as, err := s.Lib.Courseware(r.Context(), r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	out := []coursewareView{}
	for _, a := range as {
		m := library.CoursewareInfo(a)
		out = append(out, coursewareView{Path: a.Path, Name: m.Name, Bytes: a.Bytes, CreatedAt: a.CreatedAt, Uploaded: m.Uploaded, Parse: m.Parse})
	}
	return out, nil
}

// uploadCourseware takes the raw file as the request body (?name=file.pdf).
func (s *Server) uploadCourseware(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	name := strings.TrimSpace(r.URL.Query().Get("name"))
	if name == "" {
		return nil, badRequest("缺少文件名")
	}
	a, err := s.Lib.ImportCourseware(ctx, id, name, r.Body, mineru.MaxBytes)
	if err != nil {
		return nil, badRequest(err.Error())
	}
	var queued bool
	if s.MinerU != nil && s.MinerU.AutoParse() && r.URL.Query().Get("parse") != "0" {
		_, err := s.Jobs.Enqueue(ctx, id, []string{"parse"})
		queued = err == nil
	}
	s.publishLecture(ctx, id, "courseware")
	m := library.CoursewareInfo(a)
	return map[string]any{"file": coursewareView{Path: a.Path, Name: m.Name, Bytes: a.Bytes, Uploaded: true}, "parse_queued": queued}, nil
}

func (s *Server) deleteCourseware(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	freed, err := s.Lib.RemoveCourseware(ctx, id, r.URL.Query().Get("path"))
	if err != nil {
		return nil, badRequest(err.Error())
	}
	s.publishLecture(ctx, id, "courseware")
	return map[string]any{"ok": true, "freed": freed}, nil
}

// coursewareText returns a slice of a parsed courseware file's Markdown,
// for the assistant.
func (s *Server) coursewareText(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id, q := r.Context(), r.PathValue("id"), r.URL.Query()
	as, err := s.Lib.Courseware(ctx, id)
	if err != nil {
		return nil, err
	}
	for _, a := range as {
		m := library.CoursewareInfo(a)
		if a.Path != q.Get("path") && m.Name != q.Get("path") {
			continue
		}
		if m.Parse == nil || m.Parse.State != "done" {
			return nil, badRequest("这个课件还没有解析")
		}
		b, err := os.ReadFile(s.Lib.Abs(m.Parse.MD))
		if err != nil {
			return nil, err
		}
		text := []rune(string(b))
		off, _ := strconv.Atoi(q.Get("offset"))
		n, _ := strconv.Atoi(q.Get("max"))
		if n <= 0 || n > 20000 {
			n = 12000
		}
		off = min(max(off, 0), len(text))
		end := min(off+n, len(text))
		return map[string]any{"name": m.Name, "pages": m.Parse.Pages, "total": len(text), "offset": off, "next": end,
			"more": end < len(text), "text": string(text[off:end]), "dir": filepath.ToSlash(filepath.Dir(m.Parse.MD))}, nil
	}
	return nil, apiError{http.StatusNotFound, "没有这个课件"}
}

// ---- MinerU ----

func (s *Server) mineruStatus(http.ResponseWriter, *http.Request) (any, error) {
	return s.MinerU.Status(), nil
}

func (s *Server) putMinerU(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Token   *string         `json:"token"`
		Options *mineru.Options `json:"options"`
		Auto    *bool           `json:"auto"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if err := s.MinerU.Update(in.Token, in.Options, in.Auto); err != nil {
		return nil, err
	}
	return s.MinerU.Status(), nil
}

func (s *Server) testMinerU(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	if err := s.MinerU.Test(ctx); err != nil {
		return map[string]any{"ok": false, "error": err.Error()}, nil
	}
	return map[string]any{"ok": true, "status": s.MinerU.Status()}, nil
}

// searchCourseware searches the parsed courseware of a lecture, or of its
// whole course with scope=course.
func (s *Server) searchCourseware(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id, q := r.Context(), r.PathValue("id"), r.URL.Query()
	ids := []string{id}
	if q.Get("scope") == "course" {
		l, err := s.St.Lecture(ctx, id)
		if err != nil {
			return nil, err
		}
		ls, err := s.St.Lectures(ctx, l.CourseID)
		if err != nil {
			return nil, err
		}
		ids = ids[:0]
		for _, x := range ls {
			ids = append(ids, x.ID)
		}
	}
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 30 {
		limit = 8
	}
	return s.Lib.SearchCourseware(ctx, ids, q.Get("q"), limit)
}
