package server

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"lookstudio/lookd/internal/store"
)

func TestCheckActivity(t *testing.T) {
	now := time.Date(2026, 10, 14, 0, 30, 0, 0, time.Local)
	cases := []struct {
		name string
		in   activityIn
		day  string
		bad  bool
	}{
		{"watch now", activityIn{Kind: "watch", Seconds: 60}, "2026-10-14", false},
		{"before midnight keeps its own day", activityIn{Kind: "read", Seconds: 60, At: now.Add(-time.Hour).Unix()}, "2026-10-13", false},
		{"ask count", activityIn{Kind: "ask", Count: 1}, "2026-10-14", false},
		{"too many seconds", activityIn{Kind: "watch", Seconds: 301}, "", true},
		{"negative", activityIn{Kind: "watch", Seconds: -1}, "", true},
		{"empty report", activityIn{Kind: "watch"}, "", true},
		{"ask with seconds", activityIn{Kind: "ask", Seconds: 10}, "", true},
		{"ask with both", activityIn{Kind: "ask", Seconds: 10, Count: 1}, "", true},
		{"watch with a count", activityIn{Kind: "watch", Seconds: 10, Count: 1}, "", true},
		{"read with only a count", activityIn{Kind: "read", Count: 1}, "", true},
		{"unknown kind", activityIn{Kind: "sleep", Seconds: 10}, "", true},
		{"older than a day", activityIn{Kind: "watch", Seconds: 10, At: now.Add(-25 * time.Hour).Unix()}, "", true},
		{"future", activityIn{Kind: "watch", Seconds: 10, At: now.Add(time.Hour).Unix()}, "", true},
		{"report id", activityIn{ID: "a1b2c3d4e5f6", Kind: "watch", Seconds: 10}, "2026-10-14", false},
		{"bad report id", activityIn{ID: "x/y", Kind: "watch", Seconds: 10}, "", true},
	}
	for _, c := range cases {
		day, err := checkActivity(c.in, now)
		if (err != nil) != c.bad || day != c.day {
			t.Errorf("%s: day=%q err=%v", c.name, day, err)
		}
	}
}

func TestResolveActivityIDs(t *testing.T) {
	ctx := context.Background()
	st, err := store.Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	if err := st.UpsertCourse(ctx, store.Course{ID: "C1", Title: "数据结构"}); err != nil {
		t.Fatal(err)
	}
	if err := st.UpsertLectures(ctx, []store.Lecture{{ID: "L1", CourseID: "C1", Title: "栈"}}); err != nil {
		t.Fatal(err)
	}
	in := activityIn{LectureID: "L1", CourseID: "C9"}
	if err := resolveActivityIDs(ctx, st, &in); err != nil || in.CourseID != "C1" {
		t.Fatalf("lecture: %+v %v", in, err)
	}
	for _, bad := range []activityIn{{LectureID: "made-up"}, {CourseID: "made-up"}} {
		var api apiError
		if err := resolveActivityIDs(ctx, st, &bad); !errors.As(err, &api) || api.Code != 400 {
			t.Errorf("%+v: %v", bad, err)
		}
	}
	if err := resolveActivityIDs(ctx, st, &activityIn{CourseID: "C1"}); err != nil {
		t.Fatal(err)
	}
}
