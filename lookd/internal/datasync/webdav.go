package datasync

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Client speaks the part of WebDAV (RFC 4918) the sync needs: PROPFIND to
// check access, MKCOL, GET, PUT with If-Match, DELETE. Paths are relative
// to Base, slash separated and unescaped.
type Client struct {
	Base       *url.URL // a collection, ending in "/"
	User, Pass string
	HC         *http.Client

	mkMu sync.Mutex // parallel uploads into one new folder create it once
	made map[string]bool
}

// HTTPError is a failed WebDAV request.
type HTTPError struct {
	Method, Path string
	Status       int
	RetryAfter   time.Duration
	Edge         bool // answered by Cloudflare, not the WebDAV server
}

var davActions = map[string]string{"PROPFIND": "列出", "MKCOL": "新建文件夹", "GET": "下载", "PUT": "上传", "DELETE": "删除"}

func (e *HTTPError) Error() string {
	switch e.Status {
	case http.StatusUnauthorized:
		return "WebDAV 账号或应用密码不正确"
	case http.StatusForbidden:
		what := strings.TrimSpace(davActions[e.Method] + " " + strings.Trim(e.Path, "/"))
		if e.Edge {
			return fmt.Sprintf("Cloudflare 拦截了同步请求（%s）。请在 Cloudflare 里为这个 WebDAV 域名放行 WebDAV 请求（WAF 或机器人防护规则）", what)
		}
		return fmt.Sprintf("WebDAV 服务器不允许%s（HTTP 403）。请确认这个账号对同步目录有读取、新建、修改和删除权限", what)
	case http.StatusTooManyRequests, http.StatusServiceUnavailable:
		return "WebDAV 服务器暂时限制了请求次数，稍后会自动继续"
	case http.StatusInsufficientStorage:
		return "网盘空间不足"
	case http.StatusRequestEntityTooLarge:
		return fmt.Sprintf("%s 超过了服务器允许的单个文件大小", e.Path)
	}
	return fmt.Sprintf("WebDAV %s %s 失败（HTTP %d）", e.Method, e.Path, e.Status)
}

// Fatal errors stop the whole run; others only fail one file.
func (e *HTTPError) Fatal() bool {
	switch e.Status {
	case http.StatusUnauthorized, http.StatusForbidden, http.StatusTooManyRequests,
		http.StatusServiceUnavailable, http.StatusInsufficientStorage:
		return true
	}
	return false
}

var (
	ErrNotFound = errors.New("not found")
	// ErrChanged is a failed If-Match: another device wrote first.
	ErrChanged = errors.New("remote changed")
)

func (c *Client) url(p string) string {
	segs := strings.Split(strings.Trim(p, "/"), "/")
	for i, s := range segs {
		segs[i] = url.PathEscape(s)
	}
	return strings.TrimSuffix(c.Base.String(), "/") + "/" + strings.Join(segs, "/")
}

func (c *Client) do(ctx context.Context, method, p string, body io.Reader, size int64, hdr map[string]string) (*http.Response, error) {
	target := c.url(p)
	if p == "" {
		target = c.Base.String()
	}
	req, err := http.NewRequestWithContext(ctx, method, target, body)
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.ContentLength = size
	}
	if c.User != "" || c.Pass != "" {
		req.SetBasicAuth(c.User, c.Pass)
	}
	req.Header.Set("User-Agent", "LookStudio-Sync/1")
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	hc := c.HC
	if hc == nil {
		hc = http.DefaultClient
	}
	return hc.Do(req)
}

func failed(method, p string, resp *http.Response) error {
	io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	resp.Body.Close()
	e := &HTTPError{Method: method, Path: p, Status: resp.StatusCode, Edge: edge(resp)}
	if s, err := strconv.Atoi(resp.Header.Get("Retry-After")); err == nil {
		e.RetryAfter = time.Duration(s) * time.Second
	}
	return e
}

// edge reports an answer of Cloudflare itself (a WAF block or a challenge
// page) rather than of the server behind it.
func edge(resp *http.Response) bool {
	return resp.Header.Get("Cf-Mitigated") != "" ||
		strings.EqualFold(resp.Header.Get("Server"), "cloudflare") && strings.HasPrefix(resp.Header.Get("Content-Type"), "text/html")
}

func ok(resp *http.Response) bool { return resp.StatusCode >= 200 && resp.StatusCode < 300 }

// Check confirms the account can list Base.
func (c *Client) Check(ctx context.Context) error {
	_, err := c.exists(ctx, "")
	return err
}

// exists lists p (a collection) without its members.
func (c *Client) exists(ctx context.Context, p string) (bool, error) {
	body := `<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>`
	resp, err := c.do(ctx, "PROPFIND", p, strings.NewReader(body), int64(len(body)),
		map[string]string{"Depth": "0", "Content-Type": "application/xml; charset=utf-8"})
	if err != nil {
		return false, err
	}
	switch {
	case resp.StatusCode == http.StatusMultiStatus || ok(resp):
		resp.Body.Close()
		return true, nil
	case resp.StatusCode == http.StatusNotFound:
		resp.Body.Close()
		return false, nil
	}
	return false, failed("PROPFIND", "/"+p, resp)
}

// mkcol creates one collection; one that is already there counts as made.
// Servers answer 405 for it, or 403 when the account may not create
// folders (some check the permission before looking).
func (c *Client) mkcol(ctx context.Context, p string) (*http.Response, error) {
	resp, err := c.do(ctx, "MKCOL", p+"/", nil, 0, nil)
	if err != nil || resp.StatusCode != http.StatusForbidden {
		return resp, err
	}
	if there, _ := c.exists(ctx, p+"/"); there {
		resp.Body.Close()
		resp.StatusCode = http.StatusMethodNotAllowed
	}
	return resp, nil
}

// Get opens a file and returns its ETag.
func (c *Client) Get(ctx context.Context, p string) (io.ReadCloser, string, error) {
	resp, err := c.do(ctx, http.MethodGet, p, nil, 0, nil)
	if err != nil {
		return nil, "", err
	}
	if resp.StatusCode == http.StatusNotFound {
		resp.Body.Close()
		return nil, "", ErrNotFound
	}
	if !ok(resp) {
		return nil, "", failed("GET", p, resp)
	}
	return resp.Body, resp.Header.Get("ETag"), nil
}

// Put uploads a file, creating missing parent collections. ifMatch is an
// ETag the file must still have, or "*" for a file that must not exist yet
// when written as If-None-Match; "" writes unconditionally.
func (c *Client) Put(ctx context.Context, p string, open func() (io.ReadCloser, int64, error), ifMatch string) (string, error) {
	for attempt := 0; ; attempt++ {
		body, size, err := open()
		if err != nil {
			return "", err
		}
		hdr := map[string]string{"Content-Type": "application/octet-stream"}
		switch ifMatch {
		case "":
		case "*":
			hdr["If-None-Match"] = "*"
		default:
			hdr["If-Match"] = ifMatch
		}
		resp, err := c.do(ctx, http.MethodPut, p, body, size, hdr)
		body.Close()
		if err != nil {
			return "", err
		}
		switch {
		case ok(resp):
			resp.Body.Close()
			return resp.Header.Get("ETag"), nil
		case resp.StatusCode == http.StatusPreconditionFailed:
			resp.Body.Close()
			return "", ErrChanged
		case (resp.StatusCode == http.StatusConflict || resp.StatusCode == http.StatusNotFound) && attempt == 0:
			resp.Body.Close()
			if err := c.MkdirAll(ctx, parent(p)); err != nil {
				return "", err
			}
		default:
			return "", failed("PUT", p, resp)
		}
	}
}

func parent(p string) string {
	if i := strings.LastIndex(strings.Trim(p, "/"), "/"); i >= 0 {
		return strings.Trim(p, "/")[:i]
	}
	return ""
}

// MkdirAll creates a collection and its parents.
func (c *Client) MkdirAll(ctx context.Context, p string) error {
	p = strings.Trim(p, "/")
	if p == "" {
		return nil
	}
	c.mkMu.Lock()
	defer c.mkMu.Unlock()
	if c.made[p] {
		return nil
	}
	if err := c.mkdirAll(ctx, p); err != nil {
		return err
	}
	if c.made == nil {
		c.made = map[string]bool{}
	}
	for q := p; q != ""; q = parent(q) {
		c.made[q] = true
	}
	return nil
}

func (c *Client) mkdirAll(ctx context.Context, p string) error {
	segs := strings.Split(p, "/")
	// Try the deepest first: usually only the last level is missing.
	for i := len(segs); i >= 1; i-- {
		resp, err := c.mkcol(ctx, strings.Join(segs[:i], "/"))
		if err != nil {
			return err
		}
		switch {
		case ok(resp), resp.StatusCode == http.StatusMethodNotAllowed:
			resp.Body.Close()
			// Created, or already there: make the levels below it.
			for j := i + 1; j <= len(segs); j++ {
				resp, err := c.mkcol(ctx, strings.Join(segs[:j], "/"))
				if err != nil {
					return err
				}
				if !ok(resp) && resp.StatusCode != http.StatusMethodNotAllowed {
					return failed("MKCOL", strings.Join(segs[:j], "/"), resp)
				}
				resp.Body.Close()
			}
			return nil
		case resp.StatusCode == http.StatusConflict:
			resp.Body.Close()
			continue // a parent is missing
		default:
			return failed("MKCOL", strings.Join(segs[:i], "/"), resp)
		}
	}
	return &HTTPError{Method: "MKCOL", Path: p, Status: http.StatusConflict}
}

// Delete removes a file; a missing file is not an error.
func (c *Client) Delete(ctx context.Context, p string) error {
	resp, err := c.do(ctx, http.MethodDelete, p, nil, 0, nil)
	if err != nil {
		return err
	}
	if ok(resp) || resp.StatusCode == http.StatusNotFound {
		resp.Body.Close()
		return nil
	}
	return failed("DELETE", p, resp)
}
