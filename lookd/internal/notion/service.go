package notion

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"lookstudio/lookd/internal/tongji"
)

// RootTitle is the page the sync creates under the chosen parent.
const RootTitle = "Look Studio 课程库"

const rootBody = "由 Look Studio 同步的课程笔记和转写稿。笔记和转写稿页面在 Notion 里修改后，Look Studio 不会再覆盖它们。\n"

// Doc is one page to sync; parents come before their children.
type Doc struct {
	Key, Parent, Title, Body string
	Container                bool // written once when created, never replaced
}

// entry is what the sync remembers about a page it created.
type entry struct {
	ID     string `json:"id"`
	Parent string `json:"parent,omitempty"` // key of the parent entry
	URL    string `json:"url,omitempty"`
	Title  string `json:"title"`
	Hash   string `json:"hash"` // of the title and Markdown we last wrote
	Seen   string `json:"seen"` // of the Markdown Notion returned right after our write
}

type Result struct {
	At        int64    `json:"at"`
	Created   int      `json:"created"`
	Updated   int      `json:"updated"`
	Unchanged int      `json:"unchanged"`
	Trashed   int      `json:"trashed"`
	Conflicts []string `json:"conflicts"` // pages kept because they were edited in Notion
	Errors    []string `json:"errors"`
	Error     string   `json:"error,omitempty"`
}

type state struct {
	Token   string           `json:"token_sealed,omitempty"`
	Bot     Bot              `json:"bot"`
	Parent  *Page            `json:"parent,omitempty"`
	Auto    bool             `json:"auto"`
	RootID  string           `json:"root_id,omitempty"`
	RootURL string           `json:"root_url,omitempty"`
	Pages   map[string]entry `json:"pages,omitempty"`
	Last    *Result          `json:"last,omitempty"`
}

type Progress struct {
	Done  int `json:"done"`
	Total int `json:"total"`
}

type Status struct {
	Connected  bool      `json:"connected"`
	Bot        Bot       `json:"bot"`
	TokenLast4 string    `json:"token_last4,omitempty"`
	Parent     *Page     `json:"parent,omitempty"`
	RootURL    string    `json:"root_url,omitempty"`
	Auto       bool      `json:"auto"`
	Pages      int       `json:"pages"`
	Running    bool      `json:"running"`
	Progress   *Progress `json:"progress,omitempty"`
	Last       *Result   `json:"last,omitempty"`
}

type Service struct {
	Path    string // notion.json
	HC      *http.Client
	Base    string        // tests
	Pace    time.Duration // tests
	Docs    func(ctx context.Context) ([]Doc, error)
	Publish func(kind string, data any)

	mu       sync.Mutex
	st       state
	token    string
	loaded   bool
	running  bool
	progress *Progress
	syncMu   sync.Mutex
}

var ErrNotConnected = errors.New("尚未连接 Notion")
var ErrNoParent = errors.New("请先选择同步到哪个 Notion 页面")

func (s *Service) loadLocked() {
	if s.loaded {
		return
	}
	s.loaded = true
	if b, err := os.ReadFile(s.Path); err == nil {
		json.Unmarshal(b, &s.st)
	}
	if s.st.Token != "" {
		s.token, _ = tongji.Unseal(s.st.Token)
	}
}

func (s *Service) saveLocked() {
	b, _ := json.MarshalIndent(s.st, "", "  ")
	tmp := s.Path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		slog.Warn("notion: save failed", "err", err)
		return
	}
	os.Rename(tmp, s.Path)
}

func (s *Service) publish(kind string, data any) {
	if s.Publish != nil {
		s.Publish(kind, data)
	}
}

func (s *Service) client(token string) *Client {
	return &Client{Token: token, HC: s.HC, Base: s.Base, Pace: s.Pace}
}

func (s *Service) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.loadLocked()
	st := Status{Connected: s.token != "", Bot: s.st.Bot, Parent: s.st.Parent, RootURL: s.st.RootURL, Auto: s.st.Auto,
		Pages: len(s.st.Pages), Running: s.running, Progress: s.progress, Last: s.st.Last}
	if len(s.token) >= 4 {
		st.TokenLast4 = s.token[len(s.token)-4:]
	}
	return st
}

// AutoOn reports whether notes changes should trigger a sync.
func (s *Service) AutoOn() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.loadLocked()
	return s.token != "" && s.st.Parent != nil && s.st.Auto
}

// Connect checks a token and keeps it sealed.
func (s *Service) Connect(ctx context.Context, token string) (Status, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return Status{}, errors.New("请粘贴 Notion 集成的内部令牌")
	}
	bot, err := s.client(token).Me(ctx)
	if err != nil {
		return Status{}, err
	}
	sealed, err := tongji.Seal(token)
	if err != nil {
		return Status{}, err
	}
	s.mu.Lock()
	s.loadLocked()
	if s.st.Bot.Workspace != bot.Workspace {
		// Another workspace: nothing we created is reachable from it.
		s.st = state{Auto: s.st.Auto}
	}
	s.st.Token, s.st.Bot, s.token = sealed, bot, token
	s.saveLocked()
	s.mu.Unlock()
	s.publish("notion_changed", map[string]string{"what": "connect"})
	return s.Status(), nil
}

// Disconnect forgets the token and what was synced; pages stay in Notion.
func (s *Service) Disconnect() {
	s.mu.Lock()
	s.loadLocked()
	s.st, s.token = state{}, ""
	os.Remove(s.Path)
	s.mu.Unlock()
	s.publish("notion_changed", map[string]string{"what": "disconnect"})
}

// Search lists pages the integration can write into.
func (s *Service) Search(ctx context.Context, q string) ([]Page, error) {
	s.mu.Lock()
	s.loadLocked()
	tok := s.token
	s.mu.Unlock()
	if tok == "" {
		return nil, ErrNotConnected
	}
	return s.client(tok).Search(ctx, q)
}

// Configure sets the parent page (a new parent starts a new tree; the old
// one stays) and automatic sync.
func (s *Service) Configure(ctx context.Context, parentID *string, auto *bool) (Status, error) {
	s.mu.Lock()
	s.loadLocked()
	tok := s.token
	s.mu.Unlock()
	if tok == "" {
		return Status{}, ErrNotConnected
	}
	var parent *Page
	if parentID != nil && *parentID != "" {
		p, err := s.client(tok).Page(ctx, normalizeID(*parentID))
		if err != nil {
			if gone(err) {
				return Status{}, errors.New("找不到这个页面：请在 Notion 中把它分享给集成（页面右上角 ··· → 连接）")
			}
			return Status{}, err
		}
		parent = &p
	}
	s.mu.Lock()
	if parent != nil && (s.st.Parent == nil || s.st.Parent.ID != parent.ID) {
		s.st.Parent, s.st.RootID, s.st.RootURL, s.st.Pages = parent, "", "", nil
	}
	if auto != nil {
		s.st.Auto = *auto
	}
	s.saveLocked()
	s.mu.Unlock()
	s.publish("notion_changed", map[string]string{"what": "config"})
	return s.Status(), nil
}

// normalizeID accepts a page id or a Notion page URL.
func normalizeID(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexAny(s, "?#"); i >= 0 {
		s = s[:i]
	}
	s = s[strings.LastIndex(s, "/")+1:]
	compact := strings.ReplaceAll(s, "-", "")
	if len(compact) >= 32 {
		return compact[len(compact)-32:]
	}
	return s
}

func hash(parts ...string) string {
	h := sha256.New()
	for _, p := range parts {
		h.Write([]byte(p))
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))[:24]
}

// Sync brings the Notion tree up to date with the library. Unchanged pages
// cost no requests; full also checks that every page still exists and
// recreates deleted ones. One runs at a time; a second call while one runs
// returns at once.
func (s *Service) Sync(ctx context.Context, full bool) (Result, error) {
	if !s.syncMu.TryLock() {
		return Result{}, nil
	}
	defer s.syncMu.Unlock()
	s.mu.Lock()
	s.loadLocked()
	tok, parent := s.token, s.st.Parent
	s.mu.Unlock()
	if tok == "" {
		return Result{}, ErrNotConnected
	}
	if parent == nil {
		return Result{}, ErrNoParent
	}
	s.setProgress(&Progress{})
	res := Result{At: time.Now().UnixMilli(), Conflicts: []string{}, Errors: []string{}}
	err := s.sync(ctx, s.client(tok), parent.ID, full, &res)
	if err != nil {
		res.Error = err.Error()
		if errors.Is(err, ErrAuth) {
			res.Error = ErrAuth.Error() + "，请重新连接"
		}
	}
	s.mu.Lock()
	s.st.Last = &res
	s.saveLocked()
	s.mu.Unlock()
	s.setProgress(nil)
	s.publish("notion_synced", res)
	return res, err
}

func (s *Service) setProgress(p *Progress) {
	s.mu.Lock()
	s.running, s.progress = p != nil, p
	s.mu.Unlock()
	if p != nil {
		s.publish("notion_progress", *p)
	}
}

func (s *Service) put(key string, e *entry) {
	s.mu.Lock()
	if s.st.Pages == nil {
		s.st.Pages = map[string]entry{}
	}
	if e == nil {
		delete(s.st.Pages, key)
	} else {
		s.st.Pages[key] = *e
	}
	s.saveLocked()
	s.mu.Unlock()
}

func (s *Service) sync(ctx context.Context, c *Client, parentID string, full bool, res *Result) error {
	docs, err := s.Docs(ctx)
	if err != nil {
		return err
	}
	// The root page: recreated when it was deleted.
	s.mu.Lock()
	rootID := s.st.RootID
	s.mu.Unlock()
	if rootID != "" {
		if p, err := c.Page(ctx, rootID); err != nil && !gone(err) {
			return err
		} else if err != nil || p.InTrash {
			rootID = ""
		}
	}
	if rootID == "" {
		p, err := c.Create(ctx, parentID, RootTitle, rootBody)
		if err != nil {
			if gone(err) {
				return errors.New("没有权限写入所选页面：请在 Notion 中把它分享给集成，或重新选择页面")
			}
			return err
		}
		rootID = p.ID
		s.mu.Lock()
		s.st.RootID, s.st.RootURL, s.st.Pages = p.ID, p.URL, nil // a new tree
		s.saveLocked()
		s.mu.Unlock()
	}

	s.mu.Lock()
	pages := make(map[string]entry, len(s.st.Pages))
	for k, v := range s.st.Pages {
		pages[k] = v
	}
	s.mu.Unlock()
	want := map[string]bool{}
	prog := &Progress{Total: len(docs)}
	for _, d := range docs {
		if err := ctx.Err(); err != nil {
			return err
		}
		want[d.Key] = true
		prog.Done++
		if prog.Done%5 == 0 || prog.Done == prog.Total {
			s.setProgress(&Progress{Done: prog.Done, Total: prog.Total})
		}
		parent := rootID
		if d.Parent != "" {
			pe, ok := pages[d.Parent]
			if !ok {
				continue // the parent failed; its error is already listed
			}
			parent = pe.ID
		}
		if err := s.syncDoc(ctx, c, d, parent, full, pages, res); err != nil {
			if errors.Is(err, ErrAuth) || ctx.Err() != nil {
				return err
			}
			res.Errors = append(res.Errors, d.Title+"："+err.Error())
		}
	}
	// Pages no longer produced: leaves go to the trash when untouched since
	// our last write; containers may hold the user's own pages and stay.
	for key, e := range pages {
		if want[key] {
			continue
		}
		if !strings.HasPrefix(key, "course:") && !strings.HasPrefix(key, "lecture:") {
			md, err := c.Markdown(ctx, e.ID)
			switch {
			case gone(err):
			case err != nil:
				res.Errors = append(res.Errors, e.Title+"："+err.Error())
				continue
			case hash(md) != e.Seen:
				res.Conflicts = append(res.Conflicts, e.Title)
			default:
				if err := c.Trash(ctx, e.ID); err != nil && !gone(err) {
					res.Errors = append(res.Errors, e.Title+"："+err.Error())
					continue
				}
				res.Trashed++
			}
		}
		delete(pages, key)
		s.put(key, nil)
	}
	return nil
}

// drop forgets key and every page below it, so they are created again.
func (s *Service) drop(pages map[string]entry, key string) {
	gone := map[string]bool{key: true}
	for changed := true; changed; {
		changed = false
		for k, e := range pages {
			if !gone[k] && gone[e.Parent] {
				gone[k], changed = true, true
			}
		}
	}
	for k := range gone {
		delete(pages, k)
		s.put(k, nil)
	}
}

func (s *Service) syncDoc(ctx context.Context, c *Client, d Doc, parent string, full bool, pages map[string]entry, res *Result) error {
	h := hash(d.Title, d.Body)
	e, ok := pages[d.Key]
	if ok && full {
		if p, err := c.Page(ctx, e.ID); gone(err) || (err == nil && p.InTrash) {
			s.drop(pages, d.Key)
			ok = false
		} else if err != nil {
			return err
		}
	}
	if ok && (d.Container || e.Hash == h) {
		res.Unchanged++
		return nil
	}
	if ok {
		cur, err := c.Markdown(ctx, e.ID)
		switch {
		case gone(err):
			ok = false // deleted in Notion: write it again
		case err != nil:
			return err
		case hash(cur) != e.Seen:
			res.Conflicts = append(res.Conflicts, d.Title)
			return nil
		default:
			if err := c.Replace(ctx, e.ID, d.Body); err != nil {
				return err
			}
			if d.Title != e.Title {
				if err := c.SetTitle(ctx, e.ID, d.Title); err != nil {
					return err
				}
			}
			seen, err := c.Markdown(ctx, e.ID)
			if err != nil {
				return err
			}
			e.Title, e.Hash, e.Seen = d.Title, h, hash(seen)
			pages[d.Key] = e
			s.put(d.Key, &e)
			res.Updated++
			return nil
		}
	}
	p, err := c.Create(ctx, parent, d.Title, d.Body)
	if err != nil {
		if gone(err) && d.Parent != "" {
			// The parent page was deleted in Notion: forget it and what is
			// below it, so the next sync creates them again.
			s.drop(pages, d.Parent)
			return errors.New("上级页面已在 Notion 中删除，下次同步会重建")
		}
		return err
	}
	seen := ""
	if !d.Container {
		md, err := c.Markdown(ctx, p.ID)
		if err != nil {
			return err
		}
		seen = hash(md)
	}
	e = entry{ID: p.ID, Parent: d.Parent, URL: p.URL, Title: d.Title, Hash: h, Seen: seen}
	pages[d.Key] = e
	s.put(d.Key, &e)
	res.Created++
	return nil
}
