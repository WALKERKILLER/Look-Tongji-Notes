// logintest exercises the IAM login against the live service.
// Credentials come from LOOK_USER / LOOK_PASS; nothing is persisted.
package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"os"
	"time"

	"lookstudio/lookd/internal/tongji"
)

func main() {
	jar, _ := cookiejar.New(nil)
	hc := &http.Client{Jar: jar, Timeout: 30 * time.Second}
	ctx := context.Background()
	t0 := time.Now()
	tok, err := tongji.Login(ctx, hc, os.Getenv("LOOK_USER"), os.Getenv("LOOK_PASS"), "")
	if err != nil {
		fmt.Println("login error:", err)
		os.Exit(1)
	}
	claims, _ := tongji.ParseJWT(tok)
	fmt.Printf("login ok in %v, jwt len=%d sub=%s exp=%v\n", time.Since(t0), len(tok), claims.Subject(), claims.Expiry())
	t0 = time.Now()
	tok2, err := tongji.SilentRenew(ctx, hc)
	if err != nil {
		fmt.Println("silent renew error:", err)
		os.Exit(1)
	}
	c2, _ := tongji.ParseJWT(tok2)
	fmt.Printf("silent renew ok in %v, new=%v exp=%v\n", time.Since(t0), tok2 != tok, c2.Expiry())
}
