package server

import (
	"encoding/json"
	"errors"
	"io"
	"lookstudio/lookd/internal/library"
	"net/http"
	"path"
	"strconv"
)

func studyError(e error) error {
	if errors.Is(e, library.ErrStudyConflict) {
		return apiError{409, e.Error()}
	}
	if errors.Is(e, library.ErrStudyLimit) {
		return apiError{413, e.Error()}
	}
	if errors.Is(e, library.ErrStudyInvalid) {
		return badRequest(e.Error())
	}
	return e
}
func (s *Server) studyCanvas(w http.ResponseWriter, r *http.Request) (any, error) {
	id := r.PathValue("id")
	if r.Method == "GET" {
		d, e := s.Lib.StudyCanvas(r.Context(), id)
		return d, studyError(e)
	}
	var d library.StudyDocument
	b, e := io.ReadAll(http.MaxBytesReader(w, r.Body, library.StudyDocumentLimit))
	if e != nil {
		return nil, apiError{413, "画布超过 32 MiB"}
	}
	if e = json.Unmarshal(b, &d); e != nil {
		return nil, badRequest("画布 JSON 无效")
	}
	d, e = s.Lib.SaveStudyCanvas(r.Context(), id, d)
	if e != nil {
		return nil, studyError(e)
	}
	return d, nil
}
func (s *Server) studyCanvasImport(w http.ResponseWriter, r *http.Request) (any, error) {
	id := r.PathValue("id")
	q := r.URL.Query()
	name := q.Get("name")
	reader := io.Reader(http.MaxBytesReader(w, r.Body, library.StudyAssetLimit+1))
	if rel := q.Get("path"); rel != "" {
		f, e := s.Lib.StudySource(r.Context(), id, rel)
		if e != nil {
			return nil, studyError(e)
		}
		defer f.Close()
		reader = f
		name = path.Base(rel)
	}
	out, e := s.Lib.ImportStudyModule(r.Context(), id, name, reader)
	return out, studyError(e)
}

func (s *Server) studyCanvasContext(w http.ResponseWriter, r *http.Request) (any, error) {
	var q library.StudyContextRequest
	if e := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&q); e != nil {
		return nil, badRequest("画布上下文请求无效")
	}
	out, e := s.Lib.StudyContext(r.Context(), r.PathValue("id"), q)
	return out, studyError(e)
}

func (s *Server) studyConversation(w http.ResponseWriter, r *http.Request) (any, error) {
	var next *library.StudyConversation
	if r.Method == "PUT" {
		next = &library.StudyConversation{}
		if e := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20)).Decode(next); e != nil {
			return nil, badRequest("对话数据无效或过大")
		}
	}
	out, e := s.Lib.StudyConversation(r.Context(), r.PathValue("id"), r.PathValue("conversation"), next)
	return out, studyError(e)
}
func (s *Server) studyMaterial(w http.ResponseWriter, r *http.Request) (any, error) {
	var q struct {
		Path string `json:"path"`
	}
	if e := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&q); e != nil {
		return nil, badRequest("资料引用无效")
	}
	out, e := s.Lib.ImportStudyMaterial(r.Context(), r.PathValue("id"), q.Path)
	return out, studyError(e)
}

func (s *Server) studyPDFPage(w http.ResponseWriter, r *http.Request) (any, error) {
	page, e := strconv.Atoi(r.URL.Query().Get("page"))
	if e != nil {
		return nil, badRequest("页码无效")
	}
	out, e := s.Lib.StudyPDFPage(r.Context(), r.PathValue("id"), r.URL.Query().Get("source"), page)
	return out, studyError(e)
}

func (s *Server) studyVideoFile(w http.ResponseWriter, r *http.Request) (any, error) {
	s.studyMediaFile(w, r)
	return nil, nil
}
