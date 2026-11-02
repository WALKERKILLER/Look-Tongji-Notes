// Package datasync moves a user's data between devices: backup archives to
// export and restore, and a two-way sync of the library over WebDAV.
// Contract: docs/specs/0014-data-sync-and-backup.md
package datasync

import (
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Paths inside an archive or the sync tree are slash separated and start
// with "library/" (the course library) or "data/" (the assistant's data).

// media are the large files that come back by downloading the lecture again.
var media = map[string]bool{
	".mp4": true, ".m4v": true, ".mkv": true, ".webm": true, ".flv": true, ".ts": true, ".mov": true,
	".mp3": true, ".m4a": true, ".aac": true, ".wav": true, ".flac": true, ".ogg": true, ".opus": true,
}

// IsMedia reports whether rel is a video or audio file.
func IsMedia(rel string) bool { return media[strings.ToLower(path.Ext(rel))] }

// libraryFile reports whether a library-relative path is user data worth
// carrying: not the index (rebuilt from the files), not hidden working
// folders (.cache, .mirror-journal, sync conflicts), not partial downloads.
func libraryFile(rel string, withMedia bool) bool {
	for _, seg := range strings.Split(rel, "/") {
		if strings.HasPrefix(seg, ".") {
			return false
		}
	}
	base := path.Base(rel)
	switch {
	case strings.HasPrefix(rel, "library.db"),
		strings.HasSuffix(base, ".part"), strings.HasSuffix(base, ".tmp"), strings.HasSuffix(base, ".moving"):
		return false
	case IsMedia(rel):
		return withMedia
	}
	return true
}

// dataFiles are the assistant's portable data under the data directory.
// Credentials (keys, sessions, sealed tokens and seal.key), caches and
// device settings stay on the device: sealed values cannot be opened on
// another one anyway.
var dataFiles = []string{
	"agent/assistant.json",
	"agent/sessions-meta.json",
	"agent/tasks.json",
	"agent/tasks-runs.jsonl",
	"agent/usage.jsonl",
}

var dataDirs = []string{"agent/sessions", "agent/bot"}

// File is one file of the data set.
type File struct {
	Path    string    // "library/…" or "data/…"
	Abs     string    // on this device
	Size    int64     //
	ModTime time.Time //
}

// Roots locates the data on this device.
type Roots struct {
	Library string
	Data    string
}

// Abs maps an archive path to this device; false for paths outside the set.
func (r Roots) Abs(p string) (string, bool) {
	if p != path.Clean(p) || strings.Contains(p, "\\") || strings.HasPrefix(p, "/") {
		return "", false
	}
	switch {
	case strings.HasPrefix(p, "library/"):
		rel := strings.TrimPrefix(p, "library/")
		if rel == "" || !libraryFile(rel, true) {
			return "", false
		}
		return filepath.Join(r.Library, filepath.FromSlash(rel)), true
	case strings.HasPrefix(p, "data/"):
		rel := strings.TrimPrefix(p, "data/")
		if !dataAllowed(rel) {
			return "", false
		}
		return filepath.Join(r.Data, filepath.FromSlash(rel)), true
	}
	return "", false
}

func dataAllowed(rel string) bool {
	for _, f := range dataFiles {
		if rel == f {
			return true
		}
	}
	for _, d := range dataDirs {
		if strings.HasPrefix(rel, d+"/") && !strings.Contains(rel[len(d)+1:], "..") {
			for _, seg := range strings.Split(rel, "/") {
				if strings.HasPrefix(seg, ".") {
					return false
				}
			}
			return true
		}
	}
	return false
}

// ScanLibrary lists the library's files, sorted by path.
func (r Roots) ScanLibrary(withMedia bool) ([]File, error) {
	var out []File
	err := filepath.WalkDir(r.Library, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			if p == r.Library && os.IsNotExist(err) {
				return nil
			}
			return err
		}
		rel, err := filepath.Rel(r.Library, p)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if d.IsDir() {
			if rel != "." && strings.HasPrefix(d.Name(), ".") {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() || !libraryFile(rel, withMedia) {
			return nil
		}
		fi, err := d.Info()
		if err != nil {
			return err
		}
		out = append(out, File{Path: "library/" + rel, Abs: p, Size: fi.Size(), ModTime: fi.ModTime()})
		return nil
	})
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out, err
}

// ScanData lists portable files; an unreadable subtree is not a deletion.
func (r Roots) ScanData() ([]File, error) {
	var out []File
	add := func(rel string) error {
		p := filepath.Join(r.Data, filepath.FromSlash(rel))
		fi, err := os.Lstat(p)
		if err != nil {
			return err
		}
		if fi.Mode().IsRegular() {
			out = append(out, File{Path: "data/" + rel, Abs: p, Size: fi.Size(), ModTime: fi.ModTime()})
		}
		return nil
	}
	for _, f := range dataFiles {
		if err := add(f); err != nil && !os.IsNotExist(err) {
			return out, err
		}
	}
	for _, d := range dataDirs {
		root := filepath.Join(r.Data, filepath.FromSlash(d))
		err := filepath.WalkDir(root, func(p string, e fs.DirEntry, err error) error {
			if err != nil {
				if p == root && os.IsNotExist(err) {
					return nil
				}
				return err
			}
			rel, err := filepath.Rel(r.Data, p)
			if err != nil {
				return err
			}
			if e.IsDir() && p != root && !dataAllowed(filepath.ToSlash(rel)+"/") {
				return filepath.SkipDir
			}
			if e.Type().IsRegular() && dataAllowed(filepath.ToSlash(rel)) {
				return add(filepath.ToSlash(rel))
			}
			return nil
		})
		if err != nil {
			return out, err
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out, nil
}

// writeFile replaces dst atomically with the bytes from fill.
func writeFile(dst string, mod time.Time, fill func(f *os.File) error) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(dst), "."+filepath.Base(dst)+".sync-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	if err := fill(f); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if !mod.IsZero() {
		os.Chtimes(tmp, mod, mod)
	}
	if err := os.Rename(tmp, dst); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}
