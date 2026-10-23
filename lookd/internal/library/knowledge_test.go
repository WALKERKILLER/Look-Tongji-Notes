package library

import (
	"strings"
	"testing"

	"lookstudio/lookd/internal/store"
)

func TestKnowledgeDocs(t *testing.T) {
	lib, ctx := newTestLibrary(t)
	st := lib.Store
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(st.UpsertCourse(ctx, store.Course{ID: "C1", Title: "海洋地质学", Teacher: "张三"}))
	must(st.UpsertCourse(ctx, store.Course{ID: "C2", Title: "空课程"}))
	must(st.UpsertLectures(ctx, []store.Lecture{
		{ID: "L1", CourseID: "C1", Title: "第一讲", Date: "2026-09-10"},
		{ID: "L2", CourseID: "C1", Title: "第二讲", Date: "2026-09-17"},
	}))
	for _, id := range []string{"L1", "L2"} {
		_, _, _, err := lib.EnsureLecture(ctx, id)
		must(err)
	}
	must(lib.SaveTranscript(ctx, "L1", []store.Segment{{Idx: 0, StartMs: 0, EndMs: 5000, Text: "今天讲板块构造"}}, "test"))
	note, err := lib.SaveNote(ctx, store.Note{LectureID: "L1", Title: "板块构造",
		Body: "[12:03] 洋中脊 \\(v=\\frac{d}{t}\\) ![PPT 12](look://slide/L1/12) [这里](look://seek?t=5)\n"})
	must(err)
	_, err = lib.SaveNote(ctx, store.Note{Title: "随手记", Body: "不属于课程"})
	must(err)

	docs, err := lib.KnowledgeDocs(ctx)
	must(err)
	var keys []string
	seen := map[string]bool{"": true}
	for _, d := range docs {
		if !seen[d.Parent] {
			t.Fatalf("%s comes before its parent %s", d.Key, d.Parent)
		}
		seen[d.Key] = true
		keys = append(keys, d.Key)
	}
	// L2 has neither notes nor a transcript, C2 nothing at all.
	if got := strings.Join(keys, ","); !strings.HasPrefix(got, "course:C1,lecture:L1,note:"+note.ID+",transcript:L1,note:") || strings.Contains(got, "L2") || strings.Contains(got, "C2") {
		t.Fatal(got)
	}
	body := docs[2].Body
	for _, want := range []string{"[12:03] 洋中脊", `$v=\frac{d}{t}$`, "PPT 12", "这里"} {
		if !strings.Contains(body, want) {
			t.Errorf("note body lacks %q:\n%s", want, body)
		}
	}
	for _, bad := range []string{"lookstudio://", "look://", "](", "!["} {
		if strings.Contains(body, bad) {
			t.Errorf("note body keeps %q:\n%s", bad, body)
		}
	}
	if !docs[0].Container || !docs[1].Container || docs[2].Container || !strings.Contains(docs[3].Body, "今天讲板块构造") {
		t.Fatalf("%+v", docs[:4])
	}
}
