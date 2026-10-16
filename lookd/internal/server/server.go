// Package server exposes the daemon over a token-protected local HTTP API.
package server

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"lookstudio/lookd/internal/agent"
	"lookstudio/lookd/internal/asr"
	"lookstudio/lookd/internal/dl"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/jobs"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/mineru"
	"lookstudio/lookd/internal/store"
	"lookstudio/lookd/internal/tongji"
)

const Version = "0.1.0"

type Server struct {
	Token string
	Sess  *tongji.Session
	Cl    *tongji.Client
	St    *store.Store
	Lib   *library.Library
	Jobs  *jobs.Manager
	Eng   *dl.Engine
	Bus   *events.Bus
	Agent *agent.Supervisor
	// MinerU parses uploaded courseware.
	MinerU *mineru.Service

	syncMu     sync.Mutex
	lastCourse time.Time

	obsidianMu    sync.Mutex
	obsidianTimer *time.Timer
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	h := func(pattern string, f func(http.ResponseWriter, *http.Request) (any, error)) {
		mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
			v, err := f(w, r)
			if err != nil {
				writeErr(w, err)
				return
			}
			if v != nil {
				writeJSON(w, http.StatusOK, v)
			}
		})
	}
	h("GET /api/health", s.health)
	h("GET /api/auth", func(http.ResponseWriter, *http.Request) (any, error) { return s.Sess.State(), nil })
	h("POST /api/auth/login", s.login)
	h("POST /api/auth/logout", func(http.ResponseWriter, *http.Request) (any, error) {
		s.Sess.Logout()
		s.Cl.ResetUser()
		return s.Sess.State(), nil
	})
	h("POST /api/auth/renew", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		return s.Sess.State(), s.Sess.Renew(r.Context())
	})
	mux.HandleFunc("GET /api/auth/captcha", s.captcha)
	h("GET /api/me", func(_ http.ResponseWriter, r *http.Request) (any, error) { return s.Cl.UserInfo(r.Context()) })

	h("GET /api/courses", s.courses)
	h("PATCH /api/courses/{id}", s.patchCourse)
	h("GET /api/courses/{id}/lectures", s.lectures)
	h("GET /api/lectures/{id}", s.lecture)
	h("GET /api/lectures/{id}/media", s.media)
	h("GET /api/lectures/{id}/slides", s.slides)
	h("GET /api/lectures/{id}/transcript", s.transcript)
	h("PUT /api/lectures/{id}/playback", s.playback)
	h("POST /api/lectures/{id}/bookmarks", s.addBookmark)
	h("DELETE /api/bookmarks/{id}", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		id, _ := strconv.ParseInt(r.PathValue("id"), 10, 64)
		return ok(), s.St.DeleteBookmark(r.Context(), id)
	})
	h("GET /api/recent", func(_ http.ResponseWriter, r *http.Request) (any, error) { return s.St.RecentLectures(r.Context(), 20) })

	h("GET /api/jobs", func(_ http.ResponseWriter, r *http.Request) (any, error) { return s.Jobs.List(r.Context()) })
	h("POST /api/jobs", s.enqueue)
	h("POST /api/jobs/clear", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		var freed int64
		if r.URL.Query().Get("files") == "1" {
			done, err := s.St.Jobs(r.Context(), "done")
			if err != nil {
				return nil, err
			}
			for _, j := range done {
				n, err := s.Jobs.RemoveFiles(r.Context(), j.ID)
				if err != nil {
					return map[string]any{"ok": false, "freed": freed}, err
				}
				freed += n
			}
		}
		return map[string]any{"ok": true, "freed": freed}, s.St.ClearFinishedJobs(r.Context())
	})
	h("POST /api/jobs/{id}/{action}", s.jobAction)
	h("DELETE /api/jobs/{id}", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		if r.URL.Query().Get("files") == "1" {
			freed, err := s.Jobs.RemoveFiles(r.Context(), r.PathValue("id"))
			return map[string]any{"ok": err == nil, "freed": freed}, err
		}
		return ok(), s.Jobs.Remove(r.Context(), r.PathValue("id"))
	})
	h("GET /api/local", func(_ http.ResponseWriter, r *http.Request) (any, error) { return s.St.LocalItems(r.Context()) })
	h("DELETE /api/lectures/{id}/assets/{kind}", s.removeAsset)

	h("GET /api/search", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		q := r.URL.Query()
		limit, _ := strconv.Atoi(q.Get("limit"))
		return s.St.Search(r.Context(), q.Get("q"), q.Get("course_id"), limit)
	})
	h("GET /api/notes", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		q := r.URL.Query()
		return s.St.Notes(r.Context(), q.Get("course_id"), q.Get("lecture_id"))
	})
	h("GET /api/notes/{id}", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		return s.St.Note(r.Context(), r.PathValue("id"))
	})
	h("PUT /api/notes", s.putNote)
	h("DELETE /api/notes/{id}", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		err := s.Lib.DeleteNote(r.Context(), r.PathValue("id"))
		if err == nil {
			s.Bus.Publish("notes_changed", map[string]string{"id": r.PathValue("id")})
			s.exportObsidianSoon()
		}
		return ok(), err
	})

	h("GET /api/settings", func(_ http.ResponseWriter, r *http.Request) (any, error) { return s.St.Settings(r.Context()) })
	h("PUT /api/settings", s.putSettings)
	h("GET /api/library", s.library)
	h("POST /api/library/reindex", func(_ http.ResponseWriter, r *http.Request) (any, error) {
		n, err := s.Lib.Reindex(r.Context())
		return map[string]int{"indexed": n}, err
	})
	h("POST /api/library/export", s.export)
	h("POST /api/library/obsidian", s.exportObsidian)
	h("GET /api/asr", func(http.ResponseWriter, *http.Request) (any, error) {
		cfg, chans, events := s.Jobs.ASR.Status()
		return map[string]any{"config": cfg, "channels": chans, "events": events}, nil
	})
	h("GET /api/schedule", s.schedule)
	h("POST /api/schedule", s.addSchedule)
	h("PATCH /api/schedule/{id}", s.patchSchedule)
	h("DELETE /api/schedule/{id}", s.deleteSchedule)
	h("GET /api/lectures/{id}/timeline", s.timeline)
	h("PUT /api/lectures/{id}/timeline", s.putTimeline)
	h("DELETE /api/lectures/{id}/timeline", s.deleteTimeline)
	h("GET /api/lectures/{id}/courseware", s.courseware)
	h("POST /api/lectures/{id}/courseware", s.uploadCourseware)
	h("DELETE /api/lectures/{id}/courseware", s.deleteCourseware)
	h("GET /api/lectures/{id}/courseware/text", s.coursewareText)
	h("GET /api/lectures/{id}/courseware/search", s.searchCourseware)
	mux.HandleFunc("GET /api/lectures/{id}/slides/{idx}/image", s.slideImage)
	h("GET /api/mineru", s.mineruStatus)
	h("PUT /api/mineru", s.putMinerU)
	h("POST /api/mineru/test", s.testMinerU)
	h("GET /api/agent/status", func(http.ResponseWriter, *http.Request) (any, error) {
		return map[string]any{"status": s.Agent.Status(), "logs": s.Agent.Logs()}, nil
	})

	mux.HandleFunc("GET /api/events", s.events)
	mux.HandleFunc("GET /files/{rel...}", s.files)
	mux.Handle("/agent/", s.Agent)
	return s.auth(mux)
}

// auth accepts the token as a Bearer header or ?token= (for media players).
func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" {
			next.ServeHTTP(w, r)
			return
		}
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if tok == "" {
			tok = r.URL.Query().Get("token")
		}
		if subtle.ConstantTimeCompare([]byte(tok), []byte(s.Token)) != 1 {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

type apiError struct {
	Code int
	Msg  string
}

func (e apiError) Error() string { return e.Msg }

func badRequest(msg string) error { return apiError{http.StatusBadRequest, msg} }

func writeErr(w http.ResponseWriter, err error) {
	code := http.StatusInternalServerError
	var ae apiError
	var le *tongji.LoginError
	switch {
	case errors.As(err, &ae):
		code = ae.Code
	case errors.As(err, &le):
		code = http.StatusUnauthorized
		if errors.Is(err, tongji.ErrCaptchaRequired) {
			writeJSON(w, code, map[string]any{"error": err.Error(), "captcha": true})
			return
		}
	case errors.Is(err, sql.ErrNoRows):
		code = http.StatusNotFound
	case errors.Is(err, tongji.ErrSSOExpired):
		code = http.StatusUnauthorized
	}
	writeJSON(w, code, map[string]string{"error": err.Error()})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func decode(r *http.Request, v any) error {
	if err := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 8<<20)).Decode(v); err != nil {
		return badRequest("请求体无效: " + err.Error())
	}
	return nil
}

func ok() map[string]bool { return map[string]bool{"ok": true} }

func (s *Server) health(http.ResponseWriter, *http.Request) (any, error) {
	return map[string]any{"version": Version, "ffmpeg": asr.HasFFmpeg(), "agent": s.Agent.Status(),
		"auth": s.Sess.State().Status, "library": s.Lib.Root}, nil
}

func (s *Server) login(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Captcha  string `json:"captcha"`
		Remember bool   `json:"remember"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if strings.TrimSpace(in.Username) == "" || in.Password == "" {
		return nil, badRequest("请输入学号和密码")
	}
	s.Cl.ResetUser()
	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()
	if err := s.Sess.Login(ctx, strings.TrimSpace(in.Username), in.Password, strings.TrimSpace(in.Captcha), in.Remember); err != nil {
		return nil, err
	}
	go s.syncCourses(context.Background())
	return s.Sess.State(), nil
}

func (s *Server) captcha(w http.ResponseWriter, r *http.Request) {
	b, ct, err := s.Sess.Captcha(r.Context())
	if err != nil {
		writeErr(w, err)
		return
	}
	if ct == "" {
		ct = "image/jpeg"
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("Cache-Control", "no-store")
	w.Write(b)
}

// ---- courses ----

func (s *Server) syncCourses(ctx context.Context) error {
	s.syncMu.Lock()
	defer s.syncMu.Unlock()
	cs, err := s.Cl.Courses(ctx)
	if err != nil {
		return err
	}
	for _, c := range cs {
		teachers, _ := json.Marshal(c.Teachers)
		if err := s.St.UpsertCourse(ctx, store.Course{ID: c.ID, Title: c.Title, Teacher: c.Teacher, Teachers: teachers,
			College: c.College, Term: c.Term, Thumb: c.Thumb, StartAt: c.StartAt, EndAt: c.EndAt, LectureTotal: c.Total,
			Progress: c.Progress, LastSubID: c.LastSubID, LastLearnAt: c.LastLearnAt}); err != nil {
			return err
		}
	}
	s.lastCourse = time.Now()
	s.Bus.Publish("courses_changed", map[string]int{"count": len(cs)})
	return nil
}

func (s *Server) courses(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx := r.Context()
	cs, err := s.St.Courses(ctx)
	if err != nil {
		return nil, err
	}
	if r.URL.Query().Get("sync") == "1" || len(cs) == 0 {
		if err := s.syncCourses(ctx); err != nil {
			if len(cs) == 0 {
				return nil, err
			}
			slog.Warn("course sync failed, serving cache", "err", err)
		}
		return s.St.Courses(ctx)
	}
	if time.Since(s.lastCourse) > 10*time.Minute {
		go s.syncCourses(context.Background())
	}
	return cs, nil
}

func (s *Server) patchCourse(_ http.ResponseWriter, r *http.Request) (any, error) {
	var patch map[string]any
	if err := decode(r, &patch); err != nil {
		return nil, err
	}
	if err := s.St.PatchCourse(r.Context(), r.PathValue("id"), patch); err != nil {
		return nil, badRequest(err.Error())
	}
	s.Bus.Publish("courses_changed", nil)
	return s.St.Course(r.Context(), r.PathValue("id"))
}

func (s *Server) syncLectures(ctx context.Context, courseID string) error {
	d, err := s.Cl.CourseDetail(ctx, courseID)
	if err != nil {
		return err
	}
	if _, err := s.St.Course(ctx, courseID); errors.Is(err, sql.ErrNoRows) {
		s.St.UpsertCourse(ctx, store.Course{ID: courseID, Title: d.Title, Teacher: d.Teacher, College: d.College, Term: d.Term, Thumb: d.Thumb})
	}
	ls := make([]store.Lecture, 0, len(d.Lectures))
	for _, l := range d.Lectures {
		ls = append(ls, store.Lecture{ID: l.ID, CourseID: courseID, Title: l.Title, Date: l.Date, BeginAt: l.BeginAt,
			EndAt: l.EndAt, Lecturer: l.Lecturer, Room: l.Room, HasPlayback: l.HasPlayback})
	}
	return s.St.UpsertLectures(ctx, ls)
}

func (s *Server) lectures(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	ls, err := s.St.Lectures(ctx, id)
	if err != nil {
		return nil, err
	}
	if r.URL.Query().Get("sync") == "1" || len(ls) == 0 {
		if err := s.syncLectures(ctx, id); err != nil && len(ls) == 0 {
			return nil, err
		}
		if ls, err = s.St.Lectures(ctx, id); err != nil {
			return nil, err
		}
	}
	c, err := s.St.Course(ctx, id)
	if err != nil {
		return nil, err
	}
	return map[string]any{"course": c, "lectures": ls}, nil
}

func (s *Server) lecture(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	l, err := s.St.Lecture(ctx, id)
	if err != nil {
		return nil, err
	}
	c, _ := s.St.Course(ctx, l.CourseID)
	assets, _ := s.St.Assets(ctx, id)
	pb, _ := s.St.Playback(ctx, id)
	bms, _ := s.St.Bookmarks(ctx, id)
	notes, _ := s.St.Notes(ctx, "", id)
	var js []store.Job
	all, _ := s.Jobs.List(ctx)
	for _, j := range all {
		if j.LectureID == id {
			js = append(js, j)
		}
	}
	tl, _ := s.St.Timeline(ctx, id)
	return map[string]any{"lecture": l, "course": c, "assets": assets, "playback": pb, "bookmarks": bms,
		"notes": notes, "jobs": js, "timeline": tl, "library_root": s.Lib.Root}, nil
}

func (s *Server) media(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	l, err := s.St.Lecture(ctx, id)
	if err != nil {
		return nil, err
	}
	m, err := s.Cl.LectureMedia(ctx, l.CourseID, id)
	if err != nil {
		return nil, err
	}
	s.St.SetLectureMedia(ctx, id, m.Duration, firstThumb(m))
	local := ""
	if as, err := s.St.Assets(ctx, id); err == nil {
		for _, a := range as {
			if a.Kind == "video" {
				if _, err := os.Stat(s.Lib.Abs(a.Path)); err == nil {
					local = s.Lib.Abs(a.Path)
				}
			}
		}
	}
	headers := map[string]string{}
	for k := range m.Headers {
		headers[k] = m.Headers.Get(k)
	}
	return map[string]any{"streams": m.Streams, "duration": m.Duration, "courseware": m.Courseware,
		"allow_drag": m.AllowDrag, "headers": headers, "local_path": local}, nil
}

func firstThumb(m *tongji.Media) string {
	if len(m.Streams) > 0 {
		return m.Streams[0].Thumb
	}
	return ""
}

// slides returns downloaded slides, or the remote list (indexed without
// files) so the player can show slides while streaming.
func (s *Server) slides(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	sl, err := s.lectureSlides(ctx, id)
	if err != nil {
		return nil, err
	}
	type out struct {
		store.Slide
		Abs string `json:"abs,omitempty"`
	}
	res := make([]out, len(sl))
	for i, x := range sl {
		res[i] = out{Slide: x}
		if x.Path != "" {
			res[i].Abs = s.Lib.Abs(x.Path)
		}
	}
	return res, nil
}

// lectureSlides returns the indexed slides, fetching the remote list (and
// indexing it without files) the first time.
func (s *Server) lectureSlides(ctx context.Context, id string) ([]store.Slide, error) {
	sl, err := s.St.Slides(ctx, id)
	if err != nil {
		return nil, err
	}
	if len(sl) == 0 {
		l, err := s.St.Lecture(ctx, id)
		if err != nil {
			return nil, err
		}
		snaps, err := s.Cl.Slides(ctx, l.CourseID, id)
		if err != nil {
			return nil, err
		}
		for i, sn := range snaps {
			sl = append(sl, store.Slide{Idx: i + 1, TSec: sn.TSec, IsKey: sn.IsKey, RemoteURL: sn.ImageURL})
		}
		if len(sl) > 0 {
			s.St.ReplaceSlides(ctx, id, sl)
		}
	}
	return sl, nil
}

var slideClient = &http.Client{Timeout: 30 * time.Second}

// slideImage serves one slide: the downloaded file, or the platform's image
// fetched on the fly (for the assistant and for notes that embed slides).
func (s *Server) slideImage(w http.ResponseWriter, r *http.Request) {
	ctx, id := r.Context(), r.PathValue("id")
	idx, _ := strconv.Atoi(r.PathValue("idx"))
	sl, err := s.lectureSlides(ctx, id)
	if err != nil {
		writeErr(w, err)
		return
	}
	for _, x := range sl {
		if x.Idx != idx {
			continue
		}
		w.Header().Set("Cache-Control", "private, max-age=86400")
		if x.Path != "" {
			if abs := s.Lib.Abs(x.Path); fileExists(abs) {
				http.ServeFile(w, r, abs)
				return
			}
		}
		if !strings.HasPrefix(x.RemoteURL, "https://") && !strings.HasPrefix(x.RemoteURL, "http://") {
			break
		}
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, x.RemoteURL, nil)
		req.Header.Set("User-Agent", tongji.UserAgent)
		req.Header.Set("Referer", tongji.BaseURL+"/")
		res, err := slideClient.Do(req)
		if err != nil {
			writeErr(w, apiError{http.StatusBadGateway, "获取 PPT 图片失败"})
			return
		}
		defer res.Body.Close()
		if res.StatusCode != http.StatusOK {
			writeErr(w, apiError{http.StatusBadGateway, fmt.Sprintf("获取 PPT 图片失败：HTTP %d", res.StatusCode)})
			return
		}
		if ct := res.Header.Get("Content-Type"); ct != "" {
			w.Header().Set("Content-Type", ct)
		}
		io.Copy(w, io.LimitReader(res.Body, 20<<20))
		return
	}
	writeErr(w, apiError{http.StatusNotFound, "没有这张 PPT"})
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

func (s *Server) transcript(_ http.ResponseWriter, r *http.Request) (any, error) {
	q := r.URL.Query()
	from, _ := strconv.ParseInt(q.Get("from_ms"), 10, 64)
	to, _ := strconv.ParseInt(q.Get("to_ms"), 10, 64)
	return s.St.Segments(r.Context(), r.PathValue("id"), from, to)
}

func (s *Server) playback(_ http.ResponseWriter, r *http.Request) (any, error) {
	var p store.Playback
	if err := decode(r, &p); err != nil {
		return nil, err
	}
	return ok(), s.St.SavePlayback(r.Context(), r.PathValue("id"), p)
}

func (s *Server) addBookmark(_ http.ResponseWriter, r *http.Request) (any, error) {
	var b store.Bookmark
	if err := decode(r, &b); err != nil {
		return nil, err
	}
	b.LectureID = r.PathValue("id")
	id, err := s.St.AddBookmark(r.Context(), b)
	b.ID = id
	return b, err
}

// ---- jobs ----

func (s *Server) removeAsset(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id, kind := r.Context(), r.PathValue("id"), r.PathValue("kind")
	valid := false
	for _, k := range jobs.Kinds {
		valid = valid || k == kind
	}
	if !valid {
		return nil, badRequest("未知类型 " + kind)
	}
	l, err := s.St.Lecture(ctx, id)
	if err != nil {
		return nil, err
	}
	jid := id + "-" + kind
	if j, err := s.St.Job(ctx, jid); err == nil && (j.State == "running" || j.State == "queued") {
		return nil, badRequest("该任务正在进行，请先取消")
	}
	freed, err := s.Lib.RemoveAsset(ctx, id, kind)
	if err != nil {
		return nil, err
	}
	if j, err := s.St.Job(ctx, jid); err == nil && j.State == "done" {
		s.Jobs.Remove(ctx, jid)
	}
	s.Bus.Publish("lecture_changed", map[string]string{"lecture_id": id, "course_id": l.CourseID})
	return map[string]any{"ok": true, "freed": freed}, nil
}

func (s *Server) enqueue(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		LectureIDs []string `json:"lecture_ids"`
		Kinds      []string `json:"kinds"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if len(in.LectureIDs) == 0 || len(in.Kinds) == 0 {
		return nil, badRequest("lecture_ids 和 kinds 不能为空")
	}
	var out []store.Job
	for _, id := range in.LectureIDs {
		js, err := s.Jobs.Enqueue(r.Context(), id, in.Kinds)
		if err != nil {
			return nil, badRequest(err.Error())
		}
		out = append(out, js...)
	}
	return out, nil
}

func (s *Server) jobAction(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx, id := r.Context(), r.PathValue("id")
	switch r.PathValue("action") {
	case "pause":
		return ok(), s.Jobs.Pause(ctx, id)
	case "resume", "retry":
		return ok(), s.Jobs.Resume(ctx, id)
	case "cancel":
		return ok(), s.Jobs.Cancel(ctx, id)
	}
	return nil, badRequest("未知操作")
}

// ---- notes ----

func (s *Server) putNote(_ http.ResponseWriter, r *http.Request) (any, error) {
	var n store.Note
	if err := decode(r, &n); err != nil {
		return nil, err
	}
	n, err := s.Lib.SaveNote(r.Context(), n)
	if err == nil {
		s.Bus.Publish("notes_changed", map[string]string{"id": n.ID, "lecture_id": n.LectureID, "course_id": n.CourseID})
		s.exportObsidianSoon()
	}
	return n, err
}

// ---- settings & library ----

// ApplySettings pushes persisted settings into running components.
func (s *Server) ApplySettings(ctx context.Context) {
	kv, err := s.St.Settings(ctx)
	if err != nil {
		return
	}
	get := func(k string, v any) bool { raw, ok := kv[k]; return ok && json.Unmarshal(raw, v) == nil }
	var n int64
	if get("download.max_conns", &n) {
		s.Eng.SetMaxConns(int(n))
	}
	if get("download.rate_limit", &n) {
		s.Eng.SetRateLimit(n)
	} else {
		s.Eng.SetRateLimit(0)
	}
	cfg := jobs.Config{}
	if get("download.video_parallel", &n) {
		cfg.VideoParallel = int(n)
	}
	get("download.stream", &cfg.Stream)
	get("transcript.delete_video", &cfg.DeleteVideoAfterTranscript)
	s.Jobs.SetConfig(cfg)
	var pc asr.PoolConfig
	get("asr.disabled", &pc.Disabled)
	get("asr.strategy", &pc.Strategy)
	if get("asr.concurrency", &n) {
		pc.Concurrency = int(n)
	}
	s.Jobs.ASR.SetConfig(pc)
	var tpl library.Templates
	if get("library.templates", &tpl) {
		s.Lib.SetTemplates(tpl)
	}
}

func (s *Server) putSettings(_ http.ResponseWriter, r *http.Request) (any, error) {
	var kv map[string]json.RawMessage
	if err := decode(r, &kv); err != nil {
		return nil, err
	}
	if err := s.St.PutSettings(r.Context(), kv); err != nil {
		return nil, badRequest(err.Error())
	}
	s.ApplySettings(r.Context())
	s.Bus.Publish("settings_changed", kv)
	return s.St.Settings(r.Context())
}

func (s *Server) library(_ http.ResponseWriter, r *http.Request) (any, error) {
	st, err := s.St.Stats(r.Context())
	return map[string]any{"root": s.Lib.Root, "stats": st}, err
}

func (s *Server) export(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Root string `json:"root"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Root == "" || !filepath.IsAbs(in.Root) {
		return nil, badRequest("请提供绝对路径")
	}
	n, err := s.Lib.ExportSkill(r.Context(), in.Root)
	return map[string]any{"exported": n, "root": in.Root}, err
}

// obsidianTarget reads the saved Obsidian export settings.
func (s *Server) obsidianTarget(ctx context.Context) (vault, folder string, auto bool) {
	kv, err := s.St.Settings(ctx)
	if err != nil {
		return "", "", false
	}
	json.Unmarshal(kv["obsidian.vault"], &vault)
	json.Unmarshal(kv["obsidian.folder"], &folder)
	json.Unmarshal(kv["obsidian.auto"], &auto)
	return vault, folder, auto
}

// exportObsidian refreshes the Obsidian export, into the vault named in the
// body or else the saved one.
func (s *Server) exportObsidian(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Vault  string `json:"vault"`
		Folder string `json:"folder"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Vault == "" {
		in.Vault, in.Folder, _ = s.obsidianTarget(r.Context())
	}
	if _, err := s.Lib.ObsidianRoot(in.Vault, in.Folder); err != nil {
		return nil, badRequest(err.Error())
	}
	return s.Lib.ExportObsidian(r.Context(), in.Vault, in.Folder)
}

// exportObsidianSoon refreshes the Obsidian export shortly after notes
// change, when automatic export is on. Bursts of saves export once.
func (s *Server) exportObsidianSoon() {
	vault, folder, auto := s.obsidianTarget(context.Background())
	if !auto || vault == "" {
		return
	}
	s.obsidianMu.Lock()
	defer s.obsidianMu.Unlock()
	if s.obsidianTimer != nil {
		s.obsidianTimer.Stop()
	}
	s.obsidianTimer = time.AfterFunc(3*time.Second, func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		res, err := s.Lib.ExportObsidian(ctx, vault, folder)
		event := map[string]any{"result": res}
		if err != nil {
			slog.Warn("obsidian export", "err", err)
			event["error"] = err.Error()
		}
		s.Bus.Publish("obsidian_exported", event)
	})
}

// ---- events & files ----

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	fl, okf := w.(http.Flusher)
	if !okf {
		http.Error(w, "streaming unsupported", 500)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	ch, unsub := s.Bus.Subscribe()
	defer unsub()
	hello, _ := json.Marshal(map[string]any{"type": "hello", "data": map[string]any{"auth": s.Sess.State(), "agent": s.Agent.Status()}})
	fmt.Fprintf(w, "data: %s\n\n", hello)
	fl.Flush()
	ping := time.NewTicker(20 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case msg := <-ch:
			fmt.Fprintf(w, "data: %s\n\n", msg)
			fl.Flush()
		case <-ping.C:
			fmt.Fprint(w, ": ping\n\n")
			fl.Flush()
		}
	}
}

func (s *Server) files(w http.ResponseWriter, r *http.Request) {
	rel := path.Clean("/" + r.PathValue("rel"))
	abs := s.Lib.Abs(strings.TrimPrefix(rel, "/"))
	if !strings.HasPrefix(abs, filepath.Clean(s.Lib.Root)+string(filepath.Separator)) {
		http.NotFound(w, r)
		return
	}
	if strings.HasSuffix(abs, ".db") || strings.Contains(abs, "library.db") {
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, abs)
}
