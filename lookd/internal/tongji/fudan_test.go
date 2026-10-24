package tongji

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"lookstudio/lookd/internal/fudan"
)

const (
	gw     = "https://webvpn.fudan.edu.cn"
	vodURL = "https://vod.fudan.edu.cn/v/1.mp4"
)

// fakeFudan plays UIS, the WebVPN gateway, iCourse and its video host. The
// gateway keeps the cookies of the services behind it, keyed by its own
// ticket, like the real one.
type fakeFudan struct {
	t      *testing.T
	key    *rsa.PrivateKey
	mu     sync.Mutex
	n      int
	vpn    map[string]bool // gateway sessions
	vpnUIS map[string]bool // UIS signed in behind the gateway, by gateway session
	course map[string]bool // iCourse signed in, by gateway session
	tokens map[string]string
	logins int // credential submissions
}

func vpnPrefix(host string) string { return "/https/" + fudan.VPNHost(host) }

func (f *fakeFudan) next(p string) string { f.n++; return fmt.Sprintf("%s%d", p, f.n) }

func (f *fakeFudan) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch r.Host {
	case "id.fudan.edu.cn":
		c, _ := r.Cookie("uis_tgc")
		f.uis(w, r, "https://id.fudan.edu.cn", r.URL.Path, c != nil && c.Value == "ok", "")
		return
	case "webvpn.fudan.edu.cn":
	default:
		http.Error(w, "unknown host", 502)
		return
	}
	c, _ := r.Cookie("wengine_vpn_ticket")
	sess := ""
	if c != nil && f.vpn[c.Value] {
		sess = c.Value
	}
	switch {
	case r.URL.Path == "/login":
		if tk := r.URL.Query().Get("ticket"); tk != "" && f.tokens[tk] == "vpn" {
			delete(f.tokens, tk)
			sess = f.next("V")
			f.vpn[sess] = true
			http.SetCookie(w, &http.Cookie{Name: "wengine_vpn_ticket", Value: sess, Path: "/"})
		}
		if sess != "" {
			http.Redirect(w, r, "/", http.StatusFound)
			return
		}
		http.Redirect(w, r, "https://id.fudan.edu.cn/idp/authCenter/authenticate?service="+url.QueryEscape(gw+"/login?cas_login=true"), http.StatusFound)
	case sess == "":
		http.Redirect(w, r, "/login", http.StatusFound)
	case r.URL.Path == "/":
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("portal"))
	case strings.HasPrefix(r.URL.Path, vpnPrefix("id.fudan.edu.cn")):
		p := vpnPrefix("id.fudan.edu.cn")
		f.uis(w, r, gw+p, strings.TrimPrefix(r.URL.Path, p), f.vpnUIS[sess], sess)
	case strings.HasPrefix(r.URL.Path, vpnPrefix("icourse.fudan.edu.cn")):
		f.icourse(w, r, strings.TrimPrefix(r.URL.Path, vpnPrefix("icourse.fudan.edu.cn")), sess)
	case r.URL.Path == vpnPrefix("vod.fudan.edu.cn")+"/v/1.mp4":
		q := r.URL.Query()
		if q.Get("clientUUID") == "" || !strings.HasPrefix(q.Get("t"), "7-") {
			http.Error(w, "unsigned", 403)
			return
		}
		http.ServeContent(w, r, "1.mp4", time.Time{}, bytes.NewReader([]byte("0123456789")))
	default:
		http.NotFound(w, r)
	}
}

// uis serves UIS at base; vpnSess is the gateway session it sits behind.
func (f *fakeFudan) uis(w http.ResponseWriter, r *http.Request, base, path string, signed bool, vpnSess string) {
	switch path {
	case "/idp/authCenter/authenticate":
		svc := r.URL.Query().Get("service")
		if signed {
			f.ticket(w, r, svc)
			return
		}
		lck := f.next("L")
		f.tokens[lck] = svc
		loc := base + "/ac/#/index?lck=" + lck
		if vpnSess == "" { // behind the gateway the entity id is missing, as seen live
			loc += "&entityId=" + url.QueryEscape(gw)
		}
		http.Redirect(w, r, loc, http.StatusFound)
	case "/ac/":
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("login"))
	case "/idp/authn/queryAuthMethods":
		var in map[string]string
		json.NewDecoder(r.Body).Decode(&in)
		want := gw
		if vpnSess != "" {
			want = fudan.ICourseBase
		}
		if f.tokens[in["lck"]] == "" || in["entityId"] != want {
			http.Error(w, "bad context", 400)
			return
		}
		w.Write([]byte(`{"code":200,"requestType":"chain_type","data":[{"moduleCode":"userAndPwd","authChainCode":"C1"}]}`))
	case "/idp/authn/getJsPublicKey":
		der, _ := x509.MarshalPKIXPublicKey(&f.key.PublicKey)
		json.NewEncoder(w).Encode(map[string]string{"code": "200", "data": base64.StdEncoding.EncodeToString(der)})
	case "/idp/authn/authExecute":
		var in struct {
			Lck      string            `json:"lck"`
			AuthPara map[string]string `json:"authPara"`
		}
		json.NewDecoder(r.Body).Decode(&in)
		f.logins++
		ct, _ := base64.StdEncoding.DecodeString(in.AuthPara["password"])
		pw, err := rsa.DecryptPKCS1v15(nil, f.key, ct)
		if err != nil || string(pw) != "secret" || in.AuthPara["loginName"] != "21300" {
			w.Write([]byte(`{"code":"500","message":"用户名或密码错误"}`))
			return
		}
		tok := f.next("T")
		f.tokens[tok] = f.tokens[in.Lck]
		w.Write([]byte(`{"code":"200","loginToken":"` + tok + `"}`))
	case "/idp/authCenter/authnEngine":
		r.ParseForm()
		svc := f.tokens[r.Form.Get("loginToken")]
		if svc == "" {
			http.Error(w, "no", 400)
			return
		}
		if vpnSess != "" {
			f.vpnUIS[vpnSess] = true
		} else {
			http.SetCookie(w, &http.Cookie{Name: "uis_tgc", Value: "ok", Path: "/"})
		}
		tk := f.newTicket(svc)
		// The page names the service's own address, also behind the gateway.
		w.Write([]byte(`<script>var locationValue = "` + strings.ReplaceAll(svc+"&ticket="+tk, "&", "&amp;") + `";</script>`))
	default:
		http.NotFound(w, r)
	}
}

func (f *fakeFudan) newTicket(svc string) string {
	tk := f.next("ST")
	if strings.HasPrefix(svc, gw) {
		f.tokens[tk] = "vpn"
	} else {
		f.tokens[tk] = "icourse"
	}
	return tk
}

func (f *fakeFudan) ticket(w http.ResponseWriter, r *http.Request, svc string) {
	tk := f.newTicket(svc)
	to := svc + "&ticket=" + tk
	if !strings.HasPrefix(to, gw) {
		to, _ = fudan.VPNURL(to)
	}
	http.Redirect(w, r, to, http.StatusFound)
}

func (f *fakeFudan) icourse(w http.ResponseWriter, r *http.Request, path, sess string) {
	switch path {
	case "/casapi/index.php":
		if tk := r.URL.Query().Get("ticket"); tk != "" && f.tokens[tk] == "icourse" {
			delete(f.tokens, tk)
			f.course[sess] = true
		}
		if f.course[sess] {
			http.Redirect(w, r, gw+vpnPrefix("icourse.fudan.edu.cn")+"/", http.StatusFound)
			return
		}
		svc := fudan.ICourseBase + "/casapi/index.php?" + r.URL.RawQuery
		http.Redirect(w, r, gw+vpnPrefix("id.fudan.edu.cn")+"/idp/authCenter/authenticate?service="+url.QueryEscape(svc), http.StatusFound)
	case "/":
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("icourse"))
	default:
		if !f.course[sess] { // as Look answers without a session
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(`{"code":401,"msg":"未登录"}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch path {
		case "/userapi/v1/infosimple":
			w.Write([]byte(`{"code":0,"params":{"id":7,"tenant_id":1,"account":"21300","realname":"张三","phone":"13800000000"}}`))
		case "/personal/courseapi/vlabpassportapi/v1/account-profile/course":
			w.Write([]byte(`{"params":{"result":{"total":1,"data":[{"Id":"42","Title":"数学分析","Teacher":"李老师"}]}}}`))
		case "/courseapi/v3/portal-home-setting/get-sub-info":
			w.Write([]byte(`{"code":0,"data":{"now":"1800000000","duration":"10","video_list":{"0":{"preview_url":"` + vodURL + `"}}}}`))
		default:
			http.NotFound(w, r)
		}
	}
}

func newFakeFudan(t *testing.T) (*fakeFudan, http.RoundTripper) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	f := &fakeFudan{t: t, key: key, vpn: map[string]bool{}, vpnUIS: map[string]bool{}, course: map[string]bool{}, tokens: map[string]string{}}
	srv := httptest.NewUnstartedServer(f)
	srv.Config.ErrorLog = log.New(io.Discard, "", 0) // handshakes cut short at Close
	srv.StartTLS()
	t.Cleanup(srv.Close)
	addr := srv.Listener.Addr().String()
	return f, &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "tcp", addr)
		},
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
}

func fudanSession(t *testing.T, path string, tr http.RoundTripper) *Session {
	s := NewSession(path, nil)
	s.hc.Transport, s.api.Transport = tr, tr
	return s
}

func TestFudanSignInThroughWebVPN(t *testing.T) {
	KeyPath = filepath.Join(t.TempDir(), "seal.key")
	f, tr := newFakeFudan(t)
	path := filepath.Join(t.TempDir(), "session.json")
	s := fudanSession(t, path, tr)
	ctx := t.Context()

	err := s.Login(ctx, Fudan, "21300", "wrong", "", true)
	if !errors.Is(err, fudan.ErrBadCredentials) || s.State().Status != "signed_out" || s.School() != Fudan {
		t.Fatalf("wrong password: err=%v state=%+v", err, s.State())
	}
	if err := s.Login(ctx, Fudan, "21300", "secret", "", true); err != nil {
		t.Fatal(err)
	}
	if st := s.State(); st.Status != "active" || st.School != Fudan || s.Base() != fudan.ICourseBase {
		t.Fatalf("state %+v", st)
	}

	c := &Client{S: s}
	cs, err := c.Courses(ctx)
	if err != nil || len(cs) != 1 || cs[0].Title != "数学分析" {
		t.Fatalf("courses %v %v", cs, err)
	}

	// Media goes through the gateway, signed for the iCourse user, with the
	// gateway cookie in the daemon's headers.
	m, err := c.LectureMedia(ctx, "42", "9")
	if err != nil || len(m.Streams) != 1 {
		t.Fatalf("media %v %v", m, err)
	}
	if !strings.HasPrefix(m.Streams[0].URL, gw+vpnPrefix("vod.fudan.edu.cn")) || !strings.Contains(m.Headers.Get("Cookie"), "wengine_vpn_ticket=") {
		t.Fatalf("stream %s headers %v", m.Streams[0].URL, m.Headers)
	}
	req, _ := http.NewRequest(http.MethodGet, m.Streams[0].URL, nil)
	req.Header = m.Headers.Clone()
	req.Header.Set("Range", "bytes=2-4")
	resp, err := (&http.Client{Transport: tr}).Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent || string(body) != "234" {
		t.Fatalf("video %d %q", resp.StatusCode, body)
	}

	// iCourse's session lapses behind a live gateway: renewed without the password.
	f.mu.Lock()
	f.course = map[string]bool{}
	logins := f.logins
	f.mu.Unlock()
	if cs, err := c.Courses(ctx); err != nil || len(cs) != 1 {
		t.Fatal(cs, err)
	}
	if st := s.State(); st.Status != "active" || st.Method != "sso" || f.logins != logins {
		t.Fatalf("silent renewal: %+v, %d credential submissions", st, f.logins-logins)
	}

	// The gateway session ends too: UIS behind it wants the password again.
	f.mu.Lock()
	f.vpn, f.vpnUIS, f.course = map[string]bool{}, map[string]bool{}, map[string]bool{}
	f.mu.Unlock()
	if cs, err := c.Courses(ctx); err != nil || len(cs) != 1 {
		t.Fatal(cs, err)
	}
	if st := s.State(); st.Status != "active" || st.Method != "password" {
		t.Fatalf("password renewal: %+v", st)
	}

	// The session survives a restart; the password is stored only sealed.
	raw, _ := os.ReadFile(path)
	if bytes.Contains(raw, []byte("secret")) {
		t.Fatal("password stored in plain text")
	}
	s2 := fudanSession(t, path, tr)
	if st := s2.State(); st.Status != "active" || st.School != Fudan || st.Username != "21300" {
		t.Fatalf("restored %+v", st)
	}
	if cs, err := (&Client{S: s2}).Courses(ctx); err != nil || len(cs) != 1 {
		t.Fatal(cs, err)
	}
}

func TestFudanRenewalWithoutRememberedPassword(t *testing.T) {
	KeyPath = filepath.Join(t.TempDir(), "seal.key")
	f, tr := newFakeFudan(t)
	s := fudanSession(t, filepath.Join(t.TempDir(), "session.json"), tr)
	if err := s.Login(t.Context(), Fudan, "21300", "secret", "", false); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	f.vpn, f.vpnUIS, f.course = map[string]bool{}, map[string]bool{}, map[string]bool{}
	f.mu.Unlock()
	if _, err := (&Client{S: s}).Courses(t.Context()); err == nil {
		t.Fatal("want an error")
	}
	if st := s.State(); st.Status != "needs_password" || !strings.Contains(st.Error, "重新登录") {
		t.Fatalf("state %+v", st)
	}
}
