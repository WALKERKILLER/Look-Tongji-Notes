package canvas

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"lookstudio/lookd/internal/notify"
	"lookstudio/lookd/internal/tongji"
)

const (
	tokenLife    = 90 * 24 * time.Hour
	tokenRotate  = 14 * 24 * time.Hour // replace an automatic token this long before it expires
	dueSoon      = 24 * time.Hour
	annWindow    = 30 * 24 * time.Hour
	TokenPurpose = "Look Studio"
)

// Auth provides the Canvas web session used by "sso" mode and for creating
// tokens.
type Auth interface {
	Client() *http.Client
	SignIn(ctx context.Context) error // (re)establish the Canvas web session
}

type Link struct {
	Course string `json:"course"` // Look course id; "" = not linked
	Manual bool   `json:"manual"`
}

// Config is what the user chose; secrets are sealed and never returned.
type Config struct {
	School    string          `json:"school"` // tongji | fudan | other
	Base      string          `json:"base"`
	Mode      string          `json:"mode"` // sso | token
	Token     string          `json:"token,omitempty"`
	TokenID   string          `json:"token_id,omitempty"`
	TokenAuto bool            `json:"token_auto,omitempty"` // created by Look Studio, rotated before expiry
	ExpiresAt *time.Time      `json:"expires_at,omitempty"`
	Username  string          `json:"username,omitempty"`
	Password  string          `json:"password,omitempty"`
	Links     map[string]Link `json:"links,omitempty"`
	Done      map[string]bool `json:"done,omitempty"` // local override of "submitted"
	Hidden    map[string]bool `json:"hidden,omitempty"`
}

type cache struct {
	User          User                    `json:"user"`
	Courses       []Course                `json:"courses"`
	Assignments   map[string][]Assignment `json:"assignments"`
	Announcements []Announcement          `json:"announcements"`
	SyncedAt      int64                   `json:"synced_at"`
	Seen          map[string]bool         `json:"seen"`
}

// Ref is a Look course for automatic linking.
type Ref struct{ ID, Title string }

type Service struct {
	Dir       string
	Transport http.RoundTripper
	AuthFor   func(Config) Auth // nil result: the school has no single sign-on
	Notify    func(notify.Item) bool
	Publish   func(kind string, data any)

	mu        sync.Mutex
	cfg       Config
	cache     cache
	auth      Auth
	syncing   bool
	err       string
	loaded    bool
	signMu    sync.Mutex // one renewal at a time
	renewedAt time.Time
}

func (s *Service) load() {
	if s.loaded {
		return
	}
	s.loaded = true
	if b, err := os.ReadFile(filepath.Join(s.Dir, "canvas.json")); err == nil {
		json.Unmarshal(b, &s.cfg)
	}
	if b, err := os.ReadFile(filepath.Join(s.Dir, "canvas-cache.json")); err == nil {
		json.Unmarshal(b, &s.cache)
	}
}

func writeJSON(path string, v any) {
	b, _ := json.MarshalIndent(v, "", "  ")
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		slog.Warn("canvas: save failed", "err", err)
		return
	}
	os.Rename(tmp, path)
}

func (s *Service) saveCfgLocked()   { writeJSON(filepath.Join(s.Dir, "canvas.json"), s.cfg) }
func (s *Service) saveCacheLocked() { writeJSON(filepath.Join(s.Dir, "canvas-cache.json"), s.cache) }

func (s *Service) publish(kind string, data any) {
	if s.Publish != nil {
		s.Publish(kind, data)
	}
}

// ---- status ----

type CourseView struct {
	Course
	LookCourse string `json:"look_course"`
	Manual     bool   `json:"manual"`
	Open       int    `json:"open"` // assignments not yet submitted with a future due date
	Total      int    `json:"total"`
}

type Status struct {
	Connected  bool         `json:"connected"`
	School     string       `json:"school"`
	Base       string       `json:"base"`
	Mode       string       `json:"mode"`
	User       string       `json:"user"`
	Username   string       `json:"username,omitempty"`
	TokenLast4 string       `json:"token_last4,omitempty"`
	TokenAuto  bool         `json:"token_auto"`
	ExpiresAt  *time.Time   `json:"expires_at,omitempty"`
	Syncing    bool         `json:"syncing"`
	Error      string       `json:"error,omitempty"`
	SyncedAt   int64        `json:"synced_at"`
	RenewedAt  int64        `json:"renewed_at,omitempty"` // last automatic sign-in or token rotation
	Courses    []CourseView `json:"courses"`
}

func (s *Service) Connected() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.load()
	return s.cfg.Base != ""
}

func (s *Service) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.load()
	c := s.cfg
	st := Status{Connected: c.Base != "", School: c.School, Base: c.Base, Mode: c.Mode, User: s.cache.User.Name, Username: c.Username,
		TokenAuto: c.TokenAuto, ExpiresAt: c.ExpiresAt, Syncing: s.syncing, Error: s.err, SyncedAt: s.cache.SyncedAt, Courses: []CourseView{}}
	if !s.renewedAt.IsZero() {
		st.RenewedAt = s.renewedAt.UnixMilli()
	}
	if c.Token != "" {
		if t, err := tongji.Unseal(c.Token); err == nil && len(t) >= 4 {
			st.TokenLast4 = t[len(t)-4:]
		}
	}
	now := time.Now()
	for _, co := range s.cache.Courses {
		v := CourseView{Course: co, LookCourse: c.Links[co.ID].Course, Manual: c.Links[co.ID].Manual}
		for _, a := range s.cache.Assignments[co.ID] {
			v.Total++
			if !s.doneLocked(a) && a.DueAt != nil && a.DueAt.After(now) {
				v.Open++
			}
		}
		st.Courses = append(st.Courses, v)
	}
	return st
}

// ---- connect ----

type ConnectIn struct {
	School   string `json:"school"`
	Base     string `json:"base"`
	Mode     string `json:"mode"`     // sso | token
	Token    string `json:"token"`    // pasted token (mode token)
	Create   bool   `json:"create"`   // mode token: let Look Studio create and rotate one through the web session
	Username string `json:"username"` // fudan
	Password string `json:"password"` // fudan
}

var ErrBadInput = errors.New("bad input")

func (s *Service) Connect(ctx context.Context, in ConnectIn) (Status, error) {
	in.Base = strings.TrimRight(strings.TrimSpace(in.Base), "/")
	if u, err := url.Parse(in.Base); err != nil || u.Scheme != "https" || u.Host == "" || u.Path != "" || u.RawQuery != "" {
		return Status{}, fmt.Errorf("%w: Canvas 地址应为 https:// 开头的站点地址", ErrBadInput)
	}
	cfg := Config{School: in.School, Base: in.Base, Mode: in.Mode, Username: strings.TrimSpace(in.Username)}
	s.mu.Lock()
	s.load()
	cfg.Links, cfg.Done, cfg.Hidden = s.cfg.Links, s.cfg.Done, s.cfg.Hidden
	if s.cfg.Base != cfg.Base {
		cfg.Links, cfg.Done, cfg.Hidden = nil, nil, nil
	}
	old := s.cfg
	s.mu.Unlock()
	if in.Password != "" {
		p, err := tongji.Seal(in.Password)
		if err != nil {
			return Status{}, err
		}
		cfg.Password = p
	} else if old.Username == cfg.Username {
		cfg.Password = old.Password
	}
	auth := s.authFor(cfg)
	switch {
	case cfg.Mode == "sso":
		if auth == nil {
			return Status{}, fmt.Errorf("%w: 这所学校的 Canvas 还不支持统一身份认证登录，请改用访问令牌", ErrBadInput)
		}
		if err := auth.SignIn(ctx); err != nil {
			return Status{}, err
		}
	case cfg.Mode == "token" && in.Token != "":
		t, err := tongji.Seal(strings.TrimSpace(in.Token))
		if err != nil {
			return Status{}, err
		}
		cfg.Token = t
	case cfg.Mode == "token" && in.Create:
		if auth == nil {
			return Status{}, fmt.Errorf("%w: 自动创建令牌需要统一身份认证", ErrBadInput)
		}
		if err := s.createToken(ctx, &cfg, auth); err != nil {
			return Status{}, err
		}
	default:
		return Status{}, fmt.Errorf("%w: 请选择登录方式并填写令牌", ErrBadInput)
	}
	c := s.clientFor(cfg, auth)
	u, err := c.Self(ctx)
	if err != nil {
		return Status{}, fmt.Errorf("连接 Canvas 失败: %w", err)
	}
	s.mu.Lock()
	if old.TokenAuto && old.TokenID != "" && old.TokenID != cfg.TokenID {
		go s.revoke(old, auth)
	}
	s.cfg, s.auth, s.err = cfg, auth, ""
	if s.cache.User.ID != u.ID {
		s.cache = cache{}
	}
	s.cache.User = u
	s.saveCfgLocked()
	s.saveCacheLocked()
	s.mu.Unlock()
	s.publish("canvas_changed", map[string]string{"what": "connect"})
	return s.Status(), nil
}

// Disconnect forgets the connection; an automatic token is revoked.
func (s *Service) Disconnect(ctx context.Context) {
	s.mu.Lock()
	s.load()
	old, auth := s.cfg, s.authLocked()
	s.cfg, s.cache, s.auth, s.err = Config{}, cache{}, nil, ""
	os.Remove(filepath.Join(s.Dir, "canvas.json"))
	os.Remove(filepath.Join(s.Dir, "canvas-cache.json"))
	s.mu.Unlock()
	if old.TokenAuto && old.TokenID != "" {
		s.revoke(old, auth)
	}
	s.publish("canvas_changed", map[string]string{"what": "disconnect"})
	s.publish("schedule_changed", map[string]string{"id": "canvas"})
}

func (s *Service) revoke(old Config, auth Auth) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := s.clientFor(old, auth).DeleteToken(ctx, old.TokenID); err != nil {
		slog.Info("canvas: revoking old token failed", "err", err)
	}
}

func (s *Service) authFor(cfg Config) Auth {
	if s.AuthFor == nil {
		return nil
	}
	return s.AuthFor(cfg)
}

func (s *Service) authLocked() Auth {
	if s.auth == nil && s.cfg.Base != "" {
		s.auth = s.authFor(s.cfg)
	}
	return s.auth
}

func (s *Service) plainClient() *http.Client {
	return &http.Client{Timeout: 60 * time.Second, Transport: s.Transport}
}

func (s *Service) clientFor(cfg Config, auth Auth) *Client {
	if cfg.Mode == "token" {
		t, _ := tongji.Unseal(cfg.Token)
		return &Client{Base: cfg.Base, HC: s.plainClient(), Token: t}
	}
	var hc *http.Client
	if auth != nil {
		hc = auth.Client()
	}
	return &Client{Base: cfg.Base, HC: hc}
}

// createToken makes a token through the web session and stores it in cfg.
func (s *Service) createToken(ctx context.Context, cfg *Config, auth Auth) error {
	c := &Client{Base: cfg.Base, HC: auth.Client()}
	prime := func() error {
		resp, err := c.do(ctx, http.MethodGet, "/profile/settings", nil) // sets _csrf_token
		if err == nil {
			io.Copy(io.Discard, io.LimitReader(resp.Body, 4<<20))
			resp.Body.Close()
		}
		return err
	}
	if err := prime(); errors.Is(err, ErrAuth) {
		if err := auth.SignIn(ctx); err != nil {
			return err
		}
		if err := prime(); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	t, err := c.CreateToken(ctx, TokenPurpose, time.Now().Add(tokenLife))
	if err != nil {
		return fmt.Errorf("创建 Canvas 令牌失败: %w", err)
	}
	sealed, err := tongji.Seal(t.Secret)
	if err != nil {
		return err
	}
	cfg.Token, cfg.TokenID, cfg.TokenAuto, cfg.ExpiresAt = sealed, t.ID, true, t.ExpiresAt
	return nil
}

// ---- sync ----

var ErrNotConnected = errors.New("尚未连接 Canvas")

// call runs f with a client and recovers once from an expired session or
// token: the web session signs in again, an automatic token is recreated.
// A 404 may also mean the session is gone (Canvas hides what an anonymous
// user cannot see), so it is checked against /users/self, and a call that
// raced another call's renewal retries. Network errors
// and 5xx/429 answers are retried once after a short pause.
func (s *Service) call(ctx context.Context, f func(*Client) error) error {
	s.mu.Lock()
	s.load()
	cfg, auth := s.cfg, s.authLocked()
	s.mu.Unlock()
	if cfg.Base == "" {
		return ErrNotConnected
	}
	run := func() error {
		started := time.Now()
		s.mu.Lock()
		cfg := s.cfg
		s.mu.Unlock()
		c := s.clientFor(cfg, auth)
		err := f(c)
		if transient(ctx, err) {
			select {
			case <-time.After(2 * time.Second):
			case <-ctx.Done():
				return ctx.Err()
			}
			err = f(c)
		}
		var he *HTTPError
		if errors.As(err, &he) && he.Code == http.StatusNotFound {
			// Gone, or renewed by another call while this one ran.
			_, serr := c.Self(ctx)
			s.mu.Lock()
			renewed := s.renewedAt.After(started)
			s.mu.Unlock()
			if errors.Is(serr, ErrAuth) || renewed {
				return ErrAuth
			}
		}
		return err
	}
	err := run()
	if !errors.Is(err, ErrAuth) {
		return err
	}
	if err := s.renew(ctx, cfg, auth); err != nil {
		return err
	}
	return run()
}

// transient reports errors worth one more try.
func transient(ctx context.Context, err error) bool {
	if err == nil || ctx.Err() != nil || errors.Is(err, ErrAuth) {
		return false
	}
	var he *HTTPError
	if errors.As(err, &he) {
		return he.Code >= 500 || he.Code == http.StatusTooManyRequests
	}
	var ne net.Error
	return errors.As(err, &ne) || errors.Is(err, io.ErrUnexpectedEOF)
}

// renew restores access after Canvas rejected the session or token. Calls
// that fail together share one renewal: a caller that waited for another's
// fresh renewal just retries.
func (s *Service) renew(ctx context.Context, cfg Config, auth Auth) error {
	s.signMu.Lock()
	defer s.signMu.Unlock()
	s.mu.Lock()
	recent := time.Since(s.renewedAt) < 30*time.Second
	s.mu.Unlock()
	if recent {
		return nil
	}
	switch {
	case cfg.Mode == "sso" && auth != nil:
		if err := auth.SignIn(ctx); err != nil {
			return err
		}
		// The sign-in can end on Canvas without a usable session (for
		// example a consent page); say so instead of failing every call.
		if _, err := s.clientFor(cfg, auth).Self(ctx); errors.Is(err, ErrAuth) {
			return errors.New("已重新登录统一身份认证，但 Canvas 仍未识别会话；稍后会自动重试，也可以改用访问令牌")
		} else if err != nil {
			return err
		}
	case cfg.Mode == "token" && cfg.TokenAuto && auth != nil:
		if err := s.rotate(ctx, cfg, auth); err != nil {
			return err
		}
	default:
		return fmt.Errorf("Canvas 访问令牌已失效或被撤销，请重新粘贴令牌")
	}
	s.mu.Lock()
	s.renewedAt = time.Now()
	s.mu.Unlock()
	slog.Info("canvas: access renewed", "mode", cfg.Mode)
	return nil
}

func (s *Service) rotate(ctx context.Context, old Config, auth Auth) error {
	cfg := old
	if err := s.createToken(ctx, &cfg, auth); err != nil {
		return err
	}
	s.mu.Lock()
	if s.cfg.Base == old.Base {
		s.cfg.Token, s.cfg.TokenID, s.cfg.ExpiresAt = cfg.Token, cfg.TokenID, cfg.ExpiresAt
		s.saveCfgLocked()
	}
	s.mu.Unlock()
	if old.TokenID != "" {
		s.revoke(cfg.withID(old.TokenID), auth)
	}
	slog.Info("canvas: token rotated")
	return nil
}

// withID returns cfg whose credentials delete the token id (the new token
// may revoke the old one).
func (c Config) withID(id string) Config { c.TokenID = id; return c }

// Sync refreshes courses, assignments and announcements and raises
// notifications for what is new.
func (s *Service) Sync(ctx context.Context) error {
	s.mu.Lock()
	s.load()
	if s.cfg.Base == "" {
		s.mu.Unlock()
		return ErrNotConnected
	}
	if s.syncing {
		s.mu.Unlock()
		return nil
	}
	s.syncing = true
	cfg, auth := s.cfg, s.authLocked()
	first := s.cache.SyncedAt == 0
	s.mu.Unlock()
	s.publish("canvas_changed", map[string]string{"what": "syncing"})

	err := func() error {
		if cfg.Mode == "token" && cfg.TokenAuto && auth != nil && cfg.ExpiresAt != nil && time.Until(*cfg.ExpiresAt) < tokenRotate {
			if err := s.rotate(ctx, cfg, auth); err != nil {
				return err
			}
		}
		var (
			u    User
			cs   []Course
			as   = map[string][]Assignment{}
			anns []Announcement
		)
		err := s.call(ctx, func(c *Client) error {
			var err error
			if u, err = c.Self(ctx); err != nil {
				return err
			}
			if cs, err = c.Courses(ctx); err != nil {
				return err
			}
			ids := make([]string, 0, len(cs))
			for _, co := range cs {
				a, err := c.Assignments(ctx, co.ID)
				var he *HTTPError
				if errors.As(err, &he) {
					continue // a course can hide assignments from students
				} else if err != nil {
					return err
				}
				as[co.ID] = a
				ids = append(ids, co.ID)
			}
			anns, err = c.Announcements(ctx, ids, time.Now().Add(-annWindow))
			var he *HTTPError
			if errors.As(err, &he) {
				err = nil
			}
			return err
		})
		if err != nil {
			return err
		}
		s.mu.Lock()
		changed := assignmentsChanged(s.cache.Assignments, as)
		s.cache.User, s.cache.Courses, s.cache.Assignments, s.cache.Announcements = u, cs, as, anns
		s.cache.SyncedAt = time.Now().UnixMilli()
		items := s.newsLocked(first)
		s.saveCacheLocked()
		s.mu.Unlock()
		for _, it := range items {
			if s.Notify != nil {
				s.Notify(it)
			}
		}
		if changed {
			s.publish("schedule_changed", map[string]string{"id": "canvas"})
		}
		return nil
	}()
	s.mu.Lock()
	s.syncing = false
	if err != nil {
		s.err = err.Error()
	} else {
		s.err = ""
	}
	s.mu.Unlock()
	s.publish("canvas_changed", map[string]string{"what": "synced"})
	return err
}

func assignmentsChanged(a, b map[string][]Assignment) bool {
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	return string(ja) != string(jb)
}

var tagRe = regexp.MustCompile(`<[^>]*>`)

func plain(html string, n int) string {
	t := strings.Join(strings.Fields(tagRe.ReplaceAllString(html, " ")), " ")
	t = strings.NewReplacer("&nbsp;", " ", "&amp;", "&", "&lt;", "<", "&gt;", ">", "&quot;", `"`).Replace(t)
	if utf8.RuneCountInString(t) > n {
		t = string([]rune(t)[:n]) + "…"
	}
	return t
}

// newsLocked lists notifications for unseen assignments, assignments due
// within a day and unseen announcements. The first sync only marks
// everything seen.
func (s *Service) newsLocked(first bool) []notify.Item {
	if s.cache.Seen == nil {
		s.cache.Seen = map[string]bool{}
	}
	seen := map[string]bool{}
	var out []notify.Item
	now := time.Now()
	names := map[string]string{}
	for _, co := range s.cache.Courses {
		names[co.ID] = co.Name
	}
	mark := func(key string, it notify.Item) {
		seen[key] = true
		if !s.cache.Seen[key] && !first {
			it.ID, it.At = "canvas:"+key, now.UnixMilli()
			out = append(out, it)
		}
	}
	for cid, as := range s.cache.Assignments {
		look := s.cfg.Links[cid].Course
		for _, a := range as {
			if s.cfg.Hidden["canvas:"+a.ID] {
				continue
			}
			body := names[cid]
			if a.DueAt != nil {
				body += " · 截止 " + a.DueAt.In(shanghai).Format("1月2日 15:04")
			}
			mark("a:"+a.ID, notify.Item{Kind: "assignment_new", Title: "新作业：" + a.Name, Body: body, CourseID: look, URL: a.HTMLURL})
			if a.DueAt != nil && !s.doneLocked(a) && a.DueAt.After(now) && a.DueAt.Sub(now) < dueSoon {
				// Not suppressed on the first sync: a deadline tomorrow is news.
				key := "due:" + a.ID
				seen[key] = true
				if !s.cache.Seen[key] {
					out = append(out, notify.Item{ID: "canvas:" + key, Kind: "assignment_due", Title: "作业即将截止：" + a.Name,
						Body: body, CourseID: look, URL: a.HTMLURL, At: now.UnixMilli()})
				}
			}
		}
	}
	for _, an := range s.cache.Announcements {
		cid := strings.TrimPrefix(an.ContextCode, "course_")
		mark("n:"+an.ID, notify.Item{Kind: "announcement", Title: "课程公告：" + an.Title,
			Body: names[cid] + " · " + plain(an.Message, 80), CourseID: s.cfg.Links[cid].Course, URL: an.HTMLURL})
	}
	s.cache.Seen = seen
	return out
}

var shanghai = func() *time.Location {
	if l, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return l
	}
	return time.FixedZone("CST", 8*3600)
}()

func (s *Service) doneLocked(a Assignment) bool {
	if v, ok := s.cfg.Done["canvas:"+a.ID]; ok {
		return v
	}
	return a.Submitted()
}

// ---- schedule ----

// Item is a Canvas assignment as a schedule entry.
type Item struct {
	ID         string
	Title      string
	Detail     string
	DueDate    string
	DueTime    string
	CourseID   string // linked Look course
	CourseName string // Canvas course
	Done       bool
	URL        string
	UpdatedAt  int64
}

// Items lists assignments with a due date, without hidden ones.
func (s *Service) Items() []Item {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.load()
	if s.cfg.Base == "" {
		return nil
	}
	var out []Item
	for _, co := range s.cache.Courses {
		for _, a := range s.cache.Assignments[co.ID] {
			id := "canvas:" + a.ID
			if a.DueAt == nil || s.cfg.Hidden[id] {
				continue
			}
			d := a.DueAt.In(shanghai)
			detail := co.Name
			if a.PointsPossible != nil && *a.PointsPossible > 0 {
				detail += fmt.Sprintf(" · %g 分", *a.PointsPossible)
			}
			out = append(out, Item{ID: id, Title: a.Name, Detail: detail, DueDate: d.Format("2006-01-02"), DueTime: d.Format("15:04"),
				CourseID: s.cfg.Links[co.ID].Course, CourseName: co.Name, Done: s.doneLocked(a), URL: a.HTMLURL, UpdatedAt: s.cache.SyncedAt})
		}
	}
	return out
}

func (s *Service) findLocked(id string) (Assignment, bool) {
	for _, as := range s.cache.Assignments {
		for _, a := range as {
			if "canvas:"+a.ID == id {
				return a, true
			}
		}
	}
	return Assignment{}, false
}

// SetDone overrides the done state locally; Canvas is not changed.
func (s *Service) SetDone(id string, done bool) (Item, error) {
	s.mu.Lock()
	s.load()
	a, ok := s.findLocked(id)
	if !ok {
		s.mu.Unlock()
		return Item{}, ErrNotFound
	}
	if s.cfg.Done == nil {
		s.cfg.Done = map[string]bool{}
	}
	if done == a.Submitted() {
		delete(s.cfg.Done, id)
	} else {
		s.cfg.Done[id] = done
	}
	s.saveCfgLocked()
	s.mu.Unlock()
	for _, it := range s.Items() {
		if it.ID == id {
			return it, nil
		}
	}
	return Item{}, ErrNotFound
}

var ErrNotFound = errors.New("没有这条 Canvas 作业")

// Hide removes an assignment from the schedule; Unhide puts it back.
func (s *Service) Hide(id string) error { return s.setHidden(id, true) }

func (s *Service) Unhide(id string) error { return s.setHidden(id, false) }

func (s *Service) setHidden(id string, hidden bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.load()
	if _, ok := s.findLocked(id); !ok {
		return ErrNotFound
	}
	if s.cfg.Hidden == nil {
		s.cfg.Hidden = map[string]bool{}
	}
	if hidden {
		s.cfg.Hidden[id] = true
	} else {
		delete(s.cfg.Hidden, id)
	}
	s.saveCfgLocked()
	return nil
}

// ---- links ----

var bracketRe = regexp.MustCompile(`[(（\[【][^)）\]】]*[)）\]】]`)

func normName(s string) string {
	s = strings.ToLower(bracketRe.ReplaceAllString(s, ""))
	return strings.Map(func(r rune) rune {
		if r <= ' ' || strings.ContainsRune(",，。.、:：;；!！?？\"“”'‘’()（）《》<>-_—·/\\", r) {
			return -1
		}
		return r
	}, s)
}

// AutoLink links unlinked Canvas courses to the Look course with the same
// name; manual links stay.
func (s *Service) AutoLink(refs []Ref) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.load()
	if s.cfg.Base == "" {
		return false
	}
	if s.cfg.Links == nil {
		s.cfg.Links = map[string]Link{}
	}
	changed := false
	for _, co := range s.cache.Courses {
		if s.cfg.Links[co.ID].Manual {
			continue
		}
		want := match(co.Name, refs)
		if s.cfg.Links[co.ID].Course != want {
			s.cfg.Links[co.ID] = Link{Course: want}
			changed = true
		}
	}
	if changed {
		s.saveCfgLocked()
	}
	return changed
}

// match picks the one Look course whose name equals or contains the Canvas
// name (or the reverse); ambiguous names stay unlinked.
func match(name string, refs []Ref) string {
	n := normName(name)
	if n == "" {
		return ""
	}
	var exact, part []string
	for _, r := range refs {
		m := normName(r.Title)
		switch {
		case m == "":
		case m == n:
			exact = append(exact, r.ID)
		case utf8.RuneCountInString(m) >= 3 && utf8.RuneCountInString(n) >= 3 && (strings.Contains(n, m) || strings.Contains(m, n)):
			part = append(part, r.ID)
		}
	}
	if len(exact) == 1 {
		return exact[0]
	}
	if len(exact) == 0 && len(part) == 1 {
		return part[0]
	}
	return ""
}

// SetLink links a Canvas course to a Look course ("" unlinks); auto clears
// the manual choice.
func (s *Service) SetLink(canvasID, look string, auto bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.load()
	found := false
	for _, co := range s.cache.Courses {
		found = found || co.ID == canvasID
	}
	if !found {
		return ErrNotFound
	}
	if s.cfg.Links == nil {
		s.cfg.Links = map[string]Link{}
	}
	if auto {
		delete(s.cfg.Links, canvasID)
	} else {
		s.cfg.Links[canvasID] = Link{Course: look, Manual: true}
	}
	s.saveCfgLocked()
	return nil
}

// ---- course detail ----

type AssignmentView struct {
	Assignment
	Done bool `json:"done"`
}

type CourseDetail struct {
	Course        CourseView       `json:"course"`
	Assignments   []AssignmentView `json:"assignments"`
	Announcements []Announcement   `json:"announcements"`
}

// Detail returns a cached course with its assignments and announcements.
func (s *Service) Detail(canvasID string) (CourseDetail, error) {
	st := s.Status()
	s.mu.Lock()
	defer s.mu.Unlock()
	var d CourseDetail
	ok := false
	for _, v := range st.Courses {
		if v.ID == canvasID {
			d.Course, ok = v, true
		}
	}
	if !ok {
		return d, ErrNotFound
	}
	d.Assignments = []AssignmentView{}
	for _, a := range s.cache.Assignments[canvasID] {
		d.Assignments = append(d.Assignments, AssignmentView{Assignment: a, Done: s.doneLocked(a)})
	}
	sort.SliceStable(d.Assignments, func(i, j int) bool {
		a, b := d.Assignments[i].DueAt, d.Assignments[j].DueAt
		if a == nil || b == nil {
			return b == nil && a != nil
		}
		return a.After(*b)
	})
	d.Announcements = []Announcement{}
	for _, an := range s.cache.Announcements {
		if an.ContextCode == "course_"+canvasID {
			d.Announcements = append(d.Announcements, an)
		}
	}
	return d, nil
}

// Files lists a course's files live from Canvas.
func (s *Service) Files(ctx context.Context, canvasID string) ([]File, error) {
	var fs []File
	err := s.call(ctx, func(c *Client) error {
		var err error
		fs, err = c.Files(ctx, canvasID)
		return err
	})
	if fs == nil {
		fs = []File{}
	}
	return fs, err
}

// Download saves a file into dir (created as needed) and returns its path.
// An existing file of the same name and size is kept.
func (s *Service) Download(ctx context.Context, fileID, dir string) (string, error) {
	var path string
	err := s.call(ctx, func(c *Client) error {
		f, err := c.File(ctx, fileID)
		if err != nil {
			return err
		}
		name := safeName(f.DisplayName, "canvas-"+f.ID)
		path = filepath.Join(dir, name)
		if fi, err := os.Stat(path); err == nil && fi.Size() == f.Size {
			return nil
		}
		body, err := c.Open(ctx, f)
		if err != nil {
			return err
		}
		defer body.Close()
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		tmp := path + ".part"
		out, err := os.Create(tmp)
		if err != nil {
			return err
		}
		_, err = io.Copy(out, io.LimitReader(body, 2<<30))
		if cerr := out.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			os.Remove(tmp)
			return err
		}
		return os.Rename(tmp, path)
	})
	return path, err
}

func safeName(s, fallback string) string {
	s = strings.Map(func(r rune) rune {
		if r < ' ' || strings.ContainsRune(`/\:*?"<>|`, r) {
			return '_'
		}
		return r
	}, strings.TrimSpace(s))
	s = strings.Trim(s, ". ")
	if s == "" {
		return fallback
	}
	if r := []rune(s); len(r) > 120 {
		ext := []rune(filepath.Ext(s))
		if len(ext) > 16 {
			ext = nil
		}
		s = string(r[:120-len(ext)]) + string(ext)
	}
	return s
}

// CourseName returns a cached Canvas course name.
func (s *Service) CourseName(canvasID string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, co := range s.cache.Courses {
		if co.ID == canvasID {
			return co.Name
		}
	}
	return ""
}

// LinkedCourse returns the Look course a Canvas course is linked to.
func (s *Service) LinkedCourse(canvasID string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.cfg.Links[canvasID].Course
}
