package notion

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"lookstudio/lookd/internal/tongji"
)

// fakeNotion keeps pages in memory and renders Markdown back with a trailing
// newline, as a reminder that Notion normalises what it stores.
type fakeNotion struct {
	mu     sync.Mutex
	pages  map[string]*fakePage
	next   int
	calls  int
	shared map[string]bool
}

type fakePage struct {
	parent, title, md string
	trash             bool
}

func newFake(t *testing.T) (*fakeNotion, *httptest.Server) {
	f := &fakeNotion{pages: map[string]*fakePage{"00000000000000000000000000parent": {title: "我的课程"}}, shared: map[string]bool{"00000000000000000000000000parent": true}}
	srv := httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(srv.Close)
	return f, srv
}

func (f *fakeNotion) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	if r.Header.Get("Authorization") != "Bearer ntn_good1234" {
		w.WriteHeader(401)
		return
	}
	if r.Header.Get("Notion-Version") != Version {
		w.WriteHeader(400)
		return
	}
	var in map[string]any
	json.NewDecoder(r.Body).Decode(&in)
	out := func(v any) { json.NewEncoder(w).Encode(v) }
	notFound := func() {
		w.WriteHeader(404)
		out(map[string]string{"code": "object_not_found", "message": "Could not find page"})
	}
	page := func(id string) map[string]any {
		p := f.pages[id]
		return map[string]any{"id": id, "url": "https://www.notion.so/" + id, "in_trash": p.trash,
			"properties": map[string]any{"title": map[string]any{"type": "title", "title": []any{map[string]string{"plain_text": p.title}}}}}
	}
	path := r.URL.Path
	switch {
	case path == "/v1/users/me":
		out(map[string]any{"name": "Look Studio", "bot": map[string]string{"workspace_name": "张三的工作区"}})
	case path == "/v1/search":
		var res []any
		for id := range f.shared {
			res = append(res, page(id))
		}
		out(map[string]any{"results": res})
	case path == "/v1/pages" && r.Method == http.MethodPost:
		parent := in["parent"].(map[string]any)["page_id"].(string)
		if p, ok := f.pages[parent]; !ok || p.trash {
			notFound()
			return
		}
		f.next++
		id := fmt.Sprintf("p%031d", f.next)
		title := in["properties"].(map[string]any)["title"].(map[string]any)["title"].([]any)[0].(map[string]any)["text"].(map[string]any)["content"].(string)
		f.pages[id] = &fakePage{parent: parent, title: title, md: in["markdown"].(string) + "\n"}
		out(page(id))
	case strings.HasSuffix(path, "/markdown"):
		id := strings.TrimSuffix(strings.TrimPrefix(path, "/v1/pages/"), "/markdown")
		p, ok := f.pages[id]
		if !ok || p.trash {
			notFound()
			return
		}
		if r.Method == http.MethodPatch {
			p.md = in["replace_content"].(map[string]any)["new_str"].(string) + "\n"
			out(map[string]any{})
			return
		}
		out(map[string]any{"markdown": p.md})
	case strings.HasPrefix(path, "/v1/pages/"):
		id := strings.TrimPrefix(path, "/v1/pages/")
		p, ok := f.pages[id]
		if !ok {
			notFound()
			return
		}
		if r.Method == http.MethodPatch {
			if v, ok := in["in_trash"].(bool); ok {
				p.trash = v
			}
			if props, ok := in["properties"].(map[string]any); ok {
				p.title = props["title"].(map[string]any)["title"].([]any)[0].(map[string]any)["text"].(map[string]any)["content"].(string)
			}
		}
		out(page(id))
	default:
		notFound()
	}
}

func (f *fakeNotion) find(title string) (string, *fakePage) {
	for id, p := range f.pages {
		if p.title == title {
			return id, p
		}
	}
	return "", nil
}

func setup(t *testing.T) (*fakeNotion, *Service, *[]Doc) {
	tongji.KeyPath = filepath.Join(t.TempDir(), "seal.key")
	f, srv := newFake(t)
	docs := &[]Doc{
		{Key: "course:c1", Title: "数据结构", Body: "王老师\n", Container: true},
		{Key: "lecture:l1", Parent: "course:c1", Title: "第一讲", Body: "2026-09-08\n", Container: true},
		{Key: "note:n1", Parent: "lecture:l1", Title: "栈与队列", Body: "先进后出。\n"},
		{Key: "transcript:l1", Parent: "lecture:l1", Title: "转写稿 · 第一讲", Body: "## 转写稿\n\n[00:01] 同学们好\n"},
	}
	s := &Service{Path: filepath.Join(t.TempDir(), "notion.json"), Base: srv.URL, Pace: time.Millisecond,
		Docs: func(context.Context) ([]Doc, error) { return *docs, nil }}
	return f, s, docs
}

func TestConnectConfigureAndSync(t *testing.T) {
	ctx := context.Background()
	f, s, docs := setup(t)
	if _, err := s.Connect(ctx, "ntn_bad"); err != ErrAuth {
		t.Fatal(err)
	}
	st, err := s.Connect(ctx, " ntn_good1234 ")
	if err != nil || st.Bot.Workspace != "张三的工作区" || st.TokenLast4 != "1234" {
		t.Fatal(err, st)
	}
	if b, _ := os.ReadFile(s.Path); strings.Contains(string(b), "ntn_good") {
		t.Fatal("token stored in plain text")
	}
	if _, err := s.Sync(ctx, false); err != ErrNoParent {
		t.Fatal(err)
	}
	pages, err := s.Search(ctx, "")
	if err != nil || len(pages) != 1 || pages[0].Title != "我的课程" {
		t.Fatal(err, pages)
	}
	url := "https://www.notion.so/me/My-0000-00000000000000000000000000parent?pvs=4"
	on := true
	if st, err := s.Configure(ctx, &url, &on); err != nil || st.Parent == nil || st.Parent.Title != "我的课程" || !s.AutoOn() {
		t.Fatal(err, st)
	}

	res, err := s.Sync(ctx, false)
	if err != nil || res.Created != 4 || len(res.Errors) != 0 {
		t.Fatalf("%v %+v", err, res)
	}
	rootID, _ := f.find(RootTitle)
	cid, _ := f.find("数据结构")
	lid, lec := f.find("第一讲")
	_, note := f.find("栈与队列")
	if rootID == "" || f.pages[cid].parent != rootID || lec.parent != cid || note.parent != lid || s.Status().RootURL == "" {
		t.Fatal("tree shape")
	}

	// Nothing changed: no writes, and no reads beyond the root check.
	calls := f.calls
	if res, _ := s.Sync(ctx, false); res.Unchanged != 4 || f.calls-calls != 1 {
		t.Fatalf("%+v, %d calls", res, f.calls-calls)
	}

	// A note changes in the library, another is renamed.
	(*docs)[2].Body = "先进后出，后进先出。\n"
	(*docs)[3].Title = "转写稿 · 第一讲（修订）"
	if res, _ := s.Sync(ctx, false); res.Updated != 2 || note.md != "先进后出，后进先出。\n\n" {
		t.Fatalf("%+v %q", res, note.md)
	}
	if id, _ := f.find("转写稿 · 第一讲（修订）"); id == "" {
		t.Fatal("title not updated")
	}

	// Edited in Notion: kept, reported, not overwritten.
	note.md = "我在 Notion 里加了一句。\n"
	(*docs)[2].Body = "库里又改了。\n"
	if res, _ := s.Sync(ctx, false); len(res.Conflicts) != 1 || note.md != "我在 Notion 里加了一句。\n" {
		t.Fatalf("%+v", res)
	}

	// Removed from the library: the untouched transcript goes to the trash,
	// the edited note stays.
	*docs = (*docs)[:2]
	res, _ = s.Sync(ctx, false)
	_, tr := f.find("转写稿 · 第一讲（修订）")
	if res.Trashed != 1 || !tr.trash || note.trash || len(res.Conflicts) != 1 {
		t.Fatalf("%+v", res)
	}
}

func TestRecreatesDeletedPages(t *testing.T) {
	ctx := context.Background()
	f, s, _ := setup(t)
	s.Connect(ctx, "ntn_good1234")
	id := "00000000000000000000000000parent"
	s.Configure(ctx, &id, nil)
	if _, err := s.Sync(ctx, false); err != nil {
		t.Fatal(err)
	}
	// The user deletes the course page (and with it the tree below).
	cid, course := f.find("数据结构")
	course.trash = true
	for _, p := range f.pages {
		if p.parent == cid {
			p.trash = true
		}
	}
	// A routine sync costs no requests for unchanged pages and so does not
	// notice; a full check recreates the course and everything below it.
	if res, _ := s.Sync(ctx, false); res.Unchanged != 4 {
		t.Fatalf("%+v", res)
	}
	res, err := s.Sync(ctx, true)
	if err != nil || len(res.Errors) != 0 || res.Created != 4 {
		t.Fatalf("%v %+v", err, res)
	}
	n := 0
	for _, p := range f.pages {
		if p.title == "数据结构" && !p.trash {
			n++
		}
	}
	if n != 1 {
		t.Fatal("course page not recreated")
	}
	// The root page itself deleted: a fresh tree.
	rootID, root := f.find(RootTitle)
	root.trash = true
	if res, err := s.Sync(ctx, false); err != nil || res.Created != 4 {
		t.Fatalf("%v %+v", err, res)
	}
	live := 0
	for id, p := range f.pages {
		if p.title == RootTitle && !p.trash && id != rootID {
			live++
		}
	}
	if live != 1 {
		t.Fatal("root not recreated")
	}
}

func TestNormalizeID(t *testing.T) {
	for in, want := range map[string]string{
		"https://www.notion.so/ws/Title-0123456789abcdef0123456789abcdef?pvs=4": "0123456789abcdef0123456789abcdef",
		"01234567-89ab-cdef-0123-456789abcdef":                                  "0123456789abcdef0123456789abcdef",
	} {
		if got := normalizeID(in); got != want {
			t.Errorf("%s → %s", in, got)
		}
	}
}
