// Package library maps the SQLite index onto a human- and AI-readable folder
// tree. Files are the source of truth; Reindex rebuilds the database from them.
package library

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"lookstudio/lookd/internal/store"
)

type Templates struct {
	Course  string `json:"course"`  // vars: {title} {teacher} {term} {id}
	Lecture string `json:"lecture"` // vars: {date} {title} {sub_id} {lecturer}
}

var DefaultTemplates = Templates{Course: "{title}", Lecture: "{date} {title}"}

type Library struct {
	Root  string
	Store *store.Store
	mu    sync.Mutex
	tpl   Templates

	// mirrorMu serializes mirrored writes, recovery and Reindex (mirror.go).
	mirrorMu sync.Mutex
}

func Open(root string, st *store.Store) (*Library, error) {
	if err := os.MkdirAll(filepath.Join(root, "courses"), 0o755); err != nil {
		return nil, err
	}
	l := &Library{Root: root, Store: st, tpl: DefaultTemplates}
	l.writeReadme()
	l.mirrorMu.Lock()
	if err := l.recoverMirrors(context.Background()); err != nil {
		log.Printf("library: %v", err)
	}
	l.mirrorMu.Unlock()
	return l, nil
}

func (l *Library) SetTemplates(t Templates) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if t.Course != "" {
		l.tpl.Course = t.Course
	}
	if t.Lecture != "" {
		l.tpl.Lecture = t.Lecture
	}
}

func (l *Library) Abs(rel string) string { return filepath.Join(l.Root, filepath.FromSlash(rel)) }

// Rel converts an absolute path inside the library to a slash path.
func (l *Library) Rel(abs string) string {
	r, err := filepath.Rel(l.Root, abs)
	if err != nil {
		return abs
	}
	return filepath.ToSlash(r)
}

var badChars = regexp.MustCompile(`[\\/:*?"<>|\x00-\x1f]`)
var spaces = regexp.MustCompile(`\s+`)

// Sanitize keeps CJK text readable while making it a safe path component.
func Sanitize(s, fallback string) string {
	s = badChars.ReplaceAllString(strings.TrimSpace(s), "_")
	s = strings.Trim(spaces.ReplaceAllString(s, " "), " ._")
	for utf8.RuneCountInString(s) > 80 {
		r := []rune(s)
		s = strings.TrimRight(string(r[:80]), " ._")
	}
	if s == "" {
		return fallback
	}
	return s
}

func expand(tpl string, vars map[string]string) string {
	out := tpl
	for k, v := range vars {
		out = strings.ReplaceAll(out, "{"+k+"}", v)
	}
	return out
}

func (l *Library) courseDirName(c store.Course) string {
	l.mu.Lock()
	tpl := l.tpl.Course
	l.mu.Unlock()
	title := c.Title
	if c.Alias != "" {
		title = c.Alias
	}
	return Sanitize(expand(tpl, map[string]string{"title": title, "teacher": c.Teacher, "term": c.Term, "id": c.ID}), "课程-"+c.ID)
}

func (l *Library) lectureDirName(x store.Lecture) string {
	l.mu.Lock()
	tpl := l.tpl.Lecture
	l.mu.Unlock()
	date := x.Date
	if date != "" && strings.HasPrefix(x.Title, date) {
		date = "" // titles like "2026-09-14第3-4节" already carry the date
	}
	name := expand(tpl, map[string]string{"date": date, "title": x.Title, "sub_id": x.ID, "lecturer": x.Lecturer})
	return Sanitize(name, "节次-"+x.ID)
}

// EnsureLecture assigns stable folders for a lecture and writes metadata.
func (l *Library) EnsureLecture(ctx context.Context, lectureID string) (store.Course, store.Lecture, string, error) {
	lec, err := l.Store.Lecture(ctx, lectureID)
	if err != nil {
		return store.Course{}, store.Lecture{}, "", fmt.Errorf("lecture %s not indexed: %w", lectureID, err)
	}
	c, err := l.Store.Course(ctx, lec.CourseID)
	if err != nil {
		return store.Course{}, store.Lecture{}, "", err
	}
	if c.Dir == "" {
		c.Dir = l.unique("courses/"+l.courseDirName(c), c.ID, "course.json")
		if err := l.Store.SetCourseDir(ctx, c.ID, c.Dir); err != nil {
			return c, lec, "", err
		}
	}
	if lec.Dir == "" {
		lec.Dir = l.unique(c.Dir+"/"+l.lectureDirName(lec), lec.ID, "lecture.json")
		if err := l.Store.SetLectureDir(ctx, lec.ID, lec.Dir); err != nil {
			return c, lec, "", err
		}
	}
	if err := os.MkdirAll(l.Abs(lec.Dir), 0o755); err != nil {
		return c, lec, "", err
	}
	l.writeCourseJSON(c)
	return c, lec, lec.Dir, nil
}

// unique returns rel, or rel + " (id)" when another entity already owns it.
func (l *Library) unique(rel, id, metaFile string) string {
	b, err := os.ReadFile(filepath.Join(l.Abs(rel), metaFile))
	if err != nil {
		return rel
	}
	var m struct {
		ID string `json:"id"`
	}
	if json.Unmarshal(b, &m) == nil && m.ID != "" && m.ID != id {
		return rel + " (" + id + ")"
	}
	return rel
}

func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return writeFileAtomic(path, append(b, '\n'))
}

func writeFileAtomic(path string, b []byte) error {
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	_, err = f.Write(b)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}

func (l *Library) writeCourseJSON(c store.Course) {
	writeJSON(filepath.Join(l.Abs(c.Dir), "course.json"), map[string]any{
		"schema": "look-studio/course@1", "id": c.ID, "title": c.Title, "alias": c.Alias, "teacher": c.Teacher,
		"teachers": c.Teachers, "college": c.College, "term": c.Term,
		"source_url": "https://look.tongji.edu.cn/course/" + c.ID,
	})
}

// WriteLectureJSON refreshes lecture.json, the per-lecture manifest an agent
// reads first: identity, timing and the list of local artifacts.
func (l *Library) WriteLectureJSON(ctx context.Context, lectureID string) error {
	lec, err := l.Store.Lecture(ctx, lectureID)
	if err != nil || lec.Dir == "" {
		return err
	}
	c, _ := l.Store.Course(ctx, lec.CourseID)
	assets, _ := l.Store.Assets(ctx, lectureID)
	files := []map[string]any{}
	for _, a := range assets {
		rel := strings.TrimPrefix(a.Path, lec.Dir+"/")
		files = append(files, map[string]any{"kind": a.Kind, "path": rel, "bytes": a.Bytes, "meta": a.Meta})
	}
	notes, _ := l.Store.Notes(ctx, "", lectureID)
	noteFiles := []string{}
	for _, n := range notes {
		noteFiles = append(noteFiles, strings.TrimPrefix(n.Path, lec.Dir+"/"))
	}
	return writeJSON(filepath.Join(l.Abs(lec.Dir), "lecture.json"), map[string]any{
		"schema": "look-studio/lecture@1", "id": lec.ID, "course_id": lec.CourseID, "course_title": c.Title,
		"title": lec.Title, "date": lec.Date, "begin_at": unixISO(lec.BeginAt), "end_at": unixISO(lec.EndAt),
		"lecturer": lec.Lecturer, "room": lec.Room, "duration_seconds": lec.DurationS,
		"source_url": fmt.Sprintf("https://look.tongji.edu.cn/player?course_id=%s&sub_id=%s", lec.CourseID, lec.ID),
		"files":      files, "notes": noteFiles, "timeline": timelineFile(l.Abs(lec.Dir)),
		"updated_at": time.Now().Format(time.RFC3339),
	})
}

func timelineFile(dir string) string {
	if _, err := os.Stat(filepath.Join(dir, "timeline.txt")); err == nil {
		return "timeline.txt"
	}
	return ""
}

func unixISO(t int64) string {
	if t <= 0 {
		return ""
	}
	return time.Unix(t, 0).Format(time.RFC3339)
}

// ---- transcript ----

func fmtSRT(ms int64) string {
	return fmt.Sprintf("%02d:%02d:%02d,%03d", ms/3600000, ms%3600000/60000, ms%60000/1000, ms%1000)
}

func fmtClock(ms int64) string {
	s := ms / 1000
	if s >= 3600 {
		return fmt.Sprintf("%d:%02d:%02d", s/3600, s%3600/60, s%60)
	}
	return fmt.Sprintf("%02d:%02d", s/60, s%60)
}

// SaveTranscript writes transcript.srt and transcript.md and indexes segments.
func (l *Library) SaveTranscript(ctx context.Context, lectureID string, segs []store.Segment, engine string) error {
	c, lec, dir, err := l.EnsureLecture(ctx, lectureID)
	if err != nil {
		return err
	}
	var srt, md strings.Builder
	for i, g := range segs {
		fmt.Fprintf(&srt, "%d\n%s --> %s\n%s\n\n", i+1, fmtSRT(g.StartMs), fmtSRT(g.EndMs), strings.TrimSpace(g.Text))
	}
	fmt.Fprintf(&md, "---\nschema: look-studio/transcript@1\ncourse: %q\nlecture: %q\nlecture_id: %q\ndate: %q\nengine: %s\nsegments: %d\n---\n\n",
		c.Title, lec.Title, lec.ID, lec.Date, engine, len(segs))
	fmt.Fprintf(&md, "# %s · %s 转写稿\n\n", c.Title, lec.Title)
	md.WriteString("> 每段以 `[mm:ss]` 开头，表示该段在录像中的起始时间。\n\n")
	// Group utterances into ~60s paragraphs for readability.
	var para []string
	var paraStart int64 = -1
	flush := func() {
		if len(para) > 0 {
			fmt.Fprintf(&md, "[%s] %s\n\n", fmtClock(paraStart), strings.Join(para, ""))
		}
		para, paraStart = nil, -1
	}
	for _, g := range segs {
		if paraStart < 0 {
			paraStart = g.StartMs
		}
		para = append(para, strings.TrimSpace(g.Text)+punct(g.Text))
		if g.EndMs-paraStart >= 60000 {
			flush()
		}
	}
	flush()
	base := l.Abs(dir)
	if err := os.WriteFile(filepath.Join(base, "transcript.srt"), []byte(srt.String()), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(base, "transcript.md"), []byte(md.String()), 0o644); err != nil {
		return err
	}
	if err := l.Store.ReplaceSegments(ctx, lectureID, segs); err != nil {
		return err
	}
	var dur int64
	if n := len(segs); n > 0 {
		dur = segs[n-1].EndMs / 1000
	}
	meta, _ := json.Marshal(map[string]any{"engine": engine, "segments": len(segs), "duration_seconds": dur})
	l.Store.DeleteAssets(ctx, lectureID, "transcript")
	fi, _ := os.Stat(filepath.Join(base, "transcript.srt"))
	l.Store.PutAsset(ctx, store.Asset{LectureID: lectureID, Kind: "transcript", Path: dir + "/transcript.srt", Bytes: fi.Size(), Meta: meta})
	return l.WriteLectureJSON(ctx, lectureID)
}

func punct(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	r, _ := utf8.DecodeLastRuneInString(s)
	if strings.ContainsRune("。！？，、；：.!?,", r) {
		return ""
	}
	return "，"
}

// ---- notes ----

func NewID() string {
	var b [6]byte
	rand.Read(b[:])
	return time.Now().Format("20060102") + "-" + hex.EncodeToString(b[:])
}

// SaveNote writes notes/<title>-<id>.md with YAML front matter and indexes it.
func (l *Library) SaveNote(ctx context.Context, n store.Note) (store.Note, error) {
	if n.ID == "" {
		n.ID = NewID()
	}
	if strings.TrimSpace(n.Title) == "" {
		n.Title = "未命名笔记"
	}
	var dir string
	switch {
	case n.LectureID != "":
		c, _, d, err := l.EnsureLecture(ctx, n.LectureID)
		if err != nil {
			return n, err
		}
		dir, n.CourseID = d+"/notes", c.ID
	case n.CourseID != "":
		c, err := l.Store.Course(ctx, n.CourseID)
		if err != nil {
			return n, err
		}
		if c.Dir == "" {
			c.Dir = l.unique("courses/"+l.courseDirName(c), c.ID, "course.json")
			l.Store.SetCourseDir(ctx, c.ID, c.Dir)
			os.MkdirAll(l.Abs(c.Dir), 0o755)
			l.writeCourseJSON(c)
		}
		dir = c.Dir + "/notes"
	default:
		dir = "notes"
	}
	if old, err := l.Store.Note(ctx, n.ID); err == nil && old.Path != "" {
		os.Remove(l.Abs(old.Path))
	}
	n.Path = dir + "/" + Sanitize(n.Title, "笔记") + "-" + n.ID + ".md"
	if err := os.MkdirAll(l.Abs(dir), 0o755); err != nil {
		return n, err
	}
	fm := fmt.Sprintf("---\nschema: look-studio/note@1\nid: %s\ntitle: %q\ncourse_id: %q\nlecture_id: %q\nsource: %s\nupdated_at: %s\n---\n\n",
		n.ID, n.Title, n.CourseID, n.LectureID, orDefault(n.Source, "user"), time.Now().Format(time.RFC3339))
	if err := os.WriteFile(l.Abs(n.Path), []byte(fm+strings.TrimLeft(n.Body, "\n")), 0o644); err != nil {
		return n, err
	}
	if err := l.Store.PutNote(ctx, n); err != nil {
		return n, err
	}
	if n.LectureID != "" {
		l.WriteLectureJSON(ctx, n.LectureID)
	}
	return l.Store.Note(ctx, n.ID)
}

func (l *Library) DeleteNote(ctx context.Context, id string) error {
	n, err := l.Store.Note(ctx, id)
	if err != nil {
		return err
	}
	if n.Path != "" {
		os.Remove(l.Abs(n.Path))
	}
	if err := l.Store.DeleteNote(ctx, id); err != nil {
		return err
	}
	if n.LectureID != "" {
		l.WriteLectureJSON(ctx, n.LectureID)
	}
	return nil
}

func orDefault(s, d string) string {
	if s == "" {
		return d
	}
	return s
}

// ---- reindex ----

// Reindex rebuilds transcript segments and notes from files on disk, so the
// database can always be deleted and regenerated.
func (l *Library) Reindex(ctx context.Context) (int, error) {
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	if err := l.recoverMirrors(ctx); err != nil {
		return 0, err
	}
	count := 0
	err := filepath.WalkDir(l.Abs("courses"), func(p string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		switch {
		case d.Name() == "transcript.srt":
			b, _ := os.ReadFile(filepath.Join(filepath.Dir(p), "lecture.json"))
			var m struct {
				ID string `json:"id"`
			}
			if json.Unmarshal(b, &m) != nil || m.ID == "" {
				return nil
			}
			raw, err := os.ReadFile(p)
			if err != nil {
				return nil
			}
			segs := ParseSRT(string(raw))
			if l.Store.ReplaceSegments(ctx, m.ID, segs) == nil {
				count++
			}
		case d.Name() == "timeline.txt":
			b, _ := os.ReadFile(filepath.Join(filepath.Dir(p), "lecture.json"))
			var m struct {
				ID string `json:"id"`
			}
			raw, err := os.ReadFile(p)
			if json.Unmarshal(b, &m) != nil || m.ID == "" || err != nil {
				return nil
			}
			if chs := ParseTimeline(string(raw)); len(chs) > 0 && l.Store.ReplaceTimeline(ctx, m.ID, chs) == nil {
				count++
			}
		case strings.HasSuffix(d.Name(), ".md") && filepath.Base(filepath.Dir(p)) == "notes":
			if n, ok := parseNote(p); ok {
				n.Path = l.Rel(p)
				if l.Store.PutNote(ctx, n) == nil {
					count++
				}
			}
		}
		return nil
	})
	return count + l.reindexSchedule(ctx) + l.reindexActivity(ctx), err
}

var srtTime = regexp.MustCompile(`(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)`)

func ParseSRT(s string) []store.Segment {
	var out []store.Segment
	blocks := regexp.MustCompile(`\r?\n\r?\n`).Split(strings.TrimSpace(s), -1)
	for _, b := range blocks {
		lines := strings.Split(strings.TrimSpace(b), "\n")
		for i, ln := range lines {
			m := srtTime.FindStringSubmatch(ln)
			if m == nil {
				continue
			}
			ms := func(h, mi, se, f string) int64 {
				var a, b2, c, d int64
				fmt.Sscan(h, &a)
				fmt.Sscan(mi, &b2)
				fmt.Sscan(se, &c)
				fmt.Sscan(f, &d)
				return a*3600000 + b2*60000 + c*1000 + d
			}
			text := strings.TrimSpace(strings.Join(lines[i+1:], " "))
			out = append(out, store.Segment{Idx: len(out), StartMs: ms(m[1], m[2], m[3], m[4]), EndMs: ms(m[5], m[6], m[7], m[8]), Text: text})
			break
		}
	}
	return out
}

func parseNote(p string) (store.Note, bool) {
	b, err := os.ReadFile(p)
	if err != nil {
		return store.Note{}, false
	}
	s := string(b)
	if !strings.HasPrefix(s, "---\n") {
		return store.Note{}, false
	}
	end := strings.Index(s[4:], "\n---")
	if end < 0 {
		return store.Note{}, false
	}
	n := store.Note{Body: strings.TrimLeft(s[4+end+4:], "\n")}
	for _, ln := range strings.Split(s[4:4+end], "\n") {
		k, v, ok := strings.Cut(ln, ":")
		if !ok {
			continue
		}
		v = strings.TrimSpace(v)
		if uq, err := unquote(v); err == nil {
			v = uq
		}
		switch strings.TrimSpace(k) {
		case "id":
			n.ID = v
		case "title":
			n.Title = v
		case "course_id":
			n.CourseID = v
		case "lecture_id":
			n.LectureID = v
		case "source":
			n.Source = v
		}
	}
	return n, n.ID != ""
}

func unquote(s string) (string, error) {
	if len(s) >= 2 && s[0] == '"' {
		var out string
		err := json.Unmarshal([]byte(s), &out)
		return out, err
	}
	return s, errors.New("not quoted")
}

// ---- export ----

// ExportSkill mirrors lectures into the Look Tongji Notes skill workspace
// layout (raw/<课程>/<节次>/原始数据/...) so the llmwiki pipeline can build a site.
// Large media are hard-linked when possible to avoid copying.
func (l *Library) ExportSkill(ctx context.Context, root string) (int, error) {
	courses, err := l.Store.Courses(ctx)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, c := range courses {
		lecs, _ := l.Store.Lectures(ctx, c.ID)
		for _, lec := range lecs {
			if lec.Dir == "" || lec.Segments == 0 {
				continue
			}
			raw := filepath.Join(root, "raw", Sanitize(c.Title, "课程"), l.lectureDirName(lec), "原始数据")
			tdir := filepath.Join(raw, "transcript")
			os.MkdirAll(tdir, 0o755)
			base := c.ID + "_" + lec.ID
			src := l.Abs(lec.Dir)
			linkOrCopy(filepath.Join(src, "transcript.srt"), filepath.Join(tdir, base+".srt"))
			segs, _ := l.Store.Segments(ctx, lec.ID, 0, 0)
			var txt strings.Builder
			for _, g := range segs {
				txt.WriteString(g.Text + " ")
			}
			os.WriteFile(filepath.Join(tdir, base+".txt"), []byte(strings.TrimSpace(txt.String())+"\n"), 0o644)
			slides, _ := l.Store.Slides(ctx, lec.ID)
			sdir := filepath.Join(raw, "slides")
			os.MkdirAll(sdir, 0o755)
			var items []map[string]any
			for _, sl := range slides {
				if sl.Path == "" {
					continue
				}
				dst := filepath.Join(sdir, filepath.Base(sl.Path))
				linkOrCopy(l.Abs(sl.Path), dst)
				items = append(items, map[string]any{"created_sec": sl.TSec, "image_url": sl.RemoteURL, "filename": filepath.Base(sl.Path), "filepath": dst})
			}
			writeJSON(filepath.Join(sdir, "index.json"), map[string]any{"course_id": c.ID, "sub_id": lec.ID, "items": items})
			artifacts := map[string]string{
				"transcript_txt": filepath.Join(tdir, base+".txt"), "subtitle_srt": filepath.Join(tdir, base+".srt"),
				"slides_dir": sdir, "slide_index": filepath.Join(sdir, "index.json"),
			}
			if tl := filepath.Join(src, "timeline.txt"); timelineFile(src) != "" {
				linkOrCopy(tl, filepath.Join(raw, base+"_timeline.txt"))
				artifacts["timeline_txt"] = filepath.Join(raw, base+"_timeline.txt")
			}
			if cw, _ := l.Courseware(ctx, lec.ID); len(cw) > 0 {
				mdir := filepath.Join(raw, "materials")
				os.MkdirAll(mdir, 0o755)
				for _, a := range cw {
					linkOrCopy(l.Abs(a.Path), filepath.Join(mdir, filepath.Base(a.Path)))
					if p := CoursewareInfo(a).Parse; p != nil && p.MD != "" {
						linkOrCopy(l.Abs(p.MD), filepath.Join(mdir, filepath.Base(a.Path)+".md"))
					}
				}
				artifacts["materials_dir"] = mdir
			}
			writeJSON(filepath.Join(raw, "manifest.json"), map[string]any{
				"course_id": c.ID, "sub_id": lec.ID, "course_title": c.Title, "session_title": lec.Title,
				"agent": "look-studio", "agents": []string{"look-studio"}, "base_name": base,
				"generated_at": time.Now().Format(time.RFC3339), "duration_seconds": lec.DurationS,
				"artifacts": artifacts,
			})
			n++
		}
	}
	return n, nil
}

func linkOrCopy(src, dst string) {
	os.Remove(dst)
	if os.Link(src, dst) == nil {
		return
	}
	if b, err := os.ReadFile(src); err == nil {
		os.WriteFile(dst, b, 0o644)
	}
}

// RemoveAsset deletes the local files of one artifact kind for a lecture and
// forgets them in the index. Returns the bytes freed.
func (l *Library) RemoveAsset(ctx context.Context, lectureID, kind string) (int64, error) {
	lec, err := l.Store.Lecture(ctx, lectureID)
	if err != nil {
		return 0, err
	}
	assets, err := l.Store.Assets(ctx, lectureID)
	if err != nil {
		return 0, err
	}
	var freed int64
	if kind == "parse" {
		// Parsing results live beside the courseware they came from.
		for _, a := range assets {
			if a.Kind == "courseware" {
				freed += l.DiskUsage(ParsedDir(a.Path))
				os.RemoveAll(l.Abs(ParsedDir(a.Path)))
				l.SetParse(ctx, a, nil)
			}
		}
		return freed, nil
	}
	rm := func(rel string) {
		if rel == "" || strings.Contains(rel, "..") {
			return
		}
		abs := l.Abs(rel)
		if !strings.HasPrefix(abs, filepath.Clean(l.Root)+string(filepath.Separator)) {
			return
		}
		freed += l.DiskUsage(rel)
		os.RemoveAll(abs)
	}
	for _, a := range assets {
		if a.Kind != kind {
			continue
		}
		rm(a.Path)
		if kind == "courseware" {
			rm(ParsedDir(a.Path))
		}
		if kind == "video" {
			os.Remove(l.Abs(a.Path) + ".part")
			os.Remove(l.Abs(a.Path) + ".part.json")
		}
	}
	if lec.Dir != "" {
		switch kind {
		case "slides":
			rm(lec.Dir + "/slides")
		case "courseware":
			if ents, err := os.ReadDir(l.Abs(lec.Dir + "/courseware")); err == nil && len(ents) == 0 {
				os.Remove(l.Abs(lec.Dir + "/courseware"))
			}
		case "transcript":
			rm(lec.Dir + "/transcript.md")
			rm(lec.Dir + "/transcript.srt")
		}
	}
	switch kind {
	case "slides":
		l.Store.ClearSlidePaths(ctx, lectureID)
	case "transcript":
		l.Store.ReplaceSegments(ctx, lectureID, nil)
	}
	if err := l.Store.DeleteAssets(ctx, lectureID, kind); err != nil {
		return freed, err
	}
	return freed, l.WriteLectureJSON(ctx, lectureID)
}

// DiskUsage walks a lecture folder (for the storage screen).
func (l *Library) DiskUsage(rel string) int64 {
	var total int64
	filepath.WalkDir(l.Abs(rel), func(_ string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if fi, err := d.Info(); err == nil {
				total += fi.Size()
			}
		}
		return nil
	})
	return total
}

// SortedKinds is a stable order for asset chips.
func SortedKinds(k []string) []string {
	order := map[string]int{"video": 0, "slides": 1, "courseware": 2, "transcript": 3, "audio": 4, "material": 5}
	sort.Slice(k, func(i, j int) bool { return order[k[i]] < order[k[j]] })
	return k
}
