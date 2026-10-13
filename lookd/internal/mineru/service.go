package mineru

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// Use is one parse attempt, kept to show daily usage.
type Use struct {
	At    int64  `json:"at"`
	File  string `json:"file"`
	Pages int    `json:"pages"`
	Mode  string `json:"mode"` // precise | flash
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

type saved struct {
	Token string  `json:"token_sealed,omitempty"`
	Opts  Options `json:"options"`
	Auto  bool    `json:"auto"`
	Uses  []Use   `json:"uses"`
}

// Status is what the settings screen shows. The token itself never leaves
// lookd; only its last characters and expiry do.
type Status struct {
	Configured bool    `json:"configured"`
	Mode       string  `json:"mode"`
	TokenTail  string  `json:"token_tail,omitempty"`
	TokenExp   int64   `json:"token_exp,omitempty"`
	Options    Options `json:"options"`
	Auto       bool    `json:"auto"`
	TodayPages int     `json:"today_pages"`
	TodayFiles int     `json:"today_files"`
	DailyPages int     `json:"daily_pages"`
	MaxBytes   int64   `json:"max_bytes"`
	MaxPages   int     `json:"max_pages"`
	Recent     []Use   `json:"recent"`
}

// Service keeps MinerU settings (token sealed at rest) and usage.
type Service struct {
	mu     sync.Mutex
	path   string
	seal   func(string) (string, error)
	unseal func(string) (string, error)
	st     saved
	token  string
	hc     *http.Client
}

func NewService(path string, seal, unseal func(string) (string, error)) *Service {
	s := &Service{path: path, seal: seal, unseal: unseal,
		st: saved{Opts: Options{Model: "vlm", Formula: true, Table: true, Language: "ch"}, Auto: true}}
	if b, err := os.ReadFile(path); err == nil {
		json.Unmarshal(b, &s.st)
	}
	if s.st.Token != "" {
		s.token, _ = unseal(s.st.Token)
	}
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.DialContext = (&net.Dialer{Timeout: 15 * time.Second}).DialContext
	tr.ResponseHeaderTimeout = 60 * time.Second
	s.hc = &http.Client{Transport: tr, Timeout: 30 * time.Minute}
	return s
}

func (s *Service) saveLocked() {
	b, _ := json.MarshalIndent(s.st, "", "  ")
	tmp := s.path + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, s.path)
	}
}

// tokenExp reads the exp claim when the token is a JWT.
func tokenExp(tok string) int64 {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return 0
	}
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(parts[1], "="))
	if err != nil {
		return 0
	}
	var c struct {
		Exp int64 `json:"exp"`
	}
	json.Unmarshal(b, &c)
	return c.Exp
}

func (s *Service) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := Status{Configured: s.token != "", Mode: "flash", Options: s.st.Opts.normalized(), Auto: s.st.Auto,
		DailyPages: DailyPages, MaxBytes: FlashMaxBytes, MaxPages: FlashMaxPages, Recent: []Use{}}
	if s.token != "" {
		st.Mode, st.MaxBytes, st.MaxPages = "precise", MaxBytes, MaxPages
		st.TokenTail = s.token[max(0, len(s.token)-4):]
		st.TokenExp = tokenExp(s.token)
	}
	y, m, d := time.Now().Date()
	start := time.Date(y, m, d, 0, 0, 0, 0, time.Local).Unix()
	for _, u := range s.st.Uses {
		if u.At >= start && u.OK && u.Mode == "precise" {
			st.TodayPages += u.Pages
		}
		if u.At >= start && u.OK {
			st.TodayFiles++
		}
	}
	for i := len(s.st.Uses) - 1; i >= 0 && len(st.Recent) < 20; i-- {
		st.Recent = append(st.Recent, s.st.Uses[i])
	}
	return st
}

// Update changes settings. A nil token keeps the current one; "" clears it.
func (s *Service) Update(token *string, opts *Options, auto *bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if token != nil {
		t := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(*token), "Bearer "))
		if t == "" {
			s.st.Token, s.token = "", ""
		} else {
			sealed, err := s.seal(t)
			if err != nil {
				return err
			}
			s.st.Token, s.token = sealed, t
		}
	}
	if opts != nil {
		s.st.Opts = opts.normalized()
	}
	if auto != nil {
		s.st.Auto = *auto
	}
	s.saveLocked()
	return nil
}

func (s *Service) AutoParse() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.st.Auto
}

// Test checks the token by asking for a task that does not exist: a valid
// token gets "task not found", an invalid one an auth error.
func (s *Service) Test(ctx context.Context) error {
	s.mu.Lock()
	tok := s.token
	s.mu.Unlock()
	if tok == "" {
		return errors.New("还没有填写 MinerU Token")
	}
	c := &client{hc: s.hc, base: preciseBase, token: tok}
	err := c.call(ctx, http.MethodGet, "/extract/task/00000000-0000-0000-0000-000000000000", nil, nil)
	var me Error
	if err == nil || (errors.As(err, &me) && !Auth(err)) {
		return nil
	}
	return err
}

// Parse converts file into out/full.md (plus images for the precise API)
// and returns the page count when known.
func (s *Service) Parse(ctx context.Context, file, out string, p Progress) (int, string, error) {
	s.mu.Lock()
	tok, opts := s.token, s.st.Opts.normalized()
	s.mu.Unlock()
	fi, err := os.Stat(file)
	if err != nil {
		return 0, "", err
	}
	mode := "flash"
	if tok != "" {
		mode = "precise"
	}
	switch {
	case mode == "precise" && fi.Size() > MaxBytes:
		return 0, mode, Error{Code: "-60005"}
	case mode == "flash" && fi.Size() > FlashMaxBytes:
		return 0, mode, Error{Code: "-30001"}
	}
	os.RemoveAll(out)
	var pages int
	if mode == "precise" {
		pages, err = (&client{hc: s.hc, base: preciseBase, token: tok}).precise(ctx, file, out, opts, p)
	} else {
		pages, err = (&client{hc: s.hc, base: flashBase}).flash(ctx, file, out, opts, p)
	}
	if ctx.Err() != nil {
		return pages, mode, ctx.Err()
	}
	u := Use{At: time.Now().Unix(), File: fi.Name(), Pages: pages, Mode: mode, OK: err == nil}
	if err != nil {
		u.Error = err.Error()
		os.RemoveAll(out)
	}
	s.mu.Lock()
	s.st.Uses = append(s.st.Uses, u)
	if n := len(s.st.Uses); n > 200 {
		s.st.Uses = s.st.Uses[n-200:]
	}
	s.saveLocked()
	s.mu.Unlock()
	return pages, mode, err
}
