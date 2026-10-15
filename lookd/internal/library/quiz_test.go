package library

import (
	"context"
	"database/sql"
	"errors"
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

func TestQuizNotKeptWhenMirrorFails(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	qs := []store.QuizQuestion{{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0}}
	// A file where the quizzes folder goes makes the mirror fail.
	os.WriteFile(filepath.Join(l.Root, "quizzes"), []byte("x"), 0o644)
	if _, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: qs}); err == nil {
		t.Fatal("save reported success without its file")
	}
	if list, _ := st.Quizzes(ctx, "", ""); len(list) != 0 {
		t.Fatalf("set kept without its file: %+v", list)
	}
	os.Remove(filepath.Join(l.Root, "quizzes"))

	q, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: qs})
	if err != nil {
		t.Fatal(err)
	}
	// An unreadable mirror (a directory) makes the attempt's rewrite fail.
	p := l.quizPath(q.ID)
	os.Remove(p)
	os.MkdirAll(filepath.Join(p, "x"), 0o755)
	if _, err := l.AddQuizAttempt(ctx, q.ID, 0, []int{0}); err == nil {
		t.Fatal("attempt reported success without its file")
	}
	if a, _ := st.QuizAttempts(ctx, q.ID); len(a) != 0 {
		t.Fatalf("attempt kept without its file: %+v", a)
	}
}

func TestQuizAttemptAfterDeleteKeepsItDeleted(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	q, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: []store.QuizQuestion{
		{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	full, _ := st.Quiz(ctx, q.ID) // read before a concurrent delete commits
	if err := l.DeleteQuiz(ctx, q.ID); err != nil {
		t.Fatal(err)
	}
	m := l.beginMirror()
	a := store.QuizAttempt{ID: NewID(), QuizID: q.ID, StartedAt: 1, FinishedAt: 2, Answers: []int{0}, Correct: 1, Total: 1}
	err = st.PutQuizAttemptMirrored(ctx, m.token(), full, a, l.quizMirror(m))
	m.finish(ctx, err)
	if !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("attempt on a deleted set: %v", err)
	}
	if _, err := os.Stat(l.quizPath(q.ID)); !os.IsNotExist(err) {
		t.Fatal("deleted set's file written back")
	}
	var n int
	st.DB.QueryRow(`SELECT count(*) FROM quiz_attempts`).Scan(&n)
	if n != 0 {
		t.Fatalf("%d orphan attempt(s)", n)
	}
}

func TestQuizReindexReplacesAttempts(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	q, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: []store.QuizQuestion{
		{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	keep, _ := l.AddQuizAttempt(ctx, q.ID, 0, []int{0})
	if _, err := l.AddQuizAttempt(ctx, q.ID, 0, []int{1}); err != nil {
		t.Fatal(err)
	}
	// The file is edited to hold only the first attempt.
	full, _ := st.Quiz(ctx, q.ID)
	full.Best, full.Last, full.LectureTitle = nil, nil, ""
	writeJSON(l.quizPath(q.ID), map[string]any{"quiz": full, "attempts": []store.QuizAttempt{keep}})
	if _, err := l.Reindex(ctx); err != nil {
		t.Fatal(err)
	}
	got, _ := st.Quiz(ctx, q.ID)
	if got.Attempts != 1 || got.Best.Correct != 1 {
		t.Fatalf("after reindex: attempts %d, best %+v", got.Attempts, got.Best)
	}
}

func TestQuizDeleteInterruptedIsRestored(t *testing.T) {
	ctx := context.Background()
	l, st := openLib(t)
	q, err := l.SaveQuiz(ctx, store.Quiz{Title: "自测", Questions: []store.QuizQuestion{
		{Stem: "1+1=?", Options: []store.QuizOption{{Text: "2"}, {Text: "3"}}, Answer: 0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(l.quizPath(q.ID))
	m := l.beginMirror()
	if _, err := m.remove(l.quizPath(q.ID)); err != nil { // crash before the delete commits
		t.Fatal(err)
	}
	if _, err := Open(l.Root, st); err != nil {
		t.Fatal(err)
	}
	if after, _ := os.ReadFile(l.quizPath(q.ID)); string(after) != string(before) {
		t.Fatal("file of a set still in the index not restored")
	}
}
