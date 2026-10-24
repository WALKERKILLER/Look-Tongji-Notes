package datasync

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/net/webdav"
)

func davServer(t *testing.T) *httptest.Server {
	h := &webdav.Handler{Prefix: "/dav", FileSystem: webdav.NewMemFS(), LockSystem: webdav.NewMemLS()}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if u, p, ok := r.BasicAuth(); !ok || u != "me" || p != "secret" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		h.ServeHTTP(w, r)
	}))
	t.Cleanup(srv.Close)
	return srv
}

type device struct {
	*Service
	changedLib, changedData int
}

func newDevice(t *testing.T) *device {
	root := t.TempDir()
	d := &device{}
	d.Service = &Service{
		Roots:  Roots{Library: filepath.Join(root, "LookStudio"), Data: filepath.Join(root, "data")},
		App:    "test",
		Seal:   func(s string) (string, error) { return "sealed:" + s, nil },
		Unseal: func(s string) (string, error) { return strings.TrimPrefix(s, "sealed:"), nil },
		Changed: func(_ context.Context, lib, data bool) {
			if lib {
				d.changedLib++
			}
			if data {
				d.changedData++
			}
		},
	}
	os.MkdirAll(d.Roots.Library, 0o755)
	os.MkdirAll(d.Roots.Data, 0o700)
	return d
}

func (d *device) write(t *testing.T, p, body string, age time.Duration) {
	t.Helper()
	abs, ok := d.Roots.Abs(p)
	if !ok {
		t.Fatalf("%s outside the set", p)
	}
	os.MkdirAll(filepath.Dir(abs), 0o755)
	if err := os.WriteFile(abs, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	mt := time.Now().Add(-age)
	os.Chtimes(abs, mt, mt)
}

func (d *device) read(p string) string {
	abs, _ := d.Roots.Abs(p)
	b, err := os.ReadFile(abs)
	if err != nil {
		return "<missing>"
	}
	return string(b)
}

func (d *device) sync(t *testing.T) Result {
	t.Helper()
	res, err := d.Sync(context.Background())
	if err != nil {
		t.Fatalf("sync: %v (%+v)", err, res)
	}
	return res
}

func connect(t *testing.T, d *device, url string, media bool) {
	t.Helper()
	pass := "secret"
	if _, err := d.Configure(context.Background(), Settings{URL: url + "/dav", User: "me", Pass: &pass, Folder: "Look Studio/备份", Media: media}); err != nil {
		t.Fatal(err)
	}
}

func TestScopeKeepsSecretsAndScratchOut(t *testing.T) {
	r := Roots{Library: "/lib", Data: "/data"}
	for _, p := range []string{
		"library/../x", "library/.cache/1.mp4", "library/library.db", "library/a/video.mp4.part",
		"data/seal.key", "data/session.json", "data/agent/keys.json", "data/agent/auth.json", "data/agent/models.json",
		"data/agent/plugins/x/storage.json", "/etc/passwd", "library//a", "library/a/../../b",
	} {
		if _, ok := r.Abs(p); ok {
			t.Errorf("%s accepted", p)
		}
	}
	for _, p := range []string{"library/courses/海洋/笔记.md", "data/agent/sessions/1.jsonl", "data/agent/bot/memory/a.md", "data/agent/tasks.json"} {
		if _, ok := r.Abs(p); !ok {
			t.Errorf("%s rejected", p)
		}
	}
}

func TestWebDAVSyncBetweenDevices(t *testing.T) {
	srv := davServer(t)
	a, b := newDevice(t), newDevice(t)
	connect(t, a, srv.URL, false)
	connect(t, b, srv.URL, false)

	a.write(t, "library/notes/一.md", "first", time.Hour)
	a.write(t, "library/notes/二.md", "second", time.Hour)
	a.write(t, "library/courses/c/l/video.mp4", "big", time.Hour)
	a.write(t, "data/agent/sessions/s1.jsonl", "{}\n", time.Hour)
	os.MkdirAll(filepath.Join(a.Roots.Library, ".cache"), 0o755)
	os.WriteFile(filepath.Join(a.Roots.Library, ".cache", "x.mp3"), []byte("scratch"), 0o644)
	if res := a.sync(t); res.Uploaded != 3 {
		t.Fatalf("first upload = %+v", res)
	}
	if res := b.sync(t); res.Downloaded != 3 || b.changedLib != 1 || b.changedData != 1 {
		t.Fatalf("first download = %+v lib=%d data=%d", res, b.changedLib, b.changedData)
	}
	if b.read("library/notes/一.md") != "first" || b.read("library/courses/c/l/video.mp4") != "<missing>" {
		t.Fatal("files did not arrive, or media came without asking")
	}
	if res := b.sync(t); res.Uploaded+res.Downloaded+res.Deleted != 0 {
		t.Fatalf("idle sync changed things: %+v", res)
	}

	// An edit and a deletion on b reach a; the deleted file goes to the trash.
	b.write(t, "library/notes/一.md", "edited on b", 0)
	os.Remove(filepath.Join(b.Roots.Library, "notes", "二.md"))
	b.sync(t)
	a.sync(t)
	if a.read("library/notes/一.md") != "edited on b" || a.read("library/notes/二.md") != "<missing>" {
		t.Fatalf("a = %q, %q", a.read("library/notes/一.md"), a.read("library/notes/二.md"))
	}
	trash, _ := filepath.Glob(filepath.Join(a.Roots.Library, TrashDir, "*", "notes", "二.md"))
	if len(trash) != 1 {
		t.Fatal("deleted file not kept in the trash")
	}

	// Both edit: the newer edit wins and the other is kept aside.
	a.write(t, "library/notes/一.md", "older edit on a", 10*time.Minute)
	b.write(t, "library/notes/一.md", "newer edit on b", time.Minute)
	a.sync(t)
	res := b.sync(t)
	if res.Conflicts != 1 || res.ConflictDir == "" {
		t.Fatalf("conflict not reported: %+v", res)
	}
	kept, _ := os.ReadFile(filepath.Join(res.ConflictDir, "notes", "一.md"))
	if string(kept) != "older edit on a" {
		t.Fatalf("losing copy = %q", kept)
	}
	a.sync(t)
	if a.read("library/notes/一.md") != "newer edit on b" {
		t.Fatalf("a kept %q", a.read("library/notes/一.md"))
	}

	// Logs changed on both sides keep every line.
	a.write(t, "data/agent/usage.jsonl", "{\"a\":1}\n", time.Hour)
	a.sync(t)
	b.sync(t)
	a.write(t, "data/agent/usage.jsonl", "{\"a\":1}\n{\"a\":2}\n", 0)
	b.write(t, "data/agent/usage.jsonl", "{\"a\":1}\n{\"b\":1}\n", 0)
	a.sync(t)
	b.sync(t)
	a.sync(t)
	for _, d := range []*device{a, b} {
		if got := d.read("data/agent/usage.jsonl"); got != "{\"a\":1}\n{\"b\":1}\n{\"a\":2}\n" && got != "{\"a\":1}\n{\"a\":2}\n{\"b\":1}\n" {
			t.Fatalf("merged log = %q", got)
		}
	}
}

func TestWebDAVWrongPassword(t *testing.T) {
	srv := davServer(t)
	d := newDevice(t)
	bad := "nope"
	_, err := d.Configure(context.Background(), Settings{URL: srv.URL, User: "me", Pass: &bad})
	if err == nil || !strings.Contains(err.Error(), "密码") {
		t.Fatalf("err = %v", err)
	}
	if d.Status().Configured {
		t.Fatal("a rejected account was saved")
	}
}

// Servers that check the create permission first answer 403 to MKCOL of
// a folder that is already there; a 403 says what was refused.
func TestWebDAVForbiddenFolders(t *testing.T) {
	ctx := context.Background()
	fs := webdav.NewMemFS()
	fs.Mkdir(ctx, "/a", 0o755)
	fs.Mkdir(ctx, "/a/b", 0o755)
	h := &webdav.Handler{FileSystem: fs, LockSystem: webdav.NewMemLS()}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "MKCOL" {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		h.ServeHTTP(w, r)
	}))
	defer srv.Close()
	base, _ := url.Parse(srv.URL + "/")
	c := &Client{Base: base}
	if err := c.MkdirAll(ctx, "a/b"); err != nil {
		t.Fatalf("existing folders: %v", err)
	}
	if err := c.MkdirAll(ctx, "a/c"); err == nil || !strings.Contains(err.Error(), "新建文件夹 a/c") {
		t.Fatalf("missing folder: %v", err)
	}
}

// Some servers answer 403 for a file whose folder is missing, and a read-only
// account is refused when connecting, not on the first sync.
func TestWebDAVForbiddenWrites(t *testing.T) {
	ctx := context.Background()
	readOnly := false
	h := &webdav.Handler{FileSystem: webdav.NewMemFS(), LockSystem: webdav.NewMemLS()}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPut {
			if _, err := h.FileSystem.Stat(ctx, r.URL.Path[:strings.LastIndex(r.URL.Path, "/")+1]); err != nil || readOnly {
				w.WriteHeader(http.StatusForbidden)
				return
			}
		}
		h.ServeHTTP(w, r)
	}))
	defer srv.Close()
	base, _ := url.Parse(srv.URL + "/")
	if _, err := (&Client{Base: base}).Put(ctx, "state/library.json", func() (io.ReadCloser, int64, error) {
		return io.NopCloser(strings.NewReader("{}")), 2, nil
	}, ""); err != nil {
		t.Fatalf("put into a missing folder: %v", err)
	}
	readOnly = true
	d := newDevice(t)
	if _, err := d.Configure(ctx, Settings{URL: srv.URL, Folder: "LookStudio"}); err == nil || !strings.Contains(err.Error(), "上传 state/write-check") {
		t.Fatalf("read-only account: %v", err)
	}
}

// Uploads run in parallel: one that found a new folder missing (403) must
// not fail because another upload created that folder meanwhile.
func TestWebDAVParallelUploadsIntoNewFolders(t *testing.T) {
	ctx := context.Background()
	fs := webdav.NewMemFS()
	h := &webdav.Handler{Prefix: "/dav", FileSystem: fs, LockSystem: webdav.NewMemLS()}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if u, p, ok := r.BasicAuth(); !ok || u != "me" || p != "secret" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if r.Method == http.MethodPut {
			if _, err := fs.Stat(ctx, path.Dir(strings.TrimPrefix(r.URL.Path, "/dav"))); err != nil {
				w.WriteHeader(http.StatusForbidden)
				return
			}
		}
		h.ServeHTTP(w, r)
	}))
	defer srv.Close()
	d := newDevice(t)
	for c := range 3 {
		for l := range 6 {
			for _, f := range []string{"lecture.json", "笔记.md", "transcript.json", "slides/001.png"} {
				d.write(t, fmt.Sprintf("library/courses/课程%d/第%d讲/%s", c, l, f), "x", time.Hour)
			}
		}
	}
	connect(t, d, srv.URL, false)
	if res := d.sync(t); res.Uploaded != 3*6*4 || res.Error != "" {
		t.Fatalf("%+v", res)
	}
}

func TestWebDAVCloudflareBlock(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Server", "cloudflare")
		w.Header().Set("Content-Type", "text/html; charset=UTF-8")
		w.WriteHeader(http.StatusForbidden)
	}))
	defer srv.Close()
	base, _ := url.Parse(srv.URL + "/")
	_, _, err := (&Client{Base: base}).Get(context.Background(), "manifest.json")
	if err == nil || !strings.Contains(err.Error(), "Cloudflare") || !strings.Contains(err.Error(), "下载 manifest.json") {
		t.Fatalf("err %v", err)
	}
}

func TestWebDAVStateMerges(t *testing.T) {
	srv := davServer(t)
	a, b := newDevice(t), newDevice(t)
	var got []string
	a.State = func(context.Context) ([]byte, error) { return []byte(`{"from":"a"}`), nil }
	a.MergeState = func(_ context.Context, b []byte) (bool, error) { return false, nil }
	b.State = func(context.Context) ([]byte, error) { return []byte(`{"from":"b"}`), nil }
	b.MergeState = func(_ context.Context, in []byte) (bool, error) { got = append(got, string(in)); return true, nil }
	connect(t, a, srv.URL, false)
	connect(t, b, srv.URL, false)
	a.sync(t)
	b.sync(t)
	if len(got) != 1 || got[0] != `{"from":"a"}` || b.changedLib != 1 {
		t.Fatalf("b merged %q (lib changes %d)", got, b.changedLib)
	}
}

func TestBackupRoundTrip(t *testing.T) {
	ctx := context.Background()
	a, b := newDevice(t), newDevice(t)
	a.write(t, "library/notes/n.md", "note", time.Hour)
	a.write(t, "library/courses/c/l/slides/0001.jpg", "jpg", time.Hour)
	a.write(t, "library/courses/c/l/video.mp4", "video", time.Hour)
	a.write(t, "data/agent/tasks.json", "[]", time.Hour)
	os.WriteFile(filepath.Join(a.Roots.Data, "seal.key"), []byte("k"), 0o600)
	var merged string
	a.State = func(context.Context) ([]byte, error) { return []byte(`{"playback":{}}`), nil }
	b.MergeState = func(_ context.Context, in []byte) (bool, error) { merged = string(in); return true, nil }

	if e := a.Estimate(); e.Files != 3 || e.MediaFiles != 1 {
		t.Fatalf("estimate = %+v", e)
	}
	var buf bytes.Buffer
	if err := a.Export(ctx, &buf, false); err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	for _, f := range zr.File {
		if strings.Contains(f.Name, "seal.key") || strings.HasSuffix(f.Name, ".mp4") {
			t.Fatalf("backup contains %s", f.Name)
		}
	}

	b.write(t, "library/notes/n.md", "newer here", 0)
	pv, err := b.Receive(ctx, bytes.NewReader(buf.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if pv.Files != 3 || pv.New != 2 || pv.Older != 1 || !pv.State {
		t.Fatalf("preview = %+v", pv)
	}
	res, err := b.Restore(ctx, pv.ID, "merge")
	if err != nil {
		t.Fatal(err)
	}
	if res.Written != 2 || res.Kept != 1 || b.read("library/notes/n.md") != "newer here" || merged == "" {
		t.Fatalf("merge restore = %+v, note %q, state %q", res, b.read("library/notes/n.md"), merged)
	}
	if b.read("data/agent/tasks.json") != "[]" || b.changedData != 1 {
		t.Fatal("assistant data not restored")
	}

	pv, _ = b.Receive(ctx, bytes.NewReader(buf.Bytes()))
	res, err = b.Restore(ctx, pv.ID, "overwrite")
	if err != nil || b.read("library/notes/n.md") != "note" || res.Conflict == "" {
		t.Fatalf("overwrite restore = %+v, %v", res, err)
	}
	if kept, _ := os.ReadFile(filepath.Join(res.Conflict, "notes", "n.md")); string(kept) != "newer here" {
		t.Fatalf("replaced newer file not kept: %q", kept)
	}
}

func TestRestoreRejectsEscapingPaths(t *testing.T) {
	ctx := context.Background()
	d := newDevice(t)
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create(manifestName)
	w.Write([]byte(`{"format":"look-studio-backup","version":1}`))
	for _, name := range []string{"library/../../evil.txt", "data/seal.key", "data/agent/keys.json", "library/ok.md"} {
		w, _ := zw.Create(name)
		w.Write([]byte("x"))
	}
	zw.Close()
	pv, err := d.Receive(ctx, &buf)
	if err != nil {
		t.Fatal(err)
	}
	if pv.Files != 1 || pv.Skipped != 3 {
		t.Fatalf("preview = %+v", pv)
	}
	if _, err := d.Restore(ctx, pv.ID, "overwrite"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(d.Roots.Library), "evil.txt")); err == nil {
		t.Fatal("zip slip")
	}
	if _, err := os.Stat(filepath.Join(d.Roots.Data, "seal.key")); err == nil {
		t.Fatal("restored a key")
	}
	if d.read("library/ok.md") != "x" {
		t.Fatal("valid entry not restored")
	}
	if _, err := d.Receive(ctx, strings.NewReader("not a zip")); err != ErrNotBackup {
		t.Fatalf("err = %v", err)
	}
}

// The assistant's data gets the same protection as library files: a losing
// edit, a remote deletion and a file replaced by a restore are kept aside.
func TestAssistantDataIsKeptAside(t *testing.T) {
	ctx := context.Background()
	srv := davServer(t)
	a, b := newDevice(t), newDevice(t)
	connect(t, a, srv.URL, false)
	connect(t, b, srv.URL, false)
	const mem = "data/agent/bot/memory/profile.md"
	a.write(t, mem, "v1", time.Hour)
	a.sync(t)
	b.sync(t)

	a.write(t, mem, "older edit on a", 10*time.Minute)
	b.write(t, mem, "newer edit on b", time.Minute)
	a.sync(t)
	res := b.sync(t)
	if res.ConflictDir == "" {
		t.Fatalf("conflict not kept aside: %+v", res)
	}
	if kept, _ := os.ReadFile(filepath.Join(res.ConflictDir, "data", "agent", "bot", "memory", "profile.md")); string(kept) != "older edit on a" {
		t.Fatalf("losing copy = %q", kept)
	}

	a.sync(t)
	abs, _ := b.Roots.Abs(mem)
	os.Remove(abs)
	b.sync(t)
	a.sync(t)
	trash, _ := filepath.Glob(filepath.Join(a.Roots.Library, TrashDir, "*", "data", "agent", "bot", "memory", "profile.md"))
	if a.read(mem) != "<missing>" || len(trash) != 1 {
		t.Fatalf("remote deletion: file %q, trash %v", a.read(mem), trash)
	}

	c := newDevice(t)
	c.write(t, "data/agent/tasks.json", "[]", time.Hour)
	var buf bytes.Buffer
	if err := c.Export(ctx, &buf, false); err != nil {
		t.Fatal(err)
	}
	d := newDevice(t)
	d.write(t, "data/agent/tasks.json", `[{"id":"newer"}]`, 0)
	pv, err := d.Receive(ctx, bytes.NewReader(buf.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	r, err := d.Restore(ctx, pv.ID, "overwrite")
	if err != nil || d.read("data/agent/tasks.json") != "[]" {
		t.Fatalf("overwrite restore = %+v, %v", r, err)
	}
	if kept, _ := os.ReadFile(filepath.Join(r.Conflict, "data", "agent", "tasks.json")); string(kept) != `[{"id":"newer"}]` {
		t.Fatalf("replaced newer data not kept: %q", kept)
	}
}
