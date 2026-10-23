package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"lookstudio/lookd/internal/notion"
)

// Notion sync: routes, and an automatic sync a while after notes change.
// Contract: docs/specs/0013-notion-sync.md

const notionDelay = time.Minute // notes are often saved in bursts

// NotionDocs adapts the library's page tree for the Notion sync.
func (s *Server) NotionDocs(ctx context.Context) ([]notion.Doc, error) {
	docs, err := s.Lib.KnowledgeDocs(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]notion.Doc, len(docs))
	for i, d := range docs {
		out[i] = notion.Doc{Key: d.Key, Parent: d.Parent, Title: d.Title, Body: d.Body, Container: d.Container}
	}
	return out, nil
}

func notionErr(err error) error {
	var ae *notion.APIError
	switch {
	case errors.Is(err, notion.ErrNotConnected), errors.Is(err, notion.ErrNoParent):
		return apiError{http.StatusConflict, err.Error()}
	case errors.Is(err, notion.ErrAuth):
		return apiError{http.StatusUnauthorized, err.Error()}
	case errors.As(err, &ae):
		return apiError{http.StatusBadGateway, err.Error()}
	}
	return err
}

func (s *Server) notionStatus(http.ResponseWriter, *http.Request) (any, error) {
	return s.Notion.Status(), nil
}

func (s *Server) notionConnect(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Token string `json:"token"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	st, err := s.Notion.Connect(r.Context(), in.Token)
	if err != nil {
		return nil, notionErr(err)
	}
	return st, nil
}

func (s *Server) notionDisconnect(http.ResponseWriter, *http.Request) (any, error) {
	s.Notion.Disconnect()
	return s.Notion.Status(), nil
}

func (s *Server) notionPages(_ http.ResponseWriter, r *http.Request) (any, error) {
	ps, err := s.Notion.Search(r.Context(), r.URL.Query().Get("q"))
	if err != nil {
		return nil, notionErr(err)
	}
	return ps, nil
}

func (s *Server) notionConfigure(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Parent *string `json:"parent"`
		Auto   *bool   `json:"auto"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	st, err := s.Notion.Configure(r.Context(), in.Parent, in.Auto)
	if err != nil {
		return nil, notionErr(err)
	}
	return st, nil
}

func (s *Server) notionSync(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Full bool `json:"full"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	st := s.Notion.Status()
	switch {
	case !st.Connected:
		return nil, notionErr(notion.ErrNotConnected)
	case st.Parent == nil:
		return nil, notionErr(notion.ErrNoParent)
	}
	go s.runNotionSync(in.Full)
	st.Running = true
	return st, nil
}

func (s *Server) runNotionSync(full bool) {
	ctx, cancel := context.WithTimeout(s.Ctx, 30*time.Minute)
	defer cancel()
	if _, err := s.Notion.Sync(ctx, full); err != nil {
		slog.Warn("notion sync", "err", err)
	}
}

// knowledgeChanged refreshes the automatic exports after notes change.
func (s *Server) knowledgeChanged() {
	s.exportObsidianSoon()
	if s.Data != nil {
		s.Data.Soon(s.Ctx)
	}
	if s.Notion == nil || !s.Notion.AutoOn() {
		return
	}
	s.obsidianMu.Lock()
	defer s.obsidianMu.Unlock()
	if s.notionTimer != nil {
		s.notionTimer.Stop()
	}
	s.notionTimer = time.AfterFunc(notionDelay, func() { s.runNotionSync(false) })
}
