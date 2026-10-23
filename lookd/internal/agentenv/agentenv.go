// Package agentenv sets up what the assistant host needs to run: a Node.js
// binary and the agent's npm dependencies. It installs both inside Look
// Studio's private data directory, never system-wide.
// Contract: docs/specs/0008-assistant-runtime-setup.md
package agentenv

import (
	"archive/tar"
	"archive/zip"
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Mirror is where Node.js builds and npm packages come from.
type Mirror struct {
	Node     string // directory holding index.json and v*/ releases
	Registry string
}

// Mirrors are the only sources an install may use.
var Mirrors = map[string]Mirror{
	"npmmirror": {Node: "https://npmmirror.com/mirrors/node/", Registry: "https://registry.npmmirror.com"},
	"official":  {Node: "https://nodejs.org/dist/", Registry: "https://registry.npmjs.org"},
}

// MinMajor is the oldest Node.js the agent supports; NodeMajor is the line
// an install picks.
const (
	MinMajor  = 22
	NodeMajor = 24
)

// The Pi SDK package proves the dependencies are installed.
const depMarker = "node_modules/@earendil-works/pi-coding-agent/package.json"

var ErrRunning = errors.New("运行环境正在安装")

// Status is what GET /api/agent/runtime returns.
type Status struct {
	Node    NodeStatus `json:"node"`
	Deps    DepsStatus `json:"deps"`
	Install Install    `json:"install"`
}

type NodeStatus struct {
	Path    string `json:"path"`
	Version string `json:"version"`
	Source  string `json:"source"` // flag | managed | none
	OK      bool   `json:"ok"`
}

type DepsStatus struct {
	OK  bool   `json:"ok"`
	Dir string `json:"dir"`
}

type Install struct {
	State    string   `json:"state"` // idle | running | done | failed
	Step     string   `json:"step,omitempty"`
	Progress float64  `json:"progress"`
	Error    string   `json:"error,omitempty"`
	Log      []string `json:"log"`
}

// Manager reports and installs the runtime. Set the exported fields before use.
type Manager struct {
	Dir      string // <data>/runtime
	AgentDir string // holds package.json and package-lock.json; "" when unknown
	FlagNode string // -node given to lookd
	Client   *http.Client
	Mirrors  map[string]Mirror // defaults to Mirrors
	OS, Arch string            // default runtime.GOOS, runtime.GOARCH
	// NPMTimeout bounds the dependency install (default 10 minutes).
	NPMTimeout time.Duration
	// Restart starts the agent host with a Node.js binary.
	Restart func(node string)
	// Publish announces install progress.
	Publish func(Install)

	mu sync.Mutex
	st Install
}

func (m *Manager) mirrors() map[string]Mirror {
	if m.Mirrors != nil {
		return m.Mirrors
	}
	return Mirrors
}

func (m *Manager) platform() (goos, arch string) {
	goos, arch = m.OS, m.Arch
	if goos == "" {
		goos = runtime.GOOS
	}
	if arch == "" {
		arch = runtime.GOARCH
	}
	return
}

type record struct {
	Node    string `json:"node"`
	Version string `json:"version"`
}

// Managed returns the Node.js an earlier install recorded, if it still exists.
func (m *Manager) Managed() string {
	b, err := os.ReadFile(filepath.Join(m.Dir, "runtime.json"))
	if err != nil {
		return ""
	}
	var r record
	if json.Unmarshal(b, &r) != nil || r.Node == "" {
		return ""
	}
	if _, err := os.Stat(r.Node); err != nil {
		return ""
	}
	return r.Node
}

// Node returns the binary to run the agent with: -node first, then the
// managed install.
func (m *Manager) Node() (path, source string) {
	if m.FlagNode != "" {
		return m.FlagNode, "flag"
	}
	if p := m.Managed(); p != "" {
		return p, "managed"
	}
	return "", "none"
}

var versionRe = regexp.MustCompile(`^v(\d+)\.\d+\.\d+$`)

// nodeVersion runs node --version.
func nodeVersion(ctx context.Context, node string) (string, int) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, node, "--version").Output()
	if err != nil {
		return "", 0
	}
	v := strings.TrimSpace(string(out))
	mm := versionRe.FindStringSubmatch(v)
	if mm == nil {
		return v, 0
	}
	major, _ := strconv.Atoi(mm[1])
	return v, major
}

func (m *Manager) depsOK() bool {
	if m.AgentDir == "" {
		return false
	}
	_, err := os.Stat(filepath.Join(m.AgentDir, depMarker))
	return err == nil
}

// Status checks the binary and the dependencies.
func (m *Manager) Status(ctx context.Context) Status {
	path, source := m.Node()
	ns := NodeStatus{Path: path, Source: source}
	if path != "" {
		var major int
		ns.Version, major = nodeVersion(ctx, path)
		ns.OK = major >= MinMajor
	}
	m.mu.Lock()
	in := m.st
	in.Log = append([]string{}, m.st.Log...)
	m.mu.Unlock()
	if in.State == "" {
		in.State = "idle"
	}
	return Status{Node: ns, Deps: DepsStatus{OK: m.depsOK(), Dir: m.AgentDir}, Install: in}
}

func (m *Manager) update(f func(*Install)) {
	m.mu.Lock()
	f(&m.st)
	if len(m.st.Log) > 40 {
		m.st.Log = m.st.Log[len(m.st.Log)-40:]
	}
	cp := m.st
	cp.Log = append([]string{}, m.st.Log...)
	m.mu.Unlock()
	if m.Publish != nil {
		m.Publish(cp)
	}
}

func (m *Manager) logf(format string, a ...any) {
	line := fmt.Sprintf(format, a...)
	m.update(func(in *Install) { in.Log = append(in.Log, line) })
}

// Start begins an install in the background; ctx bounds it.
func (m *Manager) Start(ctx context.Context, mirror string) error {
	mr, ok := m.mirrors()[mirror]
	if !ok {
		return fmt.Errorf("未知的下载源 %q", mirror)
	}
	m.mu.Lock()
	if m.st.State == "running" {
		m.mu.Unlock()
		return ErrRunning
	}
	m.st = Install{State: "running", Step: "检查", Log: []string{}}
	m.mu.Unlock()
	go func() {
		err := m.install(ctx, mr)
		m.update(func(in *Install) {
			if err != nil {
				in.State, in.Error = "failed", err.Error()
				in.Log = append(in.Log, "失败："+err.Error())
			} else {
				in.State, in.Step, in.Progress = "done", "完成", 1
			}
		})
	}()
	return nil
}

func (m *Manager) install(ctx context.Context, mr Mirror) error {
	node, _ := m.Node()
	if node != "" {
		if v, major := nodeVersion(ctx, node); major >= MinMajor {
			m.logf("使用已有的 Node.js %s", v)
		} else {
			node = ""
		}
	}
	if node == "" {
		var err error
		if node, err = m.installNode(ctx, mr); err != nil {
			return err
		}
	}
	if !m.depsOK() {
		if err := m.installDeps(ctx, node, mr.Registry); err != nil {
			return err
		}
	} else {
		m.logf("依赖已安装")
	}
	m.update(func(in *Install) { in.Step = "启动助手" })
	if m.Restart != nil {
		m.Restart(node)
	}
	return nil
}

// ---- Node.js ----

type release struct {
	Version string `json:"version"`
	LTS     any    `json:"lts"` // false or a codename
}

// resolve picks the newest LTS release of NodeMajor from index.json.
func (m *Manager) resolve(ctx context.Context, base string) (string, error) {
	b, err := m.get(ctx, base+"index.json", 4<<20)
	if err != nil {
		return "", fmt.Errorf("读取 Node.js 版本列表失败：%w", err)
	}
	var rs []release
	if err := json.Unmarshal(b, &rs); err != nil {
		return "", fmt.Errorf("Node.js 版本列表格式不对：%w", err)
	}
	best, bestKey := "", [3]int{}
	for _, r := range rs {
		if lts, ok := r.LTS.(bool); r.LTS == nil || (ok && !lts) {
			continue
		}
		var k [3]int
		if n, _ := fmt.Sscanf(r.Version, "v%d.%d.%d", &k[0], &k[1], &k[2]); n != 3 || k[0] != NodeMajor || versionRe.FindString(r.Version) == "" {
			continue
		}
		if best == "" || k[1] > bestKey[1] || (k[1] == bestKey[1] && k[2] > bestKey[2]) {
			best, bestKey = r.Version, k
		}
	}
	if best == "" {
		return "", fmt.Errorf("没有找到 Node.js %d 的长期支持版本", NodeMajor)
	}
	return best, nil
}

// archiveName is the official build for this platform.
func (m *Manager) archiveName(version string) (string, error) {
	goos, arch := m.platform()
	a := map[string]string{"amd64": "x64", "arm64": "arm64"}[arch]
	switch {
	case a == "":
	case goos == "linux" || goos == "darwin":
		return fmt.Sprintf("node-%s-%s-%s.tar.gz", version, goos, a), nil
	case goos == "windows" && a == "x64":
		return fmt.Sprintf("node-%s-win-x64.zip", version), nil
	}
	return "", fmt.Errorf("没有适用于 %s/%s 的 Node.js 安装包", goos, arch)
}

func (m *Manager) installNode(ctx context.Context, mr Mirror) (string, error) {
	m.update(func(in *Install) { in.Step, in.Progress = "下载 Node.js", 0 })
	version, err := m.resolve(ctx, mr.Node)
	if err != nil {
		return "", err
	}
	name, err := m.archiveName(version)
	if err != nil {
		return "", err
	}
	rel := mr.Node + version + "/"
	sums, err := m.get(ctx, rel+"SHASUMS256.txt", 1<<20)
	if err != nil {
		return "", fmt.Errorf("读取校验和失败：%w", err)
	}
	want := sumFor(sums, name)
	if want == "" {
		return "", fmt.Errorf("校验和清单里没有 %s", name)
	}
	dl := filepath.Join(m.Dir, ".download")
	if err := os.MkdirAll(dl, 0o700); err != nil {
		return "", err
	}
	archive := filepath.Join(dl, name)
	defer os.Remove(archive)
	m.logf("下载 %s", name)
	got, err := m.download(ctx, rel+name, archive)
	if err != nil {
		return "", fmt.Errorf("下载 Node.js 失败：%w", err)
	}
	if got != want {
		return "", fmt.Errorf("%s 的 SHA-256 不匹配，已删除", name)
	}
	m.logf("校验通过 %s", want[:12])
	m.update(func(in *Install) { in.Step = "解压 Node.js" })
	tmp, err := os.MkdirTemp(m.Dir, ".extract-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(tmp)
	if strings.HasSuffix(name, ".zip") {
		err = extractZip(archive, tmp)
	} else {
		err = extractTarGz(archive, tmp)
	}
	if err != nil {
		return "", fmt.Errorf("解压失败：%w", err)
	}
	dest := filepath.Join(m.Dir, "node-"+version)
	os.RemoveAll(dest)
	if err := os.Rename(tmp, dest); err != nil {
		return "", err
	}
	if n := PruneNode(dest); n > 0 {
		m.logf("已移除用不到的头文件和文档 %d MB", n>>20)
	}
	bin := filepath.Join(dest, "bin", "node")
	if strings.HasSuffix(name, ".zip") {
		bin = filepath.Join(dest, "node.exe")
	}
	if _, major := nodeVersion(ctx, bin); major < MinMajor {
		return "", fmt.Errorf("安装的 Node.js 无法运行")
	}
	b, _ := json.Marshal(record{Node: bin, Version: version})
	if err := os.WriteFile(filepath.Join(m.Dir, "runtime.json"), b, 0o600); err != nil {
		return "", err
	}
	m.logf("Node.js %s 已安装到 %s", version, dest)
	return bin, nil
}

// sumFor finds name's SHA-256 in a SHASUMS256.txt.
func sumFor(sums []byte, name string) string {
	sc := bufio.NewScanner(bytes.NewReader(sums))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) == 2 && f[1] == name && len(f[0]) == 64 {
			return strings.ToLower(f[0])
		}
	}
	return ""
}

func (m *Manager) client() *http.Client {
	if m.Client != nil {
		return m.Client
	}
	return http.DefaultClient
}

func (m *Manager) get(ctx context.Context, url string, limit int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := m.client().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err == nil && int64(len(b)) > limit {
		err = errors.New("响应过大")
	}
	return b, err
}

// download writes url to dest and returns its SHA-256, reporting progress.
func (m *Manager) download(ctx context.Context, url, dest string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	resp, err := m.client().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	f, err := os.OpenFile(dest, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	total := resp.ContentLength
	var done int64
	last := time.Now()
	buf := make([]byte, 256<<10)
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if _, err := f.Write(buf[:n]); err != nil {
				return "", err
			}
			h.Write(buf[:n])
			done += int64(n)
			if total > 0 && time.Since(last) > 200*time.Millisecond {
				last = time.Now()
				p := float64(done) / float64(total)
				m.update(func(in *Install) { in.Progress = p })
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			return "", rerr
		}
	}
	if total > 0 && done != total {
		return "", io.ErrUnexpectedEOF
	}
	m.update(func(in *Install) { in.Progress = 1 })
	return hex.EncodeToString(h.Sum(nil)), f.Sync()
}

// inside resolves an archive entry below dest after dropping its first path
// element (the release folder); "" skips the entry, an error refuses it.
func inside(dest, name string) (string, error) {
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
	if !ok || rest == "" {
		return "", nil
	}
	return filepath.Join(dest, filepath.FromSlash(rest)), nil
}

func extractTarGz(archive, dest string) error {
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		p, err := inside(dest, h.Name)
		if err != nil || p == "" {
			if err != nil {
				return err
			}
			continue
		}
		switch h.Typeflag {
		case tar.TypeDir:
			err = os.MkdirAll(p, 0o755)
		case tar.TypeReg:
			err = writeFile(p, tr, h.FileInfo().Mode().Perm())
		case tar.TypeSymlink:
			err = symlinkInside(dest, p, h.Linkname)
		default:
			err = fmt.Errorf("不支持的条目 %q", h.Name)
		}
		if err != nil {
			return err
		}
	}
}

func extractZip(archive, dest string) error {
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer zr.Close()
	for _, zf := range zr.File {
		p, err := inside(dest, zf.Name)
		if err != nil {
			return err
		}
		if p == "" {
			continue
		}
		mode := zf.Mode()
		switch {
		case mode.IsDir():
			err = os.MkdirAll(p, 0o755)
		case mode.IsRegular():
			var rc io.ReadCloser
			if rc, err = zf.Open(); err == nil {
				err = writeFile(p, rc, mode.Perm()|0o600)
				rc.Close()
			}
		default:
			err = fmt.Errorf("不支持的条目 %q", zf.Name)
		}
		if err != nil {
			return err
		}
	}
	return nil
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

// symlinkInside creates a relative link that stays within dest.
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

// ---- dependencies ----

// npmCLI finds npm's entry script installed beside node.
func npmCLI(node string) string {
	dir := filepath.Dir(node)
	for _, p := range []string{
		filepath.Join(dir, "..", "lib", "node_modules", "npm", "bin", "npm-cli.js"),
		filepath.Join(dir, "node_modules", "npm", "bin", "npm-cli.js"),
	} {
		if _, err := os.Stat(p); err == nil {
			return filepath.Clean(p)
		}
	}
	return ""
}

// NPMArgs is the dependency install command after npm-cli.js.
func NPMArgs(registry string) []string {
	return []string{"ci", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund", "--registry=" + registry}
}

func (m *Manager) installDeps(ctx context.Context, node, registry string) error {
	m.update(func(in *Install) { in.Step, in.Progress = "安装依赖", 0 })
	if m.AgentDir == "" {
		return errors.New("找不到助手程序目录（agent）")
	}
	if _, err := os.Stat(filepath.Join(m.AgentDir, "package-lock.json")); err != nil {
		return fmt.Errorf("%s 缺少 package-lock.json", m.AgentDir)
	}
	probe, err := os.CreateTemp(m.AgentDir, ".write-test-")
	if err != nil {
		return fmt.Errorf("没有权限写入 %s，请用有权限的账户安装或重新下载完整的发布包", m.AgentDir)
	}
	probe.Close()
	os.Remove(probe.Name())
	cli := npmCLI(node)
	if cli == "" {
		return errors.New("找不到与 Node.js 一起安装的 npm")
	}
	timeout := m.NPMTimeout
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, node, append([]string{cli}, NPMArgs(registry)...)...)
	cmd.Dir = m.AgentDir
	cmd.Env = append(os.Environ(), "PATH="+filepath.Dir(node)+string(os.PathListSeparator)+os.Getenv("PATH"), "npm_config_update_notifier=false")
	cmd.WaitDelay = 5 * time.Second
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	go func() {
		sc := bufio.NewScanner(pr)
		for sc.Scan() {
			if line := strings.TrimSpace(sc.Text()); line != "" {
				m.logf("%s", line)
			}
		}
	}()
	m.logf("npm %s", strings.Join(NPMArgs(registry), " "))
	err = cmd.Run()
	pw.Close()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("安装依赖超过 %s，已停止", timeout)
	}
	if err != nil {
		return fmt.Errorf("安装依赖失败：%w", err)
	}
	if !m.depsOK() {
		return errors.New("npm 已完成，但没有找到 Pi SDK")
	}
	if n := PruneModules(filepath.Join(m.AgentDir, "node_modules")); n > 0 {
		m.logf("已移除类型声明和 source map %d MB", n>>20)
	}
	m.update(func(in *Install) { in.Progress = 1 })
	return nil
}
