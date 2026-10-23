package localasr

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestParse(t *testing.T) {
	out := []byte("Started\n1.542 -- 7.116: 大家好\n7.2 -- 9.000: \n10.000 -- 12.500: 今天讲 Go\n")
	us := parse(out)
	if len(us) != 2 || us[0].StartMs != 1542 || us[0].EndMs != 7116 || us[1].Text != "今天讲 Go" {
		t.Fatalf("got %+v", us)
	}
}

func TestRealign(t *testing.T) {
	got, ok := realign([]string{"其言曰士大夫", "有网友坐飞机"}, "其言曰，士大夫。有网友坐飞机。")
	if !ok || !reflect.DeepEqual(got, []string{"其言曰，士大夫。", "有网友坐飞机。"}) {
		t.Fatalf("got %q %v", got, ok)
	}
	got, ok = realign([]string{"today is monday", "ok"}, "TODAYIS MONDAY，OK。")
	if !ok || !reflect.DeepEqual(got, []string{"today is monday，", "ok。"}) {
		t.Fatalf("case/space: got %q %v", got, ok)
	}
	if _, ok := realign([]string{"你好"}, "您好。"); ok {
		t.Fatal("a changed character must fail")
	}
	if _, ok := realign([]string{"你好世界"}, "你好。"); ok {
		t.Fatal("dropped text must fail")
	}
}

func TestInsideRefusesEscapes(t *testing.T) {
	for _, bad := range []string{"/etc/passwd", "top/../../x"} {
		if _, err := inside(bad); err == nil {
			t.Fatalf("%q accepted", bad)
		}
	}
	if rel, err := inside("sherpa-onnx-v1/bin/x"); err != nil || rel != "bin/x" {
		t.Fatalf("got %q %v", rel, err)
	}
	if !wanted("lib/libonnxruntime.so") || wanted("include/x.h") {
		t.Fatal("wanted filter")
	}
}

func serve(t *testing.T, body []byte) (*httptest.Server, *int) {
	hits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		http.ServeContent(w, r, "f", time.Time{}, bytes.NewReader(body))
	}))
	t.Cleanup(srv.Close)
	return srv, &hits
}

func TestFetchResumesAndVerifies(t *testing.T) {
	body := bytes.Repeat([]byte("look studio "), 50000)
	sum := sha256.Sum256(body)
	f := File{Path: "m.onnx", Size: int64(len(body)), SHA256: hex.EncodeToString(sum[:])}
	srv, _ := serve(t, body)
	dir := t.TempDir()
	m := &Manager{Dir: dir}
	dest := filepath.Join(dir, "m.onnx")
	os.WriteFile(dest+".part", body[:1000], 0o600)
	tr := &tracker{m: m, start: time.Now()}
	if err := m.fetch(context.Background(), srv.URL, dest, f, tr); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(dest); !bytes.Equal(b, body) {
		t.Fatal("content differs after resume")
	}
	if p := m.st; p.Done != f.Size {
		t.Fatalf("progress %d of %d", p.Done, f.Size)
	}

	bad := f
	bad.SHA256 = strings.Repeat("0", 64)
	dest2 := filepath.Join(dir, "bad.onnx")
	if err := m.fetch(context.Background(), srv.URL, dest2, bad, &tracker{m: m}); err == nil || !strings.Contains(err.Error(), "校验失败") {
		t.Fatalf("want digest failure, got %v", err)
	}
	if _, err := os.Stat(dest2 + ".part"); !os.IsNotExist(err) {
		t.Fatal("a corrupt part must be removed")
	}
	big := f
	big.Size = 100
	if err := m.fetch(context.Background(), srv.URL, filepath.Join(dir, "big"), big, &tracker{m: m}); err == nil {
		t.Fatal("oversized download must fail")
	}
}

func TestSourcesAndStatus(t *testing.T) {
	md, _ := Find("qwen3-asr-0.6b")
	f := md.pack.files[2]
	if u, _ := md.pack.url("modelscope", "", f); u != "https://modelscope.cn/models/zengshuishui/Qwen3-ASR-onnx/resolve/master/model_0.6B/decoder.int8.onnx" {
		t.Fatal(u)
	}
	if u, _ := md.pack.url("custom", "https://example.org/{repo}/resolve/main/{file}", f); !strings.HasSuffix(u, md.pack.repo+"/resolve/main/decoder.int8.onnx") {
		t.Fatal(u)
	}
	if _, ok := punct.url("modelscope", "", punct.files[0]); ok {
		t.Fatal("punctuation has no ModelScope copy")
	}
	for _, md := range Models {
		if md.Bench.CER <= 0 || md.Bench.SourceURL == "" || md.License == "" || len(md.pack.files) == 0 {
			t.Fatalf("%s: incomplete catalog entry", md.ID)
		}
		for _, f := range md.pack.files {
			if f.Size <= 0 {
				t.Fatalf("%s/%s: no size", md.ID, f.Path)
			}
		}
	}
	m := &Manager{Dir: t.TempDir(), OS: "linux", Arch: "amd64"}
	st := m.Status()
	if !st.Supported || len(st.Models) != len(Models) || st.Models[0].Installed || st.Models[0].Extra == 0 {
		t.Fatalf("status %+v", st)
	}
	if (&Manager{OS: "linux", Arch: "riscv64"}).Supported() {
		t.Fatal("riscv64 has no prebuilt engine")
	}
	if err := m.Start(context.Background(), "qwen3-asr-0.6b", Options{Source: "custom", Custom: "ftp://x"}); err == nil {
		t.Fatal("invalid template accepted")
	}
}

func TestPunctFlags(t *testing.T) {
	for id, want := range map[string]bool{"qwen3-asr-0.6b": true, "fun-asr-nano": true, "sensevoice-small": false, "firered-asr2-aed": false} {
		if md, _ := Find(id); md.Punct != want {
			t.Fatalf("%s punct = %v", id, md.Punct)
		}
	}
}
