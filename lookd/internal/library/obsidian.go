package library

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
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"

	"lookstudio/lookd/internal/portable"
	"lookstudio/lookd/internal/store"
)

// The Obsidian export writes the library into a folder of an Obsidian vault
// as plain Markdown:
//
//	课程库.md                      the one index: courses, lectures, notes, schedule
//	<课程>/笔记/<节次>/<标题>.md   lecture notes, one folder per lecture (named by date)
//	<课程>/笔记/<节次>/附件/...    slides, courseware and figures those notes link to
//	<课程>/笔记/课程笔记/<标题>.md notes of the whole course
//	<课程>/转写稿/<节次>.md        lecture details and outline, then the transcript
//	未归类笔记/<标题>.md           only when there are notes outside any course
//
// It is one-way;
// files the user edited in the vault are never overwritten (the new version
// goes next to them as "<name> (Look Studio).md"). Attachments are copied,
// never hard-linked, so editing them in the vault cannot change the library.

// ObsidianFolder is the default export folder inside the vault.
const ObsidianFolder = "LookStudio"

// obsidianManifest records the content hash of every file the last export
// wrote, to tell our files from the user's edits.
const obsidianManifest = ".lookstudio-export.json"

type ObsidianResult struct {
	Root      string   `json:"root"`
	Written   int      `json:"written"`
	Unchanged int      `json:"unchanged"`
	Removed   int      `json:"removed"`
	Conflicts []string `json:"conflicts"` // export paths kept because they were edited in the vault
	Vault     bool     `json:"vault"`     // the target folder is an Obsidian vault (has .obsidian/)
}

// ObsidianRoot checks an export target and returns the export folder.
func (l *Library) ObsidianRoot(vault, folder string) (string, error) {
	if vault == "" || !filepath.IsAbs(vault) {
		return "", errors.New("请提供 Obsidian 仓库的绝对路径")
	}
	if fi, err := os.Stat(vault); err != nil || !fi.IsDir() {
		return "", fmt.Errorf("找不到仓库文件夹 %s", vault)
	}
	if folder == "" {
		folder = ObsidianFolder
	}
	folder = filepath.Clean(filepath.FromSlash(folder))
	if filepath.IsAbs(folder) || folder == "." || folder == ".." || strings.HasPrefix(folder, ".."+string(filepath.Separator)) {
		return "", errors.New("导出文件夹必须是仓库内的子文件夹")
	}
	// Compare real paths, so a symbolic link cannot point the export into
	// the library or out of the vault.
	realVault, err := filepath.EvalSymlinks(vault)
	if err != nil {
		return "", err
	}
	root := resolveExisting(filepath.Join(realVault, folder))
	lib := resolveExisting(l.Root)
	if !inside(root, realVault) || root == realVault {
		return "", errors.New("导出文件夹必须是仓库内的子文件夹")
	}
	if inside(root, lib) || inside(lib, root) {
		return "", errors.New("导出文件夹不能与课程库重叠")
	}
	return root, nil
}

// resolveExisting resolves symbolic links in the longest existing prefix of p.
func resolveExisting(p string) string {
	rest := ""
	for dir := filepath.Clean(p); ; dir = filepath.Dir(dir) {
		if real, err := filepath.EvalSymlinks(dir); err == nil {
			return filepath.Join(real, rest)
		}
		if filepath.Dir(dir) == dir {
			return filepath.Clean(p)
		}
		rest = filepath.Join(filepath.Base(dir), rest)
	}
}

// inside reports whether p is dir or below it.
func inside(p, dir string) bool {
	r, err := filepath.Rel(filepath.Clean(dir), filepath.Clean(p))
	return err == nil && r != ".." && !strings.HasPrefix(r, ".."+string(filepath.Separator))
}

// ExportObsidian writes or refreshes the export under vault/folder.
func (l *Library) ExportObsidian(ctx context.Context, vault, folder string) (ObsidianResult, error) {
	root, err := l.ObsidianRoot(vault, folder)
	if err != nil {
		return ObsidianResult{}, err
	}
	l.exportMu.Lock()
	defer l.exportMu.Unlock()
	dir, err := openExportRoot(vault, root)
	if err != nil {
		return ObsidianResult{}, err
	}
	defer dir.Close()
	src, err := os.OpenRoot(l.Root)
	if err != nil {
		return ObsidianResult{}, err
	}
	defer src.Close()
	_, vaultErr := os.Stat(filepath.Join(vault, ".obsidian"))
	e := &obsidianExport{
		ctx: ctx, lib: l, root: root, dir: dir, src: src,
		old:    readManifest(dir),
		files:  map[string]string{},
		copies: map[string]bool{},
		slides: map[string][]store.Slide{},
		res:    ObsidianResult{Root: root, Conflicts: []string{}, Vault: vaultErr == nil},
	}
	e.conv = &portable.Converter{Lib: e, Place: placeInExport, Use: func(rel string) { e.copies[rel] = true }}
	if err := e.run(); err != nil {
		return e.res, err
	}
	return e.res, nil
}

type obsidianExport struct {
	ctx    context.Context
	lib    *Library
	root   string
	dir    *os.Root // the export folder; every vault file operation goes through it
	src    *os.Root // the library; files notes link to are read through it
	conv   *portable.Converter
	old    map[string]string // manifest of the previous export
	files  map[string]string // manifest of this export
	copies map[string]bool   // library files the documents link to
	slides map[string][]store.Slide
	res    ObsidianResult
}

// Export folder names; course and lecture folders are named as in the library.
const (
	indexPage         = "课程库.md"
	notesFolder       = "笔记"
	transcriptsFolder = "转写稿"
	filesFolder       = "附件" // inside a lecture's notes folder
	courseNotesFolder = "课程笔记"
	looseNotesFolder  = "未归类笔记"
)

// courseOf splits a library path under courses/ into the course folder
// name and the rest.
func courseOf(rel string) (course, rest string, ok bool) {
	r, ok := strings.CutPrefix(rel, "courses/")
	if !ok {
		return "", "", false
	}
	course, rest, _ = strings.Cut(r, "/")
	return course, rest, course != ""
}

// placeInExport is where a library file a note links to goes: in the
// attachment folder of its lecture's notes, keeping the file's path inside
// the lecture folder (slides/..., courseware/...).
func placeInExport(rel string) string {
	course, rest, ok := courseOf(rel)
	if !ok {
		return looseNotesFolder + "/" + filesFolder + "/" + rel
	}
	lecture, inLecture, _ := strings.Cut(rest, "/")
	if inLecture == "" {
		return course + "/" + notesFolder + "/" + filesFolder + "/" + rest
	}
	return course + "/" + notesFolder + "/" + lecture + "/" + filesFolder + "/" + inLecture
}

func transcriptPage(lec store.Lecture) string {
	return path.Base(path.Dir(lec.Dir)) + "/" + transcriptsFolder + "/" + path.Base(lec.Dir) + ".md"
}

// noteFolder is the export folder of a note stored at library path rel:
// courses/<课程>/<节次>/notes/ goes to <课程>/笔记/<节次>/, the course's own
// notes/ to <课程>/笔记/课程笔记/.
func noteFolder(rel string) string {
	course, rest, ok := courseOf(rel)
	if !ok {
		return looseNotesFolder
	}
	if lecture, _, _ := strings.Cut(rest, "/"); lecture != "notes" {
		return course + "/" + notesFolder + "/" + lecture
	}
	return course + "/" + notesFolder + "/" + courseNotesFolder
}

func (e *obsidianExport) SlidePath(lectureID string, idx int) string {
	sl, ok := e.slides[lectureID]
	if !ok {
		sl, _ = e.lib.Store.Slides(e.ctx, lectureID)
		e.slides[lectureID] = sl
	}
	for _, s := range sl {
		if s.Idx == idx {
			return s.Path
		}
	}
	return ""
}

// FileExists reports whether a note's link names a regular file inside the
// library. Symbolic links are not followed out of it.
func (e *obsidianExport) FileExists(rel string) bool {
	p, ok := libraryPath(rel)
	if !ok {
		return false
	}
	fi, err := e.src.Lstat(p)
	return err == nil && fi.Mode().IsRegular()
}

// libraryPath checks a slash path relative to the library root.
func libraryPath(rel string) (string, bool) {
	for _, part := range strings.Split(rel, "/") {
		if part == "" || part == "." || part == ".." {
			return "", false
		}
	}
	return filepath.FromSlash(rel), true
}

// link is a Markdown link from export document `from` to export path `to`.
func link(label, from, to string) string {
	return "[" + label + "](" + portable.Relative(from, to) + ")"
}

func (e *obsidianExport) run() error {
	st := e.lib.Store
	courses, err := st.Courses(e.ctx)
	if err != nil {
		return err
	}
	all, err := st.Notes(e.ctx, "", "")
	if err != nil {
		return err
	}
	notePaths := notePlaces(all)
	notesIn := map[string][]store.Note{} // by lecture id, or "course:<id>" for course notes
	var loose []store.Note
	for _, n := range all {
		switch {
		case notePaths[n.ID] == "":
		case n.LectureID != "":
			notesIn[n.LectureID] = append(notesIn[n.LectureID], n)
		case n.CourseID != "":
			notesIn["course:"+n.CourseID] = append(notesIn["course:"+n.CourseID], n)
		default:
			loose = append(loose, n)
		}
	}

	var index strings.Builder
	index.WriteString(frontMatter([][2]string{{"title", "课程库"}}, "look-studio"))
	index.WriteString("# 课程库\n\n由 Look Studio 导出。在这里修改过的文件不会被下次导出覆盖。\n")
	for _, c := range courses {
		if c.Dir == "" {
			continue
		}
		if err := e.course(&index, c, notesIn, notePaths); err != nil {
			return err
		}
	}
	if len(loose) > 0 {
		index.WriteString("\n## " + looseNotesFolder + "\n\n")
		for _, n := range loose {
			if err := e.note(n, notePaths[n.ID], store.Course{}, store.Lecture{}); err != nil {
				return err
			}
			fmt.Fprintf(&index, "- %s\n", link(n.Title, indexPage, notePaths[n.ID]))
		}
	}
	if err := e.put(indexPage, index.String()); err != nil {
		return err
	}

	rels := make([]string, 0, len(e.copies))
	for rel := range e.copies {
		rels = append(rels, rel)
	}
	sort.Strings(rels)
	for _, rel := range rels {
		if err := e.copy(rel); err != nil {
			return err
		}
	}
	// A failed export returns before this point and keeps the previous
	// manifest, so nothing it did not finish is treated as ours.
	e.removeStale()
	manifest, err := json.MarshalIndent(map[string]any{"schema": "look-studio/obsidian-export@1", "files": e.files}, "", "  ")
	if err != nil {
		return err
	}
	return e.write(obsidianManifest, bytes.NewReader(manifest))
}

// notePlaces gives every note an export path named after its title, next to
// where it lives in the library. Older notes win a contested name; later
// ones get a short id suffix, so paths stay stable across exports.
func notePlaces(notes []store.Note) map[string]string {
	sorted := append([]store.Note(nil), notes...)
	sort.Slice(sorted, func(i, j int) bool {
		if sorted[i].CreatedAt != sorted[j].CreatedAt {
			return sorted[i].CreatedAt < sorted[j].CreatedAt
		}
		return sorted[i].ID < sorted[j].ID
	})
	taken := map[string]bool{}
	out := map[string]string{}
	for _, n := range sorted {
		if n.Path == "" {
			continue
		}
		dir := noteFolder(n.Path)
		name := Sanitize(n.Title, "笔记")
		p := dir + "/" + name + ".md"
		if taken[strings.ToLower(p)] {
			suffix := n.ID
			if len(suffix) > 6 {
				suffix = suffix[len(suffix)-6:]
			}
			p = dir + "/" + name + " (" + suffix + ").md"
		}
		taken[strings.ToLower(p)] = true
		out[n.ID] = p
	}
	return out
}

func courseName(c store.Course) string {
	if c.Alias != "" {
		return c.Alias
	}
	return c.Title
}

// course writes a course's notes and transcripts and adds its section to
// the index.
func (e *obsidianExport) course(index *strings.Builder, c store.Course, notesIn map[string][]store.Note, notePaths map[string]string) error {
	st := e.lib.Store
	lectures, err := st.Lectures(e.ctx, c.ID)
	if err != nil {
		return err
	}
	sched, _ := st.Schedule(e.ctx, store.ScheduleQuery{CourseID: c.ID})

	fmt.Fprintf(index, "\n## %s\n\n", courseName(c))
	if meta := joinNonEmpty(" · ", c.Teacher, c.College, c.Term); meta != "" {
		index.WriteString(meta + "\n\n")
	}
	for _, lec := range lectures {
		if lec.Dir == "" {
			continue
		}
		notes := notesIn[lec.ID]
		// Notes first: the courseware they cite is linked from the transcript page.
		for _, n := range notes {
			if err := e.note(n, notePaths[n.ID], c, lec); err != nil {
				return err
			}
		}
		tp, err := e.transcript(c, lec, notes, notePaths, sched)
		if err != nil {
			return err
		}
		parts := []string{"**" + lec.Title + "**"}
		if tp != "" {
			parts = append(parts, link("转写稿", indexPage, tp))
		}
		parts = append(parts, fmt.Sprintf("[在 Look Studio 中打开](%s)", portable.LectureLink(lec.ID, -1)))
		index.WriteString("- " + strings.Join(parts, " · ") + "\n")
		for _, n := range notes {
			fmt.Fprintf(index, "  - %s\n", link(n.Title, indexPage, notePaths[n.ID]))
		}
	}
	if ns := notesIn["course:"+c.ID]; len(ns) > 0 {
		index.WriteString("\n课程笔记：\n\n")
		for _, n := range ns {
			if err := e.note(n, notePaths[n.ID], c, store.Lecture{}); err != nil {
				return err
			}
			fmt.Fprintf(index, "- %s\n", link(n.Title, indexPage, notePaths[n.ID]))
		}
	}
	if len(sched) > 0 {
		index.WriteString("\n日程：\n\n")
		for _, it := range sched {
			index.WriteString(scheduleLine(it) + "\n")
		}
	}
	return nil
}

// transcript writes a lecture's transcript page: the lecture's details,
// outline, notes, schedule and courseware, then the transcript. Returns ""
// when the lecture has no transcript.
func (e *obsidianExport) transcript(c store.Course, lec store.Lecture, notes []store.Note, notePaths map[string]string, sched []store.ScheduleItem) (string, error) {
	raw, err := os.ReadFile(e.lib.Abs(lec.Dir + "/transcript.md"))
	if errors.Is(err, fs.ErrNotExist) {
		return "", nil
	} else if err != nil {
		return "", err
	}
	page := transcriptPage(lec)
	var b strings.Builder
	duration := ""
	if lec.DurationS > 0 {
		duration = fmtClock(lec.DurationS * 1000)
	}
	b.WriteString(frontMatter([][2]string{
		{"title", lec.Title}, {"course", courseName(c)}, {"date", lec.Date}, {"lecturer", lec.Lecturer},
		{"room", lec.Room}, {"duration", duration}, {"look_lecture_id", lec.ID},
	}, "look-studio/transcript"))
	fmt.Fprintf(&b, "# %s\n\n%s · [在 Look Studio 中打开](%s)\n", lec.Title, link("课程库", page, indexPage), portable.LectureLink(lec.ID, -1))

	if chs, _ := e.lib.Store.Timeline(e.ctx, lec.ID); len(chs) > 0 {
		b.WriteString("\n## 大纲\n\n")
		for _, ch := range chs {
			fmt.Fprintf(&b, "- [%s](%s) %s\n", fmtClock(ch.StartMs), portable.LectureLink(lec.ID, ch.StartMs/1000), ch.Title)
		}
	}
	if len(notes) > 0 {
		b.WriteString("\n## 笔记\n\n")
		for _, n := range notes {
			fmt.Fprintf(&b, "- %s\n", link(n.Title, page, notePaths[n.ID]))
		}
	}
	var items []string
	for _, it := range sched {
		if it.LectureID == lec.ID {
			items = append(items, scheduleLine(it))
		}
	}
	if len(items) > 0 {
		b.WriteString("\n## 日程\n\n" + strings.Join(items, "\n") + "\n")
	}
	// Courseware files are copied only when a note cites them; the rest are
	// listed by name, so automatic exports stay cheap.
	var files []string
	cw, _ := e.lib.Courseware(e.ctx, lec.ID)
	for _, a := range cw {
		if e.copies[a.Path] {
			files = append(files, "- "+link(path.Base(a.Path), page, placeInExport(a.Path)))
		} else {
			files = append(files, "- "+path.Base(a.Path)+"（在 Look Studio 中查看）")
		}
	}
	if len(files) > 0 {
		b.WriteString("\n## 课件\n\n" + strings.Join(files, "\n") + "\n")
	}
	b.WriteString("\n## 转写稿\n\n")
	b.WriteString(e.conv.Markdown(transcriptBody(string(raw)), portable.Doc{Path: page, LectureID: lec.ID}))
	return page, e.put(page, b.String())
}

// transcriptBody drops the library file's own front matter and title; the
// export page has its own.
func transcriptBody(s string) string {
	if strings.HasPrefix(s, "---\n") {
		if end := strings.Index(s[4:], "\n---\n"); end >= 0 {
			s = s[4+end+5:]
		}
	}
	s = strings.TrimLeft(s, "\n")
	if strings.HasPrefix(s, "# ") {
		_, s, _ = strings.Cut(s, "\n")
	}
	return strings.TrimLeft(s, "\n")
}

func scheduleLine(it store.ScheduleItem) string {
	box := " "
	if it.Done {
		box = "x"
	}
	when := strings.TrimSpace(it.DueDate + " " + it.DueTime)
	line := fmt.Sprintf("- [%s] %s %s", box, when, it.Title)
	if it.LectureID != "" && it.TMs >= 0 {
		line += fmt.Sprintf(" · [原话 %s](%s)", fmtClock(it.TMs), portable.LectureLink(it.LectureID, it.TMs/1000))
	}
	return line
}

func (e *obsidianExport) note(n store.Note, p string, c store.Course, lec store.Lecture) error {
	full, err := e.lib.Store.Note(e.ctx, n.ID)
	if err != nil {
		return err
	}
	fm := [][2]string{{"title", n.Title}}
	if c.ID != "" {
		fm = append(fm, [2]string{"course", courseName(c)})
	}
	if lec.ID != "" {
		fm = append(fm, [2]string{"lecture", lec.Title}, [2]string{"date", lec.Date})
	}
	fm = append(fm, [2]string{"source", n.Source}, [2]string{"look_note_id", n.ID},
		[2]string{"look_lecture_id", n.LectureID}, [2]string{"look_course_id", n.CourseID},
		[2]string{"updated", unixISO(n.UpdatedAt)})
	body := e.conv.Markdown(full.Body, portable.Doc{Path: p, LectureID: n.LectureID})
	return e.put(p, frontMatter(fm, "look-studio/note")+strings.TrimLeft(body, "\n"))
}

// frontMatter renders Obsidian properties; empty values are left out.
func frontMatter(kv [][2]string, tag string) string {
	var b strings.Builder
	b.WriteString("---\n")
	for _, p := range kv {
		if p[1] != "" {
			fmt.Fprintf(&b, "%s: %s\n", p[0], strconv.Quote(p[1]))
		}
	}
	fmt.Fprintf(&b, "tags:\n  - %s\n---\n\n", tag)
	return b.String()
}

func joinNonEmpty(sep string, parts ...string) string {
	var out []string
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return strings.Join(out, sep)
}

func hashOf(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// openExportRoot creates and opens the checked export folder one path
// component at a time from an os.Root of the vault. Each component is
// created with Mkdir in the already verified parent (which never follows a
// link at the new name), must be a real directory (not a symbolic link),
// and the handle opened for it must be that same directory. So a component
// swapped for a link after ObsidianRoot ran, even one pointing elsewhere
// inside the vault such as at the library, makes the export stop before
// anything is created there. From here on, paths are resolved by the kernel
// relative to the returned handle and cannot leave it.
func openExportRoot(vault, root string) (*os.Root, error) {
	changed := errors.New("导出文件夹在检查后发生了变化，已停止导出")
	realVault, err := filepath.EvalSymlinks(vault)
	if err != nil {
		return nil, err
	}
	rel, err := filepath.Rel(realVault, root)
	if err != nil || rel == "." || !inside(root, realVault) {
		return nil, changed
	}
	dir, err := os.OpenRoot(realVault)
	if err != nil {
		return nil, err
	}
	for _, part := range strings.Split(rel, string(filepath.Separator)) {
		if err := dir.Mkdir(part, 0o755); err != nil && !errors.Is(err, fs.ErrExist) {
			dir.Close()
			return nil, err
		}
		fi, err := dir.Lstat(part)
		if err != nil || !fi.IsDir() {
			dir.Close()
			return nil, changed
		}
		next, err := dir.OpenRoot(part)
		dir.Close()
		if err != nil {
			return nil, err
		}
		if st, err := next.Stat("."); err != nil || !os.SameFile(fi, st) {
			next.Close()
			return nil, changed
		}
		dir = next
	}
	return dir, nil
}

// openRegular opens p in dir for reading, only if it is a regular file:
// a FIFO, device or directory planted in its place is refused without
// blocking. ErrNotExist passes through.
func openRegular(dir *os.Root, p string) (*os.File, error) {
	fi, err := dir.Lstat(p)
	if err != nil {
		return nil, err
	}
	if !fi.Mode().IsRegular() {
		return nil, fmt.Errorf("%s 不是普通文件", p)
	}
	f, err := dir.OpenFile(p, os.O_RDONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	if st, err := f.Stat(); err != nil || !st.Mode().IsRegular() || !os.SameFile(fi, st) {
		f.Close()
		return nil, fmt.Errorf("%s 在读取时发生了变化", p)
	}
	return f, nil
}

// maxExportRead bounds what the export reads back from the vault.
const maxExportRead = 64 << 20

func readRegular(dir *os.Root, p string) ([]byte, error) {
	f, err := openRegular(dir, p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(io.LimitReader(f, maxExportRead))
}

// target checks an export path (slash, relative to the export folder) and
// returns it in OS form for use with e.dir. A path through a symbolic link is
// refused with a clear message; the os.Root handle is what actually keeps
// operations inside the folder.
func (e *obsidianExport) target(rel string) (string, error) {
	parts := strings.Split(rel, "/")
	for _, part := range parts {
		if part == "" || part == "." || part == ".." {
			return "", fmt.Errorf("无效的导出路径 %s", rel)
		}
	}
	p := ""
	for _, part := range parts {
		p = filepath.Join(p, part)
		fi, err := e.dir.Lstat(p)
		if errors.Is(err, fs.ErrNotExist) {
			break
		}
		if err != nil {
			return "", err
		}
		if fi.Mode()&fs.ModeSymlink != 0 {
			return "", fmt.Errorf("导出文件夹中的 %s 是符号链接，已停止导出", rel)
		}
	}
	return filepath.FromSlash(rel), nil
}

// write replaces export file rel with the content of r.
func (e *obsidianExport) write(rel string, r io.Reader) error {
	p, err := e.target(rel)
	if err != nil {
		return err
	}
	return writeAtomic(e.dir, p, r)
}

// put writes an export document unless the copy in the vault was edited
// since the last export (or was never ours); then the new version goes
// beside it as "<name> (Look Studio).md", under the same rule.
func (e *obsidianExport) put(rel, content string) error {
	want := hashOf([]byte(content))
	for i := 0; i < 20; i++ {
		cand := rel
		switch {
		case i == 1:
			cand = strings.TrimSuffix(rel, ".md") + " (Look Studio).md"
		case i > 1:
			cand = strings.TrimSuffix(rel, ".md") + fmt.Sprintf(" (Look Studio %d).md", i)
		}
		p, err := e.target(cand)
		if err != nil {
			return err
		}
		cur, err := readRegular(e.dir, p)
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		if err == nil {
			h := hashOf(cur)
			if h == want {
				e.files[cand] = want
				e.res.Unchanged++
				return nil
			}
			if e.old[cand] != h {
				// Edited in the vault, or a file we never wrote: keep it.
				if old, ok := e.old[cand]; ok {
					e.files[cand] = old
				}
				if i == 0 {
					e.res.Conflicts = append(e.res.Conflicts, rel)
				}
				continue
			}
		}
		if err := writeAtomic(e.dir, p, strings.NewReader(content)); err != nil {
			return err
		}
		e.files[cand] = want
		e.res.Written++
		return nil
	}
	return fmt.Errorf("%s 的冲突副本太多，请先在 Obsidian 中整理", rel)
}

// copy places a library file in the export. An attachment changed in the
// vault (or one the export did not write) is kept as it is.
func (e *obsidianExport) copy(rel string) error {
	dst := placeInExport(rel)
	p, err := e.target(dst)
	if err != nil {
		return err
	}
	sp, ok := libraryPath(rel)
	if !ok {
		return nil
	}
	// One handle for hashing and copying, so the copy is what was hashed.
	src, err := openRegular(e.src, sp)
	if errors.Is(err, fs.ErrNotExist) {
		return nil // gone from the library since the documents were written
	} else if err != nil {
		return err
	}
	defer src.Close()
	want, err := hashFile(src)
	if err != nil {
		return err
	}
	cur, err := hashAt(e.dir, p)
	switch {
	case err == nil && cur == want:
		e.files[dst] = want
		e.res.Unchanged++
		return nil
	case err == nil && e.old[dst] != cur:
		if old, ok := e.old[dst]; ok {
			e.files[dst] = old
		}
		e.res.Conflicts = append(e.res.Conflicts, dst)
		return nil
	case err != nil && !errors.Is(err, fs.ErrNotExist):
		return err
	}
	if _, err := src.Seek(0, io.SeekStart); err != nil {
		return err
	}
	if err := writeAtomic(e.dir, p, src); err != nil {
		return err
	}
	e.files[dst] = want
	e.res.Written++
	return nil
}

// hashAt hashes regular file p in dir.
func hashAt(dir *os.Root, p string) (string, error) {
	f, err := openRegular(dir, p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	return hashFile(f)
}

// hashFile hashes an opened file from its current offset.
func hashFile(f *os.File) (string, error) {
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// writeAtomic replaces dir/p with the content of r through a new temporary
// file beside it, created exclusively under a random name, so no existing
// file is ever opened for writing. All of it happens inside dir.
func writeAtomic(dir *os.Root, p string, r io.Reader) error {
	if err := dir.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	var rnd [8]byte
	rand.Read(rnd[:])
	tmp := filepath.Join(filepath.Dir(p), ".lookstudio-"+hex.EncodeToString(rnd[:])+".tmp")
	f, err := dir.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, r)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = dir.Rename(tmp, p)
	}
	if err != nil {
		dir.Remove(tmp)
	}
	return err
}

// removeStale deletes what the previous export wrote and this one did not,
// unless the user has changed it since. Emptied folders go too.
func (e *obsidianExport) removeStale() {
	for rel, want := range e.old {
		if _, keep := e.files[rel]; keep {
			continue
		}
		p, err := e.target(rel)
		if err != nil {
			continue
		}
		if cur, err := hashAt(e.dir, p); err != nil || cur != want {
			continue
		}
		if e.dir.Remove(p) == nil {
			e.res.Removed++
			for d := filepath.Dir(p); d != "."; d = filepath.Dir(d) {
				if e.dir.Remove(d) != nil {
					break
				}
			}
		}
	}
}

func readManifest(dir *os.Root) map[string]string {
	var m struct {
		Files map[string]string `json:"files"`
	}
	if b, err := readRegular(dir, obsidianManifest); err == nil {
		json.Unmarshal(b, &m)
	}
	if m.Files == nil {
		m.Files = map[string]string{}
	}
	return m.Files
}
