package library

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path"
	"path/filepath"
	"strings"
	"unicode/utf8"
)

const StudyDocumentLimit = 32 << 20
const StudyAssetLimit = 300 << 20

var ErrStudyConflict = errors.New("画布已被另一个窗口修改，请保留当前副本并重新打开")
var ErrStudyLimit = errors.New("画布或导入文件超过限制")
var ErrStudyInvalid = errors.New("无效的学习画布")

type StudyLayer struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Visible bool   `json:"visible"`
	Locked  bool   `json:"locked"`
}
type StudyCamera struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
	Z float64 `json:"z"`
}
type StudyObject struct {
	ID              string            `json:"id"`
	Type            string            `json:"type"`
	Layer           string            `json:"layer"`
	X               float64           `json:"x"`
	Y               float64           `json:"y"`
	W               float64           `json:"w"`
	H               float64           `json:"h"`
	Title           string            `json:"title"`
	Text            string            `json:"text,omitempty"`
	Path            string            `json:"path,omitempty"`
	Source          string            `json:"source,omitempty"`
	DocumentID      string            `json:"document_id,omitempty"`
	Page            int               `json:"page,omitempty"`
	PageCount       int               `json:"page_count,omitempty"`
	PageAspect      float64           `json:"page_aspect,omitempty"`
	TextBoxes       []StudyTextBox    `json:"text_boxes,omitempty"`
	Generation      string            `json:"generation,omitempty"`
	Blocks          []StudyBlock      `json:"blocks,omitempty"`
	Sources         []StudyAnchor     `json:"sources,omitempty"`
	Responses       map[string]string `json:"responses,omitempty"`
	ConversationID  string            `json:"conversation_id,omitempty"`
	Collapsed       bool              `json:"collapsed,omitempty"`
	ExpandedH       float64           `json:"expanded_h,omitempty"`
	SourceLectureID string            `json:"source_lecture_id,omitempty"`
	OriginalPath    string            `json:"original_path,omitempty"`
	PDFColumn       string            `json:"pdf_column,omitempty"`
}
type StudyStroke struct {
	ID      string       `json:"id"`
	Layer   string       `json:"layer"`
	Anchor  string       `json:"anchor,omitempty"`
	Tool    string       `json:"tool"`
	Color   uint32       `json:"color"`
	Width   float64      `json:"width"`
	Points  [][3]float64 `json:"points"`
	Gesture string       `json:"gesture,omitempty"`
	Page    int          `json:"page,omitempty"`
	Brush   *StudyBrush  `json:"brush,omitempty"`
}

// StudyDocument is a lecture-local vector document, not a Markdown note. See spec 0019.
type StudyDocument struct {
	BaseHash    string            `json:"base_hash,omitempty"`
	Version     int               `json:"version"`
	Revision    int64             `json:"revision"`
	Camera      StudyCamera       `json:"camera"`
	Layers      []StudyLayer      `json:"layers"`
	Objects     []StudyObject     `json:"objects"`
	Strokes     []StudyStroke     `json:"strokes"`
	Connections []StudyConnection `json:"connections,omitempty"`
	AppliedRuns []string          `json:"applied_runs,omitempty"`
}

func emptyStudy() StudyDocument {
	return StudyDocument{Version: 1, Camera: StudyCamera{X: 40, Y: 70, Z: 0.75}, Layers: []StudyLayer{{ID: "main", Name: "学习笔记", Visible: true}}, Objects: []StudyObject{{ID: "lecture", Type: "lecture", Layer: "main", X: 0, Y: 0, W: 880, H: 550, Title: "课程视频"}}, Strokes: []StudyStroke{}}
}
func studyID() string {
	b := make([]byte, 16)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return hex.EncodeToString(b)
}
func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) && math.Abs(v) <= 1e9 }
func validStudyID(v string) bool {
	return len(v) > 0 && len(v) <= 100 && !strings.ContainsAny(v, "/\\\x00")
}

// checkedStudyDir rejects symlinks, including those that remain inside the root.
func checkedStudyDir(root *os.Root, rel string, create bool) error {
	if rel == "" || path.Clean(rel) != rel || strings.HasPrefix(rel, "/") || strings.Contains(rel, "\\") || !strings.HasPrefix(rel, "courses/") {
		return ErrStudyInvalid
	}
	parts := strings.Split(rel, "/")
	for i := range parts {
		if parts[i] == ".." || parts[i] == "." || parts[i] == "" {
			return ErrStudyInvalid
		}
		p := strings.Join(parts[:i+1], "/")
		st, e := root.Lstat(p)
		if os.IsNotExist(e) && create {
			e = root.Mkdir(p, 0700)
			if e == nil {
				st, e = root.Lstat(p)
			}
		}
		if e != nil {
			return e
		}
		if !st.IsDir() || st.Mode()&os.ModeSymlink != 0 {
			return ErrStudyInvalid
		}
	}
	return nil
}
func (l *Library) studyRoot(ctx context.Context, id string) (*os.Root, string, error) {
	lec, e := l.Store.Lecture(ctx, id)
	if e != nil {
		return nil, "", e
	}
	root, e := os.OpenRoot(l.Root)
	if e != nil {
		return nil, "", e
	}
	fail := func(e error) (*os.Root, string, error) { root.Close(); return nil, "", e }
	if lec.Dir == "" {
		c, e := l.Store.Course(ctx, lec.CourseID)
		if e != nil {
			return fail(e)
		}
		if c.Dir == "" {
			c.Dir = "courses/" + l.courseDirName(c) + "-" + fmt.Sprintf("%x", sha256.Sum256([]byte(c.ID)))[:12]
			if e = checkedStudyDir(root, c.Dir, true); e != nil {
				return fail(e)
			}
			if e = seedStudyManifest(root, c.Dir+"/course.json", "look-studio/course@1", c, nil); e != nil {
				return fail(e)
			}
			if e = l.Store.SetCourseDir(ctx, c.ID, c.Dir); e != nil {
				return fail(e)
			}
		}
		lec.Dir = c.Dir + "/" + l.lectureDirName(lec) + "-" + fmt.Sprintf("%x", sha256.Sum256([]byte(lec.ID)))[:12]
		if e = checkedStudyDir(root, lec.Dir, true); e != nil {
			return fail(e)
		}
		if e = seedStudyManifest(root, lec.Dir+"/lecture.json", "look-studio/lecture@1", lec, map[string]any{"begin_at": unixISO(lec.BeginAt), "end_at": unixISO(lec.EndAt), "duration_seconds": lec.DurationS, "course_title": c.Title}); e != nil {
			return fail(e)
		}
		if e = l.Store.SetLectureDir(ctx, id, lec.Dir); e != nil {
			return fail(e)
		}
	}
	if e = checkedStudyDir(root, lec.Dir, true); e != nil {
		return fail(e)
	}
	return root, lec.Dir, nil
}

// First-use manifests keep a streamed lecture discoverable when the SQLite index is rebuilt.
func seedStudyManifest(root *os.Root, rel, schema string, record any, extra map[string]any) error {
	b, e := json.Marshal(record)
	if e != nil {
		return e
	}
	var m map[string]any
	if e = json.Unmarshal(b, &m); e != nil {
		return e
	}
	m["schema"] = schema
	for k, v := range extra {
		m[k] = v
	}
	if st, statErr := root.Lstat(rel); statErr == nil {
		if !st.Mode().IsRegular() {
			return ErrStudyInvalid
		}
		f, e := root.Open(rel)
		if e != nil {
			return e
		}
		defer f.Close()
		var old map[string]any
		e = json.NewDecoder(io.LimitReader(f, 1<<20)).Decode(&old)
		if e != nil || old["id"] != m["id"] {
			return ErrStudyInvalid
		}
		return nil
	} else if !os.IsNotExist(statErr) {
		return statErr
	}
	b, e = json.Marshal(m)
	if e != nil {
		return e
	}
	return writeStudyBytes(root, rel, b)
}
func readStudy(root *os.Root, rel string) (StudyDocument, error) {
	st, e := root.Lstat(rel)
	if os.IsNotExist(e) {
		return emptyStudy(), nil
	}
	if e != nil {
		return StudyDocument{}, e
	}
	if !st.Mode().IsRegular() {
		return StudyDocument{}, ErrStudyInvalid
	}
	f, e := root.Open(rel)
	if e != nil {
		return StudyDocument{}, e
	}
	defer f.Close()
	b, e := io.ReadAll(io.LimitReader(f, StudyDocumentLimit+1))
	if e != nil {
		return StudyDocument{}, e
	}
	if len(b) > StudyDocumentLimit {
		return StudyDocument{}, ErrStudyLimit
	}
	var d StudyDocument
	e = json.Unmarshal(b, &d)
	if e != nil {
		return d, fmt.Errorf("画布文件无法读取：%w", e)
	}
	sum := sha256.Sum256(b)
	d.BaseHash = hex.EncodeToString(sum[:])
	return d, nil
}
func (l *Library) StudyCanvas(ctx context.Context, id string) (StudyDocument, error) {
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	r, dir, e := l.studyRoot(ctx, id)
	if e != nil {
		return StudyDocument{}, e
	}
	defer r.Close()
	return readStudy(r, dir+"/study-canvas.json")
}
func validateStudy(d StudyDocument, root *os.Root, dir string) error {
	invalid := func(s string) error { return fmt.Errorf("%w：%s", ErrStudyInvalid, s) }
	if len(d.AppliedRuns) > 256 {
		return ErrStudyLimit
	}
	for _, id := range d.AppliedRuns {
		if !validStudyID(id) {
			return ErrStudyInvalid
		}
	}
	if (d.Version != 1 && d.Version != 2 && d.Version != 3) || d.Revision < 0 || !finite(d.Camera.X) || !finite(d.Camera.Y) || !finite(d.Camera.Z) || d.Camera.Z < 0.05 || d.Camera.Z > 8 {
		return invalid("版本或视图")
	}
	if len(d.Layers) < 1 || len(d.Layers) > 32 || len(d.Objects) > 2000 || len(d.Strokes) > 30000 {
		return ErrStudyLimit
	}
	layers := map[string]bool{}
	ids := map[string]bool{}
	objects := map[string]bool{}
	lectures := 0
	for _, a := range d.Layers {
		if !validStudyID(a.ID) || layers[a.ID] || len(a.Name) > 240 {
			return invalid("图层")
		}
		layers[a.ID] = true
	}
	asset := func(p string) bool {
		if p == "" {
			return true
		}
		if !strings.HasPrefix(p, dir+"/study-assets/") || path.Clean(p) != p || strings.Contains(p, "\\") {
			return false
		}
		if checkedStudyDir(root, path.Dir(p), false) != nil {
			return false
		}
		st, e := root.Lstat(p)
		return e == nil && st.Mode().IsRegular()
	}
	for _, a := range d.Objects {
		if a.PDFColumn != "" && !validStudyID(a.PDFColumn) {
			return invalid("PDF 列标识")
		}
		if !validStudyID(a.ID) || ids[a.ID] || !layers[a.Layer] || !finite(a.X) || !finite(a.Y) || !finite(a.W) || !finite(a.H) || a.W < 24 || a.H < 24 || a.W > 100000 || a.H > 100000 || len(a.Title) > 960 || len(a.Text) > 800000 || !utf8.ValidString(a.Text) || !asset(a.Path) || !asset(a.Source) {
			return invalid("卡片或素材引用")
		}
		if a.Type == "conversation" && !validStudyID(a.ConversationID) {
			return invalid("对话标识")
		}
		if !finite(a.ExpandedH) || a.ExpandedH < 0 || a.ExpandedH > 100000 {
			return invalid("折叠高度")
		}
		switch a.Type {
		case "pdfdoc", "conversation", "lecture", "text", "image", "pdf", "video", "note", "explanation", "knowledge", "practice":
		default:
			return invalid("卡片类型")
		}
		if a.Page < 0 || a.PageCount < 0 || a.PageCount > 5000 || len(a.TextBoxes) > 20000 {
			return invalid("文档页码或文字位置")
		}
		if a.Type == "pdfdoc" && (!finite(a.PageAspect) || a.PageAspect <= 0 || a.Source == "" || a.Path == "" || a.Page < 1 || a.Page > a.PageCount) {
			return invalid("分页文档")
		}
		if (a.Type == "image" || a.Type == "pdf" || a.Type == "video") && a.Path == "" && !(a.Type == "video" && a.OriginalPath != "") {
			return invalid("缺少素材")
		}
		if a.Type == "lecture" {
			lectures++
			if a.ID != "lecture" {
				return invalid("课次视频标识")
			}
		}
		ids[a.ID] = true
		objects[a.ID] = true
		if e := validateStudyContent(a); e != nil {
			return e
		}
	}
	if lectures != 1 {
		return invalid("须保留一张课次视频卡片")
	}
	n := 0
	for _, a := range d.Strokes {
		if !validStudyID(a.ID) || ids[a.ID] || !layers[a.Layer] || a.Width < 0.1 || a.Width > 200 || !finite(a.Width) || (a.Tool != "pen" && a.Tool != "highlighter") || len(a.Points) < 1 {
			return invalid("笔迹")
		}
		if a.Anchor != "" && !objects[a.Anchor] {
			return invalid("笔迹锚点")
		}
		if a.Gesture != "" && !validStudyID(a.Gesture) {
			return invalid("笔画标识")
		}
		if a.Brush != nil {
			b := a.Brush
			if !finite(b.Opacity) || b.Opacity < .05 || b.Opacity > 1 || !finite(b.Pressure) || b.Pressure < 0 || b.Pressure > 1 || !finite(b.Smoothing) || b.Smoothing < 0 || b.Smoothing > 1 {
				return invalid("笔刷设置")
			}
			switch b.Family {
			case "ballpoint", "fountain", "pencil", "brush", "highlighter":
			default:
				return invalid("笔刷类型")
			}
		}
		ids[a.ID] = true
		n += len(a.Points)
		if n > 500000 {
			return ErrStudyLimit
		}
		for _, p := range a.Points {
			if !finite(p[0]) || !finite(p[1]) || p[2] < 0 || p[2] > 1 || !finite(p[2]) {
				return invalid("笔迹坐标")
			}
		}
	}
	if len(d.Connections) > 4000 {
		return ErrStudyLimit
	}
	for _, c := range d.Connections {
		if !validStudyID(c.ID) || ids[c.ID] || !objects[c.From] || !objects[c.To] || c.From == c.To || len(c.Label) > 960 {
			return invalid("知识关联")
		}
		ids[c.ID] = true
	}
	return nil
}
func (l *Library) SaveStudyCanvas(ctx context.Context, id string, d StudyDocument) (StudyDocument, error) {
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	r, dir, e := l.studyRoot(ctx, id)
	if e != nil {
		return d, e
	}
	defer r.Close()
	old, e := readStudy(r, dir+"/study-canvas.json")
	if e != nil {
		return d, e
	}
	if old.Revision != d.Revision || d.BaseHash != "" && d.BaseHash != old.BaseHash {
		return d, ErrStudyConflict
	}
	for _, object := range d.Objects {
		if object.Type == "video" && object.OriginalPath != "" && object.Path == "" {
			f, err := l.StudyCourseSource(ctx, id, object.OriginalPath)
			if err != nil {
				return d, err
			}
			f.Close()
		}
	}
	if e = validateStudy(d, r, dir); e != nil {
		return d, e
	}
	if old.Version < 3 && d.Version == 3 && old.Revision > 0 {
		previous, err := r.ReadFile(dir + "/study-canvas.json")
		if err != nil {
			return d, err
		}
		backup := dir + "/study-canvas.pre-v3.json"
		if _, err = r.Lstat(backup); os.IsNotExist(err) {
			if err = writeStudyBytes(r, backup, previous); err != nil {
				return d, err
			}
		} else if err != nil {
			return d, err
		}
	}
	d.Revision++
	d.BaseHash = ""
	b, e := json.Marshal(d)
	if e != nil {
		return d, e
	}
	if len(b) > StudyDocumentLimit {
		return d, ErrStudyLimit
	}
	e = writeStudyBytes(r, dir+"/study-canvas.json", b)
	sum := sha256.Sum256(b)
	d.BaseHash = hex.EncodeToString(sum[:])
	return d, e
}
func writeStudyBytes(r *os.Root, rel string, b []byte) error {
	tmp := rel + "." + studyID() + ".tmp"
	f, e := r.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer r.Remove(tmp)
	_, e = f.Write(b)
	if e == nil {
		e = f.Sync()
	}
	if c := f.Close(); e == nil {
		e = c
	}
	if e != nil {
		return e
	}
	return r.Rename(tmp, rel)
}

type StudyImport struct {
	Objects []StudyObject `json:"objects"`
}

// ImportStudyAsset converts in a private temporary directory and publishes the entire asset set with one rename.
func (l *Library) ImportStudyAsset(ctx context.Context, id, name string, reader io.Reader) (StudyImport, error) {
	return l.importStudyAsset(ctx, id, name, reader, false)
}
func (l *Library) ImportStudyModule(ctx context.Context, id, name string, reader io.Reader) (StudyImport, error) {
	return l.importStudyAsset(ctx, id, name, reader, true)
}
func (l *Library) importStudyAsset(ctx context.Context, id, name string, reader io.Reader, paged bool) (StudyImport, error) {
	var out StudyImport
	ext := strings.ToLower(filepath.Ext(name))
	kind := ""
	switch ext {
	case ".png", ".jpg", ".jpeg", ".webp", ".gif":
		kind = "image"
	case ".pdf":
		kind = "pdf"
	case ".txt", ".md", ".markdown":
		kind = "text"
	case ".mp4", ".mov", ".m4v", ".webm", ".mkv":
		kind = "video"
	default:
		return out, fmt.Errorf("%w：支持 PDF、图片、TXT/Markdown 和视频", ErrStudyInvalid)
	}
	l.studyMu.Lock()
	r, dir, e := l.studyRoot(ctx, id)
	l.studyMu.Unlock()
	if e != nil {
		return out, e
	}
	defer r.Close()
	temp, e := os.MkdirTemp("", "look-study-import-")
	if e != nil {
		return out, e
	}
	defer os.RemoveAll(temp)
	source := filepath.Join(temp, "source"+ext)
	f, e := os.OpenFile(source, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if e != nil {
		return out, e
	}
	n, e := io.Copy(f, io.LimitReader(reader, StudyAssetLimit+1))
	ce := f.Close()
	if e == nil {
		e = ce
	}
	if e != nil {
		return out, e
	}
	if n > StudyAssetLimit {
		return out, ErrStudyLimit
	}
	if n == 0 {
		return out, fmt.Errorf("%w：空文件", ErrStudyInvalid)
	}
	object := StudyObject{ID: studyID(), Type: kind, Layer: "main", W: 600, H: 440, Title: Sanitize(name, "素材")}
	switch kind {
	case "text":
		b, e := os.ReadFile(source)
		if e != nil {
			return out, e
		}
		if len(b) > 800000 {
			return out, ErrStudyLimit
		}
		if !utf8.Valid(b) {
			return out, fmt.Errorf("%w：文字文件须为 UTF-8", ErrStudyInvalid)
		}
		object.Text = string(b)
		out.Objects = []StudyObject{object}
	case "pdf":
		if paged {
			page, e := renderStudyPage(ctx, source, temp, 1)
			if e != nil {
				return out, e
			}
			object.PageAspect = float64(page.Width) / float64(page.Height)
			object.Type = "pdfdoc"
			object.Path = page.File
			object.Text = page.Text
			object.Page = 1
			object.PageCount = page.Count
			object.TextBoxes = page.Boxes
			object.W = 600
			object.H = 600*float64(page.Height)/float64(page.Width) + 86
			out.Objects = []StudyObject{object}
			break
		}
		if e = renderStudyPDF(ctx, source, temp); e != nil {
			return out, e
		}
		b, e := os.ReadFile(filepath.Join(temp, "pages.json"))
		if e != nil {
			return out, e
		}
		var pages []struct {
			File   string `json:"file"`
			Width  int    `json:"width"`
			Height int    `json:"height"`
			Text   string `json:"text"`
		}
		if e = json.Unmarshal(b, &pages); e != nil {
			return out, e
		}
		if len(pages) < 1 || len(pages) > 100 {
			return out, ErrStudyLimit
		}
		for i, p := range pages {
			if path.Base(p.File) != p.File || !strings.HasSuffix(p.File, ".png") || p.Width < 1 || p.Height < 1 || int64(p.Width)*int64(p.Height) > 2100000 || len(p.Text) > 800000 {
				return out, ErrStudyLimit
			}
			a := object
			a.ID = studyID()
			a.Path = p.File
			a.Title = fmt.Sprintf("%s · %d", object.Title, i+1)
			a.W = 600
			a.H = 600 * float64(p.Height) / float64(p.Width)
			a.Text = p.Text
			a.Page = i + 1
			a.Y = float64(i) * (a.H + 50)
			out.Objects = append(out.Objects, a)
		}
	default:
		object.Path = "source" + ext
		out.Objects = []StudyObject{object}
	}
	if e = checkedStudyDir(r, dir+"/study-assets", true); e != nil {
		return out, e
	}
	batch := studyID()
	stage := dir + "/study-assets/." + batch
	dest := dir + "/study-assets/" + batch
	if e = r.Mkdir(stage, 0700); e != nil {
		return out, e
	}
	defer r.RemoveAll(stage)
	entries, e := os.ReadDir(temp)
	if e != nil {
		return out, e
	}
	var total int64
	for _, en := range entries {
		if en.IsDir() || en.Type()&os.ModeSymlink != 0 {
			return out, ErrStudyInvalid
		}
		if en.Name() == "pages.json" {
			continue
		}
		s, e := en.Info()
		if e != nil {
			return out, e
		}
		total += s.Size()
		if total > 400<<20 {
			return out, ErrStudyLimit
		}
		src, e := os.Open(filepath.Join(temp, en.Name()))
		if e != nil {
			return out, e
		}
		dst, e := r.OpenFile(stage+"/"+en.Name(), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
		if e != nil {
			src.Close()
			return out, e
		}
		_, e = io.Copy(dst, src)
		src.Close()
		ce = dst.Close()
		if e == nil {
			e = ce
		}
		if e != nil {
			return out, e
		}
	}
	if e = ctx.Err(); e != nil {
		return out, e
	}
	if e = r.Rename(stage, dest); e != nil {
		return out, e
	}
	for i := range out.Objects {
		if out.Objects[i].Path != "" {
			out.Objects[i].Path = dest + "/" + out.Objects[i].Path
		}
		out.Objects[i].Source = dest + "/source" + ext
		out.Objects[i].DocumentID = batch
	}
	return out, nil
}

func (l *Library) StudySource(ctx context.Context, id, rel string) (*os.File, error) {
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	r, dir, e := l.studyRoot(ctx, id)
	if e != nil {
		return nil, e
	}
	defer r.Close()
	if path.Clean(rel) != rel || !strings.HasPrefix(rel, dir+"/") || checkedStudyDir(r, path.Dir(rel), false) != nil {
		return nil, ErrStudyInvalid
	}
	st, e := r.Lstat(rel)
	if e != nil {
		return nil, e
	}
	if !st.Mode().IsRegular() {
		return nil, ErrStudyInvalid
	}
	return r.Open(rel)
}

func (l *Library) ApplySyncFiles(fn func() error) error {
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	return fn()
}
