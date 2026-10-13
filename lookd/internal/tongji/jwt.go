package tongji

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"
)

// Claims is the subset of look JWT claims the daemon relies on.
type Claims struct {
	Sub any   `json:"sub"`
	Exp int64 `json:"exp"`
	Iat int64 `json:"iat"`
}

func (c Claims) Expiry() time.Time {
	if c.Exp == 0 {
		return time.Time{}
	}
	return time.Unix(c.Exp, 0)
}

func (c Claims) Subject() string {
	switch v := c.Sub.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatInt(int64(v), 10)
	}
	return ""
}

// ParseJWT decodes the payload without verifying the signature (the server does).
func ParseJWT(tok string) (Claims, error) {
	var c Claims
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return c, errors.New("malformed jwt")
	}
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(parts[1], "="))
	if err != nil {
		return c, err
	}
	return c, json.Unmarshal(b, &c)
}
