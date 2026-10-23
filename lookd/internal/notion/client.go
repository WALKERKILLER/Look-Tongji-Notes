// Package notion syncs the library into a Notion workspace through the
// Notion API's Markdown endpoints, with an internal integration token.
// Contract: docs/specs/0013-notion-sync.md
package notion

import (
	"bytes"
	"context"
	"encoding/json"
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

// Version is the Notion API version; Markdown page content needs 2026-03-11.
const Version = "2026-03-11"

const pace = 350 * time.Millisecond // Notion allows about three requests a second

var ErrAuth = errors.New("Notion 令牌无效或已被撤销")

// APIError is an error answer from Notion.
type APIError struct {
	Status  int
	Code    string
	Message string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("Notion %d %s: %s", e.Status, e.Code, e.Message)
}

// gone reports an answer meaning the page no longer exists for us (deleted,
// in the trash, or no longer shared with the integration).
func gone(err error) bool {
	var ae *APIError
	if !errors.As(err, &ae) {
		return false
	}
	return ae.Status == http.StatusNotFound || (ae.Status == http.StatusBadRequest && strings.Contains(strings.ToLower(ae.Message), "trash")) ||
		(ae.Status == http.StatusBadRequest && strings.Contains(strings.ToLower(ae.Message), "archived"))
}

type Client struct {
	Token string
	HC    *http.Client
	Base  string        // default https://api.notion.com
	Pace  time.Duration // between requests; default pace

	mu   sync.Mutex
	last time.Time
}

func (c *Client) wait(ctx context.Context) error {
	c.mu.Lock()
	gap := c.Pace
	if gap == 0 {
		gap = pace
	}
	next := c.last.Add(gap)
	now := time.Now()
	if next.Before(now) {
		next = now
	}
	c.last = next
	c.mu.Unlock()
	select {
	case <-time.After(time.Until(next)):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (c *Client) do(ctx context.Context, method, path string, in, out any) error {
	base := c.Base
	if base == "" {
		base = "https://api.notion.com"
	}
	var body []byte
	if in != nil {
		var err error
		if body, err = json.Marshal(in); err != nil {
			return err
		}
	}
	hc := c.HC
	if hc == nil {
		hc = http.DefaultClient
	}
	for attempt := 0; ; attempt++ {
		if err := c.wait(ctx); err != nil {
			return err
		}
		req, err := http.NewRequestWithContext(ctx, method, base+path, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer "+c.Token)
		req.Header.Set("Notion-Version", Version)
		if in != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		resp, err := hc.Do(req)
		if err != nil {
			if attempt < 2 && ctx.Err() == nil {
				continue
			}
			return err
		}
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
		resp.Body.Close()
		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
			if attempt < 3 {
				delay := time.Duration(1<<attempt) * time.Second
				if s, err := strconv.Atoi(resp.Header.Get("Retry-After")); err == nil && s > 0 {
					delay = time.Duration(s) * time.Second
				}
				select {
				case <-time.After(delay):
					continue
				case <-ctx.Done():
					return ctx.Err()
				}
			}
		}
		if resp.StatusCode == http.StatusUnauthorized {
			return ErrAuth
		}
		if resp.StatusCode >= 400 {
			var e struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			}
			json.Unmarshal(raw, &e)
			return &APIError{Status: resp.StatusCode, Code: e.Code, Message: e.Message}
		}
		if out != nil {
			return json.Unmarshal(raw, out)
		}
		return nil
	}
}

// Bot is the integration behind the token.
type Bot struct {
	Name      string `json:"name"`
	Workspace string `json:"workspace"`
}

func (c *Client) Me(ctx context.Context) (Bot, error) {
	var r struct {
		Name string `json:"name"`
		Bot  struct {
			WorkspaceName string `json:"workspace_name"`
		} `json:"bot"`
	}
	if err := c.do(ctx, http.MethodGet, "/v1/users/me", nil, &r); err != nil {
		return Bot{}, err
	}
	return Bot{Name: r.Name, Workspace: r.Bot.WorkspaceName}, nil
}

// Page is what the sync keeps about a page.
type Page struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	URL     string `json:"url"`
	Icon    string `json:"icon,omitempty"` // emoji, when the page has one
	InTrash bool   `json:"-"`
}

type rawPage struct {
	ID         string                     `json:"id"`
	URL        string                     `json:"url"`
	InTrash    bool                       `json:"in_trash"`
	Properties map[string]json.RawMessage `json:"properties"`
	Icon       *struct {
		Type  string `json:"type"`
		Emoji string `json:"emoji"`
	} `json:"icon"`
}

func (p rawPage) page() Page {
	out := Page{ID: p.ID, URL: p.URL, InTrash: p.InTrash}
	for _, raw := range p.Properties {
		var prop struct {
			Type  string `json:"type"`
			Title []struct {
				PlainText string `json:"plain_text"`
			} `json:"title"`
		}
		if json.Unmarshal(raw, &prop) == nil && prop.Type == "title" {
			for _, t := range prop.Title {
				out.Title += t.PlainText
			}
		}
	}
	if p.Icon != nil && p.Icon.Type == "emoji" {
		out.Icon = p.Icon.Emoji
	}
	return out
}

// Search lists pages shared with the integration whose title matches query.
func (c *Client) Search(ctx context.Context, query string) ([]Page, error) {
	in := map[string]any{"filter": map[string]string{"property": "object", "value": "page"}, "page_size": 30,
		"sort": map[string]string{"direction": "descending", "timestamp": "last_edited_time"}}
	if query = strings.TrimSpace(query); query != "" {
		in["query"] = query
	}
	var r struct {
		Results []rawPage `json:"results"`
	}
	if err := c.do(ctx, http.MethodPost, "/v1/search", in, &r); err != nil {
		return nil, err
	}
	out := []Page{}
	for _, p := range r.Results {
		if !p.InTrash {
			out = append(out, p.page())
		}
	}
	return out, nil
}

func (c *Client) Page(ctx context.Context, id string) (Page, error) {
	var p rawPage
	if err := c.do(ctx, http.MethodGet, "/v1/pages/"+url.PathEscape(id), nil, &p); err != nil {
		return Page{}, err
	}
	return p.page(), nil
}

func titleProp(title string) map[string]any {
	if len([]rune(title)) > 200 {
		title = string([]rune(title)[:200])
	}
	return map[string]any{"title": map[string]any{"title": []any{map[string]any{"type": "text", "text": map[string]string{"content": title}}}}}
}

// Create adds a page under parent with Markdown content.
func (c *Client) Create(ctx context.Context, parent, title, markdown string) (Page, error) {
	var p rawPage
	err := c.do(ctx, http.MethodPost, "/v1/pages", map[string]any{
		"parent":     map[string]string{"page_id": parent},
		"properties": titleProp(title),
		"markdown":   markdown,
	}, &p)
	if err != nil {
		return Page{}, err
	}
	return p.page(), nil
}

// Markdown reads a page's content.
func (c *Client) Markdown(ctx context.Context, id string) (string, error) {
	var r struct {
		Markdown string `json:"markdown"`
	}
	err := c.do(ctx, http.MethodGet, "/v1/pages/"+url.PathEscape(id)+"/markdown", nil, &r)
	return r.Markdown, err
}

// Replace sets a page's whole content; child pages and databases are kept.
func (c *Client) Replace(ctx context.Context, id, markdown string) error {
	return c.do(ctx, http.MethodPatch, "/v1/pages/"+url.PathEscape(id)+"/markdown", map[string]any{
		"type":            "replace_content",
		"replace_content": map[string]any{"new_str": markdown, "allow_deleting_content": false},
	}, nil)
}

func (c *Client) SetTitle(ctx context.Context, id, title string) error {
	return c.do(ctx, http.MethodPatch, "/v1/pages/"+url.PathEscape(id), map[string]any{"properties": titleProp(title)}, nil)
}

// Trash moves a page to the trash (restorable in Notion for 30 days).
func (c *Client) Trash(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodPatch, "/v1/pages/"+url.PathEscape(id), map[string]any{"in_trash": true}, nil)
}
