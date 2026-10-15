package store

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func openTemp(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func at(day string, hour int) int64 {
	d, _ := time.ParseInLocation("2006-01-02", day, time.Local)
	return d.Add(time.Duration(hour) * time.Hour).Unix()
}

func TestActivityDaysBucketsAndDerivedCounts(t *testing.T) {
	ctx := context.Background()
	s := openTemp(t)
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(s.UpsertCourse(ctx, Course{ID: "c1", Title: "高等数学"}))
	must(s.UpsertLectures(ctx, []Lecture{{ID: "l1", CourseID: "c1", Title: "第一讲"}}))
	must(s.AddActivity(ctx, "2026-10-01", "watch", "c1", "l1", 600, 0))
	must(s.AddActivity(ctx, "2026-10-01", "watch", "c1", "l1", 300, 0)) // same bucket accumulates
	must(s.AddActivity(ctx, "2026-10-01", "read", "c1", "", 125, 0))
	must(s.AddActivity(ctx, "2026-10-02", "ask", "c1", "l1", 0, 2))
	must(s.AddActivity(ctx, "2026-10-05", "watch", "other", "", 900, 0)) // other course

	// A user note created on 10-01 and edited on 10-03; an agent note is ignored.
	must(s.PutNote(ctx, Note{ID: "n1", CourseID: "c1", LectureID: "l1", Title: "极限"}))
	must(s.PutNote(ctx, Note{ID: "n2", CourseID: "c1", Title: "助手笔记", Source: "agent"}))
	_, err := s.DB.Exec(`UPDATE notes SET created_at=?, updated_at=? WHERE id='n1'`, at("2026-10-01", 9), at("2026-10-03", 20))
	must(err)
	_, err = s.DB.Exec(`UPDATE notes SET created_at=?, updated_at=? WHERE id='n2'`, at("2026-10-02", 9), at("2026-10-02", 9))
	must(err)
	must(s.PutAsset(ctx, Asset{LectureID: "l1", Kind: "transcript", Path: "l1/transcript.md"}))
	_, err = s.DB.Exec(`UPDATE assets SET created_at=? WHERE kind='transcript'`, at("2026-10-02", 23))
	must(err)

	days, err := s.ActivityDays(ctx, "2026-09-30", "2026-10-03", "c1")
	must(err)
	if len(days) != 4 || days[0].Date != "2026-09-30" || days[0].Minutes != 0 {
		t.Fatalf("zero-filled range: %+v", days)
	}
	d1 := days[1]
	if d1.Minutes != 17 || d1.Seconds["watch"] != 900 || d1.Seconds["read"] != 125 || d1.NotesNew != 1 {
		t.Fatalf("10-01: %+v", d1)
	}
	if days[2].Asks != 2 || days[2].Transcripts != 1 || days[2].NotesNew != 0 {
		t.Fatalf("10-02: %+v", days[2])
	}
	if days[3].NotesEdited != 1 {
		t.Fatalf("10-03: %+v", days[3])
	}

	courses, err := s.ActivityByCourse(ctx, "2026-10-01", "2026-10-31")
	must(err)
	if len(courses) != 2 || courses[0].CourseID != "c1" || courses[0].Title != "高等数学" || courses[0].Minutes != 17 {
		t.Fatalf("by course: %+v", courses)
	}

	detail, err := s.ActivityOn(ctx, "2026-10-01")
	must(err)
	if len(detail.Lectures) != 1 || detail.Lectures[0].Title != "第一讲" || detail.Lectures[0].Seconds != 900 || len(detail.Notes) != 1 || !detail.Notes[0].Created {
		t.Fatalf("detail: %+v", detail)
	}
}

func TestActivityStreakAcrossMonthEnd(t *testing.T) {
	ctx := context.Background()
	s := openTemp(t)
	for _, d := range []string{"2026-09-25", "2026-09-26", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"} {
		if err := s.AddActivity(ctx, d, "watch", "", "", 120, 0); err != nil {
			t.Fatal(err)
		}
	}
	// Under a minute of study does not make a day active.
	if err := s.AddActivity(ctx, "2026-09-27", "read", "", "", 30, 0); err != nil {
		t.Fatal(err)
	}
	// A finished transcript alone does: 09-28 joins the run.
	if err := s.UpsertCourse(ctx, Course{ID: "c1", Title: "高等数学"}); err != nil {
		t.Fatal(err)
	}
	if err := s.UpsertLectures(ctx, []Lecture{{ID: "l1", CourseID: "c1", Title: "第一讲"}}); err != nil {
		t.Fatal(err)
	}
	if err := s.PutAsset(ctx, Asset{LectureID: "l1", Kind: "transcript", Path: "l1/transcript.md"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DB.Exec(`UPDATE assets SET created_at=? WHERE kind='transcript'`, at("2026-09-28", 22)); err != nil {
		t.Fatal(err)
	}
	today, _ := time.ParseInLocation("2006-01-02", "2026-10-03", time.Local)
	st, err := s.ActivityStreak(ctx, today) // today inactive: streak still counts through yesterday
	if err != nil {
		t.Fatal(err)
	}
	if st.Current != 5 || st.Longest != 5 {
		t.Fatalf("streak: %+v", st)
	}
	later := today.AddDate(0, 0, 1)
	st, _ = s.ActivityStreak(ctx, later)
	if st.Current != 0 || st.Longest != 5 {
		t.Fatalf("broken streak: %+v", st)
	}
	empty := openTemp(t)
	if st, err := empty.ActivityStreak(ctx, today); err != nil || st != (Streak{}) {
		t.Fatalf("empty: %+v %v", st, err)
	}
}

func TestActivityTableAddedToExistingDatabase(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "old.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	// Simulate a library.db created before the activity table existed.
	if err := s.PutNote(ctx, Note{ID: "keep", Title: "旧笔记"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DB.Exec(`DROP TABLE activity`); err != nil {
		t.Fatal(err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if err := s.AddActivity(ctx, "2026-10-01", "watch", "", "", 60, 0); err != nil {
		t.Fatalf("activity after reopen: %v", err)
	}
	if n, err := s.Note(ctx, "keep"); err != nil || n.Title != "旧笔记" {
		t.Fatalf("existing data lost: %v %+v", err, n)
	}
}
