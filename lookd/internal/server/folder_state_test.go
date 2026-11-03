package server

import (
	"context"
	"encoding/json"
	"lookstudio/lookd/internal/store"
	"path/filepath"
	"testing"
	"time"
)

func folderStateServer(t *testing.T) *Server {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	ctx := context.Background()
	for _, id := range []string{"selected", "other"} {
		if err := st.UpsertCourse(ctx, store.Course{ID: id, Title: id}); err != nil {
			t.Fatal(err)
		}
		if err := st.UpsertLectures(ctx, []store.Lecture{{ID: id + "-lecture", CourseID: id}}); err != nil {
			t.Fatal(err)
		}
	}
	return &Server{St: st}
}

func TestFolderActivityMergeReportsOnlyChanges(t *testing.T) {
	s := folderStateServer(t)
	ctx := context.Background()
	row := store.ActivityRow{Day: time.Now().Format("2006-01-02"), Kind: "watch", CourseID: "selected", LectureID: "selected-lecture", Seconds: 60}
	for i, seconds := range []int64{60, 60, 30, 90} {
		row.Seconds = seconds
		b, _ := json.Marshal(coursePortableState{Activity: []store.ActivityRow{row}})
		changed, err := s.MergeCourseState(ctx, []string{"selected"}, b)
		if err != nil || changed != (i == 0 || i == 3) {
			t.Fatalf("round %d: changed=%v error=%v", i, changed, err)
		}
	}
	rows, err := s.St.ActivityRows(ctx)
	if err != nil || len(rows) != 1 || rows[0].Seconds != 90 {
		t.Fatal(rows, err)
	}
}

func TestFolderActivityRejectsInvalidRowsBeforeUserState(t *testing.T) {
	for _, kind := range []string{"wrong-lecture", "wrong-selected-lecture", "invalid-totals", "invalid-kind"} {
		t.Run(kind, func(t *testing.T) {
			s := folderStateServer(t)
			ctx := context.Background()
			row := store.ActivityRow{Day: time.Now().Format("2006-01-02"), Kind: "watch", CourseID: "selected", LectureID: "selected-lecture", Seconds: 60}
			selected := []string{"selected"}
			if kind == "wrong-selected-lecture" {
				selected = append(selected, "other")
			}
			switch kind {
			case "wrong-lecture", "wrong-selected-lecture":
				row.LectureID = "other-lecture"
			case "invalid-totals":
				row.Seconds = -1
			case "invalid-kind":
				row.Kind = "unknown"
			}
			b, _ := json.Marshal(coursePortableState{User: store.UserState{Playback: map[string]store.PlaybackRecord{"selected-lecture": {Playback: store.Playback{PositionMs: 999, Speed: 1}, UpdatedAt: time.Now().UnixMilli()}}}, Activity: []store.ActivityRow{{Day: row.Day, Kind: "read", CourseID: "selected", Seconds: 30}, row}})
			if _, err := s.MergeCourseState(ctx, selected, b); err == nil {
				t.Fatal("invalid activity accepted")
			}
			rows, _ := s.St.ActivityRows(ctx)
			if len(rows) != 0 {
				t.Fatal("invalid activity written", rows)
			}
			state, _ := s.St.ExportUserState(ctx)
			if len(state.Playback) != 0 {
				t.Fatal("user state written before invalid activity was rejected")
			}
		})
	}
}

func TestFolderBookmarkCannotDeleteOtherCourseByID(t *testing.T) {
	s := folderStateServer(t)
	ctx := context.Background()
	if _, err := s.St.AddBookmark(ctx, store.Bookmark{LectureID: "other-lecture", TMs: 500, Label: "keep"}); err != nil {
		t.Fatal(err)
	}
	original, err := s.St.ExportUserState(ctx)
	if err != nil {
		t.Fatal(err)
	}
	forged := original.Bookmarks[0]
	forged.LectureID = "selected-lecture"
	forged.Deleted = true
	forged.UpdatedAt++
	b, _ := json.Marshal(coursePortableState{User: store.UserState{Bookmarks: []store.Bookmark{forged}}})
	if _, err := s.MergeCourseState(ctx, []string{"selected"}, b); err == nil {
		t.Fatal("cross-course bookmark ID accepted")
	}
	kept, err := s.St.Bookmarks(ctx, "other-lecture")
	if err != nil || len(kept) != 1 {
		t.Fatal("unselected bookmark modified", kept, err)
	}
}
