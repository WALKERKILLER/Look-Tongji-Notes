package datasync

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// The remote folder holds manifest.json (every file's size, time, hash, or
// a tombstone), files/<archive path> and state/library.json. Each device
// remembers in sync.json what it last agreed with the remote (the base), so
// a file that differs on one side only changed there; one that differs on
// both sides is a conflict, settled by the newer edit.

const (
	syncFormat   = "look-studio-sync"
	tombstoneTTL = 90 * 24 * time.Hour
	workers      = 4
)

type remoteManifest struct {
	Format  string           `json:"format"`
	Version int              `json:"version"`
	Updated int64            `json:"updated"`
	Device  string           `json:"device"`
	State   *Entry           `json:"state,omitempty"`
	Files   map[string]Entry `json:"files"`
}

type hashRec struct {
	Size  int64  `json:"size"`
	MTime int64  `json:"mtime_ns"`
	Hash  string `json:"sha256"`
}

func (s *Service) cachePath() string { return filepath.Join(s.Roots.Data, "sync-cache.json") }

func hashFile(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// localFiles lists this device's files with their hashes, reusing hashes of
// files whose size and time did not change.
func (s *Service) localFiles(ctx context.Context, media bool) (map[string]File, map[string]string, error) {
	cache := map[string]hashRec{}
	if b, err := os.ReadFile(s.cachePath()); err == nil {
		json.Unmarshal(b, &cache)
	}
	files := map[string]File{}
	hashes := map[string]string{}
	next := map[string]hashRec{}
	all := append(s.Roots.ScanLibrary(media), s.Roots.ScanData()...)
	for i, f := range all {
		if err := ctx.Err(); err != nil {
			return nil, nil, err
		}
		rec, ok := cache[f.Path]
		if !ok || rec.Size != f.Size || rec.MTime != f.ModTime.UnixNano() {
			if i%50 == 0 {
				s.setProgress(&Progress{Step: "检查本地文件", Done: i, Total: len(all)})
			}
			h, err := hashFile(f.Abs)
			if err != nil {
				continue
			}
			rec = hashRec{Size: f.Size, MTime: f.ModTime.UnixNano(), Hash: h}
		}
		files[f.Path], hashes[f.Path], next[f.Path] = f, rec.Hash, rec
	}
	if b, err := json.Marshal(next); err == nil {
		writeFile(s.cachePath(), time.Time{}, func(f *os.File) error { _, err := f.Write(b); return err })
	}
	return files, hashes, nil
}

type opKind int

const (
	opUpload opKind = iota
	opDownload
	opDeleteRemote // tombstone
	opDeleteLocal  // move to trash
	opConflict
)

type op struct {
	kind   opKind
	path   string
	remote Entry
}

// Sync runs one sync with the WebDAV folder.
func (s *Service) Sync(ctx context.Context) (Result, error) {
	if !s.runMu.TryLock() {
		return Result{}, ErrBusy
	}
	defer s.runMu.Unlock()
	s.mu.Lock()
	s.loadLocked()
	if s.cfg.URL == "" {
		s.mu.Unlock()
		return Result{}, ErrNotConfigured
	}
	s.running = true
	s.mu.Unlock()
	s.publish("sync_progress", Progress{Step: "连接 WebDAV"})
	var res Result
	var err error
	for try := 0; try < 3; try++ {
		res, err = s.syncOnce(ctx)
		if !errors.Is(err, ErrChanged) {
			break
		}
	}
	if errors.Is(err, ErrChanged) {
		err = errors.New("另一台设备正在同步，请稍后再试")
	}
	res.At = time.Now().UnixMilli()
	if err != nil {
		res.Error = err.Error()
	}
	s.mu.Lock()
	s.running, s.progress = false, nil
	s.cfg.Last = &res
	s.saveLocked()
	s.mu.Unlock()
	s.publish("sync_done", res)
	return res, err
}

func (s *Service) syncOnce(ctx context.Context) (Result, error) {
	var res Result
	s.mu.Lock()
	cfg := s.cfg
	base := make(map[string]Entry, len(cfg.Base))
	for k, v := range cfg.Base {
		base[k] = v
	}
	c, err := s.client(cfg.URL, cfg.Folder, cfg.User, s.pass)
	s.mu.Unlock()
	if err != nil {
		return res, err
	}

	s.setProgress(&Progress{Step: "读取云端清单"})
	remote, etag, err := s.readManifest(ctx, c)
	if err != nil {
		return res, err
	}
	local, hashes, err := s.localFiles(ctx, cfg.Media)
	if err != nil {
		return res, err
	}
	inScope := func(p string) bool {
		_, ok := s.Roots.Abs(p)
		return ok && (cfg.Media || !IsMedia(p))
	}

	// The index's personal state merges record by record.
	stateHash, remoteDirty, libChanged, err := s.syncState(ctx, c, &remote, cfg.StateHash)
	if err != nil {
		return res, err
	}
	remoteDirty = remoteDirty || remote.Format == ""

	paths := map[string]bool{}
	for _, m := range []map[string]Entry{remote.Files, base} {
		for p := range m {
			paths[p] = true
		}
	}
	for p := range local {
		paths[p] = true
	}
	newBase := map[string]Entry{}
	var ops []op
	for p := range paths {
		if !inScope(p) {
			if e, ok := base[p]; ok {
				newBase[p] = e
			}
			continue
		}
		lh := hashes[p]
		r := remote.Files[p]
		rh := ""
		if r.Deleted == 0 {
			rh = r.Hash
		}
		bh := base[p].Hash
		switch {
		case lh == rh:
			if lh != "" {
				newBase[p] = r
			}
			continue
		case lh == bh && rh != "":
			ops = append(ops, op{opDownload, p, r})
		case lh == bh:
			ops = append(ops, op{opDeleteLocal, p, r})
		case rh == bh && lh != "":
			ops = append(ops, op{opUpload, p, r})
		case rh == bh:
			ops = append(ops, op{opDeleteRemote, p, r})
		case lh == "": // deleted here, edited there: the edit wins
			ops = append(ops, op{opDownload, p, r})
		case rh == "": // edited here, deleted there
			ops = append(ops, op{opUpload, p, r})
		default:
			ops = append(ops, op{opConflict, p, r})
		}
		if e, ok := base[p]; ok {
			newBase[p] = e // until the change goes through
		}
	}
	sort.Slice(ops, func(i, j int) bool { return ops[i].path < ops[j].path })

	stamp := time.Now().Format("2006-01-02_150405")
	conflictRoot := filepath.Join(s.Roots.Library, ConflictDir, stamp)
	trashRoot := filepath.Join(s.Roots.Library, TrashDir, stamp)

	var mu sync.Mutex
	next := make(map[string]Entry, len(remote.Files)) // the manifest to write
	for p, e := range remote.Files {
		next[p] = e
	}
	pushed := map[string]Entry{} // reach the base once the manifest is written
	var fatal error
	dataChanged := false
	prog := Progress{Step: "同步文件", Total: len(ops)}
	s.setProgress(&prog)

	work := make(chan op)
	var wg sync.WaitGroup
	for range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for o := range work {
				mu.Lock()
				stop := fatal != nil
				mu.Unlock()
				if stop {
					continue
				}
				out := s.apply(ctx, c, o, local[o.path], conflictRoot, trashRoot)
				mu.Lock()
				prog.Done++
				switch {
				case out.err != nil:
					var he *HTTPError
					if errors.As(out.err, &he) && he.Fatal() || ctx.Err() != nil {
						if fatal == nil {
							fatal = out.err
						}
					} else if len(res.Errors) < 20 {
						res.Errors = append(res.Errors, fmt.Sprintf("%s：%v", o.path, out.err))
					}
				case out.kind == opUpload || out.kind == opDeleteRemote:
					next[o.path], pushed[o.path] = out.entry, out.entry
					remoteDirty = true
				default: // the remote already has this version
					if out.entry.Hash != "" {
						newBase[o.path] = out.entry
					} else {
						delete(newBase, o.path)
					}
					if strings.HasPrefix(o.path, "library/") {
						libChanged = true
					} else {
						dataChanged = true
					}
				}
				if out.err == nil {
					switch out.kind {
					case opUpload:
						res.Uploaded++
					case opDownload:
						res.Downloaded++
					default:
						res.Deleted++
					}
					if out.conflict {
						res.Conflicts++
						if out.aside {
							res.ConflictDir = conflictRoot
						}
					}
					res.Bytes += out.bytes
					prog.Bytes = res.Bytes
				}
				if prog.Done%10 == 0 || prog.Done == prog.Total {
					p := prog
					s.setProgress(&p)
				}
				mu.Unlock()
			}
		}()
	}
	for _, o := range ops {
		work <- o
	}
	close(work)
	wg.Wait()

	var commitErr error
	if remoteDirty {
		s.setProgress(&Progress{Step: "更新云端清单", Done: prog.Done, Total: prog.Total, Bytes: prog.Bytes})
		now := time.Now()
		for p, e := range next {
			if e.Deleted != 0 && now.Sub(time.UnixMilli(e.Deleted)) > tombstoneTTL {
				delete(next, p)
			}
		}
		m := remoteManifest{Format: syncFormat, Version: 1, Updated: now.UnixMilli(), Device: s.deviceName(),
			State: remote.State, Files: next}
		b, _ := json.Marshal(m)
		_, commitErr = c.Put(ctx, "manifest.json", func() (io.ReadCloser, int64, error) {
			return io.NopCloser(bytes.NewReader(b)), int64(len(b)), nil
		}, etag)
		if commitErr == nil {
			for p, e := range pushed {
				if e.Deleted != 0 {
					delete(newBase, p)
				} else {
					newBase[p] = e
				}
			}
		}
	}
	s.mu.Lock()
	if s.cfg.URL == cfg.URL && s.cfg.Folder == cfg.Folder {
		s.cfg.Base, s.cfg.StateHash = newBase, stateHash
		s.saveLocked()
	}
	s.mu.Unlock()
	s.changed(ctx, libChanged, dataChanged)
	if commitErr != nil {
		return res, commitErr
	}
	if fatal != nil {
		res.Partial = true
		return res, fatal
	}
	return res, nil
}

func (s *Service) readManifest(ctx context.Context, c *Client) (remoteManifest, string, error) {
	var m remoteManifest
	rc, etag, err := c.Get(ctx, "manifest.json")
	if errors.Is(err, ErrNotFound) {
		return remoteManifest{Files: map[string]Entry{}}, "", nil
	}
	if err != nil {
		return m, "", err
	}
	defer rc.Close()
	if err := json.NewDecoder(io.LimitReader(rc, 256<<20)).Decode(&m); err != nil || m.Format != syncFormat {
		return m, "", errors.New("云端同步目录里的 manifest.json 不是 Look Studio 写入的，请换一个目录")
	}
	if m.Version > 1 {
		return m, "", errors.New("云端数据来自更新版本的 Look Studio，请先升级")
	}
	if m.Files == nil {
		m.Files = map[string]Entry{}
	}
	return m, etag, nil
}

// syncState merges the remote personal state into the index and uploads
// the merged state when it differs from the remote one.
func (s *Service) syncState(ctx context.Context, c *Client, remote *remoteManifest, last string) (string, bool, bool, error) {
	if s.State == nil || s.MergeState == nil {
		return last, false, false, nil
	}
	merged := false
	if remote.State != nil && remote.State.Hash != last {
		rc, _, err := c.Get(ctx, stateName)
		if err == nil {
			b, rerr := io.ReadAll(io.LimitReader(rc, 64<<20))
			rc.Close()
			if rerr == nil {
				if merged, err = s.MergeState(ctx, b); err != nil {
					return last, false, false, err
				}
			}
		} else if !errors.Is(err, ErrNotFound) {
			return last, false, false, err
		}
	}
	b, err := s.State(ctx)
	if err != nil {
		return last, false, merged, err
	}
	sum := sha256.Sum256(b)
	h := hex.EncodeToString(sum[:])
	if remote.State != nil && remote.State.Hash == h {
		return h, false, merged, nil
	}
	if _, err := c.Put(ctx, stateName, func() (io.ReadCloser, int64, error) {
		return io.NopCloser(bytes.NewReader(b)), int64(len(b)), nil
	}, ""); err != nil {
		return last, false, merged, err
	}
	remote.State = &Entry{Size: int64(len(b)), MTime: time.Now().UnixMilli(), Hash: h}
	return h, true, merged, nil
}

type outcome struct {
	kind     opKind // what happened: opUpload, opDownload, opDeleteRemote or opDeleteLocal
	entry    Entry
	bytes    int64
	conflict bool
	aside    bool // the losing copy went to the conflict folder
	err      error
}

func remotePath(p string) string { return "files/" + p }

func (s *Service) apply(ctx context.Context, c *Client, o op, lf File, conflictRoot, trashRoot string) outcome {
	abs, _ := s.Roots.Abs(o.path)
	switch o.kind {
	case opUpload:
		e, n, err := s.upload(ctx, c, o.path, abs)
		return outcome{kind: opUpload, entry: e, bytes: n, err: err}
	case opDownload:
		n, err := s.download(ctx, c, o.path, abs, o.remote)
		return outcome{kind: opDownload, entry: o.remote, bytes: n, err: err}
	case opDeleteRemote:
		now := time.Now().UnixMilli()
		return outcome{kind: opDeleteRemote, entry: Entry{MTime: now, Deleted: now}, err: c.Delete(ctx, remotePath(o.path))}
	case opDeleteLocal:
		err := moveAside(abs, keptPath(trashRoot, o.path))
		if errors.Is(err, os.ErrNotExist) {
			err = nil
		}
		return outcome{kind: opDeleteLocal, err: err}
	}
	// Changed on both sides.
	if strings.HasPrefix(o.path, "data/") && strings.HasSuffix(o.path, ".jsonl") {
		return s.mergeLines(ctx, c, o.path, abs)
	}
	// Generated files (lecture.json and the like) only take the newer copy.
	keep := !derived(o.path)
	aside := keptPath(conflictRoot, o.path)
	if o.remote.MTime > lf.ModTime.UnixMilli() {
		if keep {
			if err := copyAside(abs, aside); err != nil {
				return outcome{err: err}
			}
		}
		n, err := s.download(ctx, c, o.path, abs, o.remote)
		return outcome{kind: opDownload, entry: o.remote, bytes: n, conflict: true, aside: keep, err: err}
	}
	keep = keep && o.remote.Size < 64<<20
	if keep {
		// Keep the remote version before replacing it.
		if _, err := s.download(ctx, c, o.path, aside, o.remote); err != nil {
			return outcome{err: err}
		}
	}
	e, n, err := s.upload(ctx, c, o.path, abs)
	return outcome{kind: opUpload, entry: e, bytes: n, conflict: true, aside: keep, err: err}
}

func (s *Service) upload(ctx context.Context, c *Client, p, abs string) (Entry, int64, error) {
	var e Entry
	h := sha256.New()
	_, err := c.Put(ctx, remotePath(p), func() (io.ReadCloser, int64, error) {
		f, err := os.Open(abs)
		if err != nil {
			return nil, 0, err
		}
		fi, err := f.Stat()
		if err != nil {
			f.Close()
			return nil, 0, err
		}
		h.Reset()
		e = Entry{Size: fi.Size(), MTime: fi.ModTime().UnixMilli()}
		return struct {
			io.Reader
			io.Closer
		}{io.TeeReader(io.LimitReader(f, fi.Size()), h), f}, fi.Size(), nil
	}, "")
	if err != nil {
		return Entry{}, 0, err
	}
	e.Hash = hex.EncodeToString(h.Sum(nil))
	return e, e.Size, nil
}

func (s *Service) download(ctx context.Context, c *Client, p, abs string, want Entry) (int64, error) {
	rc, _, err := c.Get(ctx, remotePath(p))
	if errors.Is(err, ErrNotFound) {
		return 0, errors.New("云端缺少这个文件")
	}
	if err != nil {
		return 0, err
	}
	defer rc.Close()
	var n int64
	err = writeFile(abs, time.UnixMilli(want.MTime), func(f *os.File) error {
		h := sha256.New()
		var err error
		n, err = io.Copy(io.MultiWriter(f, h), rc)
		if err == nil && (n != want.Size || hex.EncodeToString(h.Sum(nil)) != want.Hash) {
			err = errors.New("下载的内容与云端清单不符")
		}
		return err
	})
	return n, err
}

// mergeLines settles an append-only log changed on both devices by keeping
// the lines of both.
func (s *Service) mergeLines(ctx context.Context, c *Client, p, abs string) outcome {
	rc, _, err := c.Get(ctx, remotePath(p))
	if err != nil {
		return outcome{err: err}
	}
	theirs, err := io.ReadAll(io.LimitReader(rc, 64<<20))
	rc.Close()
	if err != nil {
		return outcome{err: err}
	}
	mine, err := os.ReadFile(abs)
	if err != nil {
		return outcome{err: err}
	}
	seen := map[string]bool{}
	var out bytes.Buffer
	for _, src := range [][]byte{mine, theirs} {
		sc := bufio.NewScanner(bytes.NewReader(src))
		sc.Buffer(make([]byte, 0, 64<<10), 16<<20)
		for sc.Scan() {
			ln := sc.Text()
			if strings.TrimSpace(ln) == "" || seen[ln] {
				continue
			}
			seen[ln] = true
			out.WriteString(ln)
			out.WriteByte('\n')
		}
	}
	if err := writeFile(abs, time.Time{}, func(f *os.File) error { _, err := f.Write(out.Bytes()); return err }); err != nil {
		return outcome{err: err}
	}
	e, n, err := s.upload(ctx, c, p, abs)
	return outcome{kind: opUpload, entry: e, bytes: n, conflict: true, err: err}
}

// moveAside moves a file into the trash or conflict folder.
func moveAside(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	if err := os.Rename(src, dst); err == nil || errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := copyAside(src, dst); err != nil {
		return err
	}
	return os.Remove(src)
}

// keptPath is where a replaced or deleted copy of p goes under root (a
// conflict or trash folder): library files keep their library path, the
// assistant's data goes under data/.
func keptPath(root, p string) string {
	return filepath.Join(root, filepath.FromSlash(strings.TrimPrefix(p, "library/")))
}

// derived files are rewritten from the index; their old copies are noise.
func derived(p string) bool {
	switch path.Base(p) {
	case "lecture.json", "course.json":
		return true
	}
	return p == "library/README.md" || strings.HasSuffix(p, "/slides/index.json")
}
