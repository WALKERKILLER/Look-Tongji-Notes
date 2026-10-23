package datasync

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	// ConflictDir keeps the losing copy of files changed on two devices.
	ConflictDir = ".sync-conflicts"
	// TrashDir keeps library files deleted on another device.
	TrashDir = ".sync-trash"

	autoEvery = 30 * time.Minute
	autoDelay = 2 * time.Minute // after notes change
)

var (
	ErrBusy          = errors.New("正在同步或恢复数据，请稍候")
	ErrNotConfigured = errors.New("尚未设置 WebDAV")
)

// Service owns backups and the WebDAV sync.
type Service struct {
	Roots Roots
	App   string // version written into backups
	HC    *http.Client
	// State and MergeState carry the personal state kept in the index.
	State      func(ctx context.Context) ([]byte, error)
	MergeState func(ctx context.Context, b []byte) (bool, error)
	// Changed runs after files arrived from elsewhere.
	Changed func(ctx context.Context, library, data bool)
	Publish func(kind string, data any)
	Seal    func(string) (string, error)
	Unseal  func(string) (string, error)

	mu       sync.Mutex
	cfg      config
	pass     string
	loaded   bool
	running  bool
	progress *Progress
	timer    *time.Timer
	runMu    sync.Mutex // one sync or restore at a time
}

type config struct {
	URL       string           `json:"url,omitempty"`
	User      string           `json:"user,omitempty"`
	Pass      string           `json:"pass_sealed,omitempty"`
	Folder    string           `json:"folder,omitempty"`
	Auto      bool             `json:"auto"`
	Media     bool             `json:"media"`
	DeviceID  string           `json:"device_id,omitempty"`
	Base      map[string]Entry `json:"base,omitempty"` // what both sides last agreed on
	StateHash string           `json:"state_hash,omitempty"`
	Last      *Result          `json:"last,omitempty"`
}

// Settings are the user-editable part of the sync configuration.
type Settings struct {
	URL    string  `json:"url"`
	User   string  `json:"user"`
	Pass   *string `json:"password,omitempty"` // nil keeps the saved one
	Folder string  `json:"folder"`
	Auto   bool    `json:"auto"`
	Media  bool    `json:"media"`
}

type Progress struct {
	Step  string `json:"step"`
	Done  int    `json:"done"`
	Total int    `json:"total"`
	Bytes int64  `json:"bytes"`
}

type Result struct {
	At          int64    `json:"at"`
	Uploaded    int      `json:"uploaded"`
	Downloaded  int      `json:"downloaded"`
	Deleted     int      `json:"deleted"`
	Conflicts   int      `json:"conflicts"`
	Bytes       int64    `json:"bytes"`
	ConflictDir string   `json:"conflict_dir,omitempty"`
	Errors      []string `json:"errors,omitempty"`
	Error       string   `json:"error,omitempty"`
	Partial     bool     `json:"partial,omitempty"` // stopped early; the next run continues
}

type Status struct {
	Configured  bool      `json:"configured"`
	URL         string    `json:"url,omitempty"`
	User        string    `json:"user,omitempty"`
	HasPassword bool      `json:"has_password"`
	Folder      string    `json:"folder"`
	Auto        bool      `json:"auto"`
	Media       bool      `json:"media"`
	Device      string    `json:"device"`
	Files       int       `json:"files"`
	Running     bool      `json:"running"`
	Progress    *Progress `json:"progress,omitempty"`
	Last        *Result   `json:"last,omitempty"`
}

func (s *Service) path() string { return filepath.Join(s.Roots.Data, "sync.json") }

func (s *Service) loadLocked() {
	if s.loaded {
		return
	}
	s.loaded = true
	if b, err := os.ReadFile(s.path()); err == nil {
		json.Unmarshal(b, &s.cfg)
	}
	if s.cfg.Pass != "" && s.Unseal != nil {
		s.pass, _ = s.Unseal(s.cfg.Pass)
	}
	if s.cfg.DeviceID == "" {
		var b [6]byte
		rand.Read(b[:])
		s.cfg.DeviceID = hex.EncodeToString(b[:])
	}
	if s.cfg.Folder == "" {
		s.cfg.Folder = "LookStudio"
	}
}

func (s *Service) saveLocked() {
	b, _ := json.MarshalIndent(s.cfg, "", "  ")
	if err := writeFile(s.path(), time.Time{}, func(f *os.File) error {
		f.Chmod(0o600)
		_, err := f.Write(b)
		return err
	}); err != nil {
		slog.Warn("datasync: save failed", "err", err)
	}
}

func (s *Service) publish(kind string, data any) {
	if s.Publish != nil {
		s.Publish(kind, data)
	}
}

func (s *Service) changed(ctx context.Context, library, data bool) {
	if (library || data) && s.Changed != nil {
		s.Changed(ctx, library, data)
	}
}

func (s *Service) deviceName() string {
	h, _ := os.Hostname()
	return h
}

func (s *Service) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.loadLocked()
	c := s.cfg
	return Status{Configured: c.URL != "", URL: c.URL, User: c.User, HasPassword: s.pass != "", Folder: c.Folder,
		Auto: c.Auto, Media: c.Media, Device: s.deviceName(), Files: len(c.Base), Running: s.running,
		Progress: s.progress, Last: c.Last}
}

// normalize checks a WebDAV address and folder.
func normalize(raw, folder string) (string, string, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || (u.Scheme != "https" && u.Scheme != "http") || u.Host == "" {
		return "", "", errors.New("请填写以 https:// 或 http:// 开头的 WebDAV 地址")
	}
	if !strings.HasSuffix(u.Path, "/") {
		u.Path += "/"
	}
	u.RawQuery, u.Fragment, u.User = "", "", nil
	folder = strings.Trim(strings.ReplaceAll(strings.TrimSpace(folder), "\\", "/"), "/")
	if folder == "" {
		folder = "LookStudio"
	}
	for _, seg := range strings.Split(folder, "/") {
		if seg == "" || seg == "." || seg == ".." {
			return "", "", errors.New("同步目录名称不正确")
		}
	}
	return u.String(), folder, nil
}

func (s *Service) client(rawURL, folder, user, pass string) (*Client, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	dir := strings.TrimSuffix(u.String(), "/") + "/"
	if folder != "" {
		segs := strings.Split(folder, "/")
		for i, seg := range segs {
			segs[i] = url.PathEscape(seg)
		}
		dir += strings.Join(segs, "/") + "/"
	}
	base, err := url.Parse(dir)
	if err != nil {
		return nil, err
	}
	hc := s.HC
	if hc == nil {
		hc = &http.Client{Transport: &http.Transport{Proxy: http.ProxyFromEnvironment, ResponseHeaderTimeout: time.Minute}}
	}
	return &Client{Base: base, User: user, Pass: pass, HC: hc}, nil
}

// Configure saves the WebDAV account after checking it can create the
// sync folder.
func (s *Service) Configure(ctx context.Context, in Settings) (Status, error) {
	addr, folder, err := normalize(in.URL, in.Folder)
	if err != nil {
		return Status{}, err
	}
	s.mu.Lock()
	s.loadLocked()
	pass := s.pass
	s.mu.Unlock()
	if in.Pass != nil {
		pass = *in.Pass
	}
	root, err := s.client(addr, "", strings.TrimSpace(in.User), pass)
	if err != nil {
		return Status{}, err
	}
	if err := root.Check(ctx); err != nil {
		return Status{}, err
	}
	if err := root.MkdirAll(ctx, folder); err != nil {
		return Status{}, err
	}
	sealed := ""
	if pass != "" {
		if s.Seal == nil {
			return Status{}, errors.New("无法安全保存密码")
		}
		if sealed, err = s.Seal(pass); err != nil {
			return Status{}, err
		}
	}
	s.mu.Lock()
	if s.cfg.URL != addr || s.cfg.Folder != folder || s.cfg.User != strings.TrimSpace(in.User) {
		// Another remote: nothing agreed with the old one applies.
		s.cfg.Base, s.cfg.StateHash, s.cfg.Last = nil, "", nil
	}
	if s.cfg.Media && !in.Media {
		// Media now stay out of the sync: forget them so they are never
		// read as deleted on this device.
		for p := range s.cfg.Base {
			if IsMedia(p) {
				delete(s.cfg.Base, p)
			}
		}
	}
	s.cfg.URL, s.cfg.User, s.cfg.Pass, s.cfg.Folder = addr, strings.TrimSpace(in.User), sealed, folder
	s.cfg.Auto, s.cfg.Media, s.pass = in.Auto, in.Media, pass
	s.saveLocked()
	s.mu.Unlock()
	s.publish("sync_changed", map[string]string{"what": "configure"})
	return s.Status(), nil
}

// SetAuto turns automatic sync on or off without checking the account.
func (s *Service) SetAuto(auto bool) Status {
	s.mu.Lock()
	s.loadLocked()
	s.cfg.Auto = auto
	s.saveLocked()
	s.mu.Unlock()
	return s.Status()
}

// Disconnect forgets the account; files on both sides stay.
func (s *Service) Disconnect() {
	s.mu.Lock()
	s.loadLocked()
	s.cfg = config{DeviceID: s.cfg.DeviceID, Folder: "LookStudio"}
	s.pass = ""
	s.saveLocked()
	s.mu.Unlock()
	s.publish("sync_changed", map[string]string{"what": "disconnect"})
}

func (s *Service) autoOn() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.loadLocked()
	return s.cfg.URL != "" && s.cfg.Auto
}

// Run syncs shortly after start and then every half hour while automatic
// sync is on.
func (s *Service) Run(ctx context.Context) {
	s.cleanImports(24 * time.Hour)
	select {
	case <-ctx.Done():
		return
	case <-time.After(20 * time.Second):
	}
	t := time.NewTicker(autoEvery)
	defer t.Stop()
	for {
		if s.autoOn() {
			s.runLogged(ctx)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// Soon syncs a little after local changes, coalescing bursts of saves.
func (s *Service) Soon(ctx context.Context) {
	if !s.autoOn() {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.timer != nil {
		s.timer.Stop()
	}
	s.timer = time.AfterFunc(autoDelay, func() { s.runLogged(ctx) })
}

func (s *Service) runLogged(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Hour)
	defer cancel()
	if _, err := s.Sync(ctx); err != nil && !errors.Is(err, ErrBusy) {
		slog.Warn("webdav sync", "err", err)
	}
}

func (s *Service) setProgress(p *Progress) {
	s.mu.Lock()
	s.progress = p
	s.mu.Unlock()
	if p != nil {
		s.publish("sync_progress", p)
	}
}
