package tongji

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"os"
	"path/filepath"
)

// KeyPath is the per-install key used to seal remembered passwords at rest.
// It keeps the password out of plain-text config and backups that skip the
// key; it is not a substitute for an OS keychain against a local attacker.
var KeyPath string

func sealKey() ([]byte, error) {
	if KeyPath == "" {
		return nil, errors.New("seal key path not set")
	}
	b, err := os.ReadFile(KeyPath)
	if err == nil && len(b) == 32 {
		return b, nil
	}
	b = make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	os.MkdirAll(filepath.Dir(KeyPath), 0o700)
	if err := os.WriteFile(KeyPath, b, 0o600); err != nil {
		return nil, err
	}
	return b, nil
}

func aead() (cipher.AEAD, error) {
	k, err := sealKey()
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(append([]byte("lookd-seal-v1"), k...))
	blk, err := aes.NewCipher(sum[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(blk)
}

func seal(plain string) (string, error) {
	g, err := aead()
	if err != nil {
		return "", err
	}
	nonce := make([]byte, g.NonceSize())
	rand.Read(nonce)
	return base64.StdEncoding.EncodeToString(g.Seal(nonce, nonce, []byte(plain), nil)), nil
}

func unseal(s string) (string, error) {
	g, err := aead()
	if err != nil {
		return "", err
	}
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil || len(b) < g.NonceSize() {
		return "", errors.New("bad sealed value")
	}
	p, err := g.Open(nil, b[:g.NonceSize()], b[g.NonceSize():], nil)
	return string(p), err
}

// Seal and Unseal protect other local secrets (such as API tokens) with the
// same per-install key.
func Seal(plain string) (string, error) { return seal(plain) }
func Unseal(s string) (string, error)   { return unseal(s) }
