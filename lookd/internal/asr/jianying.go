package asr

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"hash/fnv"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// JianYing talks to the free speech-recognition service behind JianYing
// (剪映) desktop, following the protocol documented by the VideoCaptioner
// project. Request signatures come from VideoCaptioner's public signing
// service, which only sees the API path, a timestamp and a device id; the
// audio goes to ByteDance's upload service.
type JianYing struct {
	hc   *http.Client
	tdid string
	// The public signing service rate-limits per IP, so signatures are
	// spaced out; ByteDance's own endpoints are far less strict.
	signPace *pacer
}

const (
	jyAPI     = "https://lv-pc-api-sinfonlinec.ulikecam.com"
	jySignAPI = "https://asrtools-update.bkfeng.top/sign"
	jyAppVer  = "6.6.0"
)

// NewJianYing builds the client on its own transport; rt is kept for tests.
func NewJianYing(rt http.RoundTripper) *JianYing {
	if rt == nil {
		rt = newTransport()
	}
	return &JianYing{hc: &http.Client{Transport: rt, Timeout: 3 * time.Minute}, tdid: deviceID(), signPace: &pacer{gap: 1500 * time.Millisecond}}
}

// deviceID is a stable 16-digit id in the shape the service expects
// ("39" + year digit + 13 digits), derived from this machine.
func deviceID() string {
	seed, _ := os.ReadFile("/etc/machine-id")
	if len(seed) == 0 {
		h, _ := os.Hostname()
		seed = []byte(h)
	}
	f := fnv.New64a()
	f.Write(seed)
	y := time.Now().Year() % 10
	return fmt.Sprintf("%d%013d", 390+y, f.Sum64()%1e13)
}

func (c *JianYing) sign(ctx context.Context, path string) (sig, ts string, err error) {
	if err := c.signPace.wait(ctx); err != nil {
		return "", "", err
	}
	ts = strconv.FormatInt(time.Now().Unix(), 10)
	b, _ := json.Marshal(map[string]string{"url": path, "current_time": ts, "pf": "4", "appvr": jyAppVer, "tdid": c.tdid})
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, jySignAPI, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "LookStudio/0.1")
	req.Header.Set("tdid", c.tdid)
	req.Header.Set("t", ts)
	resp, err := c.hc.Do(req)
	if err != nil {
		return "", "", fmt.Errorf("剪映签名服务: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", "", statusErr("剪映签名服务", "/sign", resp)
	}
	var out struct {
		Sign string `json:"sign"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil || out.Sign == "" {
		return "", "", errors.New("剪映签名服务没有返回签名")
	}
	return strings.ToLower(out.Sign), ts, nil
}

// call posts to a signed JianYing endpoint and decodes {ret, errmsg, data},
// re-signing and retrying transient failures.
func (c *JianYing) call(ctx context.Context, path string, body any, out any) error {
	return retry(ctx, 3, func() error { return c.callOnce(ctx, path, body, out) })
}

func (c *JianYing) callOnce(ctx context.Context, path string, body any, out any) error {
	sig, ts, err := c.sign(ctx, path)
	if err != nil {
		return err
	}
	b, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, jyAPI+path, bytes.NewReader(b))
	for k, v := range map[string]string{
		"User-Agent": "Cronet/TTNetVersion:d4572e53 2024-06-12 QuicVersion:4bf243e0 2023-04-17",
		"appvr":      jyAppVer, "device-time": ts, "pf": "4", "sign": sig, "sign-ver": "1", "tdid": c.tdid,
		"Content-Type": "application/json",
	} {
		req.Header.Set(k, v)
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return statusErr("剪映", path, resp)
	}
	var env struct {
		Ret    string          `json:"ret"`
		Errmsg string          `json:"errmsg"`
		Data   json.RawMessage `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return err
	}
	if env.Ret != "0" {
		return fmt.Errorf("剪映 %s: %s (ret=%s)", path, env.Errmsg, env.Ret)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(env.Data, out)
}

// Transcribe uploads an audio file and returns its utterances.
func (c *JianYing) Transcribe(ctx context.Context, audio string, onStage Stage) ([]Utterance, error) {
	data, err := os.ReadFile(audio)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, errors.New("音频为空")
	}
	crc := fmt.Sprintf("%08x", crc32.ChecksumIEEE(data))

	var cred struct {
		AccessKey string `json:"access_key_id"`
		Secret    string `json:"secret_access_key"`
		Token     string `json:"session_token"`
	}
	if err := c.call(ctx, "/lv/v1/upload_sign", map[string]string{"biz": "pc-recognition"}, &cred); err != nil {
		return nil, err
	}
	var up jyUpload
	if err := retry(ctx, 3, func() (err error) {
		up, err = c.applyUpload(ctx, cred.AccessKey, cred.Secret, cred.Token, len(data))
		return err
	}); err != nil {
		return nil, err
	}
	if onStage != nil {
		onStage("upload", 0.3)
	}
	base := "https://" + up.host + "/" + up.storeURI
	putOnce := func(method, u string, body []byte) (map[string]any, error) {
		req, _ := http.NewRequestWithContext(ctx, method, u, bytes.NewReader(body))
		req.Header.Set("Authorization", up.auth)
		req.Header.Set("Content-CRC32", crc)
		resp, err := c.hc.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
		if resp.StatusCode/100 != 2 {
			return nil, statusErr("剪映", "upload", resp)
		}
		var m map[string]any
		json.Unmarshal(raw, &m)
		return m, nil
	}
	put := func(method, u string, body []byte) (m map[string]any, err error) {
		err = retry(ctx, 3, func() error { m, err = putOnce(method, u, body); return err })
		return m, err
	}
	r, err := put(http.MethodPut, base+"?partNumber=1&uploadID="+up.uploadID, data)
	if err != nil {
		return nil, err
	}
	if s, _ := r["success"].(float64); s != 0 {
		return nil, fmt.Errorf("剪映上传失败: %v", r)
	}
	if _, err := put(http.MethodPost, base+"?uploadID="+up.uploadID, []byte("1:"+crc)); err != nil {
		return nil, err
	}
	if onStage != nil {
		onStage("upload", 1)
	}

	var task struct {
		ID string `json:"id"`
	}
	if err := c.call(ctx, "/lv/v1/audio_subtitle/submit", map[string]any{
		"adjust_endtime": 200, "audio": up.storeURI, "caption_type": 2, "client_request_id": newUUID(),
		"max_lines": 1, "words_per_line": 16,
		"songs_info": []map[string]any{{"end_time": 6000, "id": "", "start_time": 0}},
	}, &task); err != nil {
		return nil, err
	}

	poll := newPoller(10 * time.Minute)
	for {
		if onStage != nil {
			onStage("recognize", 0.5)
		}
		var res struct {
			Utterances []struct {
				Text  string `json:"text"`
				Start int64  `json:"start_time"`
				End   int64  `json:"end_time"`
			} `json:"utterances"`
		}
		// One attempt per poll; the poller decides on backoff and giving up.
		err := c.callOnce(ctx, "/lv/v1/audio_subtitle/query", map[string]any{"id": task.ID, "pack_options": map[string]any{"need_attribute": true}}, &res)
		if err == nil && res.Utterances != nil {
			out := make([]Utterance, 0, len(res.Utterances))
			for _, u := range res.Utterances {
				out = append(out, Utterance{StartMs: u.Start, EndMs: u.End, Text: u.Text})
			}
			if len(out) == 0 {
				return nil, errEmpty
			}
			return out, nil
		}
		if perr := poll.next(ctx, err); perr != nil {
			return nil, perr
		}
	}
}

type jyUpload struct{ host, storeURI, auth, uploadID string }

// applyUpload asks ByteDance VOD for an upload slot (AWS SigV4, region cn).
func (c *JianYing) applyUpload(ctx context.Context, ak, sk, token string, size int) (jyUpload, error) {
	q := "Action=ApplyUploadInner&FileSize=" + strconv.Itoa(size) + "&FileType=object&IsInner=1&SpaceName=lv-mac-recognition&Version=2020-11-19&s=5y0udbjapi"
	now := time.Now().UTC()
	amzDate, day := now.Format("20060102T150405Z"), now.Format("20060102")
	canonHeaders := "x-amz-date:" + amzDate + "\nx-amz-security-token:" + token + "\n"
	signed := "x-amz-date;x-amz-security-token"
	emptyHash := sha256.Sum256(nil)
	canon := strings.Join([]string{"GET", "/", q, canonHeaders, signed, hex.EncodeToString(emptyHash[:])}, "\n")
	scope := day + "/cn/vod/aws4_request"
	ch := sha256.Sum256([]byte(canon))
	toSign := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + hex.EncodeToString(ch[:])
	mac := func(key []byte, s string) []byte {
		m := hmac.New(sha256.New, key)
		m.Write([]byte(s))
		return m.Sum(nil)
	}
	k := mac(mac(mac(mac([]byte("AWS4"+sk), day), "cn"), "vod"), "aws4_request")
	sig := hex.EncodeToString(mac(k, toSign))

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "https://vod.bytedanceapi.com/?"+q, nil)
	req.Header.Set("x-amz-date", amzDate)
	req.Header.Set("x-amz-security-token", token)
	req.Header.Set("Authorization", "AWS4-HMAC-SHA256 Credential="+ak+"/"+scope+", SignedHeaders="+signed+", Signature="+sig)
	resp, err := c.hc.Do(req)
	if err != nil {
		return jyUpload{}, err
	}
	defer resp.Body.Close()
	var r struct {
		Result struct {
			UploadAddress struct {
				StoreInfos []struct {
					StoreURI string `json:"StoreUri"`
					Auth     string `json:"Auth"`
					UploadID string `json:"UploadID"`
				} `json:"StoreInfos"`
				UploadHosts []string `json:"UploadHosts"`
			} `json:"UploadAddress"`
		} `json:"Result"`
	}
	if resp.StatusCode != 200 {
		return jyUpload{}, statusErr("剪映", "ApplyUploadInner", resp)
	}
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return jyUpload{}, fmt.Errorf("剪映上传地址: %w", err)
	}
	ua := r.Result.UploadAddress
	if len(ua.StoreInfos) == 0 || len(ua.UploadHosts) == 0 {
		return jyUpload{}, fmt.Errorf("剪映上传地址: HTTP %d, 无可用地址", resp.StatusCode)
	}
	s := ua.StoreInfos[0]
	return jyUpload{host: ua.UploadHosts[0], storeURI: s.StoreURI, auth: s.Auth, uploadID: s.UploadID}, nil
}

func newUUID() string {
	var b [16]byte
	rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}
