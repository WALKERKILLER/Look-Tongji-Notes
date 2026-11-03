package store

import (
	"context"
	"database/sql"
	"encoding/json"
)

// Moving a library between devices: course and lecture rows adopted from
// their course.json and lecture.json, and the personal state that lives
// only in the index (playback positions, bookmarks).
// Contract: docs/specs/0014-data-sync-and-backup.md

// AdoptCourse adds a course found in the library's files. A course already
// known keeps its fields; only an unassigned folder is filled in.
func (s *Store) AdoptCourse(ctx context.Context, c Course) error {
	if len(c.Teachers) == 0 {
		c.Teachers = json.RawMessage("[]")
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO courses(id,title,teacher,teachers_json,college,term,alias,dir) VALUES(?,?,?,?,?,?,?,?)
 ON CONFLICT(id) DO UPDATE SET dir=CASE WHEN courses.dir='' THEN excluded.dir ELSE courses.dir END`,
		c.ID, c.Title, c.Teacher, string(c.Teachers), c.College, c.Term, c.Alias, c.Dir)
	return err
}

// AdoptLecture adds a lecture found in the library's files, like AdoptCourse.
func (s *Store) AdoptLecture(ctx context.Context, l Lecture) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO lectures(id,course_id,title,date,begin_at,end_at,lecturer,room,has_playback,duration_s,dir)
 VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET dir=CASE WHEN lectures.dir='' THEN excluded.dir ELSE lectures.dir END`,
		l.ID, l.CourseID, l.Title, l.Date, l.BeginAt, l.EndAt, l.Lecturer, l.Room, l.HasPlayback, l.DurationS, l.Dir)
	return err
}

// PlaybackRecord is a lecture's playback position with when it was saved.
type PlaybackRecord struct {
	Playback
	UpdatedAt int64 `json:"updated_at"`
}

// UserState is the personal state kept only in the index.
type UserState struct {
	Playback  map[string]PlaybackRecord `json:"playback"`
	Bookmarks []Bookmark                `json:"bookmarks"`
}

func (s *Store) ExportUserState(ctx context.Context) (UserState, error) {
	st := UserState{Playback: map[string]PlaybackRecord{}, Bookmarks: []Bookmark{}}
	rows, err := s.DB.QueryContext(ctx, `SELECT lecture_id,position_ms,duration_ms,speed,updated_at FROM playback ORDER BY lecture_id`)
	if err != nil {
		return st, err
	}
	for rows.Next() {
		var id string
		var p PlaybackRecord
		if err := rows.Scan(&id, &p.PositionMs, &p.DurationMs, &p.Speed, &p.UpdatedAt); err != nil {
			rows.Close()
			return st, err
		}
		if p.UpdatedAt < 100000000000 {
			p.UpdatedAt *= 1000
		}
		st.Playback[id] = p
	}
	rows.Close()
	rows, err = s.DB.QueryContext(ctx, `SELECT lecture_id,t_ms,label,created_at,sync_id,updated_at,deleted FROM bookmarks ORDER BY lecture_id,t_ms,id`)
	if err != nil {
		return st, err
	}
	defer rows.Close()
	for rows.Next() {
		var b Bookmark
		if err := rows.Scan(&b.LectureID, &b.TMs, &b.Label, &b.CreatedAt, &b.SyncID, &b.UpdatedAt, &b.Deleted); err != nil {
			return st, err
		}
		if b.SyncID == "" {
			b.SyncID = bookmarkID(b)
		}
		if b.UpdatedAt == 0 {
			b.UpdatedAt = b.CreatedAt * 1000
		}
		st.Bookmarks = append(st.Bookmarks, b)
	}
	return st, rows.Err()
}

// MergeUserState takes the newer playback position of each lecture and the
// bookmarks this index lacks. It reports whether anything changed.
func (s *Store) MergeUserState(ctx context.Context, in UserState) (bool, error) {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	changed := false
	for id, p := range in.Playback {
		if p.UpdatedAt < 100000000000 {
			p.UpdatedAt *= 1000
		}
		r, err := tx.ExecContext(ctx, `INSERT INTO playback(lecture_id,position_ms,duration_ms,speed,updated_at) VALUES(?,?,?,?,?)
 ON CONFLICT(lecture_id) DO UPDATE SET position_ms=excluded.position_ms,duration_ms=excluded.duration_ms,speed=excluded.speed,
 updated_at=excluded.updated_at WHERE excluded.updated_at>CASE WHEN playback.updated_at<100000000000 THEN playback.updated_at*1000 ELSE playback.updated_at END`, id, p.PositionMs, p.DurationMs, p.Speed, p.UpdatedAt)
		if err != nil {
			return false, err
		}
		if n, _ := r.RowsAffected(); n > 0 {
			changed = true
		}
	}
	for _, b := range in.Bookmarks {
		if b.SyncID == "" {
			b.SyncID = bookmarkID(b)
		}
		if b.UpdatedAt == 0 {
			b.UpdatedAt = b.CreatedAt * 1000
		}
		var id, updated int64
		var deleted bool
		err := tx.QueryRowContext(ctx, `SELECT id,updated_at,deleted FROM bookmarks WHERE sync_id=? OR (sync_id='' AND lecture_id=? AND t_ms=? AND label=? AND created_at=?) LIMIT 1`, b.SyncID, b.LectureID, b.TMs, b.Label, b.CreatedAt).Scan(&id, &updated, &deleted)
		if err == nil {
			if b.UpdatedAt > updated || b.Deleted && !deleted && b.UpdatedAt == updated {
				if _, err = tx.ExecContext(ctx, `UPDATE bookmarks SET sync_id=?,updated_at=?,deleted=? WHERE id=?`, b.SyncID, b.UpdatedAt, b.Deleted, id); err != nil {
					return false, err
				}
				changed = true
			}
			continue
		}
		if err != sql.ErrNoRows {
			return false, err
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO bookmarks(lecture_id,t_ms,label,created_at,sync_id,updated_at,deleted) VALUES(?,?,?,?,?,?,?)`, b.LectureID, b.TMs, b.Label, b.CreatedAt, b.SyncID, b.UpdatedAt, b.Deleted); err != nil {
			return false, err
		}
		changed = true
	}
	return changed, tx.Commit()
}

// Compact folds the write-ahead log back and rebuilds the index file
// without free pages.
func (s *Store) Compact(ctx context.Context) error {
	if _, err := s.DB.ExecContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		return err
	}
	if _, err := s.DB.ExecContext(ctx, `VACUUM`); err != nil {
		return err
	}
	_, err := s.DB.ExecContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`)
	return err
}
