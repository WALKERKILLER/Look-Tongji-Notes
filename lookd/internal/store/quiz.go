package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

// Practice quizzes (docs/specs/0002-tutor-quiz-cards.md).

type QuizOption struct {
	Text      string `json:"text"`
	Rationale string `json:"rationale"`
}

type QuizQuestion struct {
	ID      string       `json:"id"`
	Stem    string       `json:"stem"`
	Options []QuizOption `json:"options"`
	Answer  int          `json:"answer"`
	Hint    string       `json:"hint,omitempty"`
	Topic   string       `json:"topic,omitempty"`
	Ref     string       `json:"ref,omitempty"`
}

// QuizScore is one finished attempt's result; Answers is set on the last
// attempt of a single quiz so mistakes can be reviewed.
type QuizScore struct {
	Correct int   `json:"correct"`
	Total   int   `json:"total"`
	At      int64 `json:"at"`
	Answers []int `json:"answers,omitempty"`
}

type Quiz struct {
	ID           string         `json:"id"`
	Title        string         `json:"title"`
	CourseID     string         `json:"course_id"`
	LectureID    string         `json:"lecture_id"`
	LectureTitle string         `json:"lecture_title,omitempty"`
	Difficulty   string         `json:"difficulty"`
	Source       string         `json:"source"`
	CreatedAt    int64          `json:"created_at"`
	Count        int            `json:"count"`
	Questions    []QuizQuestion `json:"questions,omitempty"`
	Attempts     int            `json:"attempts"`
	Best         *QuizScore     `json:"best,omitempty"`
	Last         *QuizScore     `json:"last,omitempty"`
}

type QuizAttempt struct {
	ID         string `json:"id"`
	QuizID     string `json:"quiz_id"`
	StartedAt  int64  `json:"started_at"`
	FinishedAt int64  `json:"finished_at"`
	Answers    []int  `json:"answers"`
	Correct    int    `json:"correct"`
	Total      int    `json:"total"`
}

// QuizError is a validation failure, shown to the caller (and the assistant).
type QuizError string

func (e QuizError) Error() string { return string(e) }

var Difficulties = map[string]bool{"easy": true, "medium": true, "hard": true}

// ValidateQuiz checks a set and fills defaults. Assistant-written sets must
// cite a source for every question and explain every option.
func ValidateQuiz(q *Quiz) error {
	q.Title = strings.TrimSpace(q.Title)
	if q.Difficulty == "" {
		q.Difficulty = "medium"
	}
	if q.Source == "" {
		q.Source = "user"
	}
	switch {
	case q.Title == "" || utf8.RuneCountInString(q.Title) > 80:
		return QuizError("title 不能为空，最多 80 字")
	case !Difficulties[q.Difficulty]:
		return QuizError("difficulty 应为 easy、medium 或 hard")
	case q.Source != "user" && q.Source != "agent":
		return QuizError("source 应为 user 或 agent")
	case len(q.Questions) < 1 || len(q.Questions) > 30:
		return QuizError("题目数量应为 1–30")
	}
	stems := map[string]bool{}
	for i := range q.Questions {
		x := &q.Questions[i]
		n := i + 1
		x.Stem = strings.TrimSpace(x.Stem)
		if x.Stem == "" {
			return QuizError(fmt.Sprintf("第 %d 题题干为空", n))
		}
		if stems[x.Stem] {
			return QuizError(fmt.Sprintf("第 %d 题与前面的题目重复", n))
		}
		stems[x.Stem] = true
		if len(x.Options) < 2 || len(x.Options) > 6 {
			return QuizError(fmt.Sprintf("第 %d 题应有 2–6 个选项", n))
		}
		if x.Answer < 0 || x.Answer >= len(x.Options) {
			return QuizError(fmt.Sprintf("第 %d 题 answer 应为 0–%d 的选项序号", n, len(x.Options)-1))
		}
		seen := map[string]bool{}
		for j := range x.Options {
			o := &x.Options[j]
			o.Text, o.Rationale = strings.TrimSpace(o.Text), strings.TrimSpace(o.Rationale)
			key := strings.ToLower(o.Text)
			if o.Text == "" || seen[key] {
				return QuizError(fmt.Sprintf("第 %d 题的选项不能为空或重复", n))
			}
			seen[key] = true
			if q.Source == "agent" && o.Rationale == "" {
				return QuizError(fmt.Sprintf("第 %d 题选项 %c 缺少 rationale：每个选项都要解释为什么对或错", n, 'A'+j))
			}
		}
		x.Ref = strings.TrimSpace(x.Ref)
		if q.Source == "agent" && !strings.HasPrefix(x.Ref, "look://") {
			return QuizError(fmt.Sprintf("第 %d 题缺少出处 ref（look:// 链接，指向录像时间、PPT 或课件）", n))
		}
		if x.ID == "" {
			x.ID = fmt.Sprintf("q%d", n)
		}
	}
	q.Count = len(q.Questions)
	return nil
}

// Grade scores answers against a quiz; unanswered entries are -1.
func Grade(q Quiz, answers []int) (int, error) {
	if len(answers) != len(q.Questions) {
		return 0, QuizError(fmt.Sprintf("answers 应有 %d 项", len(q.Questions)))
	}
	correct := 0
	for i, a := range answers {
		if a < -1 || a >= len(q.Questions[i].Options) {
			return 0, QuizError(fmt.Sprintf("第 %d 题的答案无效", i+1))
		}
		if a == q.Questions[i].Answer {
			correct++
		}
	}
	return correct, nil
}

// CheckAttempt verifies a restored attempt against its set: same set, one
// valid answer per question, and the stored score matching a regrade.
func CheckAttempt(q Quiz, a QuizAttempt) error {
	if a.ID == "" || a.QuizID != q.ID {
		return QuizError("作答记录不属于这套练习")
	}
	correct, err := Grade(q, a.Answers)
	if err != nil {
		return err
	}
	if a.Total != len(q.Questions) || a.Correct != correct {
		return QuizError("作答记录的分数与题目不符")
	}
	if a.FinishedAt <= 0 || a.StartedAt > a.FinishedAt {
		return QuizError("作答记录的时间无效")
	}
	return nil
}

// Mirror writes the file copy of a set inside its transaction and returns
// how to undo the write if the transaction then fails to commit.
type Mirror func(q Quiz, attempts []QuizAttempt) (undo func(), err error)

// mirrored runs change in a transaction and then mirror; a mirror failure
// rolls the change back, and a commit failure undoes the mirror, so the index
// and the file copy agree whatever fails.
func (s *Store) mirrored(ctx context.Context, change func(tx *sql.Tx) error, mirror func(tx *sql.Tx) (func(), error)) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := change(tx); err != nil {
		return err
	}
	undo, err := mirror(tx)
	if err != nil {
		return err
	}
	if err := commitTx(tx); err != nil {
		undo()
		return err
	}
	return nil
}

// PutQuizMirrored stores a new set and writes its file copy.
func (s *Store) PutQuizMirrored(ctx context.Context, q Quiz, mirror Mirror) error {
	return s.mirrored(ctx, func(tx *sql.Tx) error { return putQuiz(ctx, tx, q) },
		func(*sql.Tx) (func(), error) { return mirror(q, []QuizAttempt{}) })
}

// PutQuizAttemptMirrored stores an attempt and rewrites the set's file copy
// with every attempt.
func (s *Store) PutQuizAttemptMirrored(ctx context.Context, q Quiz, a QuizAttempt, mirror Mirror) error {
	return s.mirrored(ctx, func(tx *sql.Tx) error { return putQuizAttempt(ctx, tx, a) },
		func(tx *sql.Tx) (func(), error) {
			attempts, err := quizAttempts(ctx, tx, q.ID)
			if err != nil {
				return nil, err
			}
			return mirror(q, attempts)
		})
}

// DeleteQuizMirrored deletes a set with its attempts in one transaction;
// remove deletes the file copy and returns how to restore it.
func (s *Store) DeleteQuizMirrored(ctx context.Context, id string, remove func() (func(), error)) error {
	return s.mirrored(ctx, func(tx *sql.Tx) error { return deleteQuiz(ctx, tx, id) },
		func(*sql.Tx) (func(), error) { return remove() })
}

func (s *Store) PutQuiz(ctx context.Context, q Quiz) error { return putQuiz(ctx, s.DB, q) }

func putQuiz(ctx context.Context, db querier, q Quiz) error {
	b, err := json.Marshal(q.Questions)
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `INSERT OR REPLACE INTO quizzes(id,title,course_id,lecture_id,difficulty,source,questions,created_at) VALUES(?,?,?,?,?,?,?,?)`,
		q.ID, q.Title, q.CourseID, q.LectureID, q.Difficulty, q.Source, string(b), q.CreatedAt)
	return err
}

const quizCols = `q.id,q.title,q.course_id,q.lecture_id,COALESCE(l.title,''),q.difficulty,q.source,q.questions,q.created_at,
 (SELECT COUNT(*) FROM quiz_attempts a WHERE a.quiz_id=q.id)`

func scanQuiz(sc interface{ Scan(...any) error }) (Quiz, error) {
	var q Quiz
	var qs string
	if err := sc.Scan(&q.ID, &q.Title, &q.CourseID, &q.LectureID, &q.LectureTitle, &q.Difficulty, &q.Source, &qs, &q.CreatedAt, &q.Attempts); err != nil {
		return q, err
	}
	if err := json.Unmarshal([]byte(qs), &q.Questions); err != nil {
		return q, err
	}
	q.Count = len(q.Questions)
	return q, nil
}

// scores fills Best and Last; Last carries its answers when withAnswers.
func (s *Store) scores(ctx context.Context, q *Quiz, withAnswers bool) error {
	if q.Attempts == 0 {
		return nil
	}
	var best, last QuizScore
	var answers string
	err := s.DB.QueryRowContext(ctx, `SELECT correct,total,finished_at FROM quiz_attempts WHERE quiz_id=? ORDER BY correct*1.0/total DESC, finished_at DESC LIMIT 1`, q.ID).
		Scan(&best.Correct, &best.Total, &best.At)
	if err != nil {
		return err
	}
	if err := s.DB.QueryRowContext(ctx, `SELECT correct,total,finished_at,answers FROM quiz_attempts WHERE quiz_id=? ORDER BY finished_at DESC LIMIT 1`, q.ID).
		Scan(&last.Correct, &last.Total, &last.At, &answers); err != nil {
		return err
	}
	if withAnswers {
		json.Unmarshal([]byte(answers), &last.Answers)
	}
	q.Best, q.Last = &best, &last
	return nil
}

// Quizzes lists sets, newest first, without their questions.
func (s *Store) Quizzes(ctx context.Context, courseID, lectureID string) ([]Quiz, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+quizCols+` FROM quizzes q LEFT JOIN lectures l ON l.id=q.lecture_id
 WHERE (?='' OR q.course_id=?) AND (?='' OR q.lecture_id=?) ORDER BY q.created_at DESC`, courseID, courseID, lectureID, lectureID)
	if err != nil {
		return nil, err
	}
	out := []Quiz{}
	for rows.Next() {
		q, err := scanQuiz(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		q.Questions = nil
		out = append(out, q)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range out {
		if err := s.scores(ctx, &out[i], false); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// Quiz returns a set with its questions, best score and last answers.
func (s *Store) Quiz(ctx context.Context, id string) (Quiz, error) {
	q, err := scanQuiz(s.DB.QueryRowContext(ctx, `SELECT `+quizCols+` FROM quizzes q LEFT JOIN lectures l ON l.id=q.lecture_id WHERE q.id=?`, id))
	if err != nil {
		return q, err
	}
	return q, s.scores(ctx, &q, true)
}

// DeleteQuiz deletes a set and its attempts together.
func (s *Store) DeleteQuiz(ctx context.Context, id string) error {
	return s.mirrored(ctx, func(tx *sql.Tx) error { return deleteQuiz(ctx, tx, id) },
		func(*sql.Tx) (func(), error) { return func() {}, nil })
}

func deleteQuiz(ctx context.Context, db querier, id string) error {
	res, err := db.ExecContext(ctx, `DELETE FROM quizzes WHERE id=?`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return sql.ErrNoRows
	}
	_, err = db.ExecContext(ctx, `DELETE FROM quiz_attempts WHERE quiz_id=?`, id)
	return err
}

func (s *Store) PutQuizAttempt(ctx context.Context, a QuizAttempt) error {
	return putQuizAttempt(ctx, s.DB, a)
}

func putQuizAttempt(ctx context.Context, db querier, a QuizAttempt) error {
	if a.Total <= 0 {
		return errors.New("attempt without questions")
	}
	b, _ := json.Marshal(a.Answers)
	_, err := db.ExecContext(ctx, `INSERT OR REPLACE INTO quiz_attempts(id,quiz_id,started_at,finished_at,answers,correct,total) VALUES(?,?,?,?,?,?,?)`,
		a.ID, a.QuizID, a.StartedAt, a.FinishedAt, string(b), a.Correct, a.Total)
	return err
}

// QuizAttempts returns a set's attempts, oldest first.
func (s *Store) QuizAttempts(ctx context.Context, quizID string) ([]QuizAttempt, error) {
	return quizAttempts(ctx, s.DB, quizID)
}

func quizAttempts(ctx context.Context, db querier, quizID string) ([]QuizAttempt, error) {
	rows, err := db.QueryContext(ctx, `SELECT id,quiz_id,started_at,finished_at,answers,correct,total FROM quiz_attempts WHERE quiz_id=? ORDER BY finished_at`, quizID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []QuizAttempt{}
	for rows.Next() {
		var a QuizAttempt
		var ans string
		if err := rows.Scan(&a.ID, &a.QuizID, &a.StartedAt, &a.FinishedAt, &ans, &a.Correct, &a.Total); err != nil {
			return nil, err
		}
		json.Unmarshal([]byte(ans), &a.Answers)
		out = append(out, a)
	}
	return out, rows.Err()
}
