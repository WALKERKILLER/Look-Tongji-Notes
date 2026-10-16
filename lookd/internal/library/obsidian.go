package library

import (
	"bytes"
	"context"
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

	"lookstudio/lookd/internal/portable"
	"lookstudio/lookd/internal/store"
)

// The Obsidian export mirrors the library into a folder of an Obsidian vault
// as plain Markdown: a page per course and lecture, the notes, transcripts,
// and the slides, courseware and figures the notes link to. It is one-way;
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
	if err := os.MkdirAll(root, 0o755); err != nil {
		return ObsidianResult{}, err
	}
	_, vaultErr := os.Stat(filepath.Join(vault, ".obsidian"))
	e := &obsidianExport{
		ctx: ctx, lib: l, root: root,
		old:    readManifest(filepath.Join(root, obsidianManifest)),
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
	conv   *portable.Converter
	old    map[string]string // manifest of the previous export
	files  map[string]string // manifest of this export
	copies map[string]bool   // library files the documents link to
	slides map[string][]store.Slide
	res    ObsidianResult
}

// placeInExport maps a library path to its export path: course folders sit
// at the export root, loose notes in their own folder.
func placeInExport(rel string) string {
	if r, ok := strings.CutPrefix(rel, "courses/"); ok {
		return r
	}
	if r, ok := strings.CutPrefix(rel+"/", "notes/"); ok {
		return strings.TrimSuffix("未归类笔记/"+r, "/")
	}
	return "_files/" + rel
}

// pageOf is the folder page of a library folder: "<folder>/<folder name>.md".
func pageOf(dir string) string {
	p := placeInExport(dir)
	return p + "/" + path.Base(p) + ".md"
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

func (e *obsidianExport) FileExists(rel string) bool {
	fi, err := os.Stat(e.lib.Abs(rel))
	return err == nil && !fi.IsDir()
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
	index.WriteString("# 课程库\n\n由 Look Studio 导出。在这里修改过的文件不会被下次导出覆盖。\n\n")
	for _, c := range courses {
		if c.Dir == "" {
			continue
		}
		page, err := e.course(c, notesIn, notePaths)
		if err != nil {
			return err
		}
		fmt.Fprintf(&index, "- %s\n", link(courseName(c), "课程库.md", page))
	}
	if len(loose) > 0 {
		index.WriteString("\n## 未归类笔记\n\n")
		for _, n := range loose {
			if err := e.note(n, notePaths[n.ID], store.Course{}, store.Lecture{}); err != nil {
				return err
			}
			fmt.Fprintf(&index, "- %s\n", link(n.Title, "课程库.md", notePaths[n.ID]))
		}
	}
	if err := e.put("课程库.md", index.String()); err != nil {
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
	abs, err := e.target(obsidianManifest)
	if err != nil {
		return err
	}
	return writeAtomic(abs, bytes.NewReader(manifest))
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
		dir := placeInExport(path.Dir(n.Path))
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

func (e *obsidianExport) course(c store.Course, notesIn map[string][]store.Note, notePaths map[string]string) (string, error) {
	st := e.lib.Store
	page := pageOf(c.Dir)
	lectures, err := st.Lectures(e.ctx, c.ID)
	if err != nil {
		return "", err
	}
	sched, _ := st.Schedule(e.ctx, store.ScheduleQuery{CourseID: c.ID})

	var b strings.Builder
	b.WriteString(frontMatter([][2]string{
		{"title", courseName(c)}, {"teacher", c.Teacher}, {"term", c.Term}, {"look_course_id", c.ID},
	}, "look-studio/course"))
	fmt.Fprintf(&b, "# %s\n\n", courseName(c))
	if meta := joinNonEmpty(" · ", c.Teacher, c.College, c.Term); meta != "" {
		b.WriteString(meta + "\n\n")
	}
	b.WriteString("## 课次\n\n")
	for _, lec := range lectures {
		if lec.Dir == "" {
			continue
		}
		lecPage, err := e.lecture(c, lec, notesIn[lec.ID], notePaths, sched)
		if err != nil {
			return "", err
		}
		line := "- " + link(lec.Title, page, lecPage)
		if k := len(notesIn[lec.ID]); k > 0 {
			line += fmt.Sprintf(" · %d 篇笔记", k)
		}
		b.WriteString(line + "\n")
	}
	if ns := notesIn["course:"+c.ID]; len(ns) > 0 {
		b.WriteString("\n## 课程笔记\n\n")
		for _, n := range ns {
			if err := e.note(n, notePaths[n.ID], c, store.Lecture{}); err != nil {
				return "", err
			}
			fmt.Fprintf(&b, "- %s\n", link(n.Title, page, notePaths[n.ID]))
		}
	}
	if len(sched) > 0 {
		b.WriteString("\n## 日程\n\n")
		for _, it := range sched {
			b.WriteString(scheduleLine(it) + "\n")
		}
	}
	return page, e.put(page, b.String())
}

func (e *obsidianExport) lecture(c store.Course, lec store.Lecture, notes []store.Note, notePaths map[string]string, sched []store.ScheduleItem) (string, error) {
	st := e.lib.Store
	page := pageOf(lec.Dir)
	dir := path.Dir(page)
	var b strings.Builder
	duration := ""
	if lec.DurationS > 0 {
		duration = fmtClock(lec.DurationS * 1000)
	}
	b.WriteString(frontMatter([][2]string{
		{"title", lec.Title}, {"course", courseName(c)}, {"date", lec.Date}, {"lecturer", lec.Lecturer},
		{"room", lec.Room}, {"duration", duration}, {"look_lecture_id", lec.ID},
	}, "look-studio/lecture"))
	fmt.Fprintf(&b, "# %s\n\n%s · [在 Look Studio 中打开](%s)\n", lec.Title, link(courseName(c), page, pageOf(c.Dir)), portable.LectureLink(lec.ID, -1))

	if chs, _ := st.Timeline(e.ctx, lec.ID); len(chs) > 0 {
		b.WriteString("\n## 大纲\n\n")
		for _, ch := range chs {
			fmt.Fprintf(&b, "- [%s](%s) %s\n", fmtClock(ch.StartMs), portable.LectureLink(lec.ID, ch.StartMs/1000), ch.Title)
		}
	}
	if len(notes) > 0 {
		b.WriteString("\n## 笔记\n\n")
		for _, n := range notes {
			if err := e.note(n, notePaths[n.ID], c, lec); err != nil {
				return "", err
			}
			fmt.Fprintf(&b, "- %s\n", link(n.Title, page, notePaths[n.ID]))
		}
	}
	var items []store.ScheduleItem
	for _, it := range sched {
		if it.LectureID == lec.ID {
			items = append(items, it)
		}
	}
	if len(items) > 0 {
		b.WriteString("\n## 日程\n\n")
		for _, it := range items {
			b.WriteString(scheduleLine(it) + "\n")
		}
	}

	var files []string
	if raw, err := os.ReadFile(e.lib.Abs(lec.Dir + "/transcript.md")); err == nil {
		tp := dir + "/transcript.md"
		if err := e.put(tp, e.conv.Markdown(string(raw), portable.Doc{Path: tp, LectureID: lec.ID})); err != nil {
			return "", err
		}
		files = append(files, "- "+link("转写稿", page, tp))
	}
	// Courseware files are copied only when a note cites them; the rest are
	// listed by name, so automatic exports stay cheap.
	cw, _ := e.lib.Courseware(e.ctx, lec.ID)
	for _, a := range cw {
		if e.copies[a.Path] {
			files = append(files, "- "+link("课件："+path.Base(a.Path), page, placeInExport(a.Path)))
		} else {
			files = append(files, "- 课件："+path.Base(a.Path)+"（在 Look Studio 中查看）")
		}
	}
	if len(files) > 0 {
		b.WriteString("\n## 资料\n\n" + strings.Join(files, "\n") + "\n")
	}
	return page, e.put(page, b.String())
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

// target is the absolute path of an export file. It refuses paths that
// leave the export folder or pass through a symbolic link, so writes and
// deletions stay inside the folder the user chose.
func (e *obsidianExport) target(rel string) (string, error) {
	parts := strings.Split(rel, "/")
	for _, part := range parts {
		if part == "" || part == "." || part == ".." {
			return "", fmt.Errorf("无效的导出路径 %s", rel)
		}
	}
	abs := e.root
	for _, part := range parts {
		abs = filepath.Join(abs, part)
		fi, err := os.Lstat(abs)
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
	return filepath.Join(e.root, filepath.FromSlash(rel)), nil
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
		abs, err := e.target(cand)
		if err != nil {
			return err
		}
		cur, err := os.ReadFile(abs)
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
		if err := writeAtomic(abs, strings.NewReader(content)); err != nil {
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
	abs, err := e.target(dst)
	if err != nil {
		return err
	}
	want, err := hashFile(e.lib.Abs(rel))
	if errors.Is(err, fs.ErrNotExist) {
		return nil // gone from the library since the documents were written
	} else if err != nil {
		return err
	}
	cur, err := hashFile(abs)
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
	src, err := os.Open(e.lib.Abs(rel))
	if err != nil {
		return err
	}
	defer src.Close()
	if err := writeAtomic(abs, src); err != nil {
		return err
	}
	e.files[dst] = want
	e.res.Written++
	return nil
}

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

// writeAtomic replaces abs with the content of r through a new, uniquely
// named temporary file beside it, so no existing file is ever opened for
// writing.
func writeAtomic(abs string, r io.Reader) error {
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(abs), ".lookstudio-*.tmp")
	if err != nil {
		return err
	}
	_, err = io.Copy(tmp, r)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Chmod(tmp.Name(), 0o644)
	}
	if err == nil {
		err = os.Rename(tmp.Name(), abs)
	}
	if err != nil {
		os.Remove(tmp.Name())
	}
	return err
}

// removeStale deletes what the previous export wrote and this one did not,
// unless the user has changed it since.
func (e *obsidianExport) removeStale() {
	for rel, want := range e.old {
		if _, keep := e.files[rel]; keep {
			continue
		}
		abs, err := e.target(rel)
		if err != nil {
			continue
		}
		if cur, err := hashFile(abs); err != nil || cur != want {
			continue
		}
		if os.Remove(abs) == nil {
			e.res.Removed++
			for dir := filepath.Dir(abs); dir != e.root && inside(dir, e.root); dir = filepath.Dir(dir) {
				if os.Remove(dir) != nil {
					break
				}
			}
		}
	}
}

func readManifest(p string) map[string]string {
	var m struct {
		Files map[string]string `json:"files"`
	}
	if b, err := os.ReadFile(p); err == nil {
		json.Unmarshal(b, &m)
	}
	if m.Files == nil {
		m.Files = map[string]string{}
	}
	return m.Files
}
