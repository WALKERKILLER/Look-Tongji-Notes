// Package canvas reads courses, assignments, announcements and files from a
// Canvas LMS instance (canvas.tongji.edu.cn, Fudan's elearning.fudan.edu.cn
// or any other) with either the student's web session, obtained through the
// school's single sign-on, or an access token.
// Contract: docs/specs/0011-canvas-and-schools.md
package canvas

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

var (
	// ErrAuth means Canvas rejected the session or token.
	ErrAuth = errors.New("Canvas 登录已失效")
	// ErrIdP means single sign-on stopped at the identity provider, which
	// wants credentials again.
	ErrIdP = errors.New("统一身份认证需要重新登录")
)

// Client talks to one Canvas instance.
type Client struct {
	Base  string       // e.g. https://canvas.tongji.edu.cn
	HC    *http.Client // carries the web session cookies when Token is empty
	Token string
}

func (c *Client) do(ctx context.Context, method, path string, form url.Values) (*http.Response, error) {
	u := path
	if !strings.HasPrefix(path, "http") {
		u = c.Base + path
	}
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	req, err := http.NewRequestWithContext(ctx, method, u, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json+canvas-string-ids, application/json")
	req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")
	if form != nil {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	if c.Token != "" {
		req.Header.Set("Authorization", "Bearer "+c.Token)
	} else if method != http.MethodGet {
		// Canvas checks a session's writes against its CSRF cookie.
		req.Header.Set("X-CSRF-Token", c.csrf())
		req.Header.Set("X-Requested-With", "XMLHttpRequest")
	}
	hc := c.HC
	if hc == nil {
		hc = http.DefaultClient
	}
	session := c.Token == "" && strings.HasPrefix(req.URL.Path, "/api/")
	if session {
		// An expired session is redirected into the sign-in flow, which may
		// end anywhere; stop at the first redirect instead.
		cp := *hc
		cp.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
		hc = &cp
	}
	resp, err := hc.Do(req)
	if err != nil {
		return nil, err
	}
	// Without a signed-in user Canvas answers 401 for most of the API but
	// 404 for /users/self, which has no user to resolve.
	if resp.StatusCode == http.StatusUnauthorized || (session && resp.StatusCode >= 300 && resp.StatusCode < 400) ||
		(resp.StatusCode == http.StatusNotFound && req.URL.Path == "/api/v1/users/self") ||
		(c.Token == "" && strings.HasPrefix(resp.Request.URL.Path, "/login")) {
		resp.Body.Close()
		return nil, ErrAuth
	}
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		resp.Body.Close()
		return nil, &HTTPError{Code: resp.StatusCode, Path: req.URL.Path, Body: strings.TrimSpace(string(b))}
	}
	return resp, nil
}

// HTTPError is a Canvas API failure other than authentication.
type HTTPError struct {
	Code int
	Path string
	Body string
}

func (e *HTTPError) Error() string { return fmt.Sprintf("Canvas %s: HTTP %d", e.Path, e.Code) }

func (c *Client) csrf() string {
	if c.HC == nil || c.HC.Jar == nil {
		return ""
	}
	u, _ := url.Parse(c.Base + "/")
	for _, k := range c.HC.Jar.Cookies(u) {
		if k.Name == "_csrf_token" {
			v, _ := url.QueryUnescape(k.Value)
			return v
		}
	}
	return ""
}

func (c *Client) getJSON(ctx context.Context, path string, out any) error {
	resp, err := c.do(ctx, http.MethodGet, path, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return decodeJSON(resp.Body, out)
}

// Canvas prefixes JSON with "while(1);" for session requests.
func decodeJSON(r io.Reader, out any) error {
	b, err := io.ReadAll(io.LimitReader(r, 32<<20))
	if err != nil {
		return err
	}
	b = []byte(strings.TrimPrefix(string(b), "while(1);"))
	return json.Unmarshal(b, out)
}

var nextLink = regexp.MustCompile(`<([^>]+)>;\s*rel="next"`)

// getAll follows Link: rel="next" pages (at most 50).
func getAll[T any](ctx context.Context, c *Client, path string) ([]T, error) {
	var out []T
	for page := 0; path != "" && page < 50; page++ {
		resp, err := c.do(ctx, http.MethodGet, path, nil)
		if err != nil {
			return out, err
		}
		var items []T
		err = decodeJSON(resp.Body, &items)
		resp.Body.Close()
		if err != nil {
			return out, err
		}
		out = append(out, items...)
		path = ""
		if m := nextLink.FindStringSubmatch(resp.Header.Get("Link")); m != nil {
			path = m[1]
		}
	}
	return out, nil
}

type User struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	ShortName string `json:"short_name"`
}

type Term struct {
	Name string `json:"name"`
}

type Course struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	CourseCode string `json:"course_code"`
	Term       *Term  `json:"term,omitempty"`
}

type Submission struct {
	WorkflowState string     `json:"workflow_state"` // unsubmitted | submitted | graded | pending_review
	SubmittedAt   *time.Time `json:"submitted_at"`
	Score         *float64   `json:"score"`
	Late          bool       `json:"late"`
	Missing       bool       `json:"missing"`
}

type Assignment struct {
	ID              string      `json:"id"`
	CourseID        string      `json:"course_id"`
	Name            string      `json:"name"`
	DueAt           *time.Time  `json:"due_at"`
	LockAt          *time.Time  `json:"lock_at"`
	HTMLURL         string      `json:"html_url"`
	PointsPossible  *float64    `json:"points_possible"`
	SubmissionTypes []string    `json:"submission_types"`
	Submission      *Submission `json:"submission,omitempty"`
}

// Submitted reports whether the student handed it in (or it was graded).
func (a Assignment) Submitted() bool {
	if a.Submission == nil {
		return false
	}
	switch a.Submission.WorkflowState {
	case "submitted", "graded", "pending_review":
		return true
	}
	return a.Submission.SubmittedAt != nil
}

type Announcement struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Message     string     `json:"message"`
	PostedAt    *time.Time `json:"posted_at"`
	ContextCode string     `json:"context_code"` // course_<id>
	HTMLURL     string     `json:"html_url"`
	Author      struct {
		DisplayName string `json:"display_name"`
	} `json:"author"`
}

type File struct {
	ID          string     `json:"id"`
	DisplayName string     `json:"display_name"`
	ContentType string     `json:"content-type"`
	Size        int64      `json:"size"`
	UpdatedAt   *time.Time `json:"updated_at"`
	URL         string     `json:"url,omitempty"`
	Locked      bool       `json:"locked_for_user"`
	Module      string     `json:"module,omitempty"` // when listed from modules
}

type moduleItem struct {
	Type      string `json:"type"`
	Title     string `json:"title"`
	ContentID string `json:"content_id"`
}

type module struct {
	Name  string       `json:"name"`
	Items []moduleItem `json:"items"`
}

func (c *Client) Self(ctx context.Context) (User, error) {
	var u User
	return u, c.getJSON(ctx, "/api/v1/users/self", &u)
}

func (c *Client) Courses(ctx context.Context) ([]Course, error) {
	return getAll[Course](ctx, c, "/api/v1/courses?enrollment_state=active&include[]=term&per_page=100")
}

func (c *Client) Assignments(ctx context.Context, courseID string) ([]Assignment, error) {
	return getAll[Assignment](ctx, c, "/api/v1/courses/"+url.PathEscape(courseID)+"/assignments?include[]=submission&order_by=due_at&per_page=100")
}

// Announcements lists announcements of the given courses posted since since.
func (c *Client) Announcements(ctx context.Context, courseIDs []string, since time.Time) ([]Announcement, error) {
	var out []Announcement
	for i := 0; i < len(courseIDs); i += 10 {
		q := url.Values{"start_date": {since.UTC().Format(time.RFC3339)}, "end_date": {time.Now().Add(24 * time.Hour).UTC().Format(time.RFC3339)}, "per_page": {"50"}}
		for _, id := range courseIDs[i:min(i+10, len(courseIDs))] {
			q.Add("context_codes[]", "course_"+id)
		}
		page, err := getAll[Announcement](ctx, c, "/api/v1/announcements?"+q.Encode())
		if err != nil {
			return out, err
		}
		out = append(out, page...)
	}
	return out, nil
}

// Files lists a course's files, newest first. Courses that hide the Files
// page from students still list files placed in modules.
func (c *Client) Files(ctx context.Context, courseID string) ([]File, error) {
	fs, err := getAll[File](ctx, c, "/api/v1/courses/"+url.PathEscape(courseID)+"/files?sort=updated_at&order=desc&per_page=100")
	var he *HTTPError
	if err == nil || !errors.As(err, &he) || (he.Code != http.StatusForbidden && he.Code != http.StatusNotFound) {
		return fs, err
	}
	mods, err := getAll[module](ctx, c, "/api/v1/courses/"+url.PathEscape(courseID)+"/modules?include[]=items&per_page=50")
	if err != nil {
		return nil, err
	}
	var out []File
	for _, m := range mods {
		for _, it := range m.Items {
			if it.Type == "File" && it.ContentID != "" {
				out = append(out, File{ID: it.ContentID, DisplayName: it.Title, Module: m.Name})
			}
		}
	}
	return out, nil
}

// File returns one file with a fresh download URL.
func (c *Client) File(ctx context.Context, id string) (File, error) {
	var f File
	return f, c.getJSON(ctx, "/api/v1/files/"+url.PathEscape(id), &f)
}

// Open streams a file's content.
func (c *Client) Open(ctx context.Context, f File) (io.ReadCloser, error) {
	if f.URL == "" {
		return nil, errors.New("文件没有下载地址（可能被教师锁定）")
	}
	// Large files outlast the API client's timeout; ctx bounds the download.
	long := *c
	if c.HC != nil {
		hc := *c.HC
		hc.Timeout = 0
		long.HC = &hc
	}
	resp, err := long.do(ctx, http.MethodGet, f.URL, nil)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}

// Token is an access token Canvas just created; Secret is shown only once.
type Token struct {
	ID        string     `json:"id"`
	Secret    string     `json:"token"`
	ExpiresAt *time.Time `json:"expires_at"`
}

// CreateToken makes an access token for the signed-in user.
func (c *Client) CreateToken(ctx context.Context, purpose string, expires time.Time) (Token, error) {
	form := url.Values{"token[purpose]": {purpose}, "token[expires_at]": {expires.UTC().Format(time.RFC3339)}}
	resp, err := c.do(ctx, http.MethodPost, "/api/v1/users/self/tokens", form)
	if err != nil {
		return Token{}, err
	}
	defer resp.Body.Close()
	var t Token
	if err := decodeJSON(resp.Body, &t); err != nil {
		return t, err
	}
	if t.Secret == "" {
		return t, errors.New("Canvas 没有返回令牌")
	}
	return t, nil
}

// DeleteToken revokes a token by id.
func (c *Client) DeleteToken(ctx context.Context, id string) error {
	resp, err := c.do(ctx, http.MethodDelete, "/api/v1/users/self/tokens/"+url.PathEscape(id), nil)
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

// OIDCSignIn opens Canvas's OpenID Connect login with hc's cookies. With a
// live identity-provider session the redirects end on Canvas, signed in;
// otherwise they stop at the provider and ErrIdP is returned.
func OIDCSignIn(ctx context.Context, hc *http.Client, base string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/login/openid_connect", nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")
	resp, err := hc.Do(req)
	if err != nil {
		return fmt.Errorf("打开 Canvas 登录失败: %w", err)
	}
	io.Copy(io.Discard, io.LimitReader(resp.Body, 4<<20))
	resp.Body.Close()
	b, _ := url.Parse(base)
	final := resp.Request.URL
	if final.Host != b.Host {
		return ErrIdP
	}
	if strings.HasPrefix(final.Path, "/login") {
		return fmt.Errorf("Canvas 没有完成登录（停在 %s）", final.Path)
	}
	return nil
}
