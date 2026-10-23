package server

import (
	"errors"
	"net/http"

	"lookstudio/lookd/internal/store"
)

// Practice quizzes (docs/specs/0002-tutor-quiz-cards.md).

// quizErr turns validation failures into 400s.
func quizErr(err error) error {
	var qe store.QuizError
	if errors.As(err, &qe) {
		return badRequest(qe.Error())
	}
	return err
}

func (s *Server) quizzesChanged(id string) {
	s.Bus.Publish("quizzes_changed", map[string]string{"id": id})
}

func (s *Server) quizzes(_ http.ResponseWriter, r *http.Request) (any, error) {
	q := r.URL.Query()
	return s.St.Quizzes(r.Context(), q.Get("course_id"), q.Get("lecture_id"))
}

func (s *Server) quiz(_ http.ResponseWriter, r *http.Request) (any, error) {
	return s.St.Quiz(r.Context(), r.PathValue("id"))
}

func (s *Server) addQuiz(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in store.Quiz
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	q, err := s.Lib.SaveQuiz(r.Context(), in)
	if err != nil {
		return nil, quizErr(err)
	}
	s.quizzesChanged(q.ID)
	return q, nil
}

func (s *Server) deleteQuiz(_ http.ResponseWriter, r *http.Request) (any, error) {
	id := r.PathValue("id")
	if err := s.Lib.DeleteQuiz(r.Context(), id); err != nil {
		return nil, err
	}
	s.quizzesChanged(id)
	s.Bus.Publish("activity_changed", map[string]string{})
	return ok(), nil
}

func (s *Server) addQuizAttempt(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		StartedAt int64 `json:"started_at"`
		Answers   []int `json:"answers"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	id := r.PathValue("id")
	a, err := s.Lib.AddQuizAttempt(r.Context(), id, in.StartedAt, in.Answers)
	if err != nil {
		return nil, quizErr(err)
	}
	q, err := s.St.Quiz(r.Context(), id)
	if err != nil {
		return nil, err
	}
	s.quizzesChanged(id)
	s.Bus.Publish("activity_changed", map[string]string{})
	return map[string]any{"attempt": a, "best": q.Best}, nil
}
