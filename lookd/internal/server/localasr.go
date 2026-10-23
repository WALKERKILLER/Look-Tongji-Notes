package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"lookstudio/lookd/internal/localasr"
)

// localASROptions reads the download settings.
func (s *Server) localASROptions(ctx context.Context) (localasr.Options, string, int) {
	kv, _ := s.St.Settings(ctx)
	var o localasr.Options
	var model string
	var threads int
	json.Unmarshal(kv["asr.local.source"], &o.Source)
	json.Unmarshal(kv["asr.local.custom_url"], &o.Custom)
	json.Unmarshal(kv["asr.local.github_proxy"], &o.Proxy)
	json.Unmarshal(kv["asr.local.model"], &model)
	json.Unmarshal(kv["asr.local.threads"], &threads)
	if o.Source == "" {
		o.Source = "hf-mirror"
	}
	return o, model, threads
}

// applyLocalASR puts the selected installed model into the ASR pool, or
// takes the local channel out.
func (s *Server) applyLocalASR(ctx context.Context) {
	if s.Local == nil {
		return
	}
	_, model, threads := s.localASROptions(ctx)
	if model == "" {
		s.Jobs.ASR.SetLocal("", "", nil)
		return
	}
	r, err := s.Local.Recognizer(model, threads)
	if err != nil {
		s.Jobs.ASR.SetLocal("", "", nil)
		return
	}
	s.Jobs.ASR.SetLocal("本地 · "+r.Model.Name, "在本机识别，音频不上传，不受免费额度限制", r)
}

// OnLocalASR announces install progress and selects the first model a user
// installs, so it starts working without another click.
func (s *Server) OnLocalASR(p localasr.Progress) {
	s.Bus.Publish("asr_local", p)
	if p.State == "failed" && p.Model == "" {
		s.applyLocalASR(s.Ctx) // a failed move: back to the models where they are
	}
	if p.State != "done" {
		return
	}
	ctx := s.Ctx
	if _, model, _ := s.localASROptions(ctx); model == "" || !s.Local.Installed(model) {
		v, _ := json.Marshal(p.Model)
		if s.St.PutSettings(ctx, map[string]json.RawMessage{"asr.local.model": v}) == nil {
			s.Bus.Publish("settings_changed", map[string]json.RawMessage{"asr.local.model": v})
		}
	}
	s.applyLocalASR(ctx)
}

func (s *Server) localASRStatus(_ http.ResponseWriter, r *http.Request) (any, error) {
	o, model, threads := s.localASROptions(r.Context())
	if threads <= 0 {
		threads = localasr.DefaultThreads()
	}
	return map[string]any{"status": s.Local.Status(), "active": model, "source": o.Source, "custom_url": o.Custom,
		"github_proxy": o.Proxy, "threads": threads}, nil
}

func (s *Server) localASRInstall(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Model string `json:"model"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	o, _, _ := s.localASROptions(r.Context())
	err := s.Local.Start(s.Ctx, in.Model, o)
	if errors.Is(err, localasr.ErrRunning) {
		return nil, apiError{http.StatusConflict, err.Error()}
	}
	if err != nil {
		return nil, badRequest(err.Error())
	}
	return s.Local.Status(), nil
}

// localASRLocation changes the folder that holds the engine and models;
// see localasr.Manager.Relocate. A move finishes in the background and
// puts the local channel back through OnLocalASR.
func (s *Server) localASRLocation(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Dir  string `json:"dir"`
		Move bool   `json:"move"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	// No transcription may start on the models while they change place.
	if !s.Jobs.ASR.TakeLocal() {
		return nil, apiError{http.StatusConflict, localasr.ErrInUse.Error()}
	}
	err := s.Local.Relocate(in.Dir, in.Move, nil)
	if err != nil || !in.Move {
		s.applyLocalASR(r.Context())
	}
	switch {
	case errors.Is(err, localasr.ErrRunning):
		return nil, apiError{http.StatusConflict, err.Error()}
	case err != nil:
		return nil, apiError{http.StatusBadRequest, err.Error()}
	}
	return s.Local.Status(), nil
}

func (s *Server) localASRRemove(_ http.ResponseWriter, r *http.Request) (any, error) {
	id := r.PathValue("id")
	if err := s.Local.Remove(id); err != nil {
		if errors.Is(err, localasr.ErrRunning) {
			return nil, apiError{http.StatusConflict, err.Error()}
		}
		return nil, badRequest(err.Error())
	}
	if _, model, _ := s.localASROptions(r.Context()); model == id {
		v, _ := json.Marshal("")
		s.St.PutSettings(r.Context(), map[string]json.RawMessage{"asr.local.model": v})
		s.Bus.Publish("settings_changed", map[string]json.RawMessage{"asr.local.model": v})
	}
	s.applyLocalASR(r.Context())
	return s.Local.Status(), nil
}
