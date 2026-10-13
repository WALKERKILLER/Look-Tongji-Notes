// Package asr transcribes lecture audio with free cloud services — Bilibili's
// BcutASR (same pipeline as the Look Tongji Notes skill) and JianYing — balanced
// by Pool, and extracts audio via ffmpeg.
package asr

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

const api = "https://member.bilibili.com/x/bcut/rubick-interface"

var ErrNoAudio = errors.New("媒体中没有音轨")

// errEmpty means the audio held no recognisable speech.
var errEmpty = errors.New("识别结果为空")

type Utterance struct {
	StartMs int64  `json:"start_time"`
	EndMs   int64  `json:"end_time"`
	Text    string `json:"transcript"`
}

// Client is the Bilibili 必剪 (BcutASR) channel.
type Client struct {
	hc   *http.Client
	pace *pacer
}

const bcutUA = "Bilibili/1.0.0 (https://www.bilibili.com)"

// New builds the client on its own transport; rt is kept for tests.
func New(rt http.RoundTripper) *Client {
	if rt == nil {
		rt = newTransport()
	}
	return &Client{hc: &http.Client{Transport: rt, Timeout: 3 * time.Minute}, pace: &pacer{gap: 800 * time.Millisecond}}
}

// apiErr is a JSON-level error; Bilibili reports risk control and "too
// frequent" this way too, with HTTP 200.
type apiErr struct {
	svc  string
	code int
	msg  string
}

func (e apiErr) Error() string { return fmt.Sprintf("%s: %d %s", e.svc, e.code, e.msg) }
func (e apiErr) limited() bool {
	return e.code == -412 || e.code == -429 || e.code == -509 || e.code == -799 || e.code == -500 || e.code == -503
}

func (c *Client) call(ctx context.Context, method, u string, body any, out any) error {
	if err := c.pace.wait(ctx); err != nil {
		return err
	}
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, rd)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", bcutUA)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return statusErr("必剪", req.URL.Path, resp)
	}
	var env struct {
		Code    int             `json:"code"`
		Message string          `json:"message"`
		Data    json.RawMessage `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return err
	}
	if env.Code != 0 {
		return apiErr{svc: "必剪", code: env.Code, msg: env.Message}
	}
	return json.Unmarshal(env.Data, out)
}

// Stage reports progress to the caller with a human-readable label.
type Stage func(stage string, frac float64)

// Transcribe uploads an mp3 file and waits for the recognition result. Each
// step retries transient failures; polling gives up after repeated rate
// limiting so the pool can move the chunk elsewhere.
func (c *Client) Transcribe(ctx context.Context, mp3 string, onStage Stage) ([]Utterance, error) {
	data, err := os.ReadFile(mp3)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, errors.New("音频为空")
	}
	var up struct {
		InBossKey  string   `json:"in_boss_key"`
		ResourceID string   `json:"resource_id"`
		UploadID   string   `json:"upload_id"`
		UploadURLs []string `json:"upload_urls"`
		PerSize    int      `json:"per_size"`
	}
	if err := retry(ctx, 3, func() error {
		return c.call(ctx, http.MethodPost, api+"/resource/create", map[string]any{
			"type": 2, "name": "audio.mp3", "size": len(data), "ResourceFileType": "mp3", "model_id": "8",
		}, &up)
	}); err != nil {
		return nil, err
	}
	if up.PerSize <= 0 || len(up.UploadURLs) == 0 {
		return nil, errors.New("必剪: 没有返回上传地址")
	}
	etags := make([]string, len(up.UploadURLs))
	for i, u := range up.UploadURLs {
		start, end := min(i*up.PerSize, len(data)), min((i+1)*up.PerSize, len(data))
		if err := retry(ctx, 3, func() error {
			if err := c.pace.wait(ctx); err != nil {
				return err
			}
			req, _ := http.NewRequestWithContext(ctx, http.MethodPut, u, bytes.NewReader(data[start:end]))
			req.Header.Set("User-Agent", bcutUA)
			resp, err := c.hc.Do(req)
			if err != nil {
				return err
			}
			io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
			resp.Body.Close()
			if resp.StatusCode/100 != 2 {
				return statusErr("必剪", fmt.Sprintf("upload part %d", i), resp)
			}
			etags[i] = resp.Header.Get("Etag")
			return nil
		}); err != nil {
			return nil, err
		}
		if onStage != nil {
			onStage("upload", float64(i+1)/float64(len(up.UploadURLs)))
		}
	}
	var commit struct {
		DownloadURL string `json:"download_url"`
	}
	if err := retry(ctx, 3, func() error {
		return c.call(ctx, http.MethodPost, api+"/resource/create/complete", map[string]any{
			"InBossKey": up.InBossKey, "ResourceId": up.ResourceID, "Etags": strings.Join(etags, ","),
			"UploadId": up.UploadID, "model_id": "8",
		}, &commit)
	}); err != nil {
		return nil, err
	}
	var task struct {
		TaskID string `json:"task_id"`
	}
	if err := retry(ctx, 3, func() error {
		return c.call(ctx, http.MethodPost, api+"/task", map[string]any{"resource": commit.DownloadURL, "model_id": "8"}, &task)
	}); err != nil {
		return nil, err
	}
	poll := newPoller(10 * time.Minute)
	for {
		var res struct {
			State  int    `json:"state"`
			Result string `json:"result"`
		}
		err := c.call(ctx, http.MethodGet, api+"/task/result?model_id=7&task_id="+task.TaskID, nil, &res)
		if err == nil {
			switch res.State {
			case 4:
				var r struct {
					Utterances []Utterance `json:"utterances"`
				}
				if err := json.Unmarshal([]byte(res.Result), &r); err != nil {
					return nil, err
				}
				if len(r.Utterances) == 0 {
					return nil, errEmpty
				}
				return r.Utterances, nil
			case -1, 5:
				return nil, fmt.Errorf("必剪识别任务失败 (state=%d)", res.State)
			}
			if onStage != nil {
				onStage("recognize", float64(res.State)/4)
			}
		}
		if perr := poll.next(ctx, err); perr != nil {
			return nil, perr
		}
	}
}

// ExtractAudio converts any media (local path or URL) to 16 kHz mono mp3.
func ExtractAudio(ctx context.Context, input string, headers string, out string) error {
	args := []string{"-hide_banner", "-loglevel", "error", "-nostdin"}
	if headers != "" {
		args = append(args, "-headers", headers)
	}
	if strings.HasPrefix(input, "http") {
		args = append(args, "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5")
	}
	args = append(args, "-i", input, "-vn", "-ar", "16000", "-ac", "1", "-c:a", "libmp3lame", "-q:a", "5", "-y", out)
	cmd := exec.CommandContext(ctx, "ffmpeg", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := stderr.String()
		if strings.Contains(msg, "does not contain any stream") || strings.Contains(msg, "Output file does not contain") {
			return ErrNoAudio
		}
		if len(msg) > 400 {
			msg = msg[len(msg)-400:]
		}
		return fmt.Errorf("ffmpeg: %v: %s", err, msg)
	}
	if fi, err := os.Stat(out); err != nil || fi.Size() == 0 {
		return ErrNoAudio
	}
	return nil
}

// HasFFmpeg reports whether ffmpeg is on PATH.
func HasFFmpeg() bool { _, err := exec.LookPath("ffmpeg"); return err == nil }
