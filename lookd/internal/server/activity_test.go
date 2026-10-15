package server

import (
	"testing"
	"time"
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
