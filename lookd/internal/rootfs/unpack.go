// Package rootfs unpacks the Linux root filesystem the Android app runs
// lookd in. Contract: docs/specs/draft-android-app.md
package rootfs

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ErrChecksum means the archive is not the one asked for.
var ErrChecksum = errors.New("checksum mismatch")

type counter struct {
	r    io.Reader
	n    int64
	tick func(int64)
}

func (c *counter) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	if c.tick != nil {
		c.tick(c.n)
	}
	return n, err
}

// Unpack extracts a .tar.gz into dir, keeping modes and symlinks. Hard
// links become copies: Android does not let apps create them. Nothing is
// written through a symlink, so entries cannot escape dir. With want set,
// the archive's SHA-256 must match it; progress gets compressed bytes read.
func Unpack(r io.Reader, dir, want string, progress func(int64)) error {
	h := sha256.New()
	cr := &counter{r: io.TeeReader(r, h), tick: progress}
	gz, err := gzip.NewReader(cr)
	if err != nil {
		return err
	}
	tr := tar.NewReader(gz)
	root := filepath.Clean(dir)
	if err := os.MkdirAll(root, 0o755); err != nil {
		return err
	}
	type link struct{ path, target string }
	var hard []link
	for {
		hd, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		p, err := inside(root, hd.Name)
		if err != nil {
			return err
		}
		if p == root {
			continue
		}
		if err := noSymlinkParents(root, filepath.Dir(p)); err != nil {
			return err
		}
		mode := os.FileMode(hd.Mode & 0o7777)
		switch hd.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(p, 0o755); err != nil {
				return err
			}
			os.Chmod(p, mode|0o700)
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				return err
			}
			os.Remove(p)
			f, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode|0o600)
			if err != nil {
				return err
			}
			_, err = io.Copy(f, tr)
			if cerr := f.Close(); err == nil {
				err = cerr
			}
			if err != nil {
				return err
			}
			os.Chmod(p, mode|0o600)
		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				return err
			}
			os.Remove(p)
			if err := os.Symlink(hd.Linkname, p); err != nil {
				return err
			}
		case tar.TypeLink:
			t, err := inside(root, hd.Linkname)
			if err != nil {
				return err
			}
			hard = append(hard, link{p, t})
		default:
			// Device nodes and FIFOs: the guest gets /dev from the host.
		}
	}
	io.Copy(io.Discard, cr) // the checksum covers the whole file
	if want != "" && !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), want) {
		return ErrChecksum
	}
	for _, l := range hard {
		if err := copyFile(l.target, l.path); err != nil {
			return fmt.Errorf("hard link %s: %w", l.path, err)
		}
	}
	return nil
}

func inside(root, name string) (string, error) {
	p := filepath.Join(root, filepath.FromSlash(name))
	if p != root && !strings.HasPrefix(p, root+string(filepath.Separator)) {
		return "", fmt.Errorf("entry %q leaves the root", name)
	}
	return p, nil
}

func noSymlinkParents(root, dir string) error {
	for d := dir; d != root && strings.HasPrefix(d, root); d = filepath.Dir(d) {
		if fi, err := os.Lstat(d); err == nil && fi.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("entry under symlink %s", d)
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	fi, err := in.Stat()
	if err != nil {
		return err
	}
	os.Remove(dst)
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, fi.Mode().Perm())
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	return err
}
