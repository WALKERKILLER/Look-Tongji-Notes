package agentenv

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeNode answers --version and, run as npm, records its arguments and
// installs the dependency marker in its working directory.
const fakeNode = `#!/bin/sh
if [ "$1" = "--version" ]; then echo v24.9.0; exit 0; fi
if [ -n "$SLOW" ]; then exec sleep 30; fi
shift
echo "$@" > npm-args.txt
mkdir -p node_modules/@earendil-works/pi-coding-agent
echo '{}' > node_modules/@earendil-works/pi-coding-agent/package.json
`

type entry struct {
	name, body, link string
	dir              bool
}

func tarball(t *testing.T, entries []entry) []byte {
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range entries {
		h := &tar.Header{Name: e.name, Mode: 0o755}
		switch {
		case e.dir:
			h.Typeflag = tar.TypeDir
		case e.link != "":
			h.Typeflag, h.Linkname = tar.TypeSymlink, e.link
		default:
			h.Typeflag, h.Size = tar.TypeReg, int64(len(e.body))
		}
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
		tw.Write([]byte(e.body))
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

const archive = "node-v24.9.0-linux-x64.tar.gz"

func nodeRelease(t *testing.T) []byte {
	return tarball(t, []entry{
		{name: "node-v24.9.0-linux-x64/", dir: true},
		{name: "node-v24.9.0-linux-x64/bin/node", body: fakeNode},
		{name: "node-v24.9.0-linux-x64/lib/node_modules/npm/bin/npm-cli.js", body: "// npm"},
		{name: "node-v24.9.0-linux-x64/bin/npm", link: "../lib/node_modules/npm/bin/npm-cli.js"},
	})
}

const index = `[
 {"version":"v25.1.0","lts":false},
 {"version":"v24.9.0","lts":"Krypton"},
 {"version":"v24.10.0","lts":false},
 {"version":"v24.8.2","lts":"Krypton"},
 {"version":"v22.20.0","lts":"Jod"}
]`

func mirror(t *testing.T, body []byte, sum string) *httptest.Server {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/index.json":
			w.Write([]byte(index))
		case "/v24.9.0/SHASUMS256.txt":
			fmt.Fprintf(w, "%s  node-v24.9.0-darwin-arm64.tar.gz\n%s  %s\n", strings.Repeat("0", 64), sum, archive)
		case "/v24.9.0/" + archive:
			w.Write(body)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func newManager(t *testing.T, srv *httptest.Server) (*Manager, *[]string) {
	agent := t.TempDir()
	os.WriteFile(filepath.Join(agent, "package-lock.json"), []byte("{}"), 0o644)
	var mu sync.Mutex
	restarts := []string{}
	m := &Manager{
		Dir: t.TempDir(), AgentDir: agent, Client: srv.Client(),
		Mirrors: map[string]Mirror{"test": {Node: srv.URL + "/", Registry: "https://registry.example"}},
		OS:      "linux", Arch: "amd64",
		Restart: func(node string) { mu.Lock(); restarts = append(restarts, node); mu.Unlock() },
	}
	return m, &restarts
}

func finish(t *testing.T, m *Manager) Install {
	t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		if st := m.Status(context.Background()).Install; st.State != "running" {
			return st
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("install did not finish")
	return Install{}
}

func TestInstallNodeAndDependencies(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell script stands in for node")
	}
	body := nodeRelease(t)
	h := sha256.Sum256(body)
	m, restarts := newManager(t, mirror(t, body, hex.EncodeToString(h[:])))
	if st := m.Status(context.Background()); st.Node.Source != "none" || st.Deps.OK {
		t.Fatalf("before: %+v", st)
	}
	if err := m.Start(context.Background(), "test"); err != nil {
		t.Fatal(err)
	}
	if in := finish(t, m); in.State != "done" {
		t.Fatalf("install: %+v", in)
	}
	st := m.Status(context.Background())
	want := filepath.Join(m.Dir, "node-v24.9.0", "bin", "node")
	if st.Node.Path != want || st.Node.Source != "managed" || !st.Node.OK || st.Node.Version != "v24.9.0" || !st.Deps.OK {
		t.Fatalf("after: %+v", st)
	}
	args, _ := os.ReadFile(filepath.Join(m.AgentDir, "npm-args.txt"))
	if strings.TrimSpace(string(args)) != strings.Join(NPMArgs("https://registry.example"), " ") {
		t.Fatalf("npm args %q", args)
	}
	if len(*restarts) != 1 || (*restarts)[0] != want {
		t.Fatalf("restarts %v", *restarts)
	}
	if link, err := os.Readlink(filepath.Join(m.Dir, "node-v24.9.0", "bin", "npm")); err != nil || link != "../lib/node_modules/npm/bin/npm-cli.js" {
		t.Fatalf("npm link %q %v", link, err)
	}
	if ents, _ := os.ReadDir(filepath.Join(m.Dir, ".download")); len(ents) != 0 {
		t.Fatalf("download left behind: %v", ents)
	}
	// A second install keeps the managed Node.js and the dependencies.
	m.Start(context.Background(), "test")
	if in := finish(t, m); in.State != "done" || !strings.Contains(strings.Join(in.Log, "\n"), "依赖已安装") {
		t.Fatalf("again: %+v", in)
	}
}

func TestChecksumMismatchIsRefused(t *testing.T) {
	body := nodeRelease(t)
	m, restarts := newManager(t, mirror(t, body, strings.Repeat("ab", 32)))
	m.Start(context.Background(), "test")
	in := finish(t, m)
	if in.State != "failed" || !strings.Contains(in.Error, "SHA-256") {
		t.Fatalf("install: %+v", in)
	}
	if ents, _ := os.ReadDir(filepath.Join(m.Dir, ".download")); len(ents) != 0 {
		t.Fatal("mismatched archive kept")
	}
	if m.Managed() != "" || len(*restarts) != 0 {
		t.Fatal("a refused archive was installed")
	}
	if err := m.Start(context.Background(), "elsewhere"); err == nil {
		t.Fatal("unknown mirror accepted")
	}
}

func TestResolvePicksNewestLTSOfTheMajor(t *testing.T) {
	m, _ := newManager(t, mirror(t, nil, ""))
	v, err := m.resolve(context.Background(), m.Mirrors["test"].Node)
	if err != nil || v != "v24.9.0" {
		t.Fatalf("resolved %q %v", v, err)
	}
	m.OS = "plan9"
	if _, err := m.archiveName(v); err == nil {
		t.Fatal("unsupported platform accepted")
	}
}

func TestExtractionStaysInside(t *testing.T) {
	for name, entries := range map[string][]entry{
		"dotdot":   {{name: "node/../../evil", body: "x"}},
		"absolute": {{name: "/etc/evil", body: "x"}},
		"link out": {{name: "node/bin/x", link: "../../../etc/passwd"}},
		"abs link": {{name: "node/bin/x", link: "/etc/passwd"}},
	} {
		dir := t.TempDir()
		archive := filepath.Join(dir, "a.tar.gz")
		os.WriteFile(archive, tarball(t, entries), 0o600)
		dest := filepath.Join(dir, "out")
		os.Mkdir(dest, 0o755)
		if err := extractTarGz(archive, dest); err == nil {
			t.Errorf("%s: extracted", name)
		}
	}
}

func TestDependencyInstallTimesOut(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell script stands in for node")
	}
	m, _ := newManager(t, mirror(t, nil, ""))
	bin := filepath.Join(t.TempDir(), "bin")
	os.MkdirAll(filepath.Join(bin, "node_modules", "npm", "bin"), 0o755)
	os.WriteFile(filepath.Join(bin, "node_modules", "npm", "bin", "npm-cli.js"), []byte("//"), 0o644)
	node := filepath.Join(bin, "node")
	os.WriteFile(node, []byte(fakeNode), 0o755)
	m.FlagNode = node
	m.NPMTimeout = 300 * time.Millisecond
	t.Setenv("SLOW", "1")
	m.Start(context.Background(), "test")
	if err := m.Start(context.Background(), "test"); !errors.Is(err, ErrRunning) {
		t.Fatalf("second start: %v", err)
	}
	if in := finish(t, m); in.State != "failed" || !strings.Contains(in.Error, "超过") {
		t.Fatalf("install: %+v", in)
	}
}
