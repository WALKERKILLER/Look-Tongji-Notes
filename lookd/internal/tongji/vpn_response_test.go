package tongji

import (
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

type trackedVPNBody struct {
	io.Reader
	closed bool
}

func (b *trackedVPNBody) Close() error { b.closed = true; return nil }

func TestVPNResponseContentType(t *testing.T) {
	for _, tt := range []struct {
		name, path, body, contentType string
		status                        int
		signedOut                     bool
	}{
		{"JSON mislabeled as HTML", "/https/encoded/courseapi/detail", `{"code":0,"data":{"sub_list":[]}}`, "text/html; charset=UTF-8", 200, false},
		{"long JSON preserves all bytes", "/https/encoded/courseapi/detail", "  {\"data\":\"" + strings.Repeat("x", 4096) + "\"}", "text/html", 200, false},
		{"JSON array", "/https/encoded/api", "\n[]", "text/html", 200, false},
		{"actual login HTML", "/https/encoded/ac/", "<!doctype html><html>login</html>", "text/html", 200, true},
		{"gateway login redirect", "/login", `{"code":0}`, "application/json", 200, true},
		{"unauthorized", "/https/encoded/api", `{"code":401}`, "application/json", 401, true},
		{"video range", "/https/encoded/video.mp4", "video data", "video/mp4", 206, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			body := &trackedVPNBody{Reader: strings.NewReader(tt.body)}
			resp := &http.Response{StatusCode: tt.status, Header: http.Header{"Content-Type": {tt.contentType}}, Request: &http.Request{URL: &url.URL{Scheme: "https", Host: "webvpn.fudan.edu.cn", Path: tt.path}}, Body: body}
			if got := VPNSignedOut(resp); got != tt.signedOut {
				t.Errorf("signedOut=%v want %v", got, tt.signedOut)
			}
			raw, err := io.ReadAll(resp.Body)
			if err != nil || string(raw) != tt.body {
				t.Fatal("classification consumed or changed body")
			}
			resp.Body.Close()
			if !body.closed {
				t.Fatal("original response body not closed")
			}
		})
	}
}
