package store

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"testing"
)

func TestQuizDeleteCommitFailureKeepsEverything(t *testing.T) {
	ctx := context.Background()
	s, err := Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	q := Quiz{ID: "q1", Title: "自测", Difficulty: "easy", Source: "user", Questions: []QuizQuestion{{Stem: "1+1=?", Options: []QuizOption{{Text: "2"}, {Text: "3"}}}}}
	if err := s.PutQuiz(ctx, q); err != nil {
		t.Fatal(err)
	}
	if err := s.PutQuizAttempt(ctx, QuizAttempt{ID: "a1", QuizID: "q1", StartedAt: 1, FinishedAt: 2, Answers: []int{0}, Correct: 1, Total: 1}); err != nil {
		t.Fatal(err)
	}
	orig := commitTx
	commitTx = func(tx *sql.Tx) error { tx.Rollback(); return errors.New("disk I/O error") }
	restored := false
	err = s.DeleteQuizMirrored(ctx, "", "q1", func() (func(), error) { return func() { restored = true }, nil })
	commitTx = orig
	if err == nil || !restored {
		t.Fatalf("err = %v, file restored = %v", err, restored)
	}
	if _, err := s.Quiz(ctx, "q1"); err != nil {
		t.Fatalf("set lost: %v", err)
	}
	if a, _ := s.QuizAttempts(ctx, "q1"); len(a) != 1 {
		t.Fatalf("attempts lost: %+v", a)
	}
	// A normal delete removes the set and its attempts together.
	if err := s.DeleteQuiz(ctx, "q1"); err != nil {
		t.Fatal(err)
	}
	if a, _ := s.QuizAttempts(ctx, "q1"); len(a) != 0 {
		t.Fatalf("attempts left behind: %+v", a)
	}
	if err := s.DeleteQuiz(ctx, "q1"); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("second delete: %v", err)
	}
}
