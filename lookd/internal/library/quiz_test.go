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
