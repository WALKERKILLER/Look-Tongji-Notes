package store

import (
	"context"
	"strings"
)

// ---- schedule ----

type ScheduleItem struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	Title     string `json:"title"`
	Detail    string `json:"detail"`
	DueDate   string `json:"due_date"`
	DueTime   string `json:"due_time"`
	CourseID  string `json:"course_id"`
	LectureID string `json:"lecture_id"`
	TMs       int64  `json:"t_ms"`
	Quote     string `json:"quote"`
	Source    string `json:"source"`
	Done      bool   `json:"done"`
	CreatedAt int64  `json:"created_at"`
	UpdatedAt int64  `json:"updated_at"`
	// Derived
	CourseTitle string `json:"course_title"`
	Lecture     string `json:"lecture"`
}

func (s *Store) PutScheduleItem(ctx context.Context, it ScheduleItem) error {
	t := now()
	if it.CreatedAt == 0 {
		it.CreatedAt = t
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO schedule(id,kind,title,detail,due_date,due_time,course_id,lecture_id,t_ms,quote,source,done,created_at,updated_at)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,title=excluded.title,detail=excluded.detail,
 due_date=excluded.due_date,due_time=excluded.due_time,course_id=excluded.course_id,lecture_id=excluded.lecture_id,t_ms=excluded.t_ms,
 quote=excluded.quote,done=excluded.done,updated_at=excluded.updated_at`,
		it.ID, it.Kind, it.Title, it.Detail, it.DueDate, it.DueTime, it.CourseID, it.LectureID, it.TMs, it.Quote, it.Source, it.Done, it.CreatedAt, t)
	return err
}

// ScheduleQuery filters schedule items; empty fields match everything.
type ScheduleQuery struct {
	From, To  string // inclusive YYYY-MM-DD bounds
	CourseID  string
	LectureID string
	Open      bool // only items not done
}

func (s *Store) Schedule(ctx context.Context, q ScheduleQuery) ([]ScheduleItem, error) {
	where := []string{"1=1"}
	var args []any
	add := func(cond string, v string) {
		if v != "" {
			where = append(where, cond)
			args = append(args, v)
		}
	}
	add("s.due_date>=?", q.From)
	add("s.due_date<=?", q.To)
	add("s.course_id=?", q.CourseID)
	add("s.lecture_id=?", q.LectureID)
	if q.Open {
		where = append(where, "s.done=0")
	}
	rows, err := s.DB.QueryContext(ctx, `SELECT s.id,s.kind,s.title,s.detail,s.due_date,s.due_time,s.course_id,s.lecture_id,s.t_ms,s.quote,s.source,s.done,
 s.created_at,s.updated_at,COALESCE(NULLIF(c.alias,''),c.title,''),COALESCE(l.title,'')
 FROM schedule s LEFT JOIN courses c ON c.id=s.course_id LEFT JOIN lectures l ON l.id=s.lecture_id
 WHERE `+strings.Join(where, " AND ")+` ORDER BY s.due_date, s.due_time='' DESC, s.due_time, s.created_at LIMIT 1000`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ScheduleItem{}
	for rows.Next() {
		var it ScheduleItem
		if err := rows.Scan(&it.ID, &it.Kind, &it.Title, &it.Detail, &it.DueDate, &it.DueTime, &it.CourseID, &it.LectureID, &it.TMs,
			&it.Quote, &it.Source, &it.Done, &it.CreatedAt, &it.UpdatedAt, &it.CourseTitle, &it.Lecture); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (s *Store) ScheduleItem(ctx context.Context, id string) (ScheduleItem, error) {
	var it ScheduleItem
	err := s.DB.QueryRowContext(ctx, `SELECT s.id,s.kind,s.title,s.detail,s.due_date,s.due_time,s.course_id,s.lecture_id,s.t_ms,s.quote,s.source,s.done,
 s.created_at,s.updated_at,COALESCE(NULLIF(c.alias,''),c.title,''),COALESCE(l.title,'')
 FROM schedule s LEFT JOIN courses c ON c.id=s.course_id LEFT JOIN lectures l ON l.id=s.lecture_id WHERE s.id=?`, id).
		Scan(&it.ID, &it.Kind, &it.Title, &it.Detail, &it.DueDate, &it.DueTime, &it.CourseID, &it.LectureID, &it.TMs,
			&it.Quote, &it.Source, &it.Done, &it.CreatedAt, &it.UpdatedAt, &it.CourseTitle, &it.Lecture)
	return it, err
}

func (s *Store) DeleteScheduleItem(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM schedule WHERE id=?`, id)
	return err
}

// ---- timeline ----

type Chapter struct {
	Idx     int    `json:"idx"`
	StartMs int64  `json:"start_ms"`
	EndMs   int64  `json:"end_ms"`
	Title   string `json:"title"`
}

func (s *Store) ReplaceTimeline(ctx context.Context, lectureID string, chs []Chapter) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM timeline WHERE lecture_id=?`, lectureID); err != nil {
		return err
	}
	for i, c := range chs {
		if _, err := tx.ExecContext(ctx, `INSERT INTO timeline(lecture_id,idx,start_ms,end_ms,title) VALUES(?,?,?,?,?)`,
			lectureID, i, c.StartMs, c.EndMs, c.Title); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) Timeline(ctx context.Context, lectureID string) ([]Chapter, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT idx,start_ms,end_ms,title FROM timeline WHERE lecture_id=? ORDER BY idx`, lectureID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Chapter{}
	for rows.Next() {
		var c Chapter
		if err := rows.Scan(&c.Idx, &c.StartMs, &c.EndMs, &c.Title); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) DeleteAsset(ctx context.Context, lectureID, kind, path string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM assets WHERE lecture_id=? AND kind=? AND path=?`, lectureID, kind, path)
	return err
}
