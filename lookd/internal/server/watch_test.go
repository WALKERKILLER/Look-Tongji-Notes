package server

import (
	"testing"
	"time"

	"lookstudio/lookd/internal/store"
)

func TestNextCheckFollowsReplayAge(t *testing.T) {
	now := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	at := func(d time.Duration) int64 { return now.Add(d).Unix() }
	cases := []struct {
		name     string
		ls       []store.Lecture
		want     time.Duration
		awaiting int
	}{
		{"quiet course", []store.Lecture{{EndAt: at(-30 * 24 * time.Hour)}}, watchSweep, 0},
		{"ends in an hour", []store.Lecture{{EndAt: at(time.Hour)}}, time.Hour + 10*time.Minute, 0},
		{"ended 5 min ago", []store.Lecture{{EndAt: at(-5 * time.Minute)}}, 10 * time.Minute, 1},
		{"ended 1 h ago", []store.Lecture{{EndAt: at(-time.Hour)}}, 10 * time.Minute, 1},
		{"ended 5 h ago", []store.Lecture{{EndAt: at(-5 * time.Hour)}}, 30 * time.Minute, 1},
		{"ended 2 days ago", []store.Lecture{{EndAt: at(-48 * time.Hour)}}, 3 * time.Hour, 1},
		{"replay already there", []store.Lecture{{EndAt: at(-time.Hour), HasPlayback: true}}, watchSweep, 0},
		{"too old to wait for", []store.Lecture{{EndAt: at(-8 * 24 * time.Hour)}}, watchSweep, 0},
		{"youngest wins", []store.Lecture{{EndAt: at(-48 * time.Hour)}, {EndAt: at(-time.Hour)}}, 10 * time.Minute, 2},
	}
	for _, c := range cases {
		next, n := nextCheck(c.ls, now)
		if got := next.Sub(now); got != c.want || n != c.awaiting {
			t.Errorf("%s: next in %v (want %v), awaiting %d (want %d)", c.name, got, c.want, n, c.awaiting)
		}
	}
}

func TestCurrentCourse(t *testing.T) {
	now := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	day := 24 * time.Hour
	for _, c := range []struct {
		c    store.Course
		want bool
	}{
		{store.Course{StartAt: now.Add(-60 * day).Unix(), EndAt: now.Add(60 * day).Unix()}, true},
		{store.Course{StartAt: now.Add(-200 * day).Unix(), EndAt: now.Add(-30 * day).Unix()}, false},
		{store.Course{StartAt: now.Add(60 * day).Unix()}, false},
		{store.Course{}, true},
		{store.Course{Hidden: true}, false},
	} {
		if got := current(c.c, now); got != c.want {
			t.Errorf("%+v: got %v", c.c, got)
		}
	}
}
