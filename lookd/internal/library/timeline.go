package library

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"lookstudio/lookd/internal/store"
)

// Timeline outlines use the Look-Tongji-Notes skill format, one chapter per
// line: "起始时间-结束时间：课程阶段内容", e.g. "00:00-05:30：课程定位与考核说明".

var timelineLine = regexp.MustCompile(`^(\d{1,3}:\d{2}(?::\d{2})?)\s*[-–—~～]\s*(\d{1,3}:\d{2}(?::\d{2})?)\s*[:：]?\s*(.+)$`)

func parseClock(s string) (int64, bool) {
	parts := strings.Split(s, ":")
	var sec int64
	for _, p := range parts {
		n, err := strconv.ParseInt(p, 10, 64)
		if err != nil {
			return 0, false
		}
		sec = sec*60 + n
	}
	return sec * 1000, len(parts) == 2 || len(parts) == 3
}

// skillClock formats like the skill's timeline tools: MM:SS, minutes past 59
// kept as is (e.g. 95:30).
func skillClock(ms int64) string {
	s := ms / 1000
	return fmt.Sprintf("%02d:%02d", s/60, s%60)
}

// ParseTimeline reads timeline text, tolerating list markers and numbering.
func ParseTimeline(text string) []store.Chapter {
	var out []store.Chapter
	strip := regexp.MustCompile(`^\s*(?:[-*•]\s*|\d+\s*[.)）]\s*|[（(]\d+[）)]\s*)`)
	for _, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(strip.ReplaceAllString(strings.TrimSpace(raw), ""))
		m := timelineLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		a, ok1 := parseClock(m[1])
		b, ok2 := parseClock(m[2])
		if ok1 && ok2 {
			out = append(out, store.Chapter{StartMs: a, EndMs: b, Title: strings.Join(strings.Fields(m[3]), " ")})
		}
	}
	return out
}

// NormalizeTimeline orders chapters, starts the first at 0, closes gaps and
// overlaps so chapters tile the lecture, and ends the last at durMs when known.
func NormalizeTimeline(chs []store.Chapter, durMs int64) ([]store.Chapter, error) {
	var in []store.Chapter
	for _, c := range chs {
		c.Title = strings.TrimSpace(c.Title)
		if c.Title == "" {
			continue
		}
		if utf8.RuneCountInString(c.Title) > 60 {
			c.Title = string([]rune(c.Title)[:60])
		}
		if c.StartMs < 0 {
			c.StartMs = 0
		}
		if durMs > 0 && c.StartMs >= durMs {
			continue
		}
		in = append(in, c)
	}
	if len(in) == 0 {
		return nil, errors.New("大纲为空")
	}
	sort.SliceStable(in, func(i, j int) bool { return in[i].StartMs < in[j].StartMs })
	in[0].StartMs = 0
	var out []store.Chapter
	for i, c := range in {
		end := c.EndMs
		if i+1 < len(in) {
			end = in[i+1].StartMs
		} else if durMs > 0 {
			end = durMs
		}
		if end-c.StartMs < 10000 && len(out) > 0 && i+1 < len(in) {
			continue // too short to be a chapter; the previous one absorbs it
		}
		if end <= c.StartMs {
			end = c.StartMs + 60000
		}
		if len(out) > 0 {
			out[len(out)-1].EndMs = c.StartMs
		}
		c.EndMs = end
		c.Idx = len(out)
		out = append(out, c)
	}
	return out, nil
}

func FormatTimeline(chs []store.Chapter) string {
	var b strings.Builder
	for _, c := range chs {
		fmt.Fprintf(&b, "%s-%s：%s\n", skillClock(c.StartMs), skillClock(c.EndMs), c.Title)
	}
	return b.String()
}

// SaveTimeline normalizes and stores a lecture's outline as timeline.txt
// and in the index.
func (l *Library) SaveTimeline(ctx context.Context, lectureID string, chs []store.Chapter) ([]store.Chapter, error) {
	_, lec, dir, err := l.EnsureLecture(ctx, lectureID)
	if err != nil {
		return nil, err
	}
	dur := lec.DurationS * 1000
	if segs, _ := l.Store.Segments(ctx, lectureID, 0, 0); len(segs) > 0 && dur == 0 {
		dur = segs[len(segs)-1].EndMs
	}
	chs, err = NormalizeTimeline(chs, dur)
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(l.Abs(dir), "timeline.txt"), []byte(FormatTimeline(chs)), 0o644); err != nil {
		return nil, err
	}
	if err := l.Store.ReplaceTimeline(ctx, lectureID, chs); err != nil {
		return nil, err
	}
	return chs, l.WriteLectureJSON(ctx, lectureID)
}

func (l *Library) DeleteTimeline(ctx context.Context, lectureID string) error {
	lec, err := l.Store.Lecture(ctx, lectureID)
	if err != nil {
		return err
	}
	if lec.Dir != "" {
		os.Remove(filepath.Join(l.Abs(lec.Dir), "timeline.txt"))
	}
	if err := l.Store.ReplaceTimeline(ctx, lectureID, nil); err != nil {
		return err
	}
	return l.WriteLectureJSON(ctx, lectureID)
}
