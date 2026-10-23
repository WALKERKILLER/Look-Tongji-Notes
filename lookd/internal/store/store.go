// Package store is the SQLite index of the Look Studio library.
package store

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

//go:embed schema.sql
var schema string

const SchemaVersion = "1"

type Store struct{ DB *sql.DB }

func Open(path string) (*Store, error) {
	dsn := "file:" + path + "?_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(4)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	if _, err := db.Exec(`INSERT INTO meta(key,value) VALUES('schema_version',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, SchemaVersion); err != nil {
		db.Close()
		return nil, err
	}
	return &Store{DB: db}, nil
}

func (s *Store) Close() error { return s.DB.Close() }

func now() int64 { return time.Now().Unix() }

// ---- courses & lectures ----

type Course struct {
	ID           string          `json:"id"`
	Title        string          `json:"title"`
	Teacher      string          `json:"teacher"`
	Teachers     json.RawMessage `json:"teachers"`
	College      string          `json:"college"`
	Term         string          `json:"term"`
	Thumb        string          `json:"thumb"`
	StartAt      int64           `json:"start_at"`
	EndAt        int64           `json:"end_at"`
	LectureTotal int             `json:"lecture_total"`
	Progress     float64         `json:"progress"`
	LastSubID    string          `json:"last_sub_id"`
	LastLearnAt  string          `json:"last_learn_at"`
	Pinned       bool            `json:"pinned"`
	Hidden       bool            `json:"hidden"`
	Alias        string          `json:"alias"`
	Color        string          `json:"color"`
	Dir          string          `json:"dir"`
	SyncedAt     int64           `json:"synced_at"`
	// Derived
	LocalLectures int `json:"local_lectures"`
}

// UpsertCourse stores remote fields and keeps user-owned fields (pinned, alias, ...).
func (s *Store) UpsertCourse(ctx context.Context, c Course) error {
	if len(c.Teachers) == 0 {
		c.Teachers = json.RawMessage("[]")
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO courses
 (id,title,teacher,teachers_json,college,term,thumb,start_at,end_at,lecture_total,progress,last_sub_id,last_learn_at,synced_at)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
 ON CONFLICT(id) DO UPDATE SET title=excluded.title,teacher=excluded.teacher,teachers_json=excluded.teachers_json,
 college=excluded.college,term=excluded.term,thumb=excluded.thumb,start_at=excluded.start_at,end_at=excluded.end_at,
 lecture_total=CASE WHEN excluded.lecture_total>0 THEN excluded.lecture_total ELSE courses.lecture_total END,
 progress=excluded.progress,last_sub_id=excluded.last_sub_id,last_learn_at=excluded.last_learn_at,synced_at=excluded.synced_at`,
		c.ID, c.Title, c.Teacher, string(c.Teachers), c.College, c.Term, c.Thumb, c.StartAt, c.EndAt, c.LectureTotal,
		c.Progress, c.LastSubID, c.LastLearnAt, now())
	return err
}

const courseCols = `c.id,c.title,c.teacher,c.teachers_json,c.college,c.term,c.thumb,c.start_at,c.end_at,c.lecture_total,c.progress,
 c.last_sub_id,c.last_learn_at,c.pinned,c.hidden,c.alias,c.color,c.dir,c.synced_at,
 (SELECT COUNT(DISTINCT a.lecture_id) FROM assets a JOIN lectures l ON l.id=a.lecture_id WHERE l.course_id=c.id)`

func scanCourse(sc interface{ Scan(...any) error }) (Course, error) {
	var c Course
	var teachers string
	err := sc.Scan(&c.ID, &c.Title, &c.Teacher, &teachers, &c.College, &c.Term, &c.Thumb, &c.StartAt, &c.EndAt,
		&c.LectureTotal, &c.Progress, &c.LastSubID, &c.LastLearnAt, &c.Pinned, &c.Hidden, &c.Alias, &c.Color, &c.Dir,
		&c.SyncedAt, &c.LocalLectures)
	c.Teachers = json.RawMessage(teachers)
	return c, err
}

func (s *Store) Courses(ctx context.Context) ([]Course, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+courseCols+` FROM courses c
 ORDER BY c.pinned DESC, c.term DESC, c.last_learn_at DESC, c.start_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Course{}
	for rows.Next() {
		c, err := scanCourse(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) Course(ctx context.Context, id string) (Course, error) {
	return scanCourse(s.DB.QueryRowContext(ctx, `SELECT `+courseCols+` FROM courses c WHERE c.id=?`, id))
}

// PatchCourse updates user-owned course fields.
func (s *Store) PatchCourse(ctx context.Context, id string, patch map[string]any) error {
	allowed := map[string]bool{"pinned": true, "hidden": true, "alias": true, "color": true}
	var sets []string
	var args []any
	for k, v := range patch {
		if !allowed[k] {
			return fmt.Errorf("field %q is not editable", k)
		}
		if b, ok := v.(bool); ok {
			if b {
				v = 1
			} else {
				v = 0
			}
		}
		sets = append(sets, k+"=?")
		args = append(args, v)
	}
	if len(sets) == 0 {
		return nil
	}
	args = append(args, id)
	_, err := s.DB.ExecContext(ctx, "UPDATE courses SET "+strings.Join(sets, ",")+" WHERE id=?", args...)
	return err
}

func (s *Store) SetCourseDir(ctx context.Context, id, dir string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE courses SET dir=? WHERE id=?`, dir, id)
	return err
}

type Lecture struct {
	ID          string `json:"id"`
	CourseID    string `json:"course_id"`
	Title       string `json:"title"`
	Date        string `json:"date"`
	BeginAt     int64  `json:"begin_at"`
	EndAt       int64  `json:"end_at"`
	Lecturer    string `json:"lecturer"`
	Room        string `json:"room"`
	HasPlayback bool   `json:"has_playback"`
	DurationS   int64  `json:"duration_s"`
	Thumb       string `json:"thumb"`
	Dir         string `json:"dir"`
	// Derived
	Assets     []string `json:"assets"`
	PositionMs int64    `json:"position_ms"`
	Segments   int      `json:"segments"`
}

func (s *Store) UpsertLectures(ctx context.Context, ls []Lecture) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	st, err := tx.PrepareContext(ctx, `INSERT INTO lectures(id,course_id,title,date,begin_at,end_at,lecturer,room,has_playback,synced_at)
 VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET course_id=excluded.course_id,title=excluded.title,date=excluded.date,
 begin_at=excluded.begin_at,end_at=excluded.end_at,lecturer=excluded.lecturer,room=excluded.room,has_playback=excluded.has_playback,
 synced_at=excluded.synced_at`)
	if err != nil {
		return err
	}
	for _, l := range ls {
		if _, err := st.ExecContext(ctx, l.ID, l.CourseID, l.Title, l.Date, l.BeginAt, l.EndAt, l.Lecturer, l.Room, l.HasPlayback, now()); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) SetLectureMedia(ctx context.Context, id string, durationS int64, thumb string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE lectures SET duration_s=CASE WHEN ?>0 THEN ? ELSE duration_s END,
 thumb=CASE WHEN ?<>'' THEN ? ELSE thumb END WHERE id=?`, durationS, durationS, thumb, thumb, id)
	return err
}

func (s *Store) SetLectureDir(ctx context.Context, id, dir string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE lectures SET dir=? WHERE id=?`, dir, id)
	return err
}

const lectureCols = `l.id,l.course_id,l.title,l.date,l.begin_at,l.end_at,l.lecturer,l.room,l.has_playback,l.duration_s,l.thumb,l.dir,
 COALESCE((SELECT group_concat(DISTINCT kind) FROM assets a WHERE a.lecture_id=l.id),''),
 COALESCE((SELECT position_ms FROM playback p WHERE p.lecture_id=l.id),0),
 (SELECT COUNT(*) FROM segments g WHERE g.lecture_id=l.id)`

func scanLecture(sc interface{ Scan(...any) error }) (Lecture, error) {
	var l Lecture
	var kinds string
	err := sc.Scan(&l.ID, &l.CourseID, &l.Title, &l.Date, &l.BeginAt, &l.EndAt, &l.Lecturer, &l.Room, &l.HasPlayback,
		&l.DurationS, &l.Thumb, &l.Dir, &kinds, &l.PositionMs, &l.Segments)
	l.Assets = []string{}
	if kinds != "" {
		l.Assets = strings.Split(kinds, ",")
	}
	return l, err
}

func (s *Store) Lectures(ctx context.Context, courseID string) ([]Lecture, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+lectureCols+` FROM lectures l WHERE l.course_id=? ORDER BY l.begin_at DESC, l.id DESC`, courseID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Lecture{}
	for rows.Next() {
		l, err := scanLecture(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

func (s *Store) Lecture(ctx context.Context, id string) (Lecture, error) {
	return scanLecture(s.DB.QueryRowContext(ctx, `SELECT `+lectureCols+` FROM lectures l WHERE l.id=?`, id))
}

// RecentLectures returns lectures with playback progress or local assets.
func (s *Store) RecentLectures(ctx context.Context, limit int) ([]Lecture, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+lectureCols+` FROM lectures l
 LEFT JOIN playback p ON p.lecture_id=l.id
 WHERE p.lecture_id IS NOT NULL ORDER BY p.updated_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Lecture{}
	for rows.Next() {
		l, err := scanLecture(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// ---- assets, slides, transcript ----

type Asset struct {
	LectureID string          `json:"lecture_id"`
	Kind      string          `json:"kind"`
	Path      string          `json:"path"`
	Bytes     int64           `json:"bytes"`
	CreatedAt int64           `json:"created_at"`
	Meta      json.RawMessage `json:"meta"`
}

func (s *Store) PutAsset(ctx context.Context, a Asset) error {
	if len(a.Meta) == 0 {
		a.Meta = json.RawMessage("{}")
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO assets(lecture_id,kind,path,bytes,created_at,meta_json) VALUES(?,?,?,?,?,?)
 ON CONFLICT(lecture_id,kind,path) DO UPDATE SET bytes=excluded.bytes,meta_json=excluded.meta_json`,
		a.LectureID, a.Kind, a.Path, a.Bytes, now(), string(a.Meta))
	return err
}

func (s *Store) DeleteAssets(ctx context.Context, lectureID, kind string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM assets WHERE lecture_id=? AND kind=?`, lectureID, kind)
	return err
}

func (s *Store) Assets(ctx context.Context, lectureID string) ([]Asset, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT lecture_id,kind,path,bytes,created_at,meta_json FROM assets WHERE lecture_id=? ORDER BY kind,path`, lectureID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Asset{}
	for rows.Next() {
		var a Asset
		var meta string
		if err := rows.Scan(&a.LectureID, &a.Kind, &a.Path, &a.Bytes, &a.CreatedAt, &meta); err != nil {
			return nil, err
		}
		a.Meta = json.RawMessage(meta)
		out = append(out, a)
	}
	return out, rows.Err()
}

// LocalItem is one downloaded artifact with its lecture and course, for the
// storage screen.
type LocalItem struct {
	LectureID   string `json:"lecture_id"`
	CourseID    string `json:"course_id"`
	CourseTitle string `json:"course_title"`
	Lecture     string `json:"lecture"`
	Date        string `json:"date"`
	Kind        string `json:"kind"`
	Bytes       int64  `json:"bytes"`
	Files       int    `json:"files"`
	CreatedAt   int64  `json:"created_at"`
}

// LocalItems groups assets by lecture and kind, newest first.
func (s *Store) LocalItems(ctx context.Context) ([]LocalItem, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT a.lecture_id, l.course_id, COALESCE(NULLIF(c.alias,''), c.title, ''), l.title, l.date,
 a.kind, SUM(a.bytes), COUNT(*), MAX(a.created_at)
 FROM assets a JOIN lectures l ON l.id=a.lecture_id LEFT JOIN courses c ON c.id=l.course_id
 GROUP BY a.lecture_id, a.kind ORDER BY MAX(a.created_at) DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []LocalItem{}
	for rows.Next() {
		var it LocalItem
		if err := rows.Scan(&it.LectureID, &it.CourseID, &it.CourseTitle, &it.Lecture, &it.Date, &it.Kind, &it.Bytes, &it.Files, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// ClearSlidePaths forgets local slide files but keeps remote URLs for streaming.
func (s *Store) ClearSlidePaths(ctx context.Context, lectureID string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE slides SET path='' WHERE lecture_id=?`, lectureID)
	return err
}

type Slide struct {
	Idx       int    `json:"idx"`
	TSec      int64  `json:"t_sec"`
	IsKey     bool   `json:"is_key"`
	RemoteURL string `json:"remote_url"`
	Path      string `json:"path"`
}

func (s *Store) ReplaceSlides(ctx context.Context, lectureID string, slides []Slide) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM slides WHERE lecture_id=?`, lectureID); err != nil {
		return err
	}
	for _, sl := range slides {
		if _, err := tx.ExecContext(ctx, `INSERT INTO slides(lecture_id,idx,t_sec,is_key,remote_url,path) VALUES(?,?,?,?,?,?)`,
			lectureID, sl.Idx, sl.TSec, sl.IsKey, sl.RemoteURL, sl.Path); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) Slides(ctx context.Context, lectureID string) ([]Slide, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT idx,t_sec,is_key,remote_url,path FROM slides WHERE lecture_id=? ORDER BY idx`, lectureID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Slide{}
	for rows.Next() {
		var sl Slide
		if err := rows.Scan(&sl.Idx, &sl.TSec, &sl.IsKey, &sl.RemoteURL, &sl.Path); err != nil {
			return nil, err
		}
		out = append(out, sl)
	}
	return out, rows.Err()
}

type Segment struct {
	Idx     int    `json:"idx"`
	StartMs int64  `json:"start_ms"`
	EndMs   int64  `json:"end_ms"`
	Text    string `json:"text"`
}

func (s *Store) ReplaceSegments(ctx context.Context, lectureID string, segs []Segment) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM segments WHERE lecture_id=?`, lectureID); err != nil {
		return err
	}
	st, err := tx.PrepareContext(ctx, `INSERT INTO segments(lecture_id,idx,start_ms,end_ms,text) VALUES(?,?,?,?,?)`)
	if err != nil {
		return err
	}
	for _, g := range segs {
		if _, err := st.ExecContext(ctx, lectureID, g.Idx, g.StartMs, g.EndMs, g.Text); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) Segments(ctx context.Context, lectureID string, fromMs, toMs int64) ([]Segment, error) {
	if toMs <= 0 {
		toMs = 1 << 62
	}
	rows, err := s.DB.QueryContext(ctx, `SELECT idx,start_ms,end_ms,text FROM segments WHERE lecture_id=? AND end_ms>=? AND start_ms<=? ORDER BY idx`,
		lectureID, fromMs, toMs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Segment{}
	for rows.Next() {
		var g Segment
		if err := rows.Scan(&g.Idx, &g.StartMs, &g.EndMs, &g.Text); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// ---- search ----

type Hit struct {
	Kind        string `json:"kind"` // segment | note
	CourseID    string `json:"course_id"`
	CourseTitle string `json:"course_title"`
	LectureID   string `json:"lecture_id"`
	Lecture     string `json:"lecture"`
	NoteID      string `json:"note_id,omitempty"`
	StartMs     int64  `json:"start_ms"`
	Snippet     string `json:"snippet"`
}

// Search runs full-text search over transcripts and notes. The trigram
// tokenizer needs >=3 characters; shorter queries fall back to LIKE.
func (s *Store) Search(ctx context.Context, q, courseID string, limit int) ([]Hit, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return []Hit{}, nil
	}
	if limit <= 0 {
		limit = 50
	}
	var segSQL, noteSQL string
	var segArgs, noteArgs []any
	if len([]rune(q)) >= 3 {
		match := `"` + strings.ReplaceAll(q, `"`, `""`) + `"`
		segSQL = `SELECT g.lecture_id AS lecture_id,g.start_ms AS start_ms,snippet(segments_fts,0,'«','»','…',24) AS snip FROM segments_fts f JOIN segments g ON g.rowid=f.rowid WHERE segments_fts MATCH ?`
		noteSQL = `SELECT n.id AS id,n.course_id AS course_id,n.lecture_id AS lecture_id,snippet(notes_fts,1,'«','»','…',24) AS snip FROM notes_fts f JOIN notes n ON n.rowid=f.rowid WHERE notes_fts MATCH ?`
		segArgs, noteArgs = []any{match}, []any{match}
	} else {
		like := "%" + q + "%"
		segSQL = `SELECT g.lecture_id AS lecture_id,g.start_ms AS start_ms,g.text AS snip FROM segments g WHERE g.text LIKE ?`
		noteSQL = `SELECT n.id AS id,n.course_id AS course_id,n.lecture_id AS lecture_id,substr(n.body,1,120) AS snip FROM notes n WHERE n.title LIKE ? OR n.body LIKE ?`
		segArgs, noteArgs = []any{like}, []any{like, like}
	}
	out := []Hit{}
	rows, err := s.DB.QueryContext(ctx, `SELECT x.lecture_id, x.start_ms, x.snip, l.course_id, COALESCE(c.title,''), l.title
 FROM (`+segSQL+`) AS x JOIN lectures l ON l.id=x.lecture_id LEFT JOIN courses c ON c.id=l.course_id
 WHERE (?='' OR l.course_id=?) LIMIT ?`, append(segArgs, courseID, courseID, limit)...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var h Hit
		h.Kind = "segment"
		if err := rows.Scan(&h.LectureID, &h.StartMs, &h.Snippet, &h.CourseID, &h.CourseTitle, &h.Lecture); err != nil {
			rows.Close()
			return nil, err
		}
		out = append(out, h)
	}
	rows.Close()
	rows, err = s.DB.QueryContext(ctx, `SELECT x.id,x.course_id,x.lecture_id,x.snip,COALESCE(c.title,''),COALESCE(l.title,'')
 FROM (`+noteSQL+`) AS x LEFT JOIN courses c ON c.id=x.course_id LEFT JOIN lectures l ON l.id=x.lecture_id
 WHERE (?='' OR x.course_id=?) LIMIT ?`, append(noteArgs, courseID, courseID, limit)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var h Hit
		h.Kind = "note"
		if err := rows.Scan(&h.NoteID, &h.CourseID, &h.LectureID, &h.Snippet, &h.CourseTitle, &h.Lecture); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

// ---- notes ----

type Note struct {
	ID        string `json:"id"`
	CourseID  string `json:"course_id"`
	LectureID string `json:"lecture_id"`
	Title     string `json:"title"`
	Body      string `json:"body,omitempty"`
	Source    string `json:"source"`
	Pinned    bool   `json:"pinned"`
	Path      string `json:"path"`
	CreatedAt int64  `json:"created_at"`
	UpdatedAt int64  `json:"updated_at"`
}

func (s *Store) PutNote(ctx context.Context, n Note) error {
	if n.Source == "" {
		n.Source = "user"
	}
	t := now()
	_, err := s.DB.ExecContext(ctx, `INSERT INTO notes(id,course_id,lecture_id,title,body,source,pinned,path,created_at,updated_at)
 VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET course_id=excluded.course_id,lecture_id=excluded.lecture_id,title=excluded.title,
 body=excluded.body,pinned=excluded.pinned,path=excluded.path,updated_at=excluded.updated_at`,
		n.ID, n.CourseID, n.LectureID, n.Title, n.Body, n.Source, n.Pinned, n.Path, t, t)
	return err
}

func (s *Store) Notes(ctx context.Context, courseID, lectureID string) ([]Note, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id,course_id,lecture_id,title,source,pinned,path,created_at,updated_at FROM notes
 WHERE (?='' OR course_id=?) AND (?='' OR lecture_id=?) ORDER BY pinned DESC, updated_at DESC`, courseID, courseID, lectureID, lectureID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Note{}
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.CourseID, &n.LectureID, &n.Title, &n.Source, &n.Pinned, &n.Path, &n.CreatedAt, &n.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

func (s *Store) Note(ctx context.Context, id string) (Note, error) {
	var n Note
	err := s.DB.QueryRowContext(ctx, `SELECT id,course_id,lecture_id,title,body,source,pinned,path,created_at,updated_at FROM notes WHERE id=?`, id).
		Scan(&n.ID, &n.CourseID, &n.LectureID, &n.Title, &n.Body, &n.Source, &n.Pinned, &n.Path, &n.CreatedAt, &n.UpdatedAt)
	return n, err
}

func (s *Store) DeleteNote(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM notes WHERE id=?`, id)
	return err
}

// ---- jobs ----

type Job struct {
	ID         string  `json:"id"`
	CourseID   string  `json:"course_id"`
	LectureID  string  `json:"lecture_id"`
	Kind       string  `json:"kind"`
	Title      string  `json:"title"`
	State      string  `json:"state"`
	DoneBytes  int64   `json:"done_bytes"`
	TotalBytes int64   `json:"total_bytes"`
	Progress   float64 `json:"progress"`
	Error      string  `json:"error"`
	CreatedAt  int64   `json:"created_at"`
	UpdatedAt  int64   `json:"updated_at"`
	// Live-only fields, filled by the scheduler.
	Speed int64  `json:"speed"`
	Conns int    `json:"conns"`
	Stage string `json:"stage,omitempty"`
	// RetryAt is when a queued job retries after a transient failure (Unix s).
	RetryAt int64 `json:"retry_at,omitempty"`
}

func (s *Store) PutJob(ctx context.Context, j Job) error {
	t := now()
	if j.CreatedAt == 0 {
		j.CreatedAt = t
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO jobs(id,course_id,lecture_id,kind,title,state,done_bytes,total_bytes,progress,error,created_at,updated_at)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state,done_bytes=excluded.done_bytes,
 total_bytes=excluded.total_bytes,progress=excluded.progress,error=excluded.error,title=excluded.title,updated_at=excluded.updated_at`,
		j.ID, j.CourseID, j.LectureID, j.Kind, j.Title, j.State, j.DoneBytes, j.TotalBytes, j.Progress, j.Error, j.CreatedAt, t)
	return err
}

func (s *Store) Jobs(ctx context.Context, states ...string) ([]Job, error) {
	q := `SELECT id,course_id,lecture_id,kind,title,state,done_bytes,total_bytes,progress,error,created_at,updated_at FROM jobs`
	var args []any
	if len(states) > 0 {
		q += ` WHERE state IN (?` + strings.Repeat(",?", len(states)-1) + `)`
		for _, s := range states {
			args = append(args, s)
		}
	}
	q += ` ORDER BY created_at DESC LIMIT 500`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Job{}
	for rows.Next() {
		var j Job
		if err := rows.Scan(&j.ID, &j.CourseID, &j.LectureID, &j.Kind, &j.Title, &j.State, &j.DoneBytes, &j.TotalBytes, &j.Progress, &j.Error, &j.CreatedAt, &j.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

func (s *Store) Job(ctx context.Context, id string) (Job, error) {
	var j Job
	err := s.DB.QueryRowContext(ctx, `SELECT id,course_id,lecture_id,kind,title,state,done_bytes,total_bytes,progress,error,created_at,updated_at FROM jobs WHERE id=?`, id).
		Scan(&j.ID, &j.CourseID, &j.LectureID, &j.Kind, &j.Title, &j.State, &j.DoneBytes, &j.TotalBytes, &j.Progress, &j.Error, &j.CreatedAt, &j.UpdatedAt)
	return j, err
}

func (s *Store) DeleteJob(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM jobs WHERE id=?`, id)
	return err
}

func (s *Store) ClearFinishedJobs(ctx context.Context) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM jobs WHERE state IN ('done','canceled')`)
	return err
}

// ---- playback, bookmarks ----

type Playback struct {
	PositionMs int64   `json:"position_ms"`
	DurationMs int64   `json:"duration_ms"`
	Speed      float64 `json:"speed"`
}

func (s *Store) SavePlayback(ctx context.Context, lectureID string, p Playback) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO playback(lecture_id,position_ms,duration_ms,speed,updated_at) VALUES(?,?,?,?,?)
 ON CONFLICT(lecture_id) DO UPDATE SET position_ms=excluded.position_ms,duration_ms=excluded.duration_ms,speed=excluded.speed,updated_at=excluded.updated_at`,
		lectureID, p.PositionMs, p.DurationMs, p.Speed, now())
	return err
}

func (s *Store) Playback(ctx context.Context, lectureID string) (Playback, error) {
	p := Playback{Speed: 1}
	err := s.DB.QueryRowContext(ctx, `SELECT position_ms,duration_ms,speed FROM playback WHERE lecture_id=?`, lectureID).Scan(&p.PositionMs, &p.DurationMs, &p.Speed)
	if errors.Is(err, sql.ErrNoRows) {
		err = nil
	}
	return p, err
}

type Bookmark struct {
	ID        int64  `json:"id"`
	LectureID string `json:"lecture_id"`
	TMs       int64  `json:"t_ms"`
	Label     string `json:"label"`
	CreatedAt int64  `json:"created_at"`
}

func (s *Store) AddBookmark(ctx context.Context, b Bookmark) (int64, error) {
	r, err := s.DB.ExecContext(ctx, `INSERT INTO bookmarks(lecture_id,t_ms,label,created_at) VALUES(?,?,?,?)`, b.LectureID, b.TMs, b.Label, now())
	if err != nil {
		return 0, err
	}
	return r.LastInsertId()
}

func (s *Store) Bookmarks(ctx context.Context, lectureID string) ([]Bookmark, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id,lecture_id,t_ms,label,created_at FROM bookmarks WHERE lecture_id=? ORDER BY t_ms`, lectureID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Bookmark{}
	for rows.Next() {
		var b Bookmark
		if err := rows.Scan(&b.ID, &b.LectureID, &b.TMs, &b.Label, &b.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (s *Store) DeleteBookmark(ctx context.Context, id int64) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM bookmarks WHERE id=?`, id)
	return err
}

// ---- settings ----

func (s *Store) Settings(ctx context.Context) (map[string]json.RawMessage, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT key,value FROM settings`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]json.RawMessage{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		out[k] = json.RawMessage(v)
	}
	return out, rows.Err()
}

func (s *Store) PutSettings(ctx context.Context, kv map[string]json.RawMessage) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for k, v := range kv {
		if !json.Valid(v) {
			return fmt.Errorf("setting %s is not valid JSON", k)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, k, string(v)); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// Stats summarizes the library for the dashboard.
type Stats struct {
	Courses  int   `json:"courses"`
	Lectures int   `json:"lectures"`
	Local    int   `json:"local_lectures"`
	Bytes    int64 `json:"bytes"`
	Segments int   `json:"segments"`
	Notes    int   `json:"notes"`
}

func (s *Store) Stats(ctx context.Context) (Stats, error) {
	var st Stats
	err := s.DB.QueryRowContext(ctx, `SELECT (SELECT COUNT(*) FROM courses),(SELECT COUNT(*) FROM lectures),
 (SELECT COUNT(DISTINCT lecture_id) FROM assets),(SELECT COALESCE(SUM(bytes),0) FROM assets),
 (SELECT COUNT(*) FROM segments),(SELECT COUNT(*) FROM notes)`).Scan(&st.Courses, &st.Lectures, &st.Local, &st.Bytes, &st.Segments, &st.Notes)
	return st, err
}
