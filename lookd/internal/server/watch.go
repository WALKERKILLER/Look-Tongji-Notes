package server

import (
	"context"
	"encoding/json"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"sync"
	"time"

	"lookstudio/lookd/internal/notify"
	"lookstudio/lookd/internal/store"
)

// Look has no push channel for students, so lookd polls it adaptively: a
// lecture that just ended is checked every 10 minutes until its replay
// appears, then less often as it ages; quiet courses are swept every few
// hours. Changes reach the app at once over /api/events.
// Contract: docs/specs/0010-live-refresh.md
const (
	watchTick      = time.Minute
	watchSweep     = 6 * time.Hour
	watchCourses   = time.Hour
	watchAwaitDays = 7
)

type watchState struct {
	mu          sync.Mutex
	next        map[string]time.Time
	awaiting    map[string]int
	lastRun     time.Time
	lastCourses time.Time
	lastCanvas  time.Time
	lastErr     string
	kick        chan struct{}
}

// nextCheck says when a course's lectures should be fetched again.
func nextCheck(ls []store.Lecture, now time.Time) (time.Time, int) {
	next := now.Add(watchSweep)
	awaiting := 0
	for _, l := range ls {
		if l.EndAt <= 0 {
			continue
		}
		end := time.Unix(l.EndAt, 0)
		age := now.Sub(end)
		switch {
		case age < 0 && age > -24*time.Hour:
			// Ends today: look shortly after it ends.
			next = minTime(next, end.Add(10*time.Minute))
		case age >= 0 && age < watchAwaitDays*24*time.Hour && !l.HasPlayback:
			awaiting++
			var every time.Duration
			switch {
			case age < 3*time.Hour:
				every = 10 * time.Minute
			case age < 24*time.Hour:
				every = 30 * time.Minute
			default:
				every = 3 * time.Hour
			}
			next = minTime(next, maxTime(now.Add(every), end.Add(10*time.Minute)))
		}
	}
	return next, awaiting
}

func minTime(a, b time.Time) time.Time {
	if b.Before(a) {
		return b
	}
	return a
}

func maxTime(a, b time.Time) time.Time {
	if b.After(a) {
		return b
	}
	return a
}

// current reports whether a course belongs to the running term.
func current(c store.Course, now time.Time) bool {
	if c.Hidden {
		return false
	}
	if c.EndAt > 0 && time.Unix(c.EndAt, 0).Before(now.Add(-14*24*time.Hour)) {
		return false
	}
	return c.StartAt == 0 || time.Unix(c.StartAt, 0).Before(now.Add(14*24*time.Hour))
}

func (s *Server) watchEnabled(ctx context.Context) bool {
	kv, _ := s.St.Settings(ctx)
	on := true
	if raw, ok := kv["watch.enabled"]; ok {
		json.Unmarshal(raw, &on)
	}
	return on
}

// RunWatcher polls until ctx ends.
func (s *Server) RunWatcher(ctx context.Context) {
	w := s.watch()
	t := time.NewTicker(watchTick)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		case <-w.kick:
		}
		s.watchOnce(ctx)
	}
}

func (s *Server) watch() *watchState {
	s.watchOnceInit.Do(func() {
		s.w = &watchState{next: map[string]time.Time{}, awaiting: map[string]int{}, kick: make(chan struct{}, 1)}
	})
	return s.w
}

func (s *Server) watchOnce(ctx context.Context) {
	w := s.watch()
	if !s.watchEnabled(ctx) {
		return
	}
	now := time.Now()
	if s.Canvas != nil && s.Canvas.Connected() {
		// Canvas does not depend on Look's session (Fudan has no Look).
		w.mu.Lock()
		due := now.Sub(w.lastCanvas) > canvasEvery
		if due {
			w.lastCanvas = now
		}
		w.mu.Unlock()
		if due {
			go s.canvasSync(ctx)
		}
	}
	if st := s.Sess.State().Status; st != "active" && st != "renewing" {
		return
	}
	w.mu.Lock()
	w.lastRun = now
	syncCourses := now.Sub(w.lastCourses) > watchCourses
	if syncCourses {
		w.lastCourses = now
	}
	w.mu.Unlock()
	if syncCourses {
		if err := s.syncCourses(ctx); err != nil {
			s.watchErr(err)
			return
		}
	}
	cs, err := s.St.Courses(ctx)
	if err != nil {
		return
	}
	for _, c := range cs {
		if !current(c, now) {
			continue
		}
		w.mu.Lock()
		due, known := w.next[c.ID]
		w.mu.Unlock()
		if known && now.Before(due) {
			continue
		}
		if !known {
			// First pass after start: fetch now only when a replay is
			// awaited; spread the other courses' first sweep so a restart
			// does not send a burst of requests.
			ls, _ := s.St.Lectures(ctx, c.ID)
			next, n := nextCheck(ls, now)
			if n == 0 {
				w.mu.Lock()
				w.next[c.ID], w.awaiting[c.ID] = minTime(next, now.Add(time.Duration(rand.Int64N(int64(watchSweep))))), 0
				w.mu.Unlock()
				continue
			}
		}
		if err := s.watchCourse(ctx, c); err != nil {
			s.watchErr(err)
			w.mu.Lock()
			w.next[c.ID] = now.Add(10 * time.Minute)
			w.mu.Unlock()
			continue
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second): // spread requests
		}
	}
}

func jitter(now, next time.Time) time.Time {
	d := next.Sub(now)
	if d <= 0 {
		return next
	}
	return next.Add(time.Duration(rand.Int64N(int64(d/10) + 1)))
}

func (s *Server) watchErr(err error) {
	slog.Warn("watch failed", "err", err)
	w := s.watch()
	w.mu.Lock()
	w.lastErr = err.Error()
	w.mu.Unlock()
}

// watchCourse refreshes one course and reports what changed.
func (s *Server) watchCourse(ctx context.Context, c store.Course) error {
	before, _ := s.St.Lectures(ctx, c.ID)
	old := map[string]store.Lecture{}
	for _, l := range before {
		old[l.ID] = l
	}
	if err := s.syncLectures(ctx, c.ID); err != nil {
		return err
	}
	after, err := s.St.Lectures(ctx, c.ID)
	if err != nil {
		return err
	}
	now := time.Now()
	name := c.Title
	if c.Alias != "" {
		name = c.Alias
	}
	for _, l := range after {
		prev, seen := old[l.ID]
		switch {
		case !seen && len(before) > 0:
			s.Bus.Publish("lecture_changed", map[string]string{"lecture_id": l.ID, "course_id": c.ID, "what": "added"})
			if l.BeginAt > 0 && now.Sub(time.Unix(l.BeginAt, 0)).Abs() < 14*24*time.Hour {
				s.Notes.Add(notify.Item{ID: "lecture_added:" + l.ID, Kind: "lecture_added", Title: name + " 新增了一节课",
					Body: lectureLabel(l), CourseID: c.ID, LectureID: l.ID})
			}
		case seen && !prev.HasPlayback && l.HasPlayback:
			s.Bus.Publish("lecture_changed", map[string]string{"lecture_id": l.ID, "course_id": c.ID, "what": "playback"})
			s.Notes.Add(notify.Item{ID: "lecture_ready:" + l.ID, Kind: "lecture_ready", Title: name + " 有新回放",
				Body: lectureLabel(l), CourseID: c.ID, LectureID: l.ID})
		}
	}
	next, n := nextCheck(after, now)
	w := s.watch()
	w.mu.Lock()
	w.next[c.ID], w.awaiting[c.ID] = jitter(now, next), n
	w.mu.Unlock()
	return nil
}

func lectureLabel(l store.Lecture) string {
	label := l.Title
	if l.BeginAt > 0 {
		label += " · " + time.Unix(l.BeginAt, 0).In(shanghai).Format("1月2日 15:04")
	}
	return label
}

var shanghai = func() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}()

func (s *Server) watchStatus(http.ResponseWriter, *http.Request) (any, error) {
	w := s.watch()
	w.mu.Lock()
	defer w.mu.Unlock()
	type course struct {
		ID       string `json:"course_id"`
		NextAt   int64  `json:"next_at"`
		Awaiting int    `json:"awaiting"`
	}
	out := []course{}
	for id, t := range w.next {
		out = append(out, course{id, t.Unix(), w.awaiting[id]})
	}
	return map[string]any{"enabled": s.watchEnabled(s.Ctx), "last_run": w.lastRun.Unix(), "last_error": w.lastErr, "courses": out}, nil
}

// watchNow schedules every current course for the next pass and wakes the watcher.
func (s *Server) watchNow(http.ResponseWriter, *http.Request) (any, error) {
	w := s.watch()
	w.mu.Lock()
	for id := range w.next {
		w.next[id] = time.Time{}
	}
	w.lastCourses, w.lastCanvas = time.Time{}, time.Time{}
	w.mu.Unlock()
	select {
	case w.kick <- struct{}{}:
	default:
	}
	return ok(), nil
}
