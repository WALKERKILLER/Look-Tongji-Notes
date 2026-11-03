package library

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"lookstudio/lookd/internal/store"
)

func reviewFixture(t *testing.T) (*Library, []store.Segment) {
	t.Helper()
	root := t.TempDir()
	st, e := store.Open(filepath.Join(root, "library.db"))
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { st.Close() })
	ctx := context.Background()
	if e = st.UpsertCourse(ctx, store.Course{ID: "os", Title: "操作系统"}); e != nil {
		t.Fatal(e)
	}
	if e = st.UpsertLectures(ctx, []store.Lecture{{ID: "one", CourseID: "os", Title: "第一节"}}); e != nil {
		t.Fatal(e)
	}
	lib, e := Open(root, st)
	if e != nil {
		t.Fatal(e)
	}
	_, _, _, e = lib.EnsureLecture(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	segs := []store.Segment{{Idx: 0, StartMs: 1000, EndMs: 4000, Text: "页表缓冲保存最近的地址翻译。"}, {Idx: 1, StartMs: 4000, EndMs: 7000, Text: "TLB 用于缓存地址转换。"}}
	if e = lib.SaveTranscript(ctx, "one", segs, "local"); e != nil {
		t.Fatal(e)
	}
	return lib, segs
}
func TestTranscriptReviewPreservesOriginalAndSurvivesReload(t *testing.T) {
	lib, segs := reviewFixture(t)
	ctx := context.Background()
	lec, _ := lib.Store.Lecture(ctx, "one")
	originals := map[string][]byte{}
	for _, f := range []string{"transcript.srt", "transcript.md"} {
		originals[f], _ = os.ReadFile(lib.Abs(lec.Dir + "/" + f))
	}
	in := TranscriptReview{RunID: "a", Fingerprint: TranscriptFingerprint(segs), State: "running", Total: 1, Model: "p/m", Suggestions: []TranscriptSuggestion{{Segment: 0, Original: "页表缓冲", Guess: "快表 TLB", Reason: "疑似术语误识别", Evidence: "邻近原文：TLB 用于缓存地址转换。"}}}
	got, e := lib.SaveTranscriptReview(ctx, "one", "", in)
	if e != nil {
		t.Fatal(e)
	}
	if len(got.Suggestions) != 1 || got.Suggestions[0].ID == "" {
		t.Fatal(got)
	}
	got, e = lib.DismissTranscriptSuggestion(ctx, "one", got.Suggestions[0].ID)
	if e != nil {
		t.Fatal(e)
	}
	// A checkpoint captured before the user's dismissal must preserve it.
	in.RunID = "a"
	in.Completed = 1
	in.State = "completed"
	got, e = lib.SaveTranscriptReview(ctx, "one", "", in)
	if e != nil || !got.Suggestions[0].Dismissed {
		t.Fatal(got, e)
	}
	reloaded, e := Open(lib.Root, lib.Store)
	if e != nil {
		t.Fatal(e)
	}
	got, e = reloaded.TranscriptReview(ctx, "one")
	if e != nil || got.State != "completed" || got.Stale {
		t.Fatal(got, e)
	}
	actual, _ := lib.Store.Segments(ctx, "one", 0, 0)
	if !reflect.DeepEqual(actual, segs) {
		t.Fatal("raw segments changed")
	}
	hits, e := lib.Store.Search(ctx, "页表缓冲", "os", 10)
	if e != nil || len(hits) == 0 {
		t.Fatal("raw search index changed", e)
	}
	for f, before := range originals {
		after, _ := os.ReadFile(lib.Abs(lec.Dir + "/" + f))
		if string(after) != string(before) {
			t.Fatalf("%s changed", f)
		}
	}
	segs[0].Text = "新转写内容"
	if e = lib.SaveTranscript(ctx, "one", segs, "local"); e != nil {
		t.Fatal(e)
	}
	got, e = lib.TranscriptReview(ctx, "one")
	if e != nil || !got.Stale {
		t.Fatal("stale review not identified", got, e)
	}
	if _, e = lib.SaveTranscriptReview(ctx, "one", "", in); !errors.Is(e, ErrReviewConflict) {
		t.Fatal("stale writer accepted", e)
	}
}
func TestTranscriptReviewRejectsUnanchoredAndOverlappingGuesses(t *testing.T) {
	_, segs := reviewFixture(t)
	good := TranscriptSuggestion{Segment: 0, Original: "页表缓冲", Guess: "快表", Reason: "同音疑点", Evidence: "TLB"}
	cases := []struct {
		name string
		rows []TranscriptSuggestion
	}{
		{"unknown segment", []TranscriptSuggestion{{Segment: 44, Original: "页表缓冲", Guess: "快表", Reason: "x", Evidence: "x"}}},
		{"wrong original", []TranscriptSuggestion{{Segment: 0, Original: "原文不存在", Guess: "快表", Reason: "x", Evidence: "x"}}},
		{"overlap", []TranscriptSuggestion{good, {Segment: 0, Original: "页表", Guess: "快表", Reason: "x", Evidence: "x"}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if _, e := ValidateSuggestions(segs, c.rows); e == nil {
				t.Fatal("invalid suggestion accepted")
			}
		})
	}
	repeated := []store.Segment{{Text: "页表和页表"}}
	if _, e := ValidateSuggestions(repeated, []TranscriptSuggestion{{Original: "页表", Guess: "快表", Reason: "x", Evidence: "x"}}); e == nil {
		t.Fatal("ambiguous occurrence accepted")
	}
}
