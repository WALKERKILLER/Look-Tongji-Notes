package tongji

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"lookstudio/lookd/internal/fudan"
)

// Schools whose lecture platform Look Studio signs in to. Both run the same
// product: Tongji's Look is public and uses a JWT; Fudan's iCourse is
// reachable only through WebVPN, whose gateway session (a cookie) carries
// iCourse's own.
const (
	Tongji = "tongji"
	Fudan  = "fudan"
)

// AuthState is reported to the UI.
type AuthState struct {
	Status    string    `json:"status"` // signed_out | active | renewing | needs_password | captcha
	School    string    `json:"school"` // tongji | fudan
	Username  string    `json:"username"`
	Realname  string    `json:"realname"`
	ExpiresAt time.Time `json:"expires_at"`
	RenewedAt time.Time `json:"renewed_at"`
	Method    string    `json:"method"` // how the current token was obtained: password | sso | cache
	Remember  bool      `json:"remember"`
	Error     string    `json:"error,omitempty"`
}

// Session owns the look JWT and keeps it fresh:
//  1. proactive renewal ahead of expiry,
//  2. silent IAM SSO renewal (cookies only) first,
//  3. password re-login as fallback when credentials are remembered.
//
// For Fudan it owns the WebVPN session instead, renewed when a request finds
// it gone: silently while the UIS session lasts, then with the password.
type Session struct {
	mu       sync.Mutex
	jar      *recordingJar
	hc       *http.Client
	api      *http.Client
	path     string
	token    string
	claims   Claims
	state    AuthState
	password string
	renewing chan struct{}
	onChange func(AuthState)
	kick     chan struct{}
}

type persisted struct {
	School   string        `json:"school,omitempty"`
	Username string        `json:"username"`
	Realname string        `json:"realname"`
	Token    string        `json:"token"`
	Method   string        `json:"method"`
	Remember bool          `json:"remember"`
	Password string        `json:"password,omitempty"` // sealed, see seal.go
	Cookies  []savedCookie `json:"cookies"`
}

func NewSession(statePath string, onChange func(AuthState)) *Session {
	jar := newRecordingJar()
	tr := &http.Transport{
		Proxy:               http.ProxyFromEnvironment,
		DialContext:         (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		ForceAttemptHTTP2:   true,
		MaxIdleConnsPerHost: 32,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	s := &Session{
		jar:      jar,
		hc:       &http.Client{Jar: jar, Timeout: 40 * time.Second, Transport: tr},
		api:      &http.Client{Timeout: 30 * time.Second, Transport: tr},
		path:     statePath,
		state:    AuthState{Status: "signed_out"},
		onChange: onChange,
		kick:     make(chan struct{}, 1),
	}
	s.load()
	return s
}

// Client is the HTTP client carrying the IAM single sign-on cookies; other
// Tongji services (such as Canvas) sign in through it.
func (s *Session) Client() *http.Client { return s.hc }

// Transport exposes the shared keep-alive transport for other HTTP users.
func (s *Session) Transport() http.RoundTripper { return s.api.Transport }

func (s *Session) load() {
	b, err := os.ReadFile(s.path)
	if err != nil {
		return
	}
	var p persisted
	if json.Unmarshal(b, &p) != nil {
		return
	}
	s.jar.restore(p.Cookies)
	s.state.School, s.state.Username, s.state.Realname, s.state.Remember = p.School, p.Username, p.Realname, p.Remember
	if p.Password != "" {
		if pw, err := unseal(p.Password); err == nil {
			s.password = pw
		}
	}
	if c, err := ParseJWT(p.Token); err == nil && p.Token != "" {
		s.token, s.claims = p.Token, c
		s.state.ExpiresAt = c.Expiry()
		s.state.Method = "cache"
		s.state.Status = "active"
		if time.Until(c.Expiry()) <= 0 {
			s.state.Status = "renewing"
		}
	}
	if p.School == Fudan && p.Username != "" && len(p.Cookies) > 0 {
		s.state.Status, s.state.Method = "active", "cache"
	}
}

func (s *Session) saveLocked() {
	p := persisted{School: s.state.School, Username: s.state.Username, Realname: s.state.Realname, Token: s.token, Method: s.state.Method,
		Remember: s.state.Remember, Cookies: s.jar.snapshot()}
	if s.state.Remember && s.password != "" {
		if sealed, err := seal(s.password); err == nil {
			p.Password = sealed
		}
	}
	b, _ := json.Marshal(p)
	tmp := s.path + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, s.path)
	}
}

func (s *Session) State() AuthState {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

func (s *Session) setState(f func(*AuthState)) {
	s.mu.Lock()
	f(&s.state)
	st := s.state
	s.saveLocked()
	s.mu.Unlock()
	if s.onChange != nil {
		s.onChange(st)
	}
}

func (s *Session) adopt(tok, method string) {
	c, _ := ParseJWT(tok)
	s.setState(func(st *AuthState) {
		s.token, s.claims = tok, c
		st.Status, st.Method, st.Error = "active", method, ""
		st.ExpiresAt, st.RenewedAt = c.Expiry(), time.Now()
	})
	select {
	case s.kick <- struct{}{}:
	default:
	}
}

// School is the school of the current (or last) sign-in.
func (s *Session) School() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.School == Fudan {
		return Fudan
	}
	return Tongji
}

// Base is the origin of the school's lecture platform.
func (s *Session) Base() string {
	if s.School() == Fudan {
		return fudan.ICourseBase
	}
	return BaseURL
}

// URL is where the daemon fetches a platform address (video, slide image,
// courseware): Fudan's campus hosts go through WebVPN.
func (s *Session) URL(raw string) string {
	if s.School() != Fudan {
		return raw
	}
	u, err := fudan.VPNURL(raw)
	if err != nil {
		return raw
	}
	return u
}

// Header goes with requests for URL's addresses. For Fudan it carries the
// gateway's session cookie, so it never leaves the daemon.
func (s *Session) Header() http.Header {
	h := http.Header{"User-Agent": {UserAgent}, "Referer": {s.URL(s.Base() + "/")}}
	if s.School() == Fudan {
		gw, _ := url.Parse(fudan.WebVPNBase + "/")
		var cs []string
		for _, c := range s.jar.Cookies(gw) {
			cs = append(cs, c.Name+"="+c.Value)
		}
		h.Set("Cookie", strings.Join(cs, "; "))
	}
	return h
}

// Login signs in with a password. remember keeps the password (sealed) on
// disk so renewal works after the IAM SSO session itself expires.
func (s *Session) Login(ctx context.Context, school, username, password, captcha string, remember bool) error {
	s.jar.reset()
	if school == Fudan {
		return s.loginFudan(ctx, username, password, remember)
	}
	tok, err := Login(ctx, s.hc, username, password, captcha)
	if err != nil {
		var le *LoginError
		status := "signed_out"
		if errors.As(err, &le) && errors.Is(le.Kind, ErrCaptchaRequired) {
			status = "captcha"
		}
		s.setState(func(st *AuthState) {
			st.Status, st.Error, st.School, st.Username = status, err.Error(), Tongji, username
		})
		return err
	}
	s.mu.Lock()
	s.password = password
	s.state.School, s.state.Username, s.state.Remember = Tongji, username, remember
	if !remember {
		s.password = ""
	}
	s.mu.Unlock()
	s.adopt(tok, "password")
	go s.fetchRealname()
	return nil
}

func (s *Session) loginFudan(ctx context.Context, username, password string, remember bool) error {
	if err := s.signInFudan(ctx, username, password); err != nil {
		s.setState(func(st *AuthState) {
			st.Status, st.Error, st.School, st.Username = "signed_out", err.Error(), Fudan, username
		})
		return err
	}
	s.mu.Lock()
	s.token, s.claims, s.password = "", Claims{}, password
	if !remember {
		s.password = ""
	}
	s.mu.Unlock()
	s.setState(func(st *AuthState) {
		st.Status, st.Method, st.Error, st.School, st.Username, st.Remember = "active", "password", "", Fudan, username, remember
		st.ExpiresAt, st.RenewedAt = time.Time{}, time.Now()
	})
	go s.fetchRealname()
	return nil
}

// signInFudan runs the WebVPN and iCourse sign-in and checks that iCourse
// answers as the signed-in user.
func (s *Session) signInFudan(ctx context.Context, username, password string) error {
	if err := fudan.SignInICourse(ctx, s.hc, username, password); err != nil {
		return err
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, fudan.ICourseBase+"/userapi/v1/infosimple", nil)
	resp, err := s.viaVPN(ctx, req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var r struct {
		Code any `json:"code"`
	}
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if VPNSignedOut(resp) || json.Unmarshal(b, &r) != nil || !okCode(r.Code) {
		return errors.New("iCourse 没有接受这次登录，请稍后重试")
	}
	return nil
}

func (s *Session) Captcha(ctx context.Context) ([]byte, string, error) {
	if s.School() == Fudan {
		return nil, "", errors.New("复旦 UIS 登录不需要这里的验证码")
	}
	return Captcha(ctx, s.hc)
}

func (s *Session) Logout() {
	s.jar.reset()
	school := s.School()
	s.setState(func(st *AuthState) {
		s.token, s.password = "", ""
		*st = AuthState{Status: "signed_out", School: school}
	})
}

// Token returns a valid JWT, renewing it first when it is close to expiry.
func (s *Session) Token(ctx context.Context) (string, error) {
	s.mu.Lock()
	tok, exp := s.token, s.claims.Expiry()
	s.mu.Unlock()
	if tok != "" && (exp.IsZero() || time.Until(exp) > 2*time.Minute) {
		return tok, nil
	}
	if err := s.Renew(ctx); err != nil {
		return "", err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.token, nil
}

// Renew refreshes the token; concurrent callers share one renewal.
func (s *Session) Renew(ctx context.Context) error {
	s.mu.Lock()
	if s.renewing != nil {
		ch := s.renewing
		s.mu.Unlock()
		select {
		case <-ch:
		case <-ctx.Done():
			return ctx.Err()
		}
		if s.State().Status == "active" {
			return nil
		}
		return errors.New(s.State().Error)
	}
	ch := make(chan struct{})
	s.renewing = ch
	user, pw, school := s.state.Username, s.password, s.state.School
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.renewing = nil
		s.mu.Unlock()
		close(ch)
	}()

	s.setState(func(st *AuthState) { st.Status = "renewing" })
	if school == Fudan {
		return s.renewFudan(ctx, user, pw)
	}
	tok, err := SilentRenew(ctx, s.hc)
	if err == nil {
		s.adopt(tok, "sso")
		slog.Info("token renewed via IAM SSO")
		return nil
	}
	slog.Info("silent renew failed", "err", err)
	if user != "" && pw != "" {
		if tok, err2 := Login(ctx, s.hc, user, pw, ""); err2 == nil {
			s.adopt(tok, "password")
			slog.Info("token renewed via stored credentials")
			return nil
		} else {
			err = err2
		}
	}
	s.setState(func(st *AuthState) { st.Status, st.Error = "needs_password", err.Error() })
	return err
}

// renewFudan signs in again: the empty password first, which works while the
// UIS session lasts, then the remembered one.
func (s *Session) renewFudan(ctx context.Context, user, pw string) error {
	err := s.signInFudan(ctx, user, "")
	method := "sso"
	if errors.Is(err, fudan.ErrNeedsPassword) && pw != "" {
		err, method = s.signInFudan(ctx, user, pw), "password"
	}
	if err != nil {
		if errors.Is(err, fudan.ErrNeedsPassword) {
			err = errors.New("复旦 WebVPN 登录已过期，请重新登录")
		}
		s.setState(func(st *AuthState) { st.Status, st.Error = "needs_password", err.Error() })
		return err
	}
	s.setState(func(st *AuthState) { st.Status, st.Method, st.Error, st.RenewedAt = "active", method, "", time.Now() })
	slog.Info("fudan session renewed", "method", method)
	return nil
}

// Run keeps the token fresh until ctx ends.
func (s *Session) Run(ctx context.Context) {
	for {
		s.mu.Lock()
		exp, has := s.claims.Expiry(), s.token != ""
		status := s.state.Status
		s.mu.Unlock()
		wait := 30 * time.Minute
		if has && !exp.IsZero() {
			// Renew at 80% of the remaining lifetime, at most 6h ahead, never sooner than 30s.
			lead := time.Until(exp) / 5
			if lead > 6*time.Hour {
				lead = 6 * time.Hour
			}
			wait = time.Until(exp) - lead
			if wait < 30*time.Second {
				wait = 30 * time.Second
			}
		}
		if has && status == "renewing" {
			wait = 0
		}
		t := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			t.Stop()
			return
		case <-s.kick:
			t.Stop()
			continue
		case <-t.C:
		}
		if !has || status == "needs_password" {
			continue
		}
		rctx, cancel := context.WithTimeout(ctx, 60*time.Second)
		if err := s.Renew(rctx); err != nil {
			slog.Warn("scheduled renew failed", "err", err)
		}
		cancel()
	}
}

// Do performs an authenticated look API request, renewing once on 401/403
// (for Fudan, also when WebVPN sends it to the gateway's sign-in).
func (s *Session) Do(ctx context.Context, req *http.Request) (*http.Response, error) {
	if s.School() == Fudan {
		for attempt := 0; ; attempt++ {
			resp, err := s.viaVPN(ctx, req)
			if err != nil || !VPNSignedOut(resp) {
				return resp, err
			}
			resp.Body.Close()
			if attempt == 1 {
				return nil, errors.New("复旦 WebVPN 会话无效，请重新登录")
			}
			if err := s.Renew(ctx); err != nil {
				return nil, err
			}
		}
	}
	for attempt := 0; attempt < 2; attempt++ {
		tok, err := s.Token(ctx)
		if err != nil {
			return nil, err
		}
		r := req.Clone(ctx)
		r.Header.Set("Authorization", "Bearer "+tok)
		r.Header.Set("User-Agent", UserAgent)
		r.Header.Set("accept-language", "zh_cn")
		resp, err := s.api.Do(r)
		if err != nil {
			return nil, err
		}
		if (resp.StatusCode == 401 || resp.StatusCode == 403) && attempt == 0 {
			resp.Body.Close()
			if err := s.Renew(ctx); err != nil {
				return nil, err
			}
			continue
		}
		return resp, nil
	}
	return nil, errors.New("unreachable")
}

// viaVPN sends an iCourse request through WebVPN with the gateway cookie.
func (s *Session) viaVPN(ctx context.Context, req *http.Request) (*http.Response, error) {
	u, err := fudan.VPNURL(req.URL.String())
	if err != nil {
		return nil, err
	}
	r := req.Clone(ctx)
	if r.URL, err = url.Parse(u); err != nil {
		return nil, err
	}
	r.Host = ""
	r.Header.Set("User-Agent", UserAgent)
	r.Header.Set("accept-language", "zh_cn")
	resp, err := s.hc.Do(r)
	if err != nil {
		return nil, fmt.Errorf("无法连接复旦 WebVPN: %w", err)
	}
	return resp, nil
}

// VPNSignedOut reports a WebVPN answer that is not the service's: the gateway
// redirects to its sign-in page (or UIS) once its session is gone.
func VPNSignedOut(resp *http.Response) bool {
	return resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden ||
		!strings.HasPrefix(resp.Request.URL.Path, "/http") ||
		strings.Contains(resp.Header.Get("Content-Type"), "text/html")
}

func (s *Session) fetchRealname() {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	c := &Client{S: s}
	if u, err := c.UserInfo(ctx); err == nil && u.Realname != "" {
		s.setState(func(st *AuthState) { st.Realname = u.Realname })
	}
}

// ---- cookie persistence ----

type savedCookie struct {
	URL    string       `json:"url"`
	Cookie *http.Cookie `json:"cookie"`
}

// recordingJar wraps cookiejar.Jar and remembers what was set so the jar
// (including IAM SSO session cookies) survives daemon restarts.
type recordingJar struct {
	mu   sync.Mutex
	jar  *cookiejar.Jar
	seen map[string]savedCookie // key: host|path|name
}

func newRecordingJar() *recordingJar {
	j, _ := cookiejar.New(nil)
	return &recordingJar{jar: j, seen: map[string]savedCookie{}}
}

func (r *recordingJar) SetCookies(u *url.URL, cs []*http.Cookie) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.jar.SetCookies(u, cs)
	for _, c := range cs {
		host := c.Domain
		if host == "" {
			host = u.Hostname()
		}
		k := host + "|" + c.Path + "|" + c.Name
		if c.MaxAge < 0 {
			delete(r.seen, k)
			continue
		}
		cc := *c
		if c.MaxAge > 0 {
			cc.Expires = time.Now().Add(time.Duration(c.MaxAge) * time.Second)
			cc.MaxAge = 0
		}
		r.seen[k] = savedCookie{URL: u.Scheme + "://" + u.Host + "/", Cookie: &cc}
	}
}

func (r *recordingJar) Cookies(u *url.URL) []*http.Cookie {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.jar.Cookies(u)
}

func (r *recordingJar) snapshot() []savedCookie {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]savedCookie, 0, len(r.seen))
	for _, c := range r.seen {
		if !c.Cookie.Expires.IsZero() && c.Cookie.Expires.Before(time.Now()) {
			continue
		}
		out = append(out, c)
	}
	return out
}

func (r *recordingJar) restore(cs []savedCookie) {
	for _, c := range cs {
		if u, err := url.Parse(c.URL); err == nil && c.Cookie != nil {
			r.SetCookies(u, []*http.Cookie{c.Cookie})
		}
	}
}

func (r *recordingJar) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.jar, _ = cookiejar.New(nil)
	r.seen = map[string]savedCookie{}
}
