package server

import (
	"errors"
	"io"
	"net/http"
	"os"
	"strings"

	"lookstudio/lookd/internal/library"
)

func reviewError(err error) error {
	if errors.Is(err, library.ErrReviewConflict) {
		return apiError{http.StatusConflict, err.Error()}
	}
	return err
}

func (s *Server) transcriptReview(_ http.ResponseWriter, r *http.Request) (any, error) {
	id := r.PathValue("id")
	switch r.Method {
	case "GET":
		return s.Lib.TranscriptReview(r.Context(), id)
	case "PUT":
		var in struct {
			library.TranscriptReview
			BaseRunID string `json:"base_run_id"`
		}
		if e := decode(r, &in); e != nil {
			return nil, e
		}
		out, e := s.Lib.SaveTranscriptReview(r.Context(), id, in.BaseRunID, in.TranscriptReview)
		if e != nil {
			return nil, reviewError(e)
		}
		s.Bus.Publish("transcript_review_changed", map[string]string{"lecture_id": id})
		return out, nil
	case "PATCH":
		var in struct {
			ID string `json:"suggestion_id"`
		}
		if e := decode(r, &in); e != nil {
			return nil, e
		}
		out, e := s.Lib.DismissTranscriptSuggestion(r.Context(), id, in.ID)
		return out, reviewError(e)
	}
	return nil, badRequest("不支持的审校操作")
}

func (s *Server) transcriptReviewContext(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx := r.Context()
	id := r.PathValue("id")
	lec, e := s.St.Lecture(ctx, id)
	if e != nil {
		return nil, e
	}
	course, e := s.St.Course(ctx, lec.CourseID)
	if e != nil {
		return nil, e
	}
	segs, e := s.St.Segments(ctx, id, 0, 0)
	if e != nil {
		return nil, e
	}
	notes, e := s.St.Notes(ctx, lec.CourseID, id)
	if e != nil {
		return nil, e
	}
	materials := []map[string]string{}
	remaining := 20000
	add := func(id, title, text string) {
		if remaining <= 0 {
			return
		}
		runes := []rune(text)
		if len(runes) > remaining {
			runes = runes[:remaining]
		}
		remaining -= len(runes)
		materials = append(materials, map[string]string{"id": id, "title": title, "text": string(runes)})
	}
	// Lecture-local OCR and material notes are evidence. Personal and historical
	// summaries are omitted because they can repeat prior model mistakes.
	for _, n := range notes {
		if strings.HasPrefix(n.Title, "课堂截图检索") || strings.HasPrefix(n.Title, "课件全文") {
			full, err := s.St.Note(ctx, n.ID)
			if err != nil {
				return nil, err
			}
			add("note:"+n.ID, n.Title, full.Body)
		}
	}
	root, e := os.OpenRoot(s.Lib.Root)
	if e != nil {
		return nil, e
	}
	defer root.Close()
	assets, e := s.Lib.Courseware(ctx, id)
	if e != nil {
		return nil, e
	}
	for _, a := range assets {
		m := library.CoursewareInfo(a)
		if remaining <= 0 {
			break
		}
		if m.Parse == nil || m.Parse.State != "done" || m.Parse.MD == "" {
			continue
		}
		f, err := root.Open(m.Parse.MD)
		if err != nil {
			continue
		}
		b, err := io.ReadAll(io.LimitReader(f, 80000))
		f.Close()
		if err == nil {
			add("file:"+a.Path, m.Name, string(b))
		}
	}
	return map[string]any{"course": course.Title, "lecture": lec.Title, "date": lec.Date, "fingerprint": library.TranscriptFingerprint(segs), "segments": segs, "materials": materials}, nil
}
