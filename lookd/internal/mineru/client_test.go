package mineru

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func resultZip(t *testing.T, extra map[string]string) []byte {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	files := map[string]string{
		"abc/full.md":               "# 第一章\n![](images/a.jpg)\n",
		"abc/images/a.jpg":          "jpg",
		"abc/abc_content_list.json": `[{"page_idx":0},{"page_idx":2}]`,
		"abc/abc_origin.pdf":        "%PDF",
		"abc/layout.json":           "{}",
	}
	for k, v := range extra {
		files[k] = v
	}
	for name, body := range files {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		io.WriteString(w, body)
	}
	zw.Close()
	return buf.Bytes()
}

func TestPreciseFlow(t *testing.T) {
	var uploaded atomic.Value
	var polls atomic.Int32
	zb := resultZip(t, nil)
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/file-urls/batch":
			if r.Header.Get("Authorization") != "Bearer tok" {
				json.NewEncoder(w).Encode(map[string]any{"code": "A0202", "msg": "bad token"})
				return
			}
			json.NewEncoder(w).Encode(map[string]any{"code": 0, "data": map[string]any{"batch_id": "b1", "file_urls": []string{srv.URL + "/upload"}}})
		case r.URL.Path == "/upload" && r.Method == http.MethodPut:
			if r.Header.Get("Content-Type") != "" {
				http.Error(w, "signature mismatch", 403)
				return
			}
			b, _ := io.ReadAll(r.Body)
			uploaded.Store(string(b))
		case r.URL.Path == "/extract-results/batch/b1":
			state := "running"
			if polls.Add(1) > 1 {
				state = "done"
			}
			json.NewEncoder(w).Encode(map[string]any{"code": 0, "data": map[string]any{"extract_result": []map[string]any{{
				"state": state, "full_zip_url": srv.URL + "/zip", "extract_progress": map[string]int{"extracted_pages": 1, "total_pages": 3},
			}}}})
		case r.URL.Path == "/zip":
			w.Write(zb)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	dir := t.TempDir()
	file := filepath.Join(dir, "讲义.pdf")
	os.WriteFile(file, []byte("%PDF-1.7 test"), 0o644)
	out := filepath.Join(dir, "讲义.pdf.parsed")
	c := &client{hc: srv.Client(), base: srv.URL, token: "tok"}
	var stages []string
	pages, err := c.precise(context.Background(), file, out, Options{}.normalized(), func(s string, _ float64) { stages = append(stages, s) })
	if err != nil {
		t.Fatal(err)
	}
	if uploaded.Load() != "%PDF-1.7 test" || pages != 3 {
		t.Fatalf("uploaded=%v pages=%d", uploaded.Load(), pages)
	}
	if b, _ := os.ReadFile(filepath.Join(out, "full.md")); !strings.Contains(string(b), "第一章") {
		t.Fatal("markdown missing")
	}
	if _, err := os.Stat(filepath.Join(out, "abc/images/a.jpg")); err != nil {
		t.Fatal("image missing")
	}
	if _, err := os.Stat(filepath.Join(out, "abc/abc_origin.pdf")); err == nil {
		t.Fatal("origin pdf should be skipped")
	}
	if !strings.Contains(strings.Join(stages, ","), "解析中") {
		t.Fatalf("stages %v", stages)
	}

	c.token = "wrong"
	if _, err := c.precise(context.Background(), file, out, Options{}.normalized(), func(string, float64) {}); !Auth(err) {
		t.Fatalf("want auth error, got %v", err)
	}
}

func TestUnpackRejectsEscapes(t *testing.T) {
	out := t.TempDir()
	if _, err := unpack(resultZip(t, map[string]string{"../evil/images/x.md": "x"}), filepath.Join(out, "r")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(out, "evil")); err == nil {
		t.Fatal("zip entry escaped the output folder")
	}
}

func TestTokenExp(t *testing.T) {
	tok := "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE4MDAwMDAwMDB9.sig"
	if tokenExp(tok) != 1800000000 || tokenExp("plain") != 0 {
		t.Fatal("exp")
	}
}
