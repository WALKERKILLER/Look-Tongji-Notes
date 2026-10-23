package datasync

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// A backup is a zip: manifest.json first, state/library.json (the personal
// state the index keeps, see store.UserState), then the files under their
// archive paths. Files keep their modification times, which restore
// compares to decide what is newer.

const (
	backupFormat = "look-studio-backup"
	manifestName = "manifest.json"
	stateName    = "state/library.json"
	// mtimes closer than this count as equal: zip keeps 2 s precision.
	timeSlack = 2 * time.Second
)

// Entry describes one file in a manifest. Times are Unix milliseconds.
type Entry struct {
	Size    int64  `json:"size"`
	MTime   int64  `json:"mtime"`
	Hash    string `json:"sha256,omitempty"`
	Deleted int64  `json:"deleted,omitempty"` // tombstone in the sync manifest
}

type BackupManifest struct {
	Format  string           `json:"format"`
	Version int              `json:"version"`
	Created int64            `json:"created"`
	Device  string           `json:"device"`
	App     string           `json:"app"`
	Media   bool             `json:"media"`
	Files   map[string]Entry `json:"files"`
}

// Estimate is what an export would contain.
type Estimate struct {
	Files int   `json:"files"`
	Bytes int64 `json:"bytes"`
	// Media are the videos and recordings left out unless asked for.
	MediaFiles int   `json:"media_files"`
	MediaBytes int64 `json:"media_bytes"`
}

func (s *Service) Estimate() Estimate {
	var e Estimate
	for _, f := range append(s.Roots.ScanLibrary(true), s.Roots.ScanData()...) {
		if IsMedia(f.Path) {
			e.MediaFiles++
			e.MediaBytes += f.Size
			continue
		}
		e.Files++
		e.Bytes += f.Size
	}
	return e
}

// stored are formats that do not shrink further.
var stored = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true,
	".zip": true, ".gz": true, ".7z": true, ".pptx": true, ".docx": true, ".xlsx": true}

// Export writes a backup archive to w.
func (s *Service) Export(ctx context.Context, w io.Writer, withMedia bool) error {
	files := append(s.Roots.ScanLibrary(withMedia), s.Roots.ScanData()...)
	m := BackupManifest{Format: backupFormat, Version: 1, Created: time.Now().UnixMilli(), Device: s.deviceName(),
		App: s.App, Media: withMedia, Files: map[string]Entry{}}
	for _, f := range files {
		m.Files[f.Path] = Entry{Size: f.Size, MTime: f.ModTime.UnixMilli()}
	}
	zw := zip.NewWriter(w)
	put := func(name string, v any) error {
		b, err := json.MarshalIndent(v, "", "  ")
		if err != nil {
			return err
		}
		fw, err := zw.CreateHeader(&zip.FileHeader{Name: name, Method: zip.Deflate, Modified: time.Now()})
		if err == nil {
			_, err = fw.Write(b)
		}
		return err
	}
	if err := put(manifestName, m); err != nil {
		return err
	}
	if s.State != nil {
		st, err := s.State(ctx)
		if err != nil {
			return err
		}
		if err := put(stateName, json.RawMessage(st)); err != nil {
			return err
		}
	}
	for _, f := range files {
		if err := ctx.Err(); err != nil {
			return err
		}
		method := zip.Deflate
		if IsMedia(f.Path) || stored[strings.ToLower(path.Ext(f.Path))] {
			method = zip.Store
		}
		fw, err := zw.CreateHeader(&zip.FileHeader{Name: f.Path, Method: method, Modified: f.ModTime})
		if err != nil {
			return err
		}
		src, err := os.Open(f.Abs)
		if err != nil {
			continue // deleted since the scan
		}
		_, err = io.Copy(fw, src)
		src.Close()
		if err != nil {
			return err
		}
	}
	return zw.Close()
}

// Preview summarizes a backup before it is restored.
type Preview struct {
	ID      string `json:"id"`
	Created int64  `json:"created"`
	Device  string `json:"device"`
	App     string `json:"app"`
	Media   bool   `json:"media"`
	Files   int    `json:"files"`
	Bytes   int64  `json:"bytes"`
	New     int    `json:"new"`   // not on this device
	Newer   int    `json:"newer"` // newer in the backup
	Older   int    `json:"older"` // newer on this device
	Same    int    `json:"same"`
	// Skipped are entries outside what a backup may restore (credentials,
	// paths escaping the library).
	Skipped int  `json:"skipped"`
	State   bool `json:"state"`
}

var ErrNotBackup = errors.New("这不是 Look Studio 的备份文件")

// RestoreResult reports an applied backup.
type RestoreResult struct {
	Written  int    `json:"written"`
	Kept     int    `json:"kept"`
	Bytes    int64  `json:"bytes"`
	Library  bool   `json:"library"`            // library files changed
	Data     bool   `json:"data"`               // assistant files changed
	Conflict string `json:"conflict,omitempty"` // where replaced newer files went
}

type verdict int

const (
	vNew verdict = iota
	vNewer
	vOlder
	vSame
)

func compare(abs string, size int64, mod time.Time) verdict {
	fi, err := os.Stat(abs)
	if err != nil {
		return vNew
	}
	d := fi.ModTime().Sub(mod)
	switch {
	case d > timeSlack:
		return vOlder
	case d < -timeSlack:
		return vNewer
	case fi.Size() == size:
		return vSame
	}
	return vNewer
}

func openBackup(p string) (*zip.ReadCloser, BackupManifest, error) {
	var m BackupManifest
	zr, err := zip.OpenReader(p)
	if err != nil {
		return nil, m, ErrNotBackup
	}
	for _, f := range zr.File {
		if f.Name != manifestName {
			continue
		}
		rc, err := f.Open()
		if err == nil {
			err = json.NewDecoder(io.LimitReader(rc, 64<<20)).Decode(&m)
			rc.Close()
		}
		if err == nil && m.Format == backupFormat {
			if m.Version > 1 {
				zr.Close()
				return nil, m, errors.New("备份来自更新版本的 Look Studio，请先升级")
			}
			return zr, m, nil
		}
		break
	}
	zr.Close()
	return nil, m, ErrNotBackup
}

func (s *Service) importPath(id string) (string, error) {
	if id == "" || strings.ContainsAny(id, `/\.`) {
		return "", os.ErrNotExist
	}
	return filepath.Join(s.Roots.Data, "imports", id+".zip"), nil
}

// Receive stores an uploaded backup and previews it.
func (s *Service) Receive(ctx context.Context, r io.Reader) (Preview, error) {
	dir := filepath.Join(s.Roots.Data, "imports")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return Preview{}, err
	}
	s.cleanImports(24 * time.Hour)
	id := fmt.Sprintf("%d", time.Now().UnixNano())
	p, _ := s.importPath(id)
	err := writeFile(p, time.Time{}, func(f *os.File) error {
		_, err := io.Copy(f, &ctxReader{ctx, r})
		return err
	})
	if err != nil {
		return Preview{}, err
	}
	pv, err := s.Inspect(id)
	if err != nil {
		os.Remove(p)
	}
	return pv, err
}

// Inspect previews a received backup.
func (s *Service) Inspect(id string) (Preview, error) {
	p, err := s.importPath(id)
	if err != nil {
		return Preview{}, err
	}
	zr, m, err := openBackup(p)
	if err != nil {
		return Preview{}, err
	}
	defer zr.Close()
	pv := Preview{ID: id, Created: m.Created, Device: m.Device, App: m.App, Media: m.Media}
	for _, f := range zr.File {
		switch {
		case f.Name == manifestName:
			continue
		case f.Name == stateName:
			pv.State = true
			continue
		case strings.HasSuffix(f.Name, "/"):
			continue
		}
		abs, ok := s.Roots.Abs(f.Name)
		if !ok {
			pv.Skipped++
			continue
		}
		pv.Files++
		pv.Bytes += int64(f.UncompressedSize64)
		switch compare(abs, int64(f.UncompressedSize64), f.Modified) {
		case vNew:
			pv.New++
		case vNewer:
			pv.Newer++
		case vOlder:
			pv.Older++
		default:
			pv.Same++
		}
	}
	return pv, nil
}

// Discard forgets a received backup.
func (s *Service) Discard(id string) {
	if p, err := s.importPath(id); err == nil {
		os.Remove(p)
	}
}

func (s *Service) cleanImports(age time.Duration) {
	ents, _ := os.ReadDir(filepath.Join(s.Roots.Data, "imports"))
	for _, e := range ents {
		if fi, err := e.Info(); err == nil && time.Since(fi.ModTime()) > age {
			os.Remove(filepath.Join(s.Roots.Data, "imports", e.Name()))
		}
	}
}

// Restore applies a received backup. In "merge" mode files newer on this
// device stay; "overwrite" takes every file from the backup and copies the
// newer local ones (library and assistant data) to the conflict folder.
func (s *Service) Restore(ctx context.Context, id, mode string) (RestoreResult, error) {
	var res RestoreResult
	if mode != "merge" && mode != "overwrite" {
		return res, errors.New("未知的恢复方式")
	}
	if !s.runMu.TryLock() {
		return res, ErrBusy
	}
	defer s.runMu.Unlock()
	p, err := s.importPath(id)
	if err != nil {
		return res, err
	}
	zr, _, err := openBackup(p)
	if err != nil {
		return res, err
	}
	defer zr.Close()
	conflicts := filepath.Join(s.Roots.Library, ConflictDir, time.Now().Format("2006-01-02_150405")+"-restore")
	for _, f := range zr.File {
		if err := ctx.Err(); err != nil {
			return res, err
		}
		if f.Name == stateName {
			if s.MergeState != nil {
				if b, err := readZip(f, 64<<20); err == nil {
					if changed, err := s.MergeState(ctx, b); err == nil && changed {
						res.Library = true
					}
				}
			}
			continue
		}
		abs, ok := s.Roots.Abs(f.Name)
		if !ok || f.Name == manifestName {
			continue
		}
		size := int64(f.UncompressedSize64)
		v := compare(abs, size, f.Modified)
		if v == vSame || (v == vOlder && mode == "merge") {
			res.Kept++
			continue
		}
		if v == vOlder {
			if err := copyAside(abs, keptPath(conflicts, f.Name)); err != nil {
				return res, err
			}
			res.Conflict = conflicts
		}
		err := writeFile(abs, f.Modified, func(dst *os.File) error {
			rc, err := f.Open()
			if err != nil {
				return err
			}
			defer rc.Close()
			n, err := io.Copy(dst, io.LimitReader(rc, size+1))
			if err == nil && n != size {
				err = fmt.Errorf("%s: 备份中的文件已损坏", f.Name)
			}
			return err
		})
		if err != nil {
			return res, err
		}
		res.Written++
		res.Bytes += size
		if strings.HasPrefix(f.Name, "library/") {
			res.Library = true
		} else {
			res.Data = true
		}
	}
	zr.Close()
	os.Remove(p)
	s.changed(ctx, res.Library, res.Data)
	return res, nil
}

func readZip(f *zip.File, limit int64) ([]byte, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	return io.ReadAll(io.LimitReader(rc, limit))
}

// copyAside keeps a copy of a file that is about to be replaced.
func copyAside(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return nil
	}
	defer in.Close()
	fi, _ := in.Stat()
	return writeFile(dst, fi.ModTime(), func(f *os.File) error {
		_, err := io.Copy(f, in)
		return err
	})
}

type ctxReader struct {
	ctx context.Context
	r   io.Reader
}

func (c *ctxReader) Read(p []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.r.Read(p)
}
