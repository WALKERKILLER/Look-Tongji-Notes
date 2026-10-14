package server

import (
	"net/http"
	"time"

	"lookstudio/lookd/internal/store"
)

// Study activity for the heatmap (docs/specs/0001-learning-activity-heatmap.md).

type activityIn struct {
	Kind      string `json:"kind"`
	Seconds   int64  `json:"seconds"`
	Count     int64  `json:"count"`
	LectureID string `json:"lecture_id"`
	CourseID  string `json:"course_id"`
	At        int64  `json:"at"` // unix seconds; 0 = now
}

// checkActivity validates a report and returns its local day.
func checkActivity(in activityIn, now time.Time) (string, error) {
	switch {
	case !store.TimedKinds[in.Kind] && in.Kind != "ask":
		return "", badRequest("kind 应为 watch、read、practice 或 ask")
	case in.Seconds < 0 || in.Seconds > 300:
		return "", badRequest("seconds 应在 0–300 之间")
	case in.Count < 0 || in.Count > 50:
		return "", badRequest("count 应在 0–50 之间")
	case in.Seconds == 0 && in.Count == 0:
		return "", badRequest("seconds 或 count 至少一个大于 0")
	}
	t := now
	if in.At != 0 {
		t = time.Unix(in.At, 0)
		if t.Before(now.Add(-24*time.Hour)) || t.After(now.Add(5*time.Minute)) {
			return "", badRequest("at 只能是最近 24 小时内的时间")
		}
	}
	return t.In(time.Local).Format("2006-01-02"), nil
}

func (s *Server) addActivity(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in activityIn
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	day, err := checkActivity(in, time.Now())
	if err != nil {
		return nil, err
	}
	if in.CourseID == "" && in.LectureID != "" {
		if l, err := s.St.Lecture(r.Context(), in.LectureID); err == nil {
			in.CourseID = l.CourseID
		}
	}
	if !store.TimedKinds[in.Kind] {
		in.Seconds = 0
	}
	if err := s.St.AddActivity(r.Context(), day, in.Kind, in.CourseID, in.LectureID, in.Seconds, in.Count); err != nil {
		return nil, err
	}
	s.Lib.WriteActivity(r.Context())
	s.Bus.Publish("activity_changed", map[string]string{"day": day})
	return ok(), nil
}

func (s *Server) activity(_ http.ResponseWriter, r *http.Request) (any, error) {
	q := r.URL.Query()
	from, to := q.Get("from"), q.Get("to")
	if !validDate(from) || !validDate(to) || from > to {
		return nil, badRequest("日期范围无效，应为 YYYY-MM-DD")
	}
	if f, _ := time.Parse("2006-01-02", from); f.AddDate(0, 0, 400).Format("2006-01-02") < to {
		return nil, badRequest("日期范围最多 400 天")
	}
	ctx := r.Context()
	days, err := s.St.ActivityDays(ctx, from, to, q.Get("course_id"))
	if err != nil {
		return nil, err
	}
	streak, err := s.St.ActivityStreak(ctx, time.Now())
	if err != nil {
		return nil, err
	}
	courses, err := s.St.ActivityByCourse(ctx, from, to)
	if err != nil {
		return nil, err
	}
	var minutes, active int64
	for _, d := range days {
		minutes += d.Minutes
		if d.Minutes >= 1 || d.Asks > 0 || d.NotesNew > 0 || d.NotesEdited > 0 {
			active++
		}
	}
	return map[string]any{
		"days":    days,
		"streak":  streak,
		"totals":  map[string]int64{"minutes": minutes, "active_days": active},
		"courses": courses,
	}, nil
}

func (s *Server) activityDay(_ http.ResponseWriter, r *http.Request) (any, error) {
	day := r.URL.Query().Get("date")
	if !validDate(day) {
		return nil, badRequest("日期格式应为 YYYY-MM-DD")
	}
	return s.St.ActivityOn(r.Context(), day)
}
