package library

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"lookstudio/lookd/internal/store"
)

// Quiz sets live in the index and are mirrored, with their attempts, to
// quizzes/<id>.json so that rebuilding the index from files keeps them.

func (l *Library) quizPath(id string) string { return filepath.Join(l.Root, "quizzes", id+".json") }

// SaveQuiz validates and stores a new set; the course comes from the lecture.
func (l *Library) SaveQuiz(ctx context.Context, q store.Quiz) (store.Quiz, error) {
	if err := store.ValidateQuiz(&q); err != nil {
		return q, err
	}
	if q.LectureID != "" {
		lec, err := l.Store.Lecture(ctx, q.LectureID)
		if errors.Is(err, sql.ErrNoRows) {
			return q, store.QuizError("lecture_id 不存在")
		} else if err != nil {
			return q, err
		}
		q.CourseID = lec.CourseID
	}
	q.ID, q.CreatedAt = NewID(), time.Now().Unix()
	if err := l.Store.PutQuiz(ctx, q); err != nil {
		return q, err
	}
	if err := l.writeQuiz(ctx, q.ID); err != nil {
		return q, err
	}
	return l.Store.Quiz(ctx, q.ID)
}

// AddQuizAttempt grades and records a finished attempt.
func (l *Library) AddQuizAttempt(ctx context.Context, quizID string, startedAt int64, answers []int) (store.QuizAttempt, error) {
	q, err := l.Store.Quiz(ctx, quizID)
	if err != nil {
		return store.QuizAttempt{}, err
	}
	correct, err := store.Grade(q, answers)
	if err != nil {
		return store.QuizAttempt{}, err
	}
	now := time.Now().Unix()
	if startedAt <= 0 || startedAt > now {
		startedAt = now
	}
	a := store.QuizAttempt{ID: NewID(), QuizID: quizID, StartedAt: startedAt, FinishedAt: now, Answers: answers, Correct: correct, Total: len(answers)}
	if err := l.Store.PutQuizAttempt(ctx, a); err != nil {
		return a, err
	}
	return a, l.writeQuiz(ctx, quizID)
}

// DeleteQuiz removes the file copy first, so a set whose file cannot be
// removed stays deleted from neither place (reindex would bring it back).
func (l *Library) DeleteQuiz(ctx context.Context, id string) error {
	if _, err := l.Store.Quiz(ctx, id); err != nil {
		return err
	}
	if err := os.Remove(l.quizPath(id)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := l.Store.DeleteQuiz(ctx, id); err != nil {
		l.writeQuiz(ctx, id) // put the file back while the index still has the set
		return err
	}
	return nil
}

func (l *Library) writeQuiz(ctx context.Context, id string) error {
	q, err := l.Store.Quiz(ctx, id)
	if err != nil {
		return err
	}
	attempts, err := l.Store.QuizAttempts(ctx, id)
	if err != nil {
		return err
	}
	os.MkdirAll(filepath.Join(l.Root, "quizzes"), 0o755)
	q.Best, q.Last, q.LectureTitle = nil, nil, ""
	return writeJSON(l.quizPath(id), map[string]any{"schema": "look-studio/quiz@1", "quiz": q, "attempts": attempts})
}

func (l *Library) reindexQuizzes(ctx context.Context) int {
	files, _ := filepath.Glob(filepath.Join(l.Root, "quizzes", "*.json"))
	n := 0
	for _, p := range files {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		var f struct {
			Quiz     store.Quiz          `json:"quiz"`
			Attempts []store.QuizAttempt `json:"attempts"`
		}
		if json.Unmarshal(b, &f) != nil || f.Quiz.ID != strings.TrimSuffix(filepath.Base(p), ".json") || store.ValidateQuiz(&f.Quiz) != nil {
			continue
		}
		if l.Store.PutQuiz(ctx, f.Quiz) != nil {
			continue
		}
		// Only attempts that belong to this set and grade to their stored score.
		for _, a := range f.Attempts {
			if store.CheckAttempt(f.Quiz, a) == nil {
				l.Store.PutQuizAttempt(ctx, a)
			}
		}
		n++
	}
	return n
}
