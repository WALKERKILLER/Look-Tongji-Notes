// Package mineru parses documents (PDF, PPT, Word, images) into Markdown
// with MinerU's online service (https://mineru.net/apiManage/docs).
//
// Two modes: the precise API (token, up to 200 MB / 200 pages per file,
// 1000 pages a day at high priority) and the token-free lightweight agent API
// (10 MB / 20 pages, rate limited per IP, Markdown only).
package mineru

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

const (
	preciseBase = "https://mineru.net/api/v4"
	flashBase   = "https://mineru.net/api/v1/agent"

	DailyPages    = 1000 // high-priority pages per day on the precise API
	MaxBytes      = 200 << 20
	MaxPages      = 200
	FlashMaxBytes = 10 << 20
	FlashMaxPages = 20
)

// Options are the parse settings sent with each file.
type Options struct {
	Model    string `json:"model"` // vlm | pipeline
	OCR      bool   `json:"ocr"`
	Formula  bool   `json:"formula"`
	Table    bool   `json:"table"`
	Language string `json:"language"`
}

func (o Options) normalized() Options {
	if o.Model != "pipeline" {
		o.Model = "vlm"
	}
	if o.Language == "" {
		o.Language = "ch"
	}
	return o
}

// Error is a MinerU API error with a readable message.
type Error struct {
	Code string
	Msg  string
}

var hints = map[string]string{
	"A0202":  "MinerU Token 无效，请在设置中重新填写",
	"A0211":  "MinerU Token 已过期，请到 mineru.net 重新生成",
	"-60005": "文件超过 200 MB 上限",
	"-60006": "文件超过 200 页上限，请拆分后再上传",
	"-60010": "MinerU 解析失败",
	"-60012": "任务不存在",
	"-60018": "今日解析额度已用完，明天再试",
	"-60019": "今日解析额度已用完，明天再试",
	"-30001": "免登录模式只能解析 10 MB 以内的文件，请在设置中填写 MinerU Token",
	"-30002": "不支持的文件类型",
	"-30003": "免登录模式只能解析 20 页以内的文件，请在设置中填写 MinerU Token",
}

func (e Error) Error() string {
	if h, ok := hints[e.Code]; ok {
		return h
	}
	if e.Msg != "" {
		return fmt.Sprintf("MinerU: %s (%s)", e.Msg, e.Code)
	}
	return "MinerU 错误 " + e.Code
}

// Auth reports whether err means the token is unusable.
func Auth(err error) bool {
	var e Error
	return errors.As(err, &e) && (e.Code == "A0202" || e.Code == "A0211")
}

type client struct {
	hc    *http.Client
	base  string
	token string
}

func codeString(v any) string {
	switch x := v.(type) {
	case nil:
		return "0"
	case string:
		return x
	case float64:
		return fmt.Sprintf("%d", int64(x))
	}
	return fmt.Sprint(v)
}

func (c *client) call(ctx context.Context, method, p string, body, out any) error {
	return retry(ctx, func() error { return c.callOnce(ctx, method, p, body, out) })
}

func (c *client) callOnce(ctx context.Context, method, p string, body, out any) error {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+p, rd)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	var env struct {
		Code any             `json:"code"`
		Msg  string          `json:"msg"`
		Data json.RawMessage `json:"data"`
	}
	if json.Unmarshal(raw, &env) != nil {
		if resp.StatusCode == http.StatusUnauthorized {
			return Error{Code: "A0202"}
		}
		return fmt.Errorf("MinerU %s: HTTP %d", p, resp.StatusCode)
	}
	if code := codeString(env.Code); code != "0" {
		return Error{Code: code, Msg: env.Msg}
	}
	if resp.StatusCode >= 400 {
		return fmt.Errorf("MinerU %s: HTTP %d %s", p, resp.StatusCode, env.Msg)
	}
	if out != nil && len(env.Data) > 0 {
		return json.Unmarshal(env.Data, out)
	}
	return nil
}

// retry repeats step on network failures (a cold DNS lookup of the storage
// host can time out once), waiting 2s, 4s, 8s between tries.
func retry(ctx context.Context, step func() error) error {
	var err error
	for i := 0; i < 4; i++ {
		if err = step(); err == nil || !transient(err) {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(2<<i) * time.Second):
		}
	}
	return err
}

func transient(err error) bool {
	var ne net.Error
	var de *net.DNSError
	return errors.As(err, &de) || errors.As(err, &ne) || errors.Is(err, io.ErrUnexpectedEOF)
}

// put uploads a file to a presigned URL. No Content-Type: the signature
// does not cover one.
func (c *client) put(ctx context.Context, url, file string) error {
	return retry(ctx, func() error { return c.putOnce(ctx, url, file) })
}

func (c *client) putOnce(ctx context.Context, url, file string) error {
	f, err := os.Open(file)
	if err != nil {
		return err
	}
	defer f.Close()
	fi, _ := f.Stat()
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, url, f)
	if err != nil {
		return err
	}
	req.ContentLength = fi.Size()
	resp, err := c.hc.Do(req)
	if err != nil {
		return fmt.Errorf("上传到 MinerU 失败: %w", bare(err))
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("上传到 MinerU 失败: HTTP %d", resp.StatusCode)
	}
	return nil
}

func (c *client) download(ctx context.Context, url string, limit int64) (b []byte, err error) {
	err = retry(ctx, func() error {
		b, err = c.downloadOnce(ctx, url, limit)
		return err
	})
	return b, err
}

func (c *client) downloadOnce(ctx context.Context, url string, limit int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("下载解析结果失败: %w", bare(err))
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("下载解析结果失败: HTTP %d", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if int64(len(b)) > limit {
		return nil, errors.New("解析结果过大")
	}
	return b, err
}

// bare drops the request URL from transport errors: presigned upload and
// result links carry signatures that should not end up in the UI or logs.
func bare(err error) error {
	var ue *url.Error
	if errors.As(err, &ue) {
		return ue.Err
	}
	return err
}

// Progress reports parsing state; frac is in [0,1] once pages are known.
type Progress func(stage string, frac float64)

type taskState struct {
	State    string `json:"state"`
	ErrMsg   string `json:"err_msg"`
	ZipURL   string `json:"full_zip_url"`
	MDURL    string `json:"markdown_url"`
	Progress *struct {
		Done  int `json:"extracted_pages"`
		Total int `json:"total_pages"`
	} `json:"extract_progress"`
	Meta *struct {
		Pages int `json:"pages"`
	} `json:"meta"`
}

// wait polls until the task is done or failed.
func wait(ctx context.Context, poll func() (taskState, error), p Progress) (taskState, int, error) {
	interval := 3 * time.Second
	deadline := time.Now().Add(40 * time.Minute)
	pages, strikes := 0, 0
	for {
		st, err := poll()
		switch {
		case err != nil:
			if ctx.Err() != nil {
				return st, pages, ctx.Err()
			}
			var me Error
			if errors.As(err, &me) {
				return st, pages, err
			}
			if strikes++; strikes >= 5 {
				return st, pages, err
			}
		default:
			strikes = 0
			if st.Progress != nil && st.Progress.Total > 0 {
				pages = st.Progress.Total
			}
			if st.Meta != nil && st.Meta.Pages > 0 {
				pages = st.Meta.Pages
			}
			switch st.State {
			case "done":
				return st, pages, nil
			case "failed":
				msg := st.ErrMsg
				if msg == "" {
					msg = "MinerU 解析失败"
				}
				return st, pages, errors.New(msg)
			case "running":
				if st.Progress != nil && st.Progress.Total > 0 {
					p(fmt.Sprintf("解析中 %d/%d 页", st.Progress.Done, st.Progress.Total), float64(st.Progress.Done)/float64(st.Progress.Total))
				} else {
					p("解析中", 0)
				}
			case "converting":
				p("转换格式", 1)
			default:
				p("排队中", 0)
			}
		}
		if time.Now().After(deadline) {
			return st, pages, errors.New("MinerU 解析超时")
		}
		select {
		case <-ctx.Done():
			return st, pages, ctx.Err()
		case <-time.After(interval):
		}
		interval = min(interval+2*time.Second, 10*time.Second)
	}
}

// precise parses with the token API and unpacks the result zip into out.
func (c *client) precise(ctx context.Context, file, out string, o Options, p Progress) (int, error) {
	var created struct {
		BatchID string   `json:"batch_id"`
		URLs    []string `json:"file_urls"`
	}
	p("申请上传", 0)
	err := c.call(ctx, http.MethodPost, "/file-urls/batch", map[string]any{
		"files":          []map[string]any{{"name": filepath.Base(file), "is_ocr": o.OCR, "data_id": "look-studio"}},
		"model_version":  o.Model,
		"enable_formula": o.Formula,
		"enable_table":   o.Table,
		"language":       o.Language,
	}, &created)
	if err != nil {
		return 0, err
	}
	if len(created.URLs) == 0 {
		return 0, errors.New("MinerU 没有返回上传地址")
	}
	p("上传文件", 0)
	if err := c.put(ctx, created.URLs[0], file); err != nil {
		return 0, err
	}
	// Uploaded files are submitted automatically; poll the batch.
	st, pages, err := wait(ctx, func() (taskState, error) {
		var r struct {
			Results []taskState `json:"extract_result"`
		}
		if err := c.call(ctx, http.MethodGet, "/extract-results/batch/"+created.BatchID, nil, &r); err != nil {
			return taskState{}, err
		}
		if len(r.Results) == 0 {
			return taskState{State: "waiting-file"}, nil
		}
		return r.Results[0], nil
	}, p)
	if err != nil {
		return pages, err
	}
	p("下载结果", 1)
	zb, err := c.download(ctx, st.ZipURL, 512<<20)
	if err != nil {
		return pages, err
	}
	n, err := unpack(zb, out)
	if n > 0 {
		pages = n
	}
	return pages, err
}

// flash parses with the token-free lightweight API (Markdown only).
func (c *client) flash(ctx context.Context, file, out string, o Options, p Progress) (int, error) {
	var created struct {
		TaskID  string `json:"task_id"`
		FileURL string `json:"file_url"`
	}
	p("申请上传", 0)
	err := c.call(ctx, http.MethodPost, "/parse/file", map[string]any{
		"file_name": filepath.Base(file), "language": o.Language, "is_ocr": o.OCR,
		"enable_formula": o.Formula, "enable_table": o.Table,
	}, &created)
	if err != nil {
		return 0, err
	}
	p("上传文件", 0)
	if err := c.put(ctx, created.FileURL, file); err != nil {
		return 0, err
	}
	st, pages, err := wait(ctx, func() (taskState, error) {
		var st taskState
		return st, c.call(ctx, http.MethodGet, "/parse/"+created.TaskID, nil, &st)
	}, p)
	if err != nil {
		return pages, err
	}
	p("下载结果", 1)
	md, err := c.download(ctx, st.MDURL, 64<<20)
	if err != nil {
		return pages, err
	}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return pages, err
	}
	return pages, os.WriteFile(filepath.Join(out, "full.md"), md, 0o644)
}

// unpack extracts the Markdown, images and content list from a result zip
// into out and returns the page count found in the content list.
func unpack(zb []byte, out string) (int, error) {
	zr, err := zip.NewReader(bytes.NewReader(zb), int64(len(zb)))
	if err != nil {
		return 0, fmt.Errorf("解析结果不是有效的 zip: %w", err)
	}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return 0, err
	}
	root := filepath.Clean(out) + string(filepath.Separator)
	pages, foundMD := 0, false
	for _, f := range zr.File {
		name := path.Clean(strings.ReplaceAll(f.Name, `\`, "/"))
		base := path.Base(name)
		if f.FileInfo().IsDir() || strings.HasPrefix(name, "../") || path.IsAbs(name) {
			continue
		}
		keep := strings.HasSuffix(base, ".md") || strings.HasSuffix(base, "content_list.json") || strings.Contains(name, "images/")
		if !keep {
			continue // origin PDF, layout and model dumps duplicate the upload
		}
		dst := filepath.Join(out, filepath.FromSlash(name))
		if strings.HasSuffix(base, ".md") && !foundMD {
			dst, foundMD = filepath.Join(out, "full.md"), true
		}
		if !strings.HasPrefix(dst, root) {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return pages, err
		}
		b, err := io.ReadAll(io.LimitReader(rc, 256<<20))
		rc.Close()
		if err != nil {
			return pages, err
		}
		os.MkdirAll(filepath.Dir(dst), 0o755)
		if err := os.WriteFile(dst, b, 0o644); err != nil {
			return pages, err
		}
		if strings.HasSuffix(base, "content_list.json") {
			var items []struct {
				Page int `json:"page_idx"`
			}
			if json.Unmarshal(b, &items) == nil {
				for _, it := range items {
					pages = max(pages, it.Page+1)
				}
			}
		}
	}
	if !foundMD {
		return pages, errors.New("解析结果里没有 Markdown")
	}
	return pages, nil
}
