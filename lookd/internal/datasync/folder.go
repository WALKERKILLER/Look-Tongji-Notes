package datasync

// Folder transport contract: docs/specs/0023-course-folder-sync.md.
// Each device owns its manifest; objects are immutable. Syncthing may deliver
// them in either order, so an incomplete generation is never materialized.
import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const folderFormat = "look-studio-folder"
const folderVersion = 2

type folderMarker struct {
	Format  string `json:"format"`
	Version int    `json:"version"`
	ID      string `json:"id"`
}
type folderEntry struct {
	Entry
	Clock        map[string]uint64 `json:"clock"`
	Alternatives []Entry           `json:"alternatives,omitempty"`
}
type folderManifest struct {
	Format  string                 `json:"format"`
	Version int                    `json:"version"`
	Library string                 `json:"library"`
	Device  string                 `json:"device"`
	Courses map[string]string      `json:"courses"`
	Files   map[string]folderEntry `json:"files"`
	State   json.RawMessage        `json:"state,omitempty"`
}
type folderBase struct {
	Library string                 `json:"library"`
	Files   map[string]folderEntry `json:"files"`
}
type folderStorage struct {
	root   *os.Root
	remote string
	token  string
	hc     *http.Client
}

func validFolderPath(p string) bool {
	return p != "" && path.Clean(p) == p && !strings.HasPrefix(p, "/") && !strings.Contains(p, "\\") && p != ".." && !strings.HasPrefix(p, "../")
}
func (f *folderStorage) get(ctx context.Context, p string) ([]byte, error) {
	r, e := f.open(ctx, p)
	if e != nil {
		return nil, e
	}
	defer r.Close()
	return io.ReadAll(io.LimitReader(r, 32<<20))
}
func (f *folderStorage) open(ctx context.Context, p string) (io.ReadCloser, error) {
	if !validFolderPath(p) {
		return nil, errors.New("同步路径无效")
	}
	if f.root != nil {
		return f.root.Open(filepath.FromSlash(p))
	}
	req, e := http.NewRequestWithContext(ctx, "GET", f.remote+"/file?path="+url.QueryEscape(p), nil)
	if e != nil {
		return nil, e
	}
	req.Header.Set("Authorization", "Bearer "+f.token)
	resp, e := f.hc.Do(req)
	if e != nil {
		return nil, e
	}
	if resp.StatusCode != 200 {
		resp.Body.Close()
		if resp.StatusCode == 404 {
			return nil, os.ErrNotExist
		}
		return nil, fmt.Errorf("文件夹授权不可用（HTTP %d），请重新选择文件夹", resp.StatusCode)
	}
	return resp.Body, nil
}
func (f *folderStorage) put(ctx context.Context, p string, r io.Reader) error {
	if !validFolderPath(p) {
		return errors.New("同步路径无效")
	}
	if f.root != nil {
		if e := f.root.MkdirAll(filepath.FromSlash(path.Dir(p)), 0700); e != nil {
			return e
		}
		nonce := make([]byte, 8)
		rand.Read(nonce)
		tmp := p + "." + hex.EncodeToString(nonce) + ".tmp"
		file, e := f.root.OpenFile(filepath.FromSlash(tmp), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if e != nil {
			return e
		}
		defer f.root.Remove(filepath.FromSlash(tmp))
		_, e = io.Copy(file, r)
		if e == nil {
			e = file.Sync()
		}
		ce := file.Close()
		if e == nil {
			e = ce
		}
		if e != nil {
			return e
		}
		// Windows Rename cannot replace an existing target. Only a device's own
		// manifest is mutable; incomplete/missing manifests are retried by readers.
		if e = f.root.Rename(filepath.FromSlash(tmp), filepath.FromSlash(p)); e != nil {
			if _, se := f.root.Stat(filepath.FromSlash(p)); se == nil {
				if re := f.root.Remove(filepath.FromSlash(p)); re != nil {
					return re
				}
				e = f.root.Rename(filepath.FromSlash(tmp), filepath.FromSlash(p))
			}
		}
		return e
	}
	req, e := http.NewRequestWithContext(ctx, "PUT", f.remote+"/file?path="+url.QueryEscape(p), r)
	if e != nil {
		return e
	}
	if file, ok := r.(*os.File); ok {
		if st, err := file.Stat(); err == nil {
			off, _ := file.Seek(0, io.SeekCurrent)
			req.ContentLength = st.Size() - off
		}
	}
	req.Header.Set("Authorization", "Bearer "+f.token)
	resp, e := f.hc.Do(req)
	if e != nil {
		return e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("文件夹写入失败（HTTP %d），请检查授权", resp.StatusCode)
	}
	return nil
}
func (f *folderStorage) devices(ctx context.Context) ([]string, error) {
	if f.root != nil {
		d, e := f.root.Open("devices")
		if os.IsNotExist(e) {
			return nil, nil
		}
		if e != nil {
			return nil, e
		}
		defer d.Close()
		names, e := d.Readdirnames(-1)
		return names, e
	}
	req, e := http.NewRequestWithContext(ctx, "GET", f.remote+"/list?path=devices", nil)
	if e != nil {
		return nil, e
	}
	req.Header.Set("Authorization", "Bearer "+f.token)
	resp, e := f.hc.Do(req)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, errors.New("无法读取授权文件夹，请重新授权")
	}
	var names []string
	e = json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&names)
	return names, e
}
func (s *Service) folderStorage(c config) (*folderStorage, error) {
	f := &folderStorage{hc: &http.Client{Timeout: 10 * time.Minute}}
	if c.BridgeURL != "" {
		u, e := url.Parse(c.BridgeURL)
		if e != nil || u.Scheme != "http" || u.Hostname() != "127.0.0.1" || u.Path != "" {
			return nil, errors.New("安卓目录桥接地址无效")
		}
		if s.Unseal == nil {
			return nil, errors.New("缺少本机凭证解密器")
		}
		token, e := s.Unseal(c.BridgeToken)
		if e != nil {
			return nil, e
		}
		f.remote = strings.TrimRight(c.BridgeURL, "/")
		f.token = token
		return f, nil
	}
	abs, e := filepath.Abs(c.LocalFolder)
	if e != nil {
		return nil, e
	}
	real, e := filepath.EvalSymlinks(abs)
	st, statErr := os.Lstat(abs)
	if e != nil || statErr != nil || !st.IsDir() || st.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("请选择本机普通目录，不支持符号链接")
	}
	for _, root := range []string{s.Roots.Library, s.Roots.Data} {
		r, err := filepath.EvalSymlinks(root)
		if err != nil {
			return nil, fmt.Errorf("工作目录不可用 %s：%w", root, err)
		}
		if real == r || strings.HasPrefix(real, r+string(os.PathSeparator)) || strings.HasPrefix(r, real+string(os.PathSeparator)) {
			return nil, errors.New("同步目录必须与工作库和私有配置目录分开")
		}
	}
	f.root, e = os.OpenRoot(real)
	return f, e
}
func (f *folderStorage) close() {
	if f.root != nil {
		f.root.Close()
	}
}
func (s *Service) configureFolder(ctx context.Context, in Settings) (Status, error) {
	if !s.runMu.TryLock() {
		return Status{}, ErrBusy
	}
	defer s.runMu.Unlock()
	if strings.TrimSpace(in.LocalFolder) == "" || len(in.CourseIDs) == 0 {
		return Status{}, errors.New("请选择同步文件夹和至少一门课程")
	}
	for _, id := range in.CourseIDs {
		if id == "" || strings.ContainsAny(id, "/\\\x00") {
			return Status{}, errors.New("课程标识无效")
		}
	}
	c := config{Kind: "folder", LocalFolder: in.LocalFolder, CourseIDs: in.CourseIDs, BridgeURL: in.BridgeURL, Auto: in.Auto, Media: in.Media}
	s.mu.Lock()
	s.loadLocked()
	c.DeviceID = s.cfg.DeviceID
	s.mu.Unlock()
	if in.BridgeURL != "" {
		if s.Seal == nil {
			return Status{}, errors.New("无法保存目录桥接凭证")
		}
		var e error
		c.BridgeToken, e = s.Seal(in.BridgeToken)
		if e != nil {
			return Status{}, e
		}
	}
	f, e := s.folderStorage(c)
	if e != nil {
		return Status{}, e
	}
	defer f.close()
	b, e := f.get(ctx, "library.json")
	if os.IsNotExist(e) {
		id := make([]byte, 16)
		rand.Read(id)
		b, _ = json.Marshal(folderMarker{folderFormat, folderVersion, hex.EncodeToString(id)})
		e = f.put(ctx, "library.json", bytes.NewReader(b))
	}
	if e != nil {
		return Status{}, e
	}
	if _, e = decodeMarker(b); e != nil {
		return Status{}, e
	}
	empty := sha256.Sum256(nil)
	if err := f.put(ctx, "objects/"+hex.EncodeToString(empty[:]), bytes.NewReader(nil)); err != nil {
		return Status{}, err
	}
	s.mu.Lock()
	s.cfg = c
	s.pass = ""
	s.saveLocked()
	s.mu.Unlock()
	s.publish("sync_changed", map[string]string{"what": "folder"})
	return s.Status(), nil
}
func decodeMarker(b []byte) (folderMarker, error) {
	var m folderMarker
	if json.Unmarshal(b, &m) != nil || m.Format != folderFormat || m.Version != folderVersion || len(m.ID) != 32 {
		return m, errors.New("同步资料库格式不兼容，请升级应用或选择新的专用目录")
	}
	if _, err := hex.DecodeString(m.ID); err != nil {
		return m, errors.New("同步资料库标识无效")
	}
	return m, nil
}
func dominates(a, b map[string]uint64) bool {
	for k, n := range b {
		if a[k] < n {
			return false
		}
	}
	return true
}
func joinClock(a, b map[string]uint64) map[string]uint64 {
	out := map[string]uint64{}
	for k, n := range a {
		out[k] = n
	}
	for k, n := range b {
		if n > out[k] {
			out[k] = n
		}
	}
	return out
}
func sameEntry(a, b Entry) bool { return a.Hash == b.Hash && (a.Deleted == 0) == (b.Deleted == 0) }
func combine(a, b folderEntry) folderEntry {
	if a.Clock == nil {
		return b
	}
	if b.Clock == nil {
		return a
	}
	if dominates(a.Clock, b.Clock) {
		return a
	}
	if dominates(b.Clock, a.Clock) {
		return b
	}
	winner, loser := a, b
	if (a.Deleted != 0 && b.Deleted == 0) || (a.Deleted == b.Deleted && (b.MTime > a.MTime || b.MTime == a.MTime && b.Hash > a.Hash)) {
		winner, loser = b, a
	}
	winner.Clock = joinClock(a.Clock, b.Clock)
	all := append(append(append([]Entry{}, a.Alternatives...), b.Alternatives...), loser.Entry)
	winner.Alternatives = nil
	seen := map[string]bool{winner.Hash: true}
	for _, v := range all {
		if v.Hash != "" && !seen[v.Hash] {
			seen[v.Hash] = true
			winner.Alternatives = append(winner.Alternatives, v)
		}
	}
	sort.Slice(winner.Alternatives, func(i, j int) bool { return winner.Alternatives[i].Hash < winner.Alternatives[j].Hash })
	return winner
}
func folderScoped(p string, dirs map[string]string) bool {
	if strings.HasPrefix(p, "course-data/") {
		parts := strings.Split(p, "/")
		if len(parts) < 3 {
			return false
		}
		_, ok := dirs[parts[1]]
		return ok && validFolderPath(p)
	}
	if !strings.HasPrefix(p, "library/") {
		return false
	}
	rel := strings.TrimPrefix(p, "library/")
	if !libraryFile(rel, true) {
		return false
	}
	for _, dir := range dirs {
		if rel == dir || strings.HasPrefix(rel, dir+"/") {
			return true
		}
	}
	return false
}
func (s *Service) folderDirs(ids []string) (map[string]string, error) {
	wanted := map[string]bool{}
	for _, id := range ids {
		wanted[id] = true
	}
	dirs := map[string]string{}
	roots, e := os.ReadDir(filepath.Join(s.Roots.Library, "courses"))
	if os.IsNotExist(e) {
		return dirs, nil
	}
	if e != nil {
		return nil, e
	}
	for _, d := range roots {
		if !d.IsDir() {
			continue
		}
		p := filepath.Join(s.Roots.Library, "courses", d.Name(), "course.json")
		var c struct {
			ID string `json:"id"`
		}
		b, e := os.ReadFile(p)
		if e == nil && json.Unmarshal(b, &c) == nil && wanted[c.ID] {
			dirs[c.ID] = "courses/" + d.Name()
		}
	}
	return dirs, nil
}
func (s *Service) syncFolder(ctx context.Context) (Result, error) {
	var result Result
	s.mu.Lock()
	c := s.cfg
	s.mu.Unlock()
	f, e := s.folderStorage(c)
	if e != nil {
		return result, e
	}
	defer f.close()
	markerBytes, e := f.get(ctx, "library.json")
	if e != nil {
		return result, e
	}
	marker, e := decodeMarker(markerBytes)
	if e != nil {
		return result, e
	}
	dirs, e := s.folderDirs(c.CourseIDs)
	if e != nil {
		return result, e
	}
	wanted := map[string]bool{}
	for _, id := range c.CourseIDs {
		wanted[id] = true
	}
	manifests := []folderManifest{}
	names, e := f.devices(ctx)
	if e != nil {
		return result, e
	}
	sort.Strings(names)
	for _, name := range names {
		if !strings.HasSuffix(name, ".json") || strings.Contains(name, "sync-conflict") || !validFolderPath(name) {
			continue
		}
		b, e := f.get(ctx, "devices/"+name)
		if e != nil {
			return result, e
		}
		var m folderManifest
		if json.Unmarshal(b, &m) != nil || m.Format != folderFormat || m.Version != folderVersion || m.Library != marker.ID {
			return result, errors.New("设备清单格式不兼容或传输尚未完成，请稍后重试")
		}
		for id, dir := range m.Courses {
			if wanted[id] && validFolderPath(dir) && strings.HasPrefix(dir, "courses/") && len(strings.Split(dir, "/")) == 2 {
				if old := dirs[id]; old != "" && old != dir {
					return result, errors.New("同一课程使用了不同目录，请先处理课程冲突")
				}
				if e := s.validateFolderCourseDir(id, dir, dirs); e != nil {
					return result, e
				}
				dirs[id] = dir
			}
		}
		manifests = append(manifests, m)
	}
	basePath := filepath.Join(s.Roots.Data, "folder-base-"+marker.ID+".json")
	base := folderBase{Library: marker.ID, Files: map[string]folderEntry{}}
	if b, e := os.ReadFile(basePath); e == nil {
		if json.Unmarshal(b, &base) != nil || base.Library != marker.ID {
			return result, errors.New("本机同步记录损坏，请从备份恢复")
		}
	}
	combined := map[string]folderEntry{}
	for _, m := range manifests {
		for p, v := range m.Files {
			if folderScoped(p, dirs) && (c.Media || !IsMedia(p)) {
				combined[p] = combine(combined[p], v)
			}
		}
	}
	local, hashes, e := s.localFilesScoped(ctx, c.Media, func(f File) bool { return folderScoped(f.Path, dirs) })
	if e != nil {
		return result, e
	}
	for p := range local {
		if !folderScoped(p, dirs) {
			delete(local, p)
			delete(hashes, p)
		}
	}
	tracked := map[string]bool{}
	for _, entries := range []map[string]folderEntry{base.Files, combined} {
		for p, v := range entries {
			if folderScoped(p, dirs) && v.Deleted == 0 {
				tracked[p] = true
			}
		}
	}
	extras, err := s.folderExtras(ctx, c.CourseIDs, tracked)
	if err != nil {
		return result, err
	}
	for _, lf := range extras {
		h, err := hashFile(lf.Abs)
		if err != nil {
			return result, err
		}
		local[lf.Path] = lf
		hashes[lf.Path] = h
	}

	for p, old := range base.Files {
		if !folderScoped(p, dirs) || (!c.Media && IsMedia(p)) {
			continue
		}
		if _, ok := combined[p]; !ok {
			combined[p] = old
		}
	}
	paths := map[string]bool{}
	for p := range combined {
		paths[p] = true
	}
	for p := range local {
		paths[p] = true
	}
	for p := range base.Files {
		if folderScoped(p, dirs) && (c.Media || !IsMedia(p)) {
			paths[p] = true
		}
	}
	releasedSessions := map[string]bool{}
	for p := range base.Files {
		if strings.Contains(p, "/assistant/") && hashes[p] == "" {
			releasedSessions[p] = true
		}
	}
	for p := range paths {
		lf, present := local[p]
		old, known := base.Files[p]
		h := hashes[p]
		if !known && h != "" && h == combined[p].Hash {
			continue
		}
		changed := known && h != old.Hash || !known && present
		if !changed {
			continue
		}
		clock := joinClock(old.Clock, nil)
		clock[c.DeviceID]++
		v := folderEntry{Entry: Entry{Hash: h}, Clock: clock}
		if present {
			v.Size = lf.Size
			v.MTime = lf.ModTime.UnixMilli()
		} else {
			v.MTime = time.Now().UnixMilli()
			v.Deleted = v.MTime
		}
		if present {
			temp, e := os.CreateTemp(s.Roots.Data, "folder-publish-")
			if e != nil {
				return result, e
			}
			source, e := os.Open(lf.Abs)
			if e != nil {
				temp.Close()
				os.Remove(temp.Name())
				return result, e
			}
			digest := sha256.New()
			n, e := io.Copy(io.MultiWriter(temp, digest), io.LimitReader(source, lf.Size+1))
			source.Close()
			if e == nil && (n != lf.Size || hex.EncodeToString(digest.Sum(nil)) != h) {
				e = errors.New("本机文件正在修改，稍后重新同步")
			}
			if e == nil {
				_, e = temp.Seek(0, io.SeekStart)
			}
			if e == nil {
				e = f.put(ctx, "objects/"+h, temp)
			}
			temp.Close()
			os.Remove(temp.Name())
			if e != nil {
				return result, e
			}
			result.Uploaded++
			result.Bytes += lf.Size
		}

		combined[p] = combine(combined[p], v)
	}
	if err := validateFolderTransfer(combined, hashes); err != nil {
		return result, err
	}
	if err := s.mergeFolderRecords(ctx, f, combined); err != nil {
		return result, err
	}
	if err := validateFolderTransfer(combined, hashes); err != nil {
		return result, err
	}
	// Stage and verify every incoming file before changing any working files.
	stage, e := os.MkdirTemp(s.Roots.Data, "folder-stage-")
	if e != nil {
		return result, e
	}
	defer os.RemoveAll(stage)
	staged := map[string]string{}
	var stagedBytes int64
	stageObject := func(entry Entry) (string, error) {
		if len(entry.Hash) != 64 {
			return "", errors.New("文件哈希无效")
		}
		if _, e := hex.DecodeString(entry.Hash); e != nil {
			return "", e
		}
		if p, ok := staged[entry.Hash]; ok {
			return p, nil
		}
		if entry.Size < 0 || entry.Size > folderObjectLimit || entry.Size > folderStageLimit-stagedBytes {
			return "", errors.New("同步对象超出暂存大小限制，请缩小同步范围")
		}
		stagedBytes += entry.Size
		r, e := f.open(ctx, "objects/"+entry.Hash)
		if e != nil {
			return "", fmt.Errorf("文件尚未完整同步，请稍后重试：%w", e)
		}
		defer r.Close()
		p := filepath.Join(stage, entry.Hash)
		w, e := os.Create(p)
		if e != nil {
			return "", e
		}
		h := sha256.New()
		n, e := io.Copy(io.MultiWriter(w, h), io.LimitReader(r, entry.Size+1))
		w.Close()
		if e != nil || n != entry.Size || hex.EncodeToString(h.Sum(nil)) != entry.Hash {
			return "", errors.New("收到的文件校验不通过，保留本地版本并等待重传")
		}
		staged[entry.Hash] = p
		return p, nil
	}
	keys := []string{}
	for p, v := range combined {
		keys = append(keys, p)
		if v.Deleted == 0 && v.Hash != hashes[p] {
			if _, e = stageObject(v.Entry); e != nil {
				return result, e
			}
		}
		for _, a := range v.Alternatives {
			if _, e = stageObject(a); e != nil {
				return result, e
			}
		}
	}
	for p, v := range combined {
		if v.Deleted == 0 && staged[v.Hash] != "" {
			if err := validateFolderDocument(p, staged[v.Hash], dirs); err != nil {
				return result, err
			}
		}
	}
	sort.Strings(keys)
	changed := false
	dataChanged := false
	next := map[string]folderEntry{}

	apply := func() error {
		// Recheck ownership after staging and before the first working-file write.
		if err := s.validateFolderTargets(ctx, combined, staged, releasedSessions); err != nil {
			return err
		}
		for id, dir := range dirs {
			if err := s.validateFolderCourseDir(id, dir, dirs); err != nil {
				return err
			}
		}
		for _, p := range keys {
			v := combined[p]
			if v.Deleted != 0 && releasedSessions[p] {
				// Leaving a logical course scope must not delete a session
				// that is now owned by a different local course.
				next[p] = v
				continue
			}
			abs, ok := s.folderAbs(p)
			if !ok {
				return errors.New("同步文件超出资料库")
			}
			root := s.Roots.Library
			if strings.Contains(p, "/assistant/") || strings.HasSuffix(p, "/metadata.json") {
				root = s.Roots.Data
			}
			if err := safeWorkingPath(abs, root); err != nil {
				return err
			}
			for _, a := range v.Alternatives {
				backupDir := ConflictDir
				canvas := strings.HasPrefix(p, "library/courses/") && strings.HasSuffix(p, "/study-canvas.json")
				if canvas {
					backupDir = TrashDir
				}
				dest := filepath.Join(s.Roots.Library, backupDir, "folder-"+a.Hash[:12], filepath.FromSlash(p))
				if _, e := os.Stat(dest); os.IsNotExist(e) {
					if e = copyAside(staged[a.Hash], dest); e != nil {
						return e
					}
					if !canvas {
						result.Conflicts++
						result.ConflictDir = filepath.Join(s.Roots.Library, ConflictDir)
					}
				}
			}
			if v.Hash != hashes[p] || v.Deleted != 0 && hashes[p] != "" {
				// Check again: an editor may have saved while a large video was staging.
				current := ""
				if _, e := os.Stat(abs); e == nil {
					current, e = hashFile(abs)
					if e != nil {
						return e
					}
				}
				if current != hashes[p] {
					return errors.New("本机编辑尚未完成，已保留内容，稍后重试")
				}
				if current != "" {
					dest := filepath.Join(s.Roots.Library, TrashDir, "folder-"+current[:12], filepath.FromSlash(p))
					if e = copyAside(abs, dest); e != nil {
						return e
					}
				}
				if v.Deleted != 0 {
					if e = os.Remove(abs); e != nil && !os.IsNotExist(e) {
						return e
					}
					result.Deleted++
				} else {
					src := staged[v.Hash]
					if e = writeFile(abs, time.UnixMilli(v.MTime), func(w *os.File) error {
						r, e := os.Open(src)
						if e != nil {
							return e
						}
						defer r.Close()
						_, e = io.Copy(w, r)
						return e
					}); e != nil {
						return e
					}
					result.Downloaded++
					result.Bytes += v.Size
				}
				changed = true
				if strings.Contains(p, "/assistant/") || strings.HasSuffix(p, "/metadata.json") {
					dataChanged = true
				}
			}
			next[p] = v
		}
		return nil
	}
	if s.ApplyFiles != nil {
		e = s.ApplyFiles(apply)
	} else {
		e = apply()
	}
	if e != nil {
		return result, e
	}

	if changed {
		s.changed(ctx, true, dataChanged)
	}
	if s.MergeCourseState != nil {
		for _, m := range manifests {
			if len(m.State) > 0 {
				did, e := s.MergeCourseState(ctx, c.CourseIDs, m.State)
				if e != nil {
					return result, e
				}
				if did {
					s.changed(ctx, true, false)
				}
			}
		}
	}
	var state json.RawMessage
	if s.CourseState != nil {
		state, e = s.CourseState(ctx, c.CourseIDs)
		if e != nil {
			return result, e
		}
	}
	manifest := folderManifest{Format: folderFormat, Version: folderVersion, Library: marker.ID, Device: c.DeviceID, Courses: dirs, Files: next, State: state}
	out, _ := json.Marshal(manifest)
	own := "devices/" + c.DeviceID + ".json"
	previous, _ := f.get(ctx, own)
	if !bytes.Equal(out, previous) {
		if e = f.put(ctx, own, bytes.NewReader(out)); e != nil {
			return result, e
		}
	}
	base.Files = next
	b, _ := json.Marshal(base)
	if e = writeFile(basePath, time.Time{}, func(w *os.File) error { _, e := w.Write(b); return e }); e != nil {
		return result, e
	}
	s.mu.Lock()
	if s.cfg.Kind == "folder" && s.cfg.LocalFolder == c.LocalFolder {
		s.cfg.Base = map[string]Entry{}
		for p, v := range next {
			s.cfg.Base[p] = v.Entry
		}
	}
	s.mu.Unlock()
	return result, nil
}

// FolderPreview is read-only; configuration creates the versioned marker.
func (s *Service) FolderPreview(ctx context.Context, in Settings) (map[string]any, error) {
	dirs, err := s.folderDirs(in.CourseIDs)
	if err != nil {
		return nil, err
	}
	wanted := map[string]bool{}
	for _, id := range in.CourseIDs {
		wanted[id] = true
	}
	incoming := map[string]Entry{}
	all, err := s.folderDirsAvailable()
	if err != nil {
		return nil, err
	}
	if in.LocalFolder != "" {
		cfg := config{LocalFolder: in.LocalFolder, BridgeURL: in.BridgeURL}
		if in.BridgeURL != "" {
			if s.Seal == nil {
				return nil, errors.New("无法保护目录凭证")
			}
			cfg.BridgeToken, err = s.Seal(in.BridgeToken)
			if err != nil {
				return nil, err
			}
		}
		f, err := s.folderStorage(cfg)
		if err != nil {
			return nil, err
		}
		defer f.close()
		b, err := f.get(ctx, "library.json")
		if err != nil && !os.IsNotExist(err) {
			return nil, err
		}
		if err == nil {
			marker, err := decodeMarker(b)
			if err != nil {
				return nil, err
			}
			names, err := f.devices(ctx)
			if err != nil {
				return nil, err
			}
			for _, name := range names {
				if !strings.HasSuffix(name, ".json") || strings.Contains(name, "sync-conflict") {
					continue
				}
				raw, err := f.get(ctx, "devices/"+name)
				if err != nil {
					return nil, err
				}
				var m folderManifest
				if json.Unmarshal(raw, &m) != nil || m.Library != marker.ID || m.Version != folderVersion {
					return nil, errors.New("同步清单不兼容，请升级应用")
				}
				for id, dir := range m.Courses {
					if validFolderPath(dir) && strings.HasPrefix(dir, "courses/") {
						all[id] = strings.TrimPrefix(dir, "courses/")
						if wanted[id] {
							dirs[id] = dir
						}
					}
				}
				for path, v := range m.Files {
					if folderScoped(path, dirs) && v.Deleted == 0 && (in.Media || !IsMedia(path)) {
						incoming[path] = v.Entry
					}
				}
			}
		}
	}
	var n, size int64
	files, err := s.Roots.ScanLibrary(in.Media)
	if err != nil {
		return nil, err
	}
	for _, f := range files {
		if folderScoped(f.Path, dirs) {
			n++
			size += f.Size
		}
	}
	var incomingBytes int64
	for _, v := range incoming {
		incomingBytes += v.Size
	}
	return map[string]any{"incoming_files": len(incoming), "incoming_bytes": incomingBytes, "files": n, "bytes": size, "course_ids": in.CourseIDs, "courses": all, "media": in.Media, "format": folderFormat, "version": folderVersion}, nil
}
func (s *Service) folderDirsAvailable() (map[string]string, error) {
	all := map[string]string{}
	entries, err := os.ReadDir(filepath.Join(s.Roots.Library, "courses"))
	if os.IsNotExist(err) {
		return all, nil
	}
	if err != nil {
		return nil, err
	}
	for _, v := range entries {
		if !v.IsDir() {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(s.Roots.Library, "courses", v.Name(), "course.json"))
		var c struct {
			ID    string `json:"id"`
			Title string `json:"title"`
		}
		if err == nil && json.Unmarshal(raw, &c) == nil && c.ID != "" {
			all[c.ID] = c.Title
		}
	}
	return all, nil
}
