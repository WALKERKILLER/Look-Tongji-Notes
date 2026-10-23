package localasr

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func put(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func waitIdle(t *testing.T, m *Manager) Progress {
	t.Helper()
	for i := 0; i < 500; i++ {
		if p := m.Status().Install; p.State != "running" {
			return p
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("move did not finish")
	return Progress{}
}

func TestRelocateMovesAndRemembers(t *testing.T) {
	base := t.TempDir()
	def, dst := filepath.Join(base, "data", "asr"), filepath.Join(base, "big disk", "models")
	m := &Manager{Dir: def}
	put(t, filepath.Join(def, "models", "m1", "model.onnx"), "weights")
	put(t, filepath.Join(def, "models", "m1", marker), "x")
	put(t, filepath.Join(def, "engine", "v1", "lib", "libx.so.1"), "lib")
	if runtime.GOOS != "windows" {
		os.Symlink("libx.so.1", filepath.Join(def, "engine", "v1", "lib", "libx.so"))
	}
	put(t, filepath.Join(def, "location.json.keep"), "not managed")

	if l := m.Location(); l.Custom || l.Dir != def || l.Used != int64(len("weights")+1+len("lib")) {
		t.Fatalf("before: %+v", l)
	}
	if err := m.Relocate(dst, true, nil); err != nil {
		t.Fatal(err)
	}
	if p := waitIdle(t, m); p.State != "done" || p.Done != p.Total {
		t.Fatalf("progress %+v", p)
	}
	if b, err := os.ReadFile(filepath.Join(dst, "models", "m1", "model.onnx")); err != nil || string(b) != "weights" {
		t.Fatal("model not moved", err)
	}
	if runtime.GOOS != "windows" {
		if target, err := os.Readlink(filepath.Join(dst, "engine", "v1", "lib", "libx.so")); err != nil || target != "libx.so.1" {
			t.Fatal("symlink not kept", target, err)
		}
	}
	if _, err := os.Stat(filepath.Join(def, "models")); !os.IsNotExist(err) {
		t.Fatal("old models left behind")
	}
	if _, err := os.Stat(filepath.Join(def, "location.json.keep")); err != nil {
		t.Fatal("unmanaged file touched")
	}
	if got := (&Manager{Dir: def}).Root(); got != dst {
		t.Fatalf("not remembered: %s", got)
	}
	if !m.Location().Custom || m.modelDir("m1") != filepath.Join(dst, "models", "m1") {
		t.Fatal("paths not switched")
	}

	// Back to the default without moving: the files stay, the choice goes.
	if err := m.Relocate("", false, nil); err != nil {
		t.Fatal(err)
	}
	if m.Root() != def || (&Manager{Dir: def}).Root() != def {
		t.Fatal("default not restored")
	}
	if _, err := os.Stat(filepath.Join(dst, "models", "m1", "model.onnx")); err != nil {
		t.Fatal("files should stay without move")
	}
}

func TestRelocateMergesIntoUsedFolder(t *testing.T) {
	base := t.TempDir()
	src, dst := filepath.Join(base, "a"), filepath.Join(base, "b")
	m := &Manager{Dir: src}
	put(t, filepath.Join(src, "models", "m1", "f"), "old")
	put(t, filepath.Join(src, "models", "m2", "f"), "two")
	put(t, filepath.Join(dst, "models", "m1", "f"), "kept")
	if err := m.Relocate(dst, true, nil); err != nil {
		t.Fatal(err)
	}
	waitIdle(t, m)
	if b, _ := os.ReadFile(filepath.Join(dst, "models", "m1", "f")); string(b) != "kept" {
		t.Fatal("existing file replaced")
	}
	if b, _ := os.ReadFile(filepath.Join(dst, "models", "m2", "f")); string(b) != "two" {
		t.Fatal("new file not merged")
	}
}

func TestRelocateRejects(t *testing.T) {
	base := t.TempDir()
	m := &Manager{Dir: filepath.Join(base, "asr")}
	if err := m.Relocate("relative/dir", true, nil); err == nil {
		t.Fatal("relative path accepted")
	}
	if err := m.Relocate(filepath.Join(base, "asr", "inner"), true, nil); err == nil {
		t.Fatal("nested move accepted")
	}
	if err := m.Relocate(filepath.Join(base, "x"), true, func() bool { return true }); err != ErrInUse {
		t.Fatalf("in use: %v", err)
	}
	m.st.State = "running"
	if err := m.Relocate(filepath.Join(base, "x"), false, nil); err != ErrRunning {
		t.Fatalf("running: %v", err)
	}
}

func TestCopyFileCountsProgress(t *testing.T) {
	dir := t.TempDir()
	put(t, filepath.Join(dir, "a"), "0123456789")
	m := &Manager{Dir: dir}
	tr := &moveTracker{m: m, total: 10, start: time.Now()}
	if err := copyFile(filepath.Join(dir, "a"), filepath.Join(dir, "b"), 0o644, tr); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "b")); string(b) != "0123456789" || tr.done != 10 {
		t.Fatal("copy", string(b), tr.done)
	}
}
