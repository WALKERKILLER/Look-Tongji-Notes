package localasr

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Where the engine and models live: Dir unless the user picked another
// folder, remembered in <Dir>/location.json. Only the entries below are
// managed there, so a shared folder keeps whatever else it holds.

var managed = []string{"engine", "models", "vad", "punct"}

// ErrInUse means a transcription is reading the models.
var ErrInUse = errors.New("正在用本地模型转写，完成后再更改位置")

type location struct {
	Dir string `json:"dir"`
}

func (m *Manager) locationFile() string { return filepath.Join(m.Dir, "location.json") }

// Root is the folder that holds the engine and models.
func (m *Manager) Root() string {
	m.rootMu.RLock()
	r, loaded := m.root, m.rootLoaded
	m.rootMu.RUnlock()
	if loaded {
		return r
	}
	m.rootMu.Lock()
	defer m.rootMu.Unlock()
	if !m.rootLoaded {
		m.root, m.rootLoaded = m.Dir, true
		var loc location
		if b, err := os.ReadFile(m.locationFile()); err == nil && json.Unmarshal(b, &loc) == nil && filepath.IsAbs(loc.Dir) {
			m.root = loc.Dir
		}
	}
	return m.root
}

func (m *Manager) setRoot(dir string) error {
	m.rootMu.Lock()
	defer m.rootMu.Unlock()
	if err := os.MkdirAll(m.Dir, 0o700); err != nil {
		return err
	}
	if filepath.Clean(dir) == filepath.Clean(m.Dir) {
		if err := os.Remove(m.locationFile()); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
	} else {
		b, _ := json.Marshal(location{Dir: dir})
		if err := os.WriteFile(m.locationFile(), b, 0o600); err != nil {
			return err
		}
	}
	m.root, m.rootLoaded = dir, true
	return nil
}

// Location describes the storage folder for the settings page.
type Location struct {
	Dir     string `json:"dir"`
	Default string `json:"default"`
	Custom  bool   `json:"custom"`
	Used    int64  `json:"used"` // bytes of engine and models
	Free    int64  `json:"free"` // bytes available there, -1 when unknown
}

func (m *Manager) Location() Location {
	root := m.Root()
	l := Location{Dir: root, Default: m.Dir, Custom: filepath.Clean(root) != filepath.Clean(m.Dir), Free: -1}
	for _, e := range managed {
		filepath.WalkDir(filepath.Join(root, e), func(_ string, d fs.DirEntry, err error) error {
			if err == nil && d.Type().IsRegular() {
				if fi, err := d.Info(); err == nil {
					l.Used += fi.Size()
				}
			}
			return nil
		})
	}
	if free, err := freeSpace(root); err == nil {
		l.Free = free
	}
	return l
}

// Relocate switches to dir ("" for the default). With move, the files in
// the current folder go along, in the background with progress; otherwise
// they stay where they are and dir is used as it is (models already there
// count as installed). inUse reports a transcription reading the models.
func (m *Manager) Relocate(dir string, move bool, inUse func() bool) error {
	if dir == "" {
		dir = m.Dir
	}
	if !filepath.IsAbs(dir) {
		return errors.New("请选择一个完整路径的文件夹")
	}
	dir = filepath.Clean(dir)
	old := filepath.Clean(m.Root())
	if dir == old {
		return nil
	}
	if move && (within(dir, old) || within(old, dir)) {
		return errors.New("新位置不能在当前位置里面，也不能包含当前位置")
	}
	if err := writable(dir); err != nil {
		return fmt.Errorf("不能写入这个文件夹：%w", err)
	}
	m.mu.Lock()
	if m.st.State == "running" {
		m.mu.Unlock()
		return ErrRunning
	}
	if inUse != nil && inUse() {
		m.mu.Unlock()
		return ErrInUse
	}
	if !move {
		m.mu.Unlock()
		return m.setRoot(dir)
	}
	m.st = Progress{State: "running", Step: "移动到新位置", Note: dir}
	m.mu.Unlock()
	go func() {
		err := m.moveAll(old, dir)
		if err == nil {
			err = m.setRoot(dir)
		}
		m.update(func(p *Progress) {
			p.Speed = 0
			if err != nil {
				p.State, p.Error = "failed", "移动失败："+err.Error()
			} else {
				p.State, p.Step = "done", "已移动"
			}
		})
	}()
	return nil
}

// within reports whether p is inside dir (or is dir).
func within(p, dir string) bool {
	rel, err := filepath.Rel(dir, p)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func writable(dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, ".look-write-test-")
	if err != nil {
		return err
	}
	f.Close()
	return os.Remove(f.Name())
}

func (m *Manager) moveAll(from, to string) error {
	var total int64
	for _, e := range managed {
		filepath.WalkDir(filepath.Join(from, e), func(_ string, d fs.DirEntry, err error) error {
			if err == nil && d.Type().IsRegular() {
				if fi, err := d.Info(); err == nil {
					total += fi.Size()
				}
			}
			return nil
		})
	}
	tr := &moveTracker{m: m, total: total, start: time.Now()}
	m.update(func(p *Progress) { p.Total = total })
	for _, e := range managed {
		src := filepath.Join(from, e)
		if _, err := os.Lstat(src); errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err := moveTree(src, filepath.Join(to, e), tr); err != nil {
			return err
		}
	}
	return nil
}

type moveTracker struct {
	m     *Manager
	total int64
	done  int64
	start time.Time
	last  time.Time
}

func (t *moveTracker) add(n int64) {
	t.done += n
	if now := time.Now(); now.Sub(t.last) > 200*time.Millisecond || t.done == t.total {
		t.last = now
		speed := float64(t.done) / max(now.Sub(t.start).Seconds(), 0.001)
		t.m.update(func(p *Progress) { p.Done, p.Speed = t.done, speed })
	}
}

// moveTree moves src to dst: a rename on the same disk, otherwise a copy
// (symbolic links kept) and a delete. Where dst already has an entry, it is
// kept and the one from src dropped, so a folder used before merges.
func moveTree(src, dst string, tr *moveTracker) error {
	if _, err := os.Lstat(dst); errors.Is(err, fs.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		if os.Rename(src, dst) == nil {
			tr.add(treeSize(dst))
			return nil
		}
	}
	si, err := os.Lstat(src)
	if err != nil {
		return err
	}
	switch {
	case si.IsDir():
		if err := os.MkdirAll(dst, si.Mode().Perm()|0o700); err != nil {
			return err
		}
		entries, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if err := moveTree(filepath.Join(src, e.Name()), filepath.Join(dst, e.Name()), tr); err != nil {
				return err
			}
		}
		return os.Remove(src)
	case si.Mode()&fs.ModeSymlink != 0:
		if _, err := os.Lstat(dst); err != nil {
			target, err := os.Readlink(src)
			if err != nil {
				return err
			}
			if err := os.Symlink(target, dst); err != nil {
				return err
			}
		}
		return os.Remove(src)
	default:
		if _, err := os.Lstat(dst); err == nil {
			tr.add(si.Size())
			return os.Remove(src)
		}
		if err := copyFile(src, dst, si.Mode().Perm(), tr); err != nil {
			os.Remove(dst)
			return err
		}
		return os.Remove(src)
	}
}

func treeSize(dir string) (n int64) {
	filepath.WalkDir(dir, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && d.Type().IsRegular() {
			if fi, err := d.Info(); err == nil {
				n += fi.Size()
			}
		}
		return nil
	})
	return n
}

func copyFile(src, dst string, perm fs.FileMode, tr *moveTracker) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".moving"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	buf := make([]byte, 1<<20)
	for {
		n, rerr := in.Read(buf)
		if n > 0 {
			if _, err := out.Write(buf[:n]); err != nil {
				out.Close()
				os.Remove(tmp)
				return err
			}
			tr.add(int64(n))
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			out.Close()
			os.Remove(tmp)
			return rerr
		}
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dst)
}
