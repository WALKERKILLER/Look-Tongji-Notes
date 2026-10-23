package localasr

import (
	"archive/tar"
	"compress/bzip2"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

var ErrRunning = errors.New("正在下载本地模型")

// Progress is the state of the current or last install.
type Progress struct {
	State  string  `json:"state"` // idle | running | done | failed | canceled
	Model  string  `json:"model,omitempty"`
	Source string  `json:"source,omitempty"`
	Step   string  `json:"step,omitempty"`
	Done   int64   `json:"done"`
	Total  int64   `json:"total"`
	Speed  float64 `json:"speed"` // bytes per second
	Note   string  `json:"note,omitempty"`
	Error  string  `json:"error,omitempty"`
}

// Options are the user's download settings.
type Options struct {
	Source string
	Custom string // URL template for the custom source
	Proxy  string // prefix for GitHub release URLs, e.g. a mirror of github.com
}

// Manager installs and removes the engine and models under Dir.
type Manager struct {
	Dir      string // <data>/asr
	Client   *http.Client
	OS, Arch string
	Publish  func(Progress)

	mu     sync.Mutex
	st     Progress
	cancel context.CancelFunc
}

func (m *Manager) platform() string {
	goos, arch := m.OS, m.Arch
	if goos == "" {
		goos = runtime.GOOS
	}
	if arch == "" {
		arch = runtime.GOARCH
	}
	return goos + "/" + arch
}

// Supported reports whether a prebuilt engine exists for this machine.
func (m *Manager) Supported() bool { _, ok := engines[m.platform()]; return ok }

func (m *Manager) engineDir() string { return filepath.Join(m.Dir, "engine", "v"+EngineVersion) }
func (m *Manager) modelDir(id string) string {
	return filepath.Join(m.Dir, "models", id)
}
func (m *Manager) vadDir() string   { return filepath.Join(m.Dir, "vad") }
func (m *Manager) punctDir() string { return filepath.Join(m.Dir, "punct") }

const marker = ".complete"

func complete(dir string) bool { _, err := os.Stat(filepath.Join(dir, marker)); return err == nil }

// EngineReady reports whether the engine, VAD and (if needed) punctuation are installed.
func (m *Manager) EngineReady() bool { return complete(m.engineDir()) && complete(m.vadDir()) }

// Installed reports whether a model and everything it needs are ready.
func (m *Manager) Installed(id string) bool {
	md, ok := Find(id)
	if !ok || !complete(m.modelDir(id)) || !m.EngineReady() {
		return false
	}
	return md.Punct || complete(m.punctDir())
}

// ModelStatus is a catalog entry plus local state.
type ModelStatus struct {
	Model
	Size      int64    `json:"size"`  // model files
	Extra     int64    `json:"extra"` // what else a first install fetches
	Installed bool     `json:"installed"`
	Sources   []string `json:"sources"`
}

type Status struct {
	Supported bool              `json:"supported"`
	Platform  string            `json:"platform"`
	Engine    map[string]any    `json:"engine"`
	Models    []ModelStatus     `json:"models"`
	Sources   []Source          `json:"sources"`
	Install   Progress          `json:"install"`
	Reference map[string]string `json:"reference"`
	CPUs      int               `json:"cpus"`
}

func (m *Manager) Status() Status {
	st := Status{Supported: m.Supported(), Platform: m.platform(), Sources: Sources, Reference: Reference, CPUs: runtime.NumCPU(),
		Engine: map[string]any{"version": EngineVersion, "installed": complete(m.engineDir())}}
	for _, md := range Models {
		ms := ModelStatus{Model: md, Size: md.pack.size(), Installed: m.Installed(md.ID),
			Sources: []string{"hf-mirror", "huggingface", "custom"}}
		if md.pack.ms != nil {
			ms.Sources = append(ms.Sources, "modelscope")
		}
		if !complete(m.engineDir()) {
			ms.Extra += engines[m.platform()].Size
		}
		if !complete(m.vadDir()) {
			ms.Extra += vad.size()
		}
		if !md.Punct && !complete(m.punctDir()) {
			ms.Extra += punct.size()
		}
		st.Models = append(st.Models, ms)
	}
	m.mu.Lock()
	st.Install = m.st
	m.mu.Unlock()
	if st.Install.State == "" {
		st.Install.State = "idle"
	}
	return st
}

func (m *Manager) update(f func(*Progress)) {
	m.mu.Lock()
	f(&m.st)
	cp := m.st
	m.mu.Unlock()
	if m.Publish != nil {
		m.Publish(cp)
	}
}

// Start downloads a model (and the engine, VAD and punctuation model when
// missing) in the background; ctx bounds it.
func (m *Manager) Start(ctx context.Context, id string, opt Options) error {
	md, ok := Find(id)
	if !ok {
		return fmt.Errorf("未知的模型 %q", id)
	}
	if !m.Supported() {
		return fmt.Errorf("暂不支持在 %s 上运行本地模型", m.platform())
	}
	if opt.Source == "custom" && !validTemplate(opt.Custom) {
		return errors.New("自定义地址需以 http:// 或 https:// 开头，并包含 {file}")
	}
	if opt.Proxy != "" && !strings.HasPrefix(opt.Proxy, "https://") && !strings.HasPrefix(opt.Proxy, "http://") {
		return errors.New("GitHub 加速前缀需以 http:// 或 https:// 开头")
	}
	m.mu.Lock()
	if m.st.State == "running" {
		m.mu.Unlock()
		return ErrRunning
	}
	ctx, cancel := context.WithCancel(ctx)
	m.cancel = cancel
	m.st = Progress{State: "running", Model: id, Source: opt.Source, Step: "准备"}
	m.mu.Unlock()
	go func() {
		defer cancel()
		err := m.install(ctx, md, opt)
		m.update(func(p *Progress) {
			p.Speed = 0
			switch {
			case err == nil:
				p.State, p.Step = "done", "完成"
			case ctx.Err() != nil:
				p.State, p.Step = "canceled", "已取消"
			default:
				p.State, p.Error = "failed", err.Error()
			}
		})
	}()
	return nil
}

// Cancel stops a running install; downloaded parts are kept for resuming.
func (m *Manager) Cancel() {
	m.mu.Lock()
	if m.cancel != nil {
		m.cancel()
	}
	m.mu.Unlock()
}

func validTemplate(t string) bool {
	return (strings.HasPrefix(t, "https://") || strings.HasPrefix(t, "http://")) && strings.Contains(t, "{file}")
}

type job struct {
	dir  string
	pack pack
}

func (m *Manager) install(ctx context.Context, md Model, opt Options) error {
	var jobs []job
	var total int64
	eng := engines[m.platform()]
	if !complete(m.engineDir()) {
		total += eng.Size
	}
	if !complete(m.vadDir()) {
		jobs = append(jobs, job{m.vadDir(), vad})
	}
	if !md.Punct && !complete(m.punctDir()) {
		jobs = append(jobs, job{m.punctDir(), punct})
	}
	if !complete(m.modelDir(md.ID)) {
		jobs = append(jobs, job{m.modelDir(md.ID), md.pack})
	}
	for _, j := range jobs {
		total += j.pack.size()
	}
	m.update(func(p *Progress) { p.Total = total })
	tr := &tracker{m: m, start: time.Now()}

	if !complete(m.engineDir()) {
		m.update(func(p *Progress) { p.Step = "下载识别引擎 sherpa-onnx " + EngineVersion })
		if err := m.installEngine(ctx, eng, opt.Proxy, tr); err != nil {
			return fmt.Errorf("识别引擎: %w", err)
		}
	}
	for _, j := range jobs {
		source := opt.Source
		if source == "modelscope" && j.pack.ms == nil {
			source = "hf-mirror"
			m.update(func(p *Progress) {
				p.Note = "ModelScope 上没有逐字节相同的副本，部分文件改用 HF-Mirror"
			})
		}
		for _, f := range j.pack.files {
			u, _ := j.pack.url(source, opt.Custom, f)
			m.update(func(p *Progress) { p.Step = "下载 " + filepath.Base(j.dir) + "/" + f.Path })
			if err := m.fetch(ctx, u, filepath.Join(j.dir, filepath.FromSlash(f.Path)), f, tr); err != nil {
				return fmt.Errorf("%s: %w", f.Path, err)
			}
		}
		if err := os.WriteFile(filepath.Join(j.dir, marker), []byte(time.Now().Format(time.RFC3339)), 0o600); err != nil {
			return err
		}
	}
	return nil
}

// tracker turns bytes received into overall progress and speed.
type tracker struct {
	m     *Manager
	start time.Time
	base  int64 // bytes from files already finished or resumed
	cur   int64
	last  time.Time
	fresh int64 // bytes actually transferred, for speed
}

func (t *tracker) add(n int64, transferred bool) {
	t.cur += n
	if transferred {
		t.fresh += n
	}
	if time.Since(t.last) < 200*time.Millisecond {
		return
	}
	t.last = time.Now()
	done, speed := t.base+t.cur, float64(t.fresh)/max(time.Since(t.start).Seconds(), 0.001)
	t.m.update(func(p *Progress) { p.Done, p.Speed = done, speed })
}

func (t *tracker) finish() { t.base += t.cur; t.cur = 0; t.last = time.Time{}; t.add(0, false) }

// defaultClient fails a source that stops answering instead of hanging.
var defaultClient = &http.Client{Transport: &http.Transport{Proxy: http.ProxyFromEnvironment,
	ResponseHeaderTimeout: 30 * time.Second, TLSHandshakeTimeout: 15 * time.Second, IdleConnTimeout: 60 * time.Second}}

func (m *Manager) client() *http.Client {
	if m.Client != nil {
		return m.Client
	}
	return defaultClient
}

// fetch downloads url to dest, resuming a partial file, and verifies size and digest.
func (m *Manager) fetch(ctx context.Context, url, dest string, f File, tr *tracker) error {
	if fi, err := os.Stat(dest); err == nil && fi.Size() == f.Size && (f.SHA256 == "" || sumFile(dest) == f.SHA256) {
		tr.add(f.Size, false)
		tr.finish()
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	part := dest + ".part"
	var have int64
	if fi, err := os.Stat(part); err == nil && fi.Size() < f.Size {
		have = fi.Size()
	} else {
		os.Remove(part)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	if have > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", have))
	}
	resp, err := m.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	flags := os.O_CREATE | os.O_WRONLY
	switch {
	case have > 0 && resp.StatusCode == http.StatusPartialContent:
		flags |= os.O_APPEND
		tr.add(have, false)
	case resp.StatusCode == http.StatusOK:
		flags |= os.O_TRUNC
		have = 0
	default:
		return fmt.Errorf("HTTP %d（%s）", resp.StatusCode, hostOf(url))
	}
	out, err := os.OpenFile(part, flags, 0o600)
	if err != nil {
		return err
	}
	buf := make([]byte, 256<<10)
	written := have
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if written+int64(n) > f.Size {
				out.Close()
				os.Remove(part)
				return fmt.Errorf("文件比预期大，来源可能不是同一版本（%s）", hostOf(url))
			}
			if _, err := out.Write(buf[:n]); err != nil {
				out.Close()
				return err
			}
			written += int64(n)
			tr.add(int64(n), true)
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			out.Close()
			return rerr
		}
	}
	if err := out.Close(); err != nil {
		return err
	}
	if written != f.Size {
		return fmt.Errorf("下载不完整（%d / %d 字节），重试会从断点继续", written, f.Size)
	}
	if f.SHA256 != "" {
		if got := sumFile(part); got != f.SHA256 {
			os.Remove(part)
			return fmt.Errorf("校验失败，来源文件与目录中的版本不一致（%s）", hostOf(url))
		}
	}
	tr.finish()
	return os.Rename(part, dest)
}

func hostOf(u string) string {
	u = strings.TrimPrefix(strings.TrimPrefix(u, "https://"), "http://")
	h, _, _ := strings.Cut(u, "/")
	return h
}

func sumFile(p string) string {
	f, err := os.Open(p)
	if err != nil {
		return ""
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return ""
	}
	return hex.EncodeToString(h.Sum(nil))
}

func (m *Manager) installEngine(ctx context.Context, a archive, proxy string, tr *tracker) error {
	root := filepath.Join(m.Dir, "engine")
	if err := os.MkdirAll(root, 0o755); err != nil {
		return err
	}
	arc := filepath.Join(root, a.name+".tar.bz2")
	f := a.File
	f.Path = filepath.Base(arc)
	if err := m.fetch(ctx, engineURL(proxy, a.name), arc, f, tr); err != nil {
		return err
	}
	m.update(func(p *Progress) { p.Step = "解压识别引擎" })
	tmp := m.engineDir() + ".tmp"
	os.RemoveAll(tmp)
	if err := extractTarBz2(arc, tmp); err != nil {
		os.RemoveAll(tmp)
		return err
	}
	if _, err := os.Stat(filepath.Join(tmp, "bin", exe(m.platform(), "sherpa-onnx-vad-with-offline-asr"))); err != nil {
		os.RemoveAll(tmp)
		return errors.New("引擎压缩包缺少识别程序")
	}
	os.RemoveAll(m.engineDir())
	if err := os.Rename(tmp, m.engineDir()); err != nil {
		return err
	}
	os.Remove(arc)
	return os.WriteFile(filepath.Join(m.engineDir(), marker), []byte(EngineVersion), 0o600)
}

func exe(platform, name string) string {
	if strings.HasPrefix(platform, "windows/") {
		return name + ".exe"
	}
	return name
}

// Only what the recogniser needs is extracted: bin/ and lib/.
func wanted(rel string) bool {
	return strings.HasPrefix(rel, "bin/") || strings.HasPrefix(rel, "lib/")
}

func extractTarBz2(archivePath, dest string) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()
	tr := tar.NewReader(bzip2.NewReader(f))
	for {
		h, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		rel, err := inside(h.Name)
		if err != nil {
			return err
		}
		if rel == "" || !wanted(rel) {
			continue
		}
		p := filepath.Join(dest, filepath.FromSlash(rel))
		switch h.Typeflag {
		case tar.TypeDir:
			err = os.MkdirAll(p, 0o755)
		case tar.TypeReg:
			err = writeFile(p, tr, h.FileInfo().Mode().Perm()|0o600)
		case tar.TypeSymlink:
			err = symlinkInside(dest, p, h.Linkname)
		default:
			continue
		}
		if err != nil {
			return err
		}
	}
}

// inside drops the archive's top folder and refuses paths that escape it.
func inside(name string) (string, error) {
	name = strings.ReplaceAll(name, "\\", "/")
	if strings.HasPrefix(name, "/") || filepath.IsAbs(name) || filepath.VolumeName(name) != "" {
		return "", fmt.Errorf("绝对路径 %q", name)
	}
	for _, part := range strings.Split(name, "/") {
		if part == ".." {
			return "", fmt.Errorf("越界路径 %q", name)
		}
	}
	_, rest, ok := strings.Cut(strings.TrimPrefix(name, "./"), "/")
	if !ok {
		return "", nil
	}
	return rest, nil
}

func writeFile(p string, r io.Reader, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, perm)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, r); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func symlinkInside(dest, p, target string) error {
	if filepath.IsAbs(target) || strings.HasPrefix(target, "/") {
		return fmt.Errorf("链接指向绝对路径 %q", target)
	}
	resolved := filepath.Join(filepath.Dir(p), filepath.FromSlash(target))
	if rel, err := filepath.Rel(dest, resolved); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return fmt.Errorf("链接越界 %q", target)
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.Symlink(target, p)
}

// Remove deletes a model. The engine and shared models stay.
func (m *Manager) Remove(id string) error {
	if _, ok := Find(id); !ok {
		return fmt.Errorf("未知的模型 %q", id)
	}
	m.mu.Lock()
	busy := m.st.State == "running" && m.st.Model == id
	m.mu.Unlock()
	if busy {
		return ErrRunning
	}
	return os.RemoveAll(m.modelDir(id))
}
