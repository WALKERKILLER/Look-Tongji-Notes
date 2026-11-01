// Package nasbridge exposes a narrow adapter to existing personal NAS workers.
// Contract: docs/specs/0017-nas-learning-services.md. No worker source is copied.
package nasbridge

import (
	"context"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

//go:embed probe.py
var probe string

type Runner func(context.Context, string, string) ([]byte, error)
type Bridge struct {
	Root, Calendar, Alias string
	Run                   Runner
	mu                    sync.Mutex
	snapshot              map[string]any
	attempted             time.Time
	commands              map[string]time.Time
}

func New() *Bridge {
	return &Bridge{Root: os.Getenv("LOOK_NAS_COURSES"), Calendar: os.Getenv("LOOK_NAS_CALENDAR"), Alias: os.Getenv("LOOK_NAS_HOST"), commands: map[string]time.Time{}}
}

type bounded struct{ data []byte }

func (b *bounded) Write(p []byte) (int, error) {
	if len(b.data)+len(p) > 2<<20 {
		return 0, errors.New("NAS response exceeds limit")
	}
	b.data = append(b.data, p...)
	return len(p), nil
}
func (b *Bridge) run(ctx context.Context, command, input string) ([]byte, error) {
	if b.Run != nil {
		return b.Run(ctx, command, input)
	}
	if strings.TrimSpace(b.Alias) == "" {
		return nil, errors.New("NAS 未配置：请设置 LOOK_NAS_HOST")
	}
	ctx, cancel := context.WithTimeout(ctx, 25*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=yes", "--", b.Alias, command)
	cmd.Stdin = strings.NewReader(input)
	var out bounded
	cmd.Stdout = &out
	cmd.Stderr = io.Discard
	err := cmd.Run()
	return out.data, err
}
func (b *Bridge) Snapshot(ctx context.Context, refresh bool) map[string]any {
	b.mu.Lock()
	defer b.mu.Unlock()
	if time.Since(b.attempted) > 30*time.Second || (refresh && time.Since(b.attempted) > 5*time.Second) {
		b.attempted = time.Now()
		raw, err := b.run(ctx, "python3 -", probe)
		var d map[string]any
		if err == nil {
			err = json.Unmarshal(raw, &d)
		}
		if err == nil && d["observed_at"] != nil && d["jobs"] != nil && d["services"] != nil {
			b.snapshot = d
			b.snapshot["online"] = true
			delete(b.snapshot, "error")
		} else {
			if b.snapshot == nil {
				b.snapshot = map[string]any{"jobs": []any{}, "services": []any{}}
			}
			b.snapshot["online"] = false
			b.snapshot["error"] = "无法读取 NAS 状态，保留上次结果；请检查 SSH 连接。"
			if b.Alias == "" && b.Run == nil {
				b.snapshot["error"] = "NAS 未配置：请设置 LOOK_NAS_HOST、LOOK_NAS_COURSES 和 LOOK_NAS_CALENDAR。"
			}
		}
	}
	result := map[string]any{}
	for k, v := range b.snapshot {
		result[k] = v
	}
	result["checked_at"] = b.attempted.Format(time.RFC3339)
	result["pending_actions"] = b.commandsCopy()
	return result
}
func (b *Bridge) commandsCopy() map[string]string {
	r := map[string]string{}
	for k, v := range b.commands {
		r[k] = v.Format(time.RFC3339)
	}
	return r
}

var units = map[string]string{"homework": "course-homework.service", "calendar": "course-calendar-nightly.service"}

func (b *Bridge) Start(ctx context.Context, action string) (map[string]string, error) {
	unit, ok := units[action]
	if !ok {
		return nil, errors.New("不支持的 NAS 操作")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if at, ok := b.commands[action]; ok && time.Since(at) < 2*time.Minute {
		return nil, errors.New("该请求已发送或结果待确认，请先刷新状态")
	}
	raw, err := b.run(ctx, "systemctl --user show --property=ActiveState --value "+unit, "")
	if err != nil {
		return nil, errors.New("无法确认任务状态，未发送运行请求")
	}
	state := strings.TrimSpace(string(raw))
	if state != "inactive" && state != "failed" {
		return nil, errors.New("任务正在运行或状态不明，请等待结束")
	}
	if b.commands == nil {
		b.commands = map[string]time.Time{}
	}
	b.commands[action] = time.Now()
	_, err = b.run(ctx, "systemctl --user start --no-block "+unit, "")
	b.attempted = time.Time{}
	if err != nil {
		return map[string]string{"state": "unknown", "message": "请求结果未确认，请刷新状态；不会自动重试。"}, nil
	}
	return map[string]string{"state": "accepted", "message": "NAS 已接受请求，执行结果请查看服务状态和作业列表。"}, nil
}

type File struct {
	ID       string `json:"id"`
	Path     string `json:"path"`
	Course   string `json:"course"`
	Kind     string `json:"kind"`
	Size     int64  `json:"size"`
	Modified string `json:"modified"`
}

var allowed = map[string]bool{".md": true, ".txt": true, ".pdf": true, ".ppt": true, ".pptx": true, ".doc": true, ".docx": true, ".png": true, ".jpg": true, ".jpeg": true, ".webp": true, ".zip": true, ".csv": true, ".json": true, ".py": true, ".c": true, ".h": true, ".cpp": true, ".ipynb": true, ".html": true, ".srt": true, ".xlsx": true}

func FileID(rel string) string { h := sha256.Sum256([]byte(rel)); return hex.EncodeToString(h[:16]) }
func visible(rel string) bool {
	for _, p := range strings.Split(filepath.ToSlash(rel), "/") {
		if strings.HasPrefix(p, ".") || p == "node_modules" || p == "venv" || p == "__pycache__" {
			return false
		}
	}
	return true
}
func (b *Bridge) Files() ([]File, error) {
	out := []File{}
	if _, err := os.Stat(b.Root); err != nil {
		return out, err
	}
	err := filepath.WalkDir(b.Root, func(p string, d fs.DirEntry, e error) error {
		if e != nil {
			return nil
		}
		rel, _ := filepath.Rel(b.Root, p)
		if rel == "." {
			return nil
		}
		if !visible(rel) {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		parts := strings.Split(filepath.ToSlash(rel), "/")
		if len(parts) < 3 || !allowed[strings.ToLower(filepath.Ext(p))] {
			return nil
		}
		kind := ""
		switch parts[1] {
		case "1.课程总览":
			kind = "overview"
		case "2.录课转写":
			kind = "lecture"
		case "3.课程资料":
			kind = "material"
		case "4.课程作业":
			kind = "homework"
		}
		if kind == "" {
			return nil
		}
		fi, err := d.Info()
		if err != nil || !fi.Mode().IsRegular() {
			return nil
		}
		if len(out) >= 10000 {
			return errors.New("资料超过一万份，请缩小课程目录")
		}
		out = append(out, File{FileID(filepath.ToSlash(rel)), filepath.ToSlash(rel), parts[0], kind, fi.Size(), fi.ModTime().Format(time.RFC3339)})
		return nil
	})
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out, err
}

// Open uses os.Root for the final operation, not only a preceding path check.
func (b *Bridge) Open(id string) (*os.File, File, error) {
	files, err := b.Files()
	if err != nil {
		return nil, File{}, err
	}
	for _, f := range files {
		if f.ID == id {
			root, e := os.OpenRoot(b.Root)
			if e != nil {
				return nil, f, e
			}
			defer root.Close()
			fh, e := root.Open(f.Path)
			return fh, f, e
		}
	}
	return nil, File{}, os.ErrNotExist
}
func (b *Bridge) Text(id string) (map[string]any, error) {
	f, meta, err := b.Open(id)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	switch strings.ToLower(filepath.Ext(meta.Path)) {
	case ".md", ".txt", ".srt", ".py", ".c", ".h", ".cpp", ".html", ".csv":
	default:
		return nil, errors.New("该格式请打开原文件；尚未生成可检索文本")
	}
	raw, err := io.ReadAll(io.LimitReader(f, 64001))
	if err != nil {
		return nil, err
	}
	r := []rune(string(raw))
	trunc := len(raw) > 64000 || len(r) > 12000
	if len(r) > 12000 {
		r = r[:12000]
	}
	return map[string]any{"file": meta, "text": string(r), "truncated": trunc}, nil
}

var calendarURL = regexp.MustCompile(`https://elearning\.fudan\.edu\.cn/courses/(\d+)/assignments/(\d+)`)

func (b *Bridge) Deadlines() ([]map[string]string, error) {
	entries, err := os.ReadDir(b.Calendar)
	out := []map[string]string{}
	if err != nil {
		return out, err
	}
	root, err := os.OpenRoot(b.Calendar)
	if err != nil {
		return out, err
	}
	defer root.Close()
	for _, e := range entries {
		if e.IsDir() || strings.HasPrefix(e.Name(), ".") || !strings.HasSuffix(e.Name(), ".md") || e.Type()&os.ModeSymlink != 0 {
			continue
		}
		f, err := root.Open(e.Name())
		if err != nil {
			continue
		}
		raw, _ := io.ReadAll(io.LimitReader(f, 64000))
		f.Close()
		s := string(raw)
		if !strings.HasPrefix(s, "---\n") {
			continue
		}
		parts := strings.SplitN(s, "---", 3)
		if len(parts) < 3 {
			continue
		}
		d := map[string]string{}
		for _, line := range strings.Split(parts[1], "\n") {
			k, v, ok := strings.Cut(line, ":")
			if !ok {
				continue
			}
			switch k {
			case "title", "course", "due", "completed", "generated_key":
				d[k] = strings.Trim(strings.TrimSpace(v), "\"")
			}
		}
		if _, err := time.Parse(time.RFC3339, d["due"]); err != nil {
			continue
		}
		if m := calendarURL.FindStringSubmatch(s); m != nil {
			d["url"] = m[0]
			d["canvas_course_id"] = m[1]
			d["assignment_id"] = m[2]
		}
		d["id"] = "nas:" + d["generated_key"]
		if d["generated_key"] == "" {
			d["id"] = "nas:" + FileID(e.Name())
		}
		out = append(out, d)
	}
	sort.Slice(out, func(i, j int) bool { return out[i]["due"] < out[j]["due"] })
	return out, nil
}
