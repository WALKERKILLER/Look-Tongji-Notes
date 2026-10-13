// probe dumps raw API responses to a directory for schema inspection.
package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"os"
	"path/filepath"
	"time"

	"lookstudio/lookd/internal/tongji"
)

func main() {
	jar, _ := cookiejar.New(nil)
	hc := &http.Client{Jar: jar, Timeout: 30 * time.Second}
	ctx := context.Background()
	tok, err := tongji.Login(ctx, hc, os.Getenv("LOOK_USER"), os.Getenv("LOOK_PASS"), "")
	if err != nil {
		panic(err)
	}
	out := os.Args[1]
	os.MkdirAll(out, 0o700)
	for i := 2; i+1 < len(os.Args); i += 2 {
		name, path := os.Args[i], os.Args[i+1]
		req, _ := http.NewRequest("GET", tongji.BaseURL+path, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		req.Header.Set("User-Agent", tongji.UserAgent)
		req.Header.Set("accept-language", "zh_cn")
		resp, err := hc.Do(req)
		if err != nil {
			fmt.Println(name, err)
			continue
		}
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		os.WriteFile(filepath.Join(out, name+".json"), b, 0o600)
		fmt.Println(name, resp.StatusCode, len(b))
	}
}
