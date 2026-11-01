package server

import (
	"encoding/json"
	"errors"
	"net/http"

	"lookstudio/lookd/internal/library"
)

func localCourseError(err error) error {
	if errors.Is(err, library.ErrLocalLimit) {
		return apiError{413, err.Error()}
	}
	if errors.Is(err, library.ErrLocalInvalid) {
		return badRequest(err.Error())
	}
	return err
}

func (s *Server) createLocalCourse(w http.ResponseWriter, r *http.Request) (any, error) {
	var q struct {
		Title   string `json:"title"`
		Teacher string `json:"teacher"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&q); err != nil {
		return nil, badRequest("无法新建课程：课程信息无效")
	}
	c, err := s.Lib.CreateLocalCourse(r.Context(), q.Title, q.Teacher)
	if err != nil {
		return nil, localCourseError(err)
	}
	s.Bus.Publish("courses_changed", nil)
	return c, nil
}

func (s *Server) importLocalVideo(w http.ResponseWriter, r *http.Request) (any, error) {
	if r.ContentLength > library.LocalVideoLimit {
		return nil, localCourseError(library.ErrLocalLimit)
	}
	lec, err := s.Lib.ImportLocalVideo(r.Context(), r.PathValue("id"), r.URL.Query().Get("name"), http.MaxBytesReader(w, r.Body, library.LocalVideoLimit+1))
	if err != nil {
		return nil, localCourseError(err)
	}
	s.Bus.Publish("lecture_changed", map[string]string{"lecture_id": lec.ID, "course_id": lec.CourseID})
	s.Bus.Publish("courses_changed", nil)
	return lec, nil
}
