package library

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"lookstudio/lookd/internal/store"
)

func TestQuizMirrorSurvivesReindex(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	st, err := store.Open(filepath.Join(root, "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	l, err := Open(root, st)
	if err != nil {
		t.Fatal(err)
	}
	in := store.Quiz{Title: "自测", Questions: []store.QuizQuestion{
		{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0},
	}}
	if _, err := l.SaveQuiz(ctx, store.Quiz{Title: "x", LectureID: "missing", Questions: in.Questions}); err == nil {
		t.Fatal("unknown lecture accepted")
	}
	q, err := l.SaveQuiz(ctx, in)
	if err != nil {
		t.Fatal(err)
	}
	a, err := l.AddQuizAttempt(ctx, q.ID, 0, []int{0})
	if err != nil || a.Correct != 1 {
		t.Fatalf("attempt = %+v, %v", a, err)
	}

	st.DB.Exec(`DELETE FROM quizzes`)
	st.DB.Exec(`DELETE FROM quiz_attempts`)
	if _, err := l.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	got, err := st.Quiz(ctx, q.ID)
	if err != nil || got.Title != "自测" || got.Attempts != 1 || got.Best.Correct != 1 {
		t.Fatalf("after reindex: %+v, %v", got, err)
	}

	if err := l.DeleteQuiz(ctx, q.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(l.quizPath(q.ID)); !os.IsNotExist(err) {
		t.Fatal("mirror kept after delete")
	}
}

func TestQuizDeleteKeepsSetWhenMirrorStays(t *testing.T) {
	ctx := context.Background()
	l, _ := openLib(t)
	q, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: []store.QuizQuestion{
		{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	// A non-empty directory in place of the mirror cannot be removed.
	p := l.quizPath(q.ID)
	os.Remove(p)
	os.MkdirAll(filepath.Join(p, "x"), 0o755)
	if err := l.DeleteQuiz(ctx, q.ID); err == nil {
		t.Fatal("delete reported success with the mirror left on disk")
	}
	if _, err := l.Store.Quiz(ctx, q.ID); err != nil {
		t.Fatalf("set dropped from the index: %v", err)
	}
}

func TestQuizReindexSkipsBadAttempts(t *testing.T) {
	ctx := context.Background()
	l, _ := openLib(t)
	q, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: []store.QuizQuestion{
		{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	good := store.QuizAttempt{ID: "a1", QuizID: q.ID, StartedAt: 1, FinishedAt: 2, Answers: []int{0}, Correct: 1, Total: 1}
	bad := []store.QuizAttempt{
		{ID: "b1", QuizID: "other", StartedAt: 1, FinishedAt: 2, Answers: []int{0}, Correct: 1, Total: 1},
		{ID: "b2", QuizID: q.ID, StartedAt: 1, FinishedAt: 2, Answers: []int{0, 1}, Correct: 1, Total: 2},
		{ID: "b3", QuizID: q.ID, StartedAt: 1, FinishedAt: 2, Answers: []int{5}, Correct: 0, Total: 1},
		{ID: "b4", QuizID: q.ID, StartedAt: 1, FinishedAt: 2, Answers: []int{1}, Correct: 1, Total: 1},
		{ID: "", QuizID: q.ID, StartedAt: 1, FinishedAt: 2, Answers: []int{0}, Correct: 1, Total: 1},
	}
	stored, _ := l.Store.Quiz(ctx, q.ID)
	stored.Best, stored.Last, stored.LectureTitle = nil, nil, ""
	writeJSON(l.quizPath(q.ID), map[string]any{"schema": "look-studio/quiz@1", "quiz": stored, "attempts": append([]store.QuizAttempt{good}, bad...)})
	l.Store.DB.Exec(`DELETE FROM quizzes`)
	l.Store.DB.Exec(`DELETE FROM quiz_attempts`)
	if _, err := l.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	got, err := l.Store.QuizAttempts(ctx, q.ID)
	if err != nil || len(got) != 1 || got[0].ID != "a1" {
		t.Fatalf("attempts after reindex = %+v, %v", got, err)
	}
}
