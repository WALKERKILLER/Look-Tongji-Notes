package canvas

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"lookstudio/lookd/internal/notify"
	"lookstudio/lookd/internal/tongji"
)

// fakeCanvas serves just enough of the Canvas API. Session requests need the
// cookie set by /login/openid_connect; token requests need a live token.
type fakeCanvas struct {
	mu       sync.Mutex
	srv      *httptest.Server
	session  string
	tokens   map[string]string // secret -> id
	nextTok  int
	deleted  []string
	signins  int
	due      time.Time
	extra    bool // second assignment appears
	filesOff bool // Files page hidden from students

	// beforeAnon runs once, outside the lock, before an anonymous modules
	// request is answered with 404: another call can run in that window.
	beforeAnon func()
}

func newFake(t *testing.T) *fakeCanvas {
	f := &fakeCanvas{tokens: map[string]string{}, due: time.Now().Add(3 * time.Hour), filesOff: true}
	f.srv = httptest.NewTLSServer(http.HandlerFunc(f.serve))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeCanvas) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch r.URL.Path {
	case "/login/openid_connect":
		f.signins++
		f.session = fmt.Sprint("s", f.signins)
		http.SetCookie(w, &http.Cookie{Name: "_normandy_session", Value: f.session, Path: "/"})
		http.SetCookie(w, &http.Cookie{Name: "_csrf_token", Value: "c%2Bsrf", Path: "/"})
		http.Redirect(w, r, "/", http.StatusFound)
		return
	case "/login/canvas":
		w.Write([]byte("<html>login</html>"))
		return
	}
	bySession := false
	if a := r.Header.Get("Authorization"); a != "" {
		if _, ok := f.tokens[strings.TrimPrefix(a, "Bearer ")]; !ok {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
	} else if c, err := r.Cookie("_normandy_session"); err == nil && c.Value == f.session {
		bySession = true
	} else if strings.HasPrefix(r.URL.Path, "/api/") {
		// As canvas.tongji.edu.cn does without a signed-in user: /users/self
		// and hidden resources are 404, the rest 401.
		switch {
		case r.URL.Path == "/api/v1/users/self", strings.Contains(r.URL.Path, "/files"), strings.Contains(r.URL.Path, "/modules"):
			if hook := f.beforeAnon; hook != nil && strings.Contains(r.URL.Path, "/modules") {
				f.beforeAnon = nil
				f.mu.Unlock()
				hook()
				f.mu.Lock()
			}
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"errors":[{"message":"The specified resource does not exist."}]}`))
		default:
			w.WriteHeader(http.StatusUnauthorized)
		}
		return
	} else {
		http.Redirect(w, r, "/login/canvas", http.StatusFound)
		return
	}
	out := func(v any) {
		if bySession {
			w.Write([]byte("while(1);"))
		}
		json.NewEncoder(w).Encode(v)
	}
	base := f.srv.URL
	switch {
	case r.URL.Path == "/" || r.URL.Path == "/profile/settings":
		w.Write([]byte("<html>ok</html>"))
	case r.URL.Path == "/api/v1/users/self":
		out(map[string]any{"id": "7", "name": "张三"})
	case r.URL.Path == "/api/v1/courses" && r.URL.Query().Get("page") == "":
		w.Header().Set("Link", `<`+base+`/api/v1/courses?page=2>; rel="next"`)
		out([]map[string]any{{"id": "1", "name": "数据结构（2026秋）", "course_code": "CS101"}})
	case r.URL.Path == "/api/v1/courses":
		out([]map[string]any{{"id": "2", "name": "体育"}})
	case r.URL.Path == "/api/v1/courses/1/assignments":
		as := []map[string]any{{"id": "11", "course_id": "1", "name": "作业一", "due_at": f.due.UTC().Format(time.RFC3339),
			"html_url": base + "/courses/1/assignments/11", "points_possible": 10, "submission": map[string]any{"workflow_state": "unsubmitted"}}}
		if f.extra {
			as = append(as, map[string]any{"id": "12", "course_id": "1", "name": "作业二", "due_at": time.Now().Add(72 * time.Hour).UTC().Format(time.RFC3339),
				"submission": map[string]any{"workflow_state": "submitted"}})
		}
		out(as)
	case r.URL.Path == "/api/v1/courses/2/assignments":
		w.WriteHeader(http.StatusForbidden)
	case r.URL.Path == "/api/v1/announcements":
		if got := r.URL.Query()["context_codes[]"]; len(got) != 1 || got[0] != "course_1" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		out([]map[string]any{{"id": "21", "title": "调课通知", "message": "<p>周三&nbsp;停课</p>", "context_code": "course_1"}})
	case r.URL.Path == "/api/v1/courses/1/files" && f.filesOff:
		w.WriteHeader(http.StatusForbidden)
	case r.URL.Path == "/api/v1/courses/1/modules":
		out([]map[string]any{{"name": "第一周", "items": []map[string]any{{"type": "File", "title": "讲义.pdf", "content_id": "9"}, {"type": "Page", "title": "x"}}}})
	case r.URL.Path == "/api/v1/files/9":
		out(map[string]any{"id": "9", "display_name": "讲义.pdf", "size": 5, "url": base + "/files/9/download?verifier=v"})
	case r.URL.Path == "/files/9/download":
		w.Write([]byte("%PDF!"))
	case r.URL.Path == "/api/v1/users/self/tokens" && r.Method == http.MethodPost:
		if bySession && r.Header.Get("X-CSRF-Token") != "c+srf" {
			w.WriteHeader(http.StatusUnprocessableEntity)
			return
		}
		r.ParseForm()
		f.nextTok++
		id, secret := fmt.Sprint(100+f.nextTok), fmt.Sprintf("secret-%d-abcd", f.nextTok)
		f.tokens[secret] = id
		out(map[string]any{"id": id, "token": secret, "expires_at": r.PostForm.Get("token[expires_at]")})
	case strings.HasPrefix(r.URL.Path, "/api/v1/users/self/tokens/") && r.Method == http.MethodDelete:
		id := strings.TrimPrefix(r.URL.Path, "/api/v1/users/self/tokens/")
		for k, v := range f.tokens {
			if v == id {
				delete(f.tokens, k)
			}
		}
		f.deleted = append(f.deleted, id)
		out(map[string]any{})
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

type fakeAuth struct {
	hc   *http.Client
	base string
}

func (a *fakeAuth) Client() *http.Client { return a.hc }
func (a *fakeAuth) SignIn(ctx context.Context) error {
	return OIDCSignIn(ctx, a.hc, a.base)
}

func setup(t *testing.T) (*fakeCanvas, *Service, *[]notify.Item) {
	t.Helper()
	tongji.KeyPath = filepath.Join(t.TempDir(), "seal.key")
	f := newFake(t)
	jar, _ := cookiejar.New(nil)
	hc := f.srv.Client()
	hc.Jar = jar
	var got []notify.Item
	feed := notify.Open("", nil)
	s := &Service{Dir: t.TempDir(), Transport: f.srv.Client().Transport,
		AuthFor: func(c Config) Auth { return &fakeAuth{hc: hc, base: c.Base} },
		Notify: func(it notify.Item) bool {
			if feed.Add(it) {
				got = append(got, it)
				return true
			}
			return false
		}}
	return f, s, &got
}

func kinds(items []notify.Item) string {
	var k []string
	for _, it := range items {
		k = append(k, it.Kind)
	}
	return strings.Join(k, ",")
}

func TestSSOSyncScheduleAndNews(t *testing.T) {
	ctx := context.Background()
	f, s, got := setup(t)
	st, err := s.Connect(ctx, ConnectIn{School: "tongji", Base: f.srv.URL, Mode: "sso"})
	if err != nil || st.User != "张三" || st.Mode != "sso" {
		t.Fatal(err, st)
	}
	if err := s.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	// First sync marks everything seen, except a deadline within a day.
	if kinds(*got) != "assignment_due" {
		t.Fatalf("first sync notified %q", kinds(*got))
	}
	items := s.Items()
	if len(items) != 1 || items[0].ID != "canvas:11" || items[0].Done || items[0].Detail != "数据结构（2026秋） · 10 分" {
		t.Fatalf("%+v", items)
	}
	if st := s.Status(); len(st.Courses) != 2 || st.Courses[0].Open != 1 || st.Courses[1].Total != 0 {
		t.Fatalf("%+v", st.Courses)
	}

	// The web session expires; the next call signs in again by itself.
	f.mu.Lock()
	f.session, f.extra = "expired", true
	f.mu.Unlock()
	*got = nil
	if err := s.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if f.signins != 2 {
		t.Fatalf("signins = %d", f.signins)
	}
	if kinds(*got) != "assignment_new" || (*got)[0].Title != "新作业：作业二" {
		t.Fatalf("second sync notified %+v", *got)
	}
	if err := s.Sync(ctx); err != nil || len(*got) != 1 {
		t.Fatalf("repeat sync renotified: %v %+v", err, *got)
	}
	if items := s.Items(); len(items) != 2 || !items[1].Done {
		t.Fatalf("%+v", items)
	}

	// Local done override and hiding.
	if it, err := s.SetDone("canvas:11", true); err != nil || !it.Done {
		t.Fatal(err, it)
	}
	if err := s.Hide("canvas:12"); err != nil {
		t.Fatal(err)
	}
	if items := s.Items(); len(items) != 1 || !items[0].Done {
		t.Fatalf("%+v", items)
	}
	if err := s.Unhide("canvas:12"); err != nil || len(s.Items()) != 2 {
		t.Fatal(err)
	}
	s.Hide("canvas:12")
	if _, err := s.SetDone("canvas:404", true); err != ErrNotFound {
		t.Fatal(err)
	}

	// Course detail and announcements.
	d, err := s.Detail("1")
	if err != nil || len(d.Assignments) != 2 || len(d.Announcements) != 1 || d.Assignments[0].Name != "作业二" {
		t.Fatalf("%v %+v", err, d)
	}

	// State survives a restart.
	s2 := &Service{Dir: s.Dir}
	if st := s2.Status(); !st.Connected || len(st.Courses) != 2 || len(s2.Items()) != 1 {
		t.Fatalf("%+v", st)
	}
}

// A call that saw the lapsed session while another call renewed it retries
// instead of reporting the 404 (by then /users/self answers again).
func TestLapseRenewedByAnotherCallIsRetried(t *testing.T) {
	ctx := context.Background()
	f, s, _ := setup(t)
	if _, err := s.Connect(ctx, ConnectIn{School: "tongji", Base: f.srv.URL, Mode: "sso"}); err != nil {
		t.Fatal(err)
	}
	var other error
	f.mu.Lock()
	f.session = "expired"
	before := f.signins
	f.beforeAnon = func() { _, other = s.Files(ctx, "1") }
	f.mu.Unlock()
	if _, err := s.Files(ctx, "1"); err != nil || other != nil || f.signins != before+1 {
		t.Fatalf("err %v, other %v, signins %d → %d", err, other, before, f.signins)
	}
}

func TestFilesFallbackAndDownload(t *testing.T) {
	ctx := context.Background()
	f, s, _ := setup(t)
	if _, err := s.Connect(ctx, ConnectIn{School: "tongji", Base: f.srv.URL, Mode: "sso"}); err != nil {
		t.Fatal(err)
	}
	fs, err := s.Files(ctx, "1")
	if err != nil || len(fs) != 1 || fs[0].ID != "9" || fs[0].Module != "第一周" {
		t.Fatalf("%v %+v", err, fs)
	}
	// The session lapses: two calls at once see only 404s, sign in once
	// together and succeed.
	f.mu.Lock()
	f.session = "expired"
	before := f.signins
	f.mu.Unlock()
	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i := range errs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, errs[i] = s.Files(ctx, "1")
		}()
	}
	wg.Wait()
	if errs[0] != nil || errs[1] != nil || f.signins != before+1 {
		t.Fatalf("errs %v, signins %d → %d", errs, before, f.signins)
	}
	if s.Status().RenewedAt == 0 {
		t.Fatal("renewal not reported")
	}
	dir := filepath.Join(t.TempDir(), "Canvas")
	p, err := s.Download(ctx, "9", dir)
	if err != nil || filepath.Base(p) != "讲义.pdf" {
		t.Fatal(err, p)
	}
	if b, _ := os.ReadFile(p); string(b) != "%PDF!" {
		t.Fatalf("%q", b)
	}
}

func TestTokenCreatedAndRotated(t *testing.T) {
	ctx := context.Background()
	f, s, _ := setup(t)
	st, err := s.Connect(ctx, ConnectIn{School: "tongji", Base: f.srv.URL, Mode: "token", Create: true})
	if err != nil || !st.TokenAuto || st.TokenLast4 != "abcd" || st.ExpiresAt == nil || time.Until(*st.ExpiresAt) < 80*24*time.Hour {
		t.Fatal(err, st)
	}
	b, _ := os.ReadFile(filepath.Join(s.Dir, "canvas.json"))
	if strings.Contains(string(b), "secret-") {
		t.Fatal("token stored in plain text")
	}
	// Close to expiry: the sync replaces the token and revokes the old one.
	s.mu.Lock()
	soon := time.Now().Add(24 * time.Hour)
	s.cfg.ExpiresAt = &soon
	s.mu.Unlock()
	if err := s.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if s.cfg.TokenID != "102" || len(f.deleted) != 1 || f.deleted[0] != "101" || len(f.tokens) != 1 {
		t.Fatalf("id %s deleted %v tokens %v", s.cfg.TokenID, f.deleted, len(f.tokens))
	}
	// Revoked behind our back: recreated through the web session.
	f.mu.Lock()
	f.tokens = map[string]string{}
	f.mu.Unlock()
	if err := s.Sync(ctx); err != nil || s.cfg.TokenID != "103" {
		t.Fatal(err, s.cfg.TokenID)
	}
	s.Disconnect(ctx)
	if len(f.tokens) != 0 || s.Connected() {
		t.Fatalf("tokens left %d", len(f.tokens))
	}
}

func TestPastedTokenRevoked(t *testing.T) {
	ctx := context.Background()
	f, s, _ := setup(t)
	f.tokens["pasted-1234"] = "1"
	s.AuthFor = func(Config) Auth { return nil } // a school without SSO
	if _, err := s.Connect(ctx, ConnectIn{School: "other", Base: f.srv.URL, Mode: "sso"}); err == nil {
		t.Fatal("sso without auth accepted")
	}
	if _, err := s.Connect(ctx, ConnectIn{School: "other", Base: "http://x", Mode: "token", Token: "t"}); err == nil {
		t.Fatal("plain http accepted")
	}
	st, err := s.Connect(ctx, ConnectIn{School: "other", Base: f.srv.URL + "/", Mode: "token", Token: " pasted-1234 "})
	if err != nil || st.TokenLast4 != "1234" || st.TokenAuto {
		t.Fatal(err, st)
	}
	delete(f.tokens, "pasted-1234")
	if err := s.Sync(ctx); err == nil || !strings.Contains(err.Error(), "令牌已失效") || !strings.Contains(s.Status().Error, "令牌") {
		t.Fatal(err)
	}
}

func TestAutoLink(t *testing.T) {
	refs := []Ref{{"a", "数据结构"}, {"b", "高等数学（上）"}, {"c", "高等数学（下）"}, {"d", "大学物理 A"}}
	for name, want := range map[string]string{
		"数据结构（2026秋）": "a",
		"高等数学":        "", // ambiguous
		"大学物理A(1)":    "d",
		"体育":          "",
	} {
		if got := match(name, refs); got != want {
			t.Errorf("match(%q) = %q, want %q", name, got, want)
		}
	}
}
