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
	l.mirrorMu.Lock()
	m := l.beginMirror()
	err := l.Store.PutQuizMirrored(ctx, m.token(), q, l.quizMirror(m))
	m.finish(ctx, err)
	l.mirrorMu.Unlock()
	if err != nil {
		return q, err
	}
	return l.Store.Quiz(ctx, q.ID)
}

// AddQuizAttempt grades and records a finished attempt.
func (l *Library) AddQuizAttempt(ctx context.Context, quizID string, startedAt int64, answers []int) (store.QuizAttempt, error) {
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
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
	m := l.beginMirror()
	err = l.Store.PutQuizAttemptMirrored(ctx, m.token(), q, a, l.quizMirror(m))
	m.finish(ctx, err)
	return a, err
}

// DeleteQuiz deletes the set, its attempts and its file copy together: if
// the file cannot be removed nothing is deleted (reindex would bring the set
// back), and if the index then does not commit the file is restored (see
// mirror.go).
func (l *Library) DeleteQuiz(ctx context.Context, id string) error {
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	m := l.beginMirror()
	err := l.Store.DeleteQuizMirrored(ctx, m.token(), id, func() (func(), error) { return m.remove(l.quizPath(id)) })
	m.finish(ctx, err)
	return err
}

// quizMirror writes quizzes/<id>.json with the set and its attempts as part
// of m.
func (l *Library) quizMirror(m *mirrorTx) store.Mirror {
	return func(q store.Quiz, attempts []store.QuizAttempt) (func(), error) {
		if err := os.MkdirAll(filepath.Join(l.Root, "quizzes"), 0o755); err != nil {
			return nil, err
		}
		q.Best, q.Last, q.LectureTitle = nil, nil, ""
		q.Count, q.Attempts = len(q.Questions), len(attempts)
		return m.replace(l.quizPath(q.ID), map[string]any{"schema": "look-studio/quiz@1", "quiz": q, "attempts": attempts})
	}
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
		// Only attempts that belong to this set and grade to their stored
		// score; they replace whatever the index held for the set.
		var attempts []store.QuizAttempt
		for _, a := range f.Attempts {
			if store.CheckAttempt(f.Quiz, a) == nil {
				attempts = append(attempts, a)
			}
		}
		if l.Store.RestoreQuiz(ctx, f.Quiz, attempts) == nil {
			n++
		}
	}
	return n
}
