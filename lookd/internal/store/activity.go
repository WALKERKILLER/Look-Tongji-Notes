package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Study activity: seconds per local day and kind, reported by the app. Note
// and transcript counts are derived from their own tables so that autosaves
// cannot inflate them and past days are covered without inventing time.
// Contract: docs/specs/0001-learning-activity-heatmap.md

// TimedKinds are the activity kinds measured in seconds; "ask" is a count.
var TimedKinds = map[string]bool{"watch": true, "read": true, "practice": true}

// ValidActivityKind reports whether kind is a timed kind or "ask".
func ValidActivityKind(kind string) bool { return TimedKinds[kind] || kind == "ask" }

// CheckActivityRow validates a stored bucket, e.g. one restored from
// activity.json: a known kind, a real calendar day no later than tomorrow,
// and totals within what one day can hold.
func CheckActivityRow(r ActivityRow) error {
	d, err := time.ParseInLocation("2006-01-02", r.Day, time.Local)
	switch {
	case !ValidActivityKind(r.Kind):
		return fmt.Errorf("activity kind %q", r.Kind)
	case err != nil || d.Format("2006-01-02") != r.Day || r.Day < "2000-01-01" || d.After(time.Now().AddDate(0, 0, 1)):
		return fmt.Errorf("activity day %q", r.Day)
	case r.Seconds < 0 || r.Seconds > 86400 || r.Count < 0 || r.Count > 100000 || (r.Seconds == 0 && r.Count == 0):
		return fmt.Errorf("activity totals %d s, %d", r.Seconds, r.Count)
	case !TimedKinds[r.Kind] && r.Seconds != 0:
		return fmt.Errorf("activity kind %q has seconds", r.Kind)
	}
	return nil
}

// ReportsKept is how long report ids are remembered for deduplication; the
// app retries a report for at most a day.
const ReportsKept = 48 * time.Hour

// commitTx is replaced in tests to simulate a failed commit.
var commitTx = func(tx *sql.Tx) error { return tx.Commit() }

// querier is a database or a transaction.
type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

func addActivity(ctx context.Context, q querier, day, kind, courseID, lectureID string, seconds, count int64) error {
	_, err := q.ExecContext(ctx, `INSERT INTO activity(day,kind,course_id,lecture_id,seconds,count) VALUES(?,?,?,?,?,?)
 ON CONFLICT(day,kind,course_id,lecture_id) DO UPDATE SET seconds=seconds+excluded.seconds, count=count+excluded.count`,
		day, kind, courseID, lectureID, seconds, count)
	return err
}

// AddActivity adds seconds and/or a count to one day bucket.
func (s *Store) AddActivity(ctx context.Context, day, kind, courseID, lectureID string, seconds, count int64) error {
	return addActivity(ctx, s.DB, day, kind, courseID, lectureID, seconds, count)
}

// AddActivityMirrored adds a report to a bucket in one transaction and keeps
// the file copy in step with it:
//   - a report id seen before is a retry and changes nothing;
//   - token (when set) is recorded in the transaction, see MirrorCommitted;
//   - mirror writes every resulting row; if it fails, nothing is kept;
//   - if the commit then fails, mirror's undo is called.
func (s *Store) AddActivityMirrored(ctx context.Context, token, reportID, day, kind, courseID, lectureID string, seconds, count int64, mirror func([]ActivityRow) (undo func(), err error)) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if reportID != "" {
		now := time.Now()
		res, err := tx.ExecContext(ctx, `INSERT INTO activity_reports(id, at) VALUES(?, ?) ON CONFLICT(id) DO NOTHING`, reportID, now.Unix())
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return nil // already counted
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM activity_reports WHERE at < ?`, now.Add(-ReportsKept).Unix()); err != nil {
			return err
		}
	}
	if err := addActivity(ctx, tx, day, kind, courseID, lectureID, seconds, count); err != nil {
		return err
	}
	if err := markMirrorCommit(ctx, tx, token); err != nil {
		return err
	}
	rows, err := activityRows(ctx, tx)
	if err != nil {
		return err
	}
	undo, err := mirror(rows)
	if err != nil {
		return err
	}
	if err := commitTx(tx); err != nil {
		undo()
		return err
	}
	return nil
}

// ActivityRow is one stored bucket, as mirrored to activity.json.
type ActivityRow struct {
	Day       string `json:"day"`
	Kind      string `json:"kind"`
	CourseID  string `json:"course_id,omitempty"`
	LectureID string `json:"lecture_id,omitempty"`
	Seconds   int64  `json:"seconds,omitempty"`
	Count     int64  `json:"count,omitempty"`
}

// ActivityRows returns every bucket in day order.
func (s *Store) ActivityRows(ctx context.Context) ([]ActivityRow, error) {
	return activityRows(ctx, s.DB)
}

func activityRows(ctx context.Context, q querier) ([]ActivityRow, error) {
	rows, err := q.QueryContext(ctx, `SELECT day,kind,course_id,lecture_id,seconds,count FROM activity ORDER BY day,kind,course_id,lecture_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ActivityRow{}
	for rows.Next() {
		var r ActivityRow
		if err := rows.Scan(&r.Day, &r.Kind, &r.CourseID, &r.LectureID, &r.Seconds, &r.Count); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// PutActivity restores a bucket when reindexing. Totals only grow, so the
// larger of the stored and restored values wins and an older file copy can
// never lower newer totals.
func (s *Store) PutActivity(ctx context.Context, r ActivityRow) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO activity(day,kind,course_id,lecture_id,seconds,count) VALUES(?,?,?,?,?,?)
 ON CONFLICT(day,kind,course_id,lecture_id) DO UPDATE SET seconds=MAX(seconds,excluded.seconds), count=MAX(count,excluded.count)`,
		r.Day, r.Kind, r.CourseID, r.LectureID, r.Seconds, r.Count)
	return err
}

// ActivityDay is one calendar day of study.
type ActivityDay struct {
	Date        string           `json:"date"`
	Minutes     int64            `json:"minutes"`
	Seconds     map[string]int64 `json:"by_kind"`
	Asks        int64            `json:"asks"`
	NotesNew    int64            `json:"notes_created"`
	NotesEdited int64            `json:"notes_edited"`
	Transcripts int64            `json:"transcripts"`
}

// Active reports whether the day counts as a study day (heatmap, streaks,
// totals): study time or any recorded event.
func (d *ActivityDay) Active() bool {
	return d.Minutes >= 1 || d.Asks > 0 || d.NotesNew > 0 || d.NotesEdited > 0 || d.Transcripts > 0
}

// ActivityDays returns every day in [from, to] (inclusive, YYYY-MM-DD),
// optionally limited to one course.
func (s *Store) ActivityDays(ctx context.Context, from, to, courseID string) ([]ActivityDay, error) {
	start, err := time.ParseInLocation("2006-01-02", from, time.Local)
	if err != nil {
		return nil, err
	}
	end, err := time.ParseInLocation("2006-01-02", to, time.Local)
	if err != nil {
		return nil, err
	}
	byDay := map[string]*ActivityDay{}
	var out []ActivityDay
	for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
		out = append(out, ActivityDay{Date: d.Format("2006-01-02"), Seconds: map[string]int64{}})
	}
	for i := range out {
		byDay[out[i].Date] = &out[i]
	}
	day := func(k string) *ActivityDay { return byDay[k] }

	rows, err := s.DB.QueryContext(ctx, `SELECT day, kind, SUM(seconds), SUM(count) FROM activity
 WHERE day BETWEEN ? AND ? AND (?='' OR course_id=?) GROUP BY day, kind`, from, to, courseID, courseID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var d, kind string
		var sec, n int64
		if err := rows.Scan(&d, &kind, &sec, &n); err != nil {
			rows.Close()
			return nil, err
		}
		a := day(d)
		if a == nil {
			continue
		}
		if TimedKinds[kind] {
			a.Seconds[kind] += sec
		}
		if kind == "ask" {
			a.Asks += n
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range out {
		var sec int64
		for _, v := range out[i].Seconds {
			sec += v
		}
		out[i].Minutes = sec / 60
	}

	// Notes written by the user: created on a day, or last edited on a later day.
	rows, err = s.DB.QueryContext(ctx, `SELECT date(created_at,'unixepoch','localtime'), date(updated_at,'unixepoch','localtime') FROM notes
 WHERE source='user' AND (?='' OR course_id=?)
 AND (date(created_at,'unixepoch','localtime') BETWEEN ? AND ? OR date(updated_at,'unixepoch','localtime') BETWEEN ? AND ?)`,
		courseID, courseID, from, to, from, to)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var c, u string
		if err := rows.Scan(&c, &u); err != nil {
			rows.Close()
			return nil, err
		}
		if a := day(c); a != nil {
			a.NotesNew++
		}
		if a := day(u); a != nil && u != c {
			a.NotesEdited++
		}
	}
	rows.Close()

	rows, err = s.DB.QueryContext(ctx, `SELECT date(a.created_at,'unixepoch','localtime'), COUNT(*) FROM assets a JOIN lectures l ON l.id=a.lecture_id
 WHERE a.kind='transcript' AND (?='' OR l.course_id=?) AND date(a.created_at,'unixepoch','localtime') BETWEEN ? AND ?
 GROUP BY 1`, courseID, courseID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var d string
		var n int64
		if err := rows.Scan(&d, &n); err != nil {
			return nil, err
		}
		if a := day(d); a != nil {
			a.Transcripts += n
		}
	}
	return out, rows.Err()
}

// Streak counts consecutive active days. Current ends today, or yesterday
// when today has no activity yet.
type Streak struct {
	Current int `json:"current"`
	Longest int `json:"longest"`
}

// ActivityStreak scans all history for active days.
func (s *Store) ActivityStreak(ctx context.Context, today time.Time) (Streak, error) {
	var first string
	if err := s.DB.QueryRowContext(ctx, `SELECT COALESCE(MIN(d),'') FROM (
 SELECT MIN(day) d FROM activity UNION ALL
 SELECT date(MIN(created_at),'unixepoch','localtime') FROM notes WHERE source='user' UNION ALL
 SELECT date(MIN(created_at),'unixepoch','localtime') FROM assets WHERE kind='transcript')`).Scan(&first); err != nil || first == "" {
		return Streak{}, err
	}
	days, err := s.ActivityDays(ctx, first, today.Format("2006-01-02"), "")
	if err != nil {
		return Streak{}, err
	}
	var st Streak
	run := 0
	for i := range days {
		if days[i].Active() {
			run++
			st.Longest = max(st.Longest, run)
		} else {
			run = 0
		}
	}
	// Walk back from today (skipping an inactive today).
	i := len(days) - 1
	if i >= 0 && !days[i].Active() {
		i--
	}
	for ; i >= 0 && days[i].Active(); i-- {
		st.Current++
	}
	return st, nil
}

// CourseMinutes ranks courses by study minutes in [from, to].
type CourseMinutes struct {
	CourseID string `json:"course_id"`
	Title    string `json:"title"`
	Minutes  int64  `json:"minutes"`
}

func (s *Store) ActivityByCourse(ctx context.Context, from, to string) ([]CourseMinutes, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT a.course_id, COALESCE(NULLIF(c.alias,''), c.title, ''), SUM(a.seconds)/60 m
 FROM activity a LEFT JOIN courses c ON c.id=a.course_id
 WHERE a.day BETWEEN ? AND ? AND a.course_id<>'' AND a.kind IN ('watch','read','practice')
 GROUP BY a.course_id HAVING m > 0 ORDER BY m DESC`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []CourseMinutes{}
	for rows.Next() {
		var c CourseMinutes
		if err := rows.Scan(&c.CourseID, &c.Title, &c.Minutes); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// DayLecture is time spent on one lecture during a day.
type DayLecture struct {
	LectureID   string `json:"lecture_id"`
	CourseID    string `json:"course_id"`
	Title       string `json:"title"`
	CourseTitle string `json:"course_title"`
	Kind        string `json:"kind"`
	Seconds     int64  `json:"seconds"`
}

// DayNote is a user note created or edited on a day.
type DayNote struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	LectureID string `json:"lecture_id"`
	Created   bool   `json:"created"`
}

// ActivityDetail lists what happened on one day.
type ActivityDetail struct {
	ActivityDay
	Lectures    []DayLecture `json:"lectures"`
	Notes       []DayNote    `json:"notes"`
	Transcribed []DayLecture `json:"transcribed"`
}

func (s *Store) ActivityOn(ctx context.Context, day string) (ActivityDetail, error) {
	days, err := s.ActivityDays(ctx, day, day, "")
	if err != nil {
		return ActivityDetail{}, err
	}
	d := ActivityDetail{ActivityDay: days[0], Lectures: []DayLecture{}, Notes: []DayNote{}, Transcribed: []DayLecture{}}
	rows, err := s.DB.QueryContext(ctx, `SELECT a.lecture_id, COALESCE(NULLIF(a.course_id,''), l.course_id, ''), COALESCE(l.title,''),
 COALESCE(NULLIF(c.alias,''), c.title, ''), a.kind, SUM(a.seconds)
 FROM activity a LEFT JOIN lectures l ON l.id=a.lecture_id LEFT JOIN courses c ON c.id=COALESCE(NULLIF(a.course_id,''), l.course_id)
 WHERE a.day=? AND a.lecture_id<>'' AND a.kind IN ('watch','read','practice')
 GROUP BY a.lecture_id, a.kind HAVING SUM(a.seconds) >= 30 ORDER BY SUM(a.seconds) DESC`, day)
	if err != nil {
		return d, err
	}
	for rows.Next() {
		var l DayLecture
		if err := rows.Scan(&l.LectureID, &l.CourseID, &l.Title, &l.CourseTitle, &l.Kind, &l.Seconds); err != nil {
			rows.Close()
			return d, err
		}
		d.Lectures = append(d.Lectures, l)
	}
	rows.Close()
	rows, err = s.DB.QueryContext(ctx, `SELECT id, title, lecture_id, date(created_at,'unixepoch','localtime')=? FROM notes
 WHERE source='user' AND (date(created_at,'unixepoch','localtime')=? OR date(updated_at,'unixepoch','localtime')=?) ORDER BY updated_at DESC`, day, day, day)
	if err != nil {
		return d, err
	}
	for rows.Next() {
		var n DayNote
		if err := rows.Scan(&n.ID, &n.Title, &n.LectureID, &n.Created); err != nil {
			rows.Close()
			return d, err
		}
		d.Notes = append(d.Notes, n)
	}
	rows.Close()
	rows, err = s.DB.QueryContext(ctx, `SELECT l.id, l.course_id, l.title, COALESCE(NULLIF(c.alias,''), c.title, '') FROM assets a
 JOIN lectures l ON l.id=a.lecture_id LEFT JOIN courses c ON c.id=l.course_id
 WHERE a.kind='transcript' AND date(a.created_at,'unixepoch','localtime')=? GROUP BY l.id`, day)
	if err != nil {
		return d, err
	}
	defer rows.Close()
	for rows.Next() {
		var l DayLecture
		if err := rows.Scan(&l.LectureID, &l.CourseID, &l.Title, &l.CourseTitle); err != nil {
			return d, err
		}
		l.Kind = "transcript"
		d.Transcribed = append(d.Transcribed, l)
	}
	return d, rows.Err()
}
