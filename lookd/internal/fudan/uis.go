// Package fudan signs in to Fudan University services through UIS
// (id.fudan.edu.cn) over plain HTTP and builds WebVPN addresses for
// campus-only hosts. Protocol learned from the public UIS web client;
// implementation is original.
// Contract: docs/specs/0011-canvas-and-schools.md
package fudan

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

const UISBase = "https://id.fudan.edu.cn"

var (
	ErrBadCredentials = errors.New("复旦 UIS 学号或密码错误")
	ErrNeedsPassword  = errors.New("复旦 UIS 需要重新输入密码") // credentials asked for, none given
	ticketRe          = regexp.MustCompile(`locationValue\s*=\s*"([^"]*ticket=[^"]*)"`)
	lckRe             = regexp.MustCompile(`lck=([^&#"]+)`)
	entityRe          = regexp.MustCompile(`entityId=([^&#"]+)`)
)

// UIS signs in with a username and password for one CAS service.
type UIS struct {
	Base string       // default UISBase; tests point it at a fake
	HC   *http.Client // must carry a cookie jar
	// VPN reaches UIS through WebVPN, for services behind the gateway; the
	// gateway session must exist already.
	VPN bool
	// Entity is the service's entity id when the sign-in address lacks one.
	Entity string
}

func (u *UIS) base() string {
	if u.Base != "" {
		return u.Base
	}
	if u.VPN {
		b, _ := VPNURL(UISBase)
		return b
	}
	return UISBase
}

func (u *UIS) do(req *http.Request) (*http.Response, error) {
	req.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")
	req.Header.Set("Referer", u.base()+"/ac/")
	if req.Method == http.MethodPost {
		if b, err := url.Parse(u.base()); err == nil {
			req.Header.Set("Origin", b.Scheme+"://"+b.Host)
		}
	}
	return u.HC.Do(req)
}

func (u *UIS) postJSON(ctx context.Context, path string, in, out any) error {
	b, _ := json.Marshal(in)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u.base()+path, bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := u.do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("UIS %s: HTTP %d", path, resp.StatusCode)
	}
	return json.Unmarshal(raw, out)
}

// Login runs the UIS chain for start, a URL that redirects to UIS (for
// example a service's CAS login page), and follows the ticket back to the
// service. On return the jar holds the service's session cookies. While the
// UIS session itself lasts, the service is signed in without the password;
// otherwise an empty password is ErrNeedsPassword.
func (u *UIS) Login(ctx context.Context, start, username, password string) error {
	// 1. The service redirects to UIS; the address carries lck and entityId.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, start, nil)
	if err != nil {
		return err
	}
	resp, err := u.do(req)
	if err != nil {
		return fmt.Errorf("打开复旦 UIS 失败: %w", err)
	}
	io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
	resp.Body.Close()
	final := resp.Request.URL.String()
	if !strings.HasPrefix(final, u.base()) {
		return nil // still signed in: the service took us back directly
	}
	lck, entity := match(lckRe, final), match(entityRe, final)
	if entity == "" {
		entity = u.Entity
	}
	if lck == "" || entity == "" {
		return errors.New("复旦 UIS 登录页缺少 lck 或 entityId")
	}
	if password == "" {
		return ErrNeedsPassword
	}

	// 2. Which auth chain handles username + password.
	var methods struct {
		Code        any    `json:"code"`
		RequestType string `json:"requestType"`
		Data        []struct {
			ModuleCode    string `json:"moduleCode"`
			AuthChainCode string `json:"authChainCode"`
		} `json:"data"`
	}
	if err := u.postJSON(ctx, "/idp/authn/queryAuthMethods", map[string]string{"lck": lck, "entityId": entity}, &methods); err != nil {
		return err
	}
	chain := ""
	for _, m := range methods.Data {
		if m.ModuleCode == "userAndPwd" {
			chain = m.AuthChainCode
		}
	}
	if chain == "" {
		return errors.New("复旦 UIS 没有提供账号密码登录方式")
	}

	// 3. The password is encrypted with the page's RSA key.
	var key struct {
		Data string `json:"data"`
	}
	kreq, _ := http.NewRequestWithContext(ctx, http.MethodGet, u.base()+"/idp/authn/getJsPublicKey", nil)
	kresp, err := u.do(kreq)
	if err != nil {
		return err
	}
	kraw, _ := io.ReadAll(io.LimitReader(kresp.Body, 64<<10))
	kresp.Body.Close()
	if err := json.Unmarshal(kraw, &key); err != nil {
		return fmt.Errorf("复旦 UIS 公钥: %w", err)
	}
	enc, err := encrypt(key.Data, password)
	if err != nil {
		return err
	}

	// 4. Submit the credentials for a login token.
	var exec struct {
		Code       any    `json:"code"`
		Message    string `json:"message"`
		LoginToken string `json:"loginToken"`
	}
	if err := u.postJSON(ctx, "/idp/authn/authExecute", map[string]any{
		"authModuleCode": "userAndPwd", "authChainCode": chain, "entityId": entity, "requestType": methods.RequestType, "lck": lck,
		"authPara": map[string]string{"loginName": username, "password": enc, "verifyCode": ""},
	}, &exec); err != nil {
		return err
	}
	if fmt.Sprint(exec.Code) != "200" || exec.LoginToken == "" {
		if exec.Message != "" {
			return fmt.Errorf("%w：%s", ErrBadCredentials, exec.Message)
		}
		return ErrBadCredentials
	}

	// 5. Trade the token for the service ticket address.
	form := url.Values{"loginToken": {exec.LoginToken}}
	ereq, _ := http.NewRequestWithContext(ctx, http.MethodPost, u.base()+"/idp/authCenter/authnEngine", strings.NewReader(form.Encode()))
	ereq.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	eresp, err := u.do(ereq)
	if err != nil {
		return err
	}
	page, _ := io.ReadAll(io.LimitReader(eresp.Body, 1<<20))
	eresp.Body.Close()
	m := ticketRe.FindSubmatch(page)
	if m == nil {
		return errors.New("复旦 UIS 没有返回服务票据")
	}

	// 6. Follow the ticket; the service sets its session. Behind WebVPN the
	// page may name the service's own address, which only the gateway reaches.
	ticket := html.UnescapeString(string(m[1]))
	if u.VPN && !strings.HasPrefix(ticket, WebVPNBase+"/") {
		if ticket, err = VPNURL(ticket); err != nil {
			return err
		}
	}
	treq, err := http.NewRequestWithContext(ctx, http.MethodGet, ticket, nil)
	if err != nil {
		return err
	}
	tresp, err := u.do(treq)
	if err != nil {
		return err
	}
	io.Copy(io.Discard, io.LimitReader(tresp.Body, 4<<20))
	tresp.Body.Close()
	if strings.HasPrefix(tresp.Request.URL.String(), u.base()) {
		return errors.New("复旦 UIS 票据未被服务接受")
	}
	return nil
}

func match(re *regexp.Regexp, s string) string {
	m := re.FindStringSubmatch(s)
	if m == nil {
		return ""
	}
	v, _ := url.QueryUnescape(m[1])
	return v
}

func encrypt(pubB64, password string) (string, error) {
	der, err := base64.StdEncoding.DecodeString(strings.TrimSpace(pubB64))
	if err != nil {
		return "", fmt.Errorf("复旦 UIS 公钥: %w", err)
	}
	pub, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		return "", fmt.Errorf("复旦 UIS 公钥: %w", err)
	}
	rk, ok := pub.(*rsa.PublicKey)
	if !ok {
		return "", errors.New("复旦 UIS 公钥不是 RSA")
	}
	ct, err := rsa.EncryptPKCS1v15(rand.Reader, rk, []byte(password))
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(ct), nil
}

// ---- WebVPN ----

const WebVPNBase = "https://webvpn.fudan.edu.cn"

// The WebVPN gateway (a Wengine deployment) names a campus host by its
// AES-128-CFB ciphertext under a fixed public key and IV.
var vpnKey = []byte("wrdvpnisthebest!")

// VPNHost returns the gateway path segment for a hostname.
func VPNHost(host string) string {
	block, _ := aes.NewCipher(vpnKey)
	// The gateway pads the plaintext to whole 16-byte blocks before CFB and
	// keeps only as many ciphertext bytes as the host has.
	n := len(host)
	padded := []byte(host)
	if r := n % 16; r != 0 {
		padded = append(padded, bytes.Repeat([]byte{'0'}, 16-r)...)
	}
	out := make([]byte, len(padded))
	cipher.NewCFBEncrypter(block, vpnKey).XORKeyStream(out, padded)
	return hex.EncodeToString(vpnKey) + hex.EncodeToString(out[:n])
}

// VPNURL rewrites a campus URL to go through WebVPN.
func VPNURL(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	proto := u.Scheme
	if p := u.Port(); p != "" {
		proto += "-" + p
	}
	out := WebVPNBase + "/" + proto + "/" + VPNHost(u.Hostname()) + u.EscapedPath()
	if u.RawQuery != "" {
		out += "?" + u.RawQuery
	}
	return out, nil
}
