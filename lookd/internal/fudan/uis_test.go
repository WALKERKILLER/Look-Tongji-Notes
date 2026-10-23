package fudan

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestVPNHostMatchesKnownGateway(t *testing.T) {
	// Prefix documented by fudan-courseflow for icourse.fudan.edu.cn.
	got := VPNHost("icourse.fudan.edu.cn")
	if !strings.HasPrefix(got, "77726476706e69737468656265737421f9f44e") || len(got) != 32+2*len("icourse.fudan.edu.cn") {
		t.Fatalf("VPNHost = %s", got)
	}
	u, _ := VPNURL("https://icourse.fudan.edu.cn/courseapi/v3/x?a=1")
	if !strings.HasPrefix(u, WebVPNBase+"/https/"+got+"/courseapi/v3/x?a=1") {
		t.Fatal(u)
	}
	if u, _ := VPNURL("http://10.0.0.1:8080/p"); !strings.HasPrefix(u, WebVPNBase+"/http-8080/") {
		t.Fatal(u)
	}
}

// fakeUIS plays UIS and a service that trusts its tickets.
func fakeUIS(t *testing.T, password string) (uis, svc *httptest.Server) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	der, _ := x509.MarshalPKIXPublicKey(&key.PublicKey)
	mux := http.NewServeMux()
	uis = httptest.NewServer(mux)
	svcMux := http.NewServeMux()
	svc = httptest.NewServer(svcMux)
	t.Cleanup(uis.Close)
	t.Cleanup(svc.Close)
	svcMux.HandleFunc("/login/cas", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("ticket") == "ST-1" {
			http.SetCookie(w, &http.Cookie{Name: "svc_session", Value: "ok", Path: "/"})
			http.Redirect(w, r, "/", http.StatusFound)
			return
		}
		if c, err := r.Cookie("svc_session"); err == nil && c.Value == "ok" {
			http.Redirect(w, r, "/", http.StatusFound)
			return
		}
		http.Redirect(w, r, uis.URL+"/ac/#/index?lck=L%2B1&entityId="+svc.URL, http.StatusFound)
	})
	svcMux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("home")) })
	mux.HandleFunc("/ac/", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("<html>login</html>")) })
	mux.HandleFunc("/idp/authn/queryAuthMethods", func(w http.ResponseWriter, r *http.Request) {
		var in map[string]string
		json.NewDecoder(r.Body).Decode(&in)
		if in["lck"] != "L+1" || in["entityId"] != svc.URL {
			http.Error(w, "bad context", 400)
			return
		}
		w.Write([]byte(`{"code":200,"requestType":"chain_type","data":[{"moduleCode":"qr","authChainCode":"q"},{"moduleCode":"userAndPwd","authChainCode":"C1"}]}`))
	})
	mux.HandleFunc("/idp/authn/getJsPublicKey", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]string{"code": "200", "data": base64.StdEncoding.EncodeToString(der)})
	})
	mux.HandleFunc("/idp/authn/authExecute", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			AuthChainCode string            `json:"authChainCode"`
			RequestType   string            `json:"requestType"`
			AuthPara      map[string]string `json:"authPara"`
		}
		json.NewDecoder(r.Body).Decode(&in)
		ct, _ := base64.StdEncoding.DecodeString(in.AuthPara["password"])
		pw, err := rsa.DecryptPKCS1v15(nil, key, ct)
		if err != nil || string(pw) != password || in.AuthChainCode != "C1" || in.RequestType != "chain_type" || in.AuthPara["loginName"] != "20300" {
			w.Write([]byte(`{"code":"500","message":"用户名或密码错误"}`))
			return
		}
		w.Write([]byte(`{"code":"200","loginToken":"T1"}`))
	})
	mux.HandleFunc("/idp/authCenter/authnEngine", func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		if r.Form.Get("loginToken") != "T1" {
			http.Error(w, "no", 400)
			return
		}
		w.Write([]byte(`<script>var locationValue = "` + svc.URL + `/login/cas?ticket=ST-1&amp;x=1";</script>`))
	})
	return uis, svc
}

func client() *http.Client { j, _ := cookiejar.New(nil); return &http.Client{Jar: j} }

func TestUISLogin(t *testing.T) {
	uis, svc := fakeUIS(t, "secret")
	hc := client()
	u := &UIS{Base: uis.URL, HC: hc}
	if err := u.Login(t.Context(), svc.URL+"/login/cas", "20300", "secret"); err != nil {
		t.Fatal(err)
	}
	// Already signed in: the service answers without UIS.
	if err := u.Login(t.Context(), svc.URL+"/login/cas", "20300", "wrong"); err != nil {
		t.Fatal(err)
	}
	err := (&UIS{Base: uis.URL, HC: client()}).Login(t.Context(), svc.URL+"/login/cas", "20300", "wrong")
	if err == nil || !strings.Contains(err.Error(), "用户名或密码错误") {
		t.Fatalf("want credential error, got %v", err)
	}
}
