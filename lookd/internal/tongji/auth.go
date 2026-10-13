// Package tongji implements the look.tongji.edu.cn platform: IAM SSO login
// over plain HTTP (no browser), JWT session handling and the course API.
package tongji

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	"golang.org/x/net/html"
)

const (
	BaseURL    = "https://look.tongji.edu.cn"
	IAMBase    = "https://iam.tongji.edu.cn"
	TenantCode = "222"
	UserAgent  = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

	// Public key from iam.tongji.edu.cn/idp/themes/default/js/main/crypt.js.
	iamRSAPublicKey      = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC9t16RqQWUE/J1IyOfoNHc4r/h6RPnXcWTJ4IbhQVUsEqMMm65F0hiytAgozXmVw68yPJywbpblDrx9zl1wdRcdHCoUvmPdr9/oCQtpQyVc7BXZIN6wJlD6MTeMeni+N0toNPxfXjiAawjNHGZZuT8wQpNEMwsVyJ/lonXaVdGZwIDAQAB"
	checkcodePlaceholder = "请输入验证码"
)

var (
	ErrBadCredentials  = errors.New("学号或密码错误")
	ErrCaptchaRequired = errors.New("需要验证码")
	ErrSSOExpired      = errors.New("IAM 会话已过期")
	jwtInCookie        = regexp.MustCompile(`s:\d+:"(eyJ[^"]+)"`)
	spChainCode        = regexp.MustCompile(`#spAuthChainCode1"\)\.val\('([0-9a-fA-F]+)'\)`)
)

// LoginError carries the IAM-provided message for UI display.
type LoginError struct {
	Kind error
	Msg  string
}

func (e *LoginError) Error() string {
	if e.Msg != "" {
		return e.Kind.Error() + "：" + e.Msg
	}
	return e.Kind.Error()
}
func (e *LoginError) Unwrap() error { return e.Kind }

// loginForm is the parsed username/password form of the IAM page.
type loginForm struct {
	action string
	fields url.Values
	order  []string
	lcKey  string
}

func ssoStartURL() string {
	return BaseURL + "/casapi/index.php?r=auth/login&auType=&tenant_code=" + TenantCode +
		"&forward=" + url.QueryEscape(BaseURL+"/validate")
}

func encryptPassword(pw string) (string, error) {
	der, err := base64.StdEncoding.DecodeString(iamRSAPublicKey)
	if err != nil {
		return "", err
	}
	pub, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		return "", err
	}
	ct, err := rsa.EncryptPKCS1v15(rand.Reader, pub.(*rsa.PublicKey), []byte(pw))
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(ct), nil
}

func newRequest(ctx context.Context, method, u string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, u, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", UserAgent)
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9")
	return req, nil
}

// startSSO walks the redirect chain from look to IAM. If the IAM session in the
// jar is still valid, the chain ends back on look with a fresh _token cookie
// and the returned form is nil.
func startSSO(ctx context.Context, hc *http.Client) (*loginForm, string, error) {
	req, err := newRequest(ctx, http.MethodGet, ssoStartURL(), nil)
	if err != nil {
		return nil, "", err
	}
	resp, err := hc.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("打开登录页失败: %w", err)
	}
	defer resp.Body.Close()
	if resp.Request.URL.Hostname() != "iam.tongji.edu.cn" {
		io.Copy(io.Discard, io.LimitReader(resp.Body, 4<<20))
		if tok := tokenFromJar(hc); tok != "" {
			return nil, tok, nil
		}
		return nil, "", fmt.Errorf("SSO 未返回令牌 (落在 %s)", resp.Request.URL.Hostname())
	}
	page, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, "", err
	}
	doc, err := html.Parse(bytes.NewReader(page))
	if err != nil {
		return nil, "", err
	}
	f := findForm(doc, "authen1Form")
	if f == nil {
		return nil, "", errors.New("未找到 IAM 登录表单")
	}
	// The page script fills the auth-chain code after load.
	if m := spChainCode.FindSubmatch(page); m != nil {
		f.fields.Set("spAuthChainCode", string(m[1]))
	}
	return f, "", nil
}

// Login performs a full username/password IAM login and returns the look JWT.
func Login(ctx context.Context, hc *http.Client, username, password, captcha string) (string, error) {
	clearLookToken(hc)
	form, tok, err := startSSO(ctx, hc)
	if err != nil {
		return "", err
	}
	if tok != "" {
		return tok, nil
	}
	if captcha == "" {
		if need, err := captchaNeeded(ctx, hc, username); err == nil && need {
			return "", &LoginError{Kind: ErrCaptchaRequired}
		}
	}
	enc, err := encryptPassword(password)
	if err != nil {
		return "", err
	}
	form.fields.Set("j_username", username)
	form.fields.Set("j_password", enc)
	if captcha != "" {
		form.fields.Set("j_checkcode", captcha)
	} else {
		form.fields.Set("j_checkcode", checkcodePlaceholder)
	}
	body := form.encode()

	chain := IAMBase + "/idp/authcenter/ActionAuthChain?authnLcKey=" + url.QueryEscape(form.lcKey)
	req, _ := newRequest(ctx, http.MethodPost, chain, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	resp, err := hc.Do(req)
	if err != nil {
		return "", fmt.Errorf("提交登录失败: %w", err)
	}
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if os.Getenv("LOOKD_DEBUG_AUTH") != "" {
		fmt.Fprintf(os.Stderr, "chain status=%d body=%.400s\nform=%v\n", resp.StatusCode, raw, form.order)
	}
	resp.Body.Close()
	var chainResp map[string]any
	if err := json.Unmarshal(raw, &chainResp); err == nil {
		if fmt.Sprint(chainResp["loginFailed"]) == "true" {
			msg, _ := chainResp["authnErrorTip"].(string)
			if strings.Contains(msg, "验证码") {
				return "", &LoginError{Kind: ErrCaptchaRequired, Msg: msg}
			}
			return "", &LoginError{Kind: ErrBadCredentials, Msg: msg}
		}
	}

	action := form.action
	if strings.HasPrefix(action, "/") {
		action = IAMBase + action
	}
	req, _ = newRequest(ctx, http.MethodPost, action, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Referer", chain)
	resp, err = hc.Do(req)
	if err != nil {
		return "", fmt.Errorf("完成 SSO 跳转失败: %w", err)
	}
	io.Copy(io.Discard, io.LimitReader(resp.Body, 4<<20))
	resp.Body.Close()
	if tok := tokenFromJar(hc); tok != "" {
		return tok, nil
	}
	return "", &LoginError{Kind: ErrBadCredentials, Msg: "登录流程结束但未获得令牌"}
}

// SilentRenew reuses the IAM SSO cookies to mint a new look JWT without the
// password. It returns ErrSSOExpired when IAM asks for credentials again.
func SilentRenew(ctx context.Context, hc *http.Client) (string, error) {
	clearLookToken(hc)
	form, tok, err := startSSO(ctx, hc)
	if err != nil {
		return "", err
	}
	if form != nil {
		return "", ErrSSOExpired
	}
	return tok, nil
}

func captchaNeeded(ctx context.Context, hc *http.Client, username string) (bool, error) {
	v := url.Values{"j_username": {username}, "j_authMethodID": {"1"}, "spAuthChainCode": {""}}
	req, _ := newRequest(ctx, http.MethodPost, IAMBase+"/idp/displayVerificationCode.do", strings.NewReader(v.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	resp, err := hc.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 64))
	return strings.TrimSpace(string(b)) == "true", nil
}

// Captcha fetches the IAM captcha image bound to the current jar session.
func Captcha(ctx context.Context, hc *http.Client) ([]byte, string, error) {
	if _, _, err := startSSO(ctx, hc); err != nil {
		return nil, "", err
	}
	u := fmt.Sprintf("%s/idp/Kaptcha.jpg?date=%d", IAMBase, time.Now().UnixMilli())
	req, _ := newRequest(ctx, http.MethodGet, u, nil)
	resp, err := hc.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return b, resp.Header.Get("Content-Type"), err
}

func lookURL() *url.URL { u, _ := url.Parse(BaseURL + "/"); return u }

func tokenFromJar(hc *http.Client) string {
	if hc.Jar == nil {
		return ""
	}
	for _, c := range hc.Jar.Cookies(lookURL()) {
		if c.Name != "_token" {
			continue
		}
		v := c.Value
		if dec, err := url.QueryUnescape(v); err == nil {
			v = dec
		}
		if m := jwtInCookie.FindStringSubmatch(v); m != nil {
			return m[1]
		}
		if strings.HasPrefix(v, "eyJ") {
			return v
		}
	}
	return ""
}

func clearLookToken(hc *http.Client) {
	if hc.Jar != nil {
		hc.Jar.SetCookies(lookURL(), []*http.Cookie{{Name: "_token", Value: "", Path: "/", MaxAge: -1}})
	}
}

func (f *loginForm) encode() string {
	var b strings.Builder
	for i, k := range f.order {
		if i > 0 {
			b.WriteByte('&')
		}
		b.WriteString(url.QueryEscape(k))
		b.WriteByte('=')
		b.WriteString(url.QueryEscape(f.fields.Get(k)))
	}
	return b.String()
}

func attr(n *html.Node, key string) string {
	for _, a := range n.Attr {
		if a.Key == key {
			return a.Val
		}
	}
	return ""
}

func findForm(n *html.Node, id string) *loginForm {
	if n.Type == html.ElementNode && n.Data == "form" && attr(n, "id") == id {
		f := &loginForm{action: attr(n, "action"), fields: url.Values{}}
		var walk func(*html.Node)
		walk = func(c *html.Node) {
			if c.Type == html.ElementNode && c.Data == "input" {
				if name := attr(c, "name"); name != "" {
					if _, seen := f.fields[name]; !seen {
						f.order = append(f.order, name)
						f.fields.Set(name, attr(c, "value"))
					}
				}
			}
			for k := c.FirstChild; k != nil; k = k.NextSibling {
				walk(k)
			}
		}
		walk(n)
		f.lcKey = f.fields.Get("authnLcKey")
		return f
	}
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		if f := findForm(c, id); f != nil {
			return f
		}
	}
	return nil
}
