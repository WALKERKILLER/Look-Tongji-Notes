package rootfs

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

type entry struct {
	name, body, link string
	typ              byte
	mode             int64
}

func archive(t *testing.T, es []entry) ([]byte, string) {
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range es {
		hd := &tar.Header{Name: e.name, Typeflag: e.typ, Mode: e.mode, Linkname: e.link, Size: int64(len(e.body))}
		if err := tw.WriteHeader(hd); err != nil {
			t.Fatal(err)
		}
		tw.Write([]byte(e.body))
	}
	tw.Close()
	gz.Close()
	sum := sha256.Sum256(buf.Bytes())
	return buf.Bytes(), hex.EncodeToString(sum[:])
}

func TestUnpack(t *testing.T) {
	b, sum := archive(t, []entry{
		{name: "./", typ: tar.TypeDir, mode: 0o755},
		{name: "./usr/bin/", typ: tar.TypeDir, mode: 0o755},
		{name: "./usr/bin/tool", typ: tar.TypeReg, mode: 0o755, body: "#!/bin/sh\n"},
		{name: "./usr/bin/same", typ: tar.TypeLink, link: "./usr/bin/tool"},
		{name: "./bin", typ: tar.TypeSymlink, link: "usr/bin"},
		{name: "./dev/null", typ: tar.TypeChar},
	})
	dir := t.TempDir()
	var seen int64
	if err := Unpack(bytes.NewReader(b), dir, sum, func(n int64) { seen = n }); err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(filepath.Join(dir, "usr/bin/tool"))
	if err != nil || fi.Mode().Perm() != 0o755 {
		t.Fatalf("tool = %v, %v", fi, err)
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "usr/bin/same")); string(got) != "#!/bin/sh\n" {
		t.Fatalf("hard link copy = %q", got)
	}
	if l, _ := os.Readlink(filepath.Join(dir, "bin")); l != "usr/bin" {
		t.Fatalf("symlink = %q", l)
	}
	if seen != int64(len(b)) {
		t.Fatalf("progress %d of %d", seen, len(b))
	}
}

func TestUnpackRejects(t *testing.T) {
	good, _ := archive(t, []entry{{name: "a", typ: tar.TypeReg, mode: 0o644, body: "x"}})
	if err := Unpack(bytes.NewReader(good), t.TempDir(), "00", nil); err != ErrChecksum {
		t.Fatalf("checksum: %v", err)
	}
	for name, es := range map[string][]entry{
		"dotdot":       {{name: "../evil", typ: tar.TypeReg, mode: 0o644, body: "x"}},
		"through link": {{name: "out", typ: tar.TypeSymlink, link: "/tmp"}, {name: "out/evil", typ: tar.TypeReg, mode: 0o644, body: "x"}},
		"link target":  {{name: "h", typ: tar.TypeLink, link: "../../etc/passwd"}},
	} {
		b, _ := archive(t, es)
		if err := Unpack(bytes.NewReader(b), t.TempDir(), "", nil); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}
