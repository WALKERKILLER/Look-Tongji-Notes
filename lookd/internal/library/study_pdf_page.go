package library

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"image/png"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
)

type StudyTextBox struct {
	Start int     `json:"start"`
	End   int     `json:"end"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	W     float64 `json:"w"`
	H     float64 `json:"h"`
}
type StudyPDFPage struct {
	File   string         `json:"file"`
	Width  int            `json:"width"`
	Height int            `json:"height"`
	Text   string         `json:"text"`
	Count  int            `json:"count"`
	Boxes  []StudyTextBox `json:"boxes"`
}

// Each request renders exactly one page. Images and text have independent bounded outputs.
func renderStudyPage(ctx context.Context, source, output string, page int, files ...*os.File) (StudyPDFPage, error) {
	var out StudyPDFPage
	if len(files) > 0 {
		source = "/dev/fd/3"
	}
	run := func(ctx context.Context, name string, args ...string) ([]byte, error) {
		return studyPDFCommandFiles(ctx, files, name, args...)
	}
	if page < 1 || page > 5000 {
		return out, ErrStudyInvalid
	}
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	if runtime.GOOS == "darwin" {
		exe, e := os.Executable()
		if e != nil {
			return out, e
		}
		_, e = run(ctx, filepath.Join(filepath.Dir(exe), "look-study-pdf"), source, output, strconv.Itoa(page))
		if e != nil {
			return out, e
		}
		b, e := os.ReadFile(filepath.Join(output, "page.json"))
		if e != nil {
			return out, e
		}
		e = json.Unmarshal(b, &out)
		return out, e
	}
	for _, tool := range []string{"pdfinfo", "pdftoppm", "pdftotext"} {
		if _, e := exec.LookPath(tool); e != nil {
			return out, fmt.Errorf("PDF 组件未安装：请到设置 → 诊断安装 PDF 组件（poppler-utils）")
		}
	}
	info, e := run(ctx, "pdfinfo", source)
	if e != nil {
		return out, e
	}
	m := studyPDFPages.FindSubmatch(info)
	if len(m) != 2 {
		return out, ErrStudyInvalid
	}
	count, _ := strconv.Atoi(string(m[1]))
	if count < 1 || count > 5000 || page > count {
		return out, ErrStudyLimit
	}
	number := strconv.Itoa(page)
	prefix := filepath.Join(output, "page-"+number)
	if _, e = run(ctx, "pdftoppm", "-f", number, "-l", number, "-singlefile", "-scale-to", "1400", "-png", source, prefix); e != nil {
		return out, e
	}
	f, e := os.Open(prefix + ".png")
	if e != nil {
		return out, e
	}
	cfg, e := png.DecodeConfig(io.LimitReader(f, 1<<20))
	f.Close()
	if e != nil {
		return out, e
	}
	raw, e := run(ctx, "pdftotext", "-f", number, "-l", number, "-bbox", "-enc", "UTF-8", source, "-")
	if e != nil {
		return out, e
	}
	var doc struct {
		Body struct {
			Doc struct {
				Pages []struct {
					Width  float64 `xml:"width,attr"`
					Height float64 `xml:"height,attr"`
					Words  []struct {
						X1   float64 `xml:"xMin,attr"`
						Y1   float64 `xml:"yMin,attr"`
						X2   float64 `xml:"xMax,attr"`
						Y2   float64 `xml:"yMax,attr"`
						Text string  `xml:",chardata"`
					} `xml:"word"`
				} `xml:"page"`
			} `xml:"doc"`
		} `xml:"body"`
	}
	if e = xml.Unmarshal(raw, &doc); e != nil {
		return out, e
	}
	out = StudyPDFPage{File: "page-" + number + ".png", Width: cfg.Width, Height: cfg.Height, Count: count, Boxes: []StudyTextBox{}}
	offset := 0
	for _, p := range doc.Body.Doc.Pages {
		if p.Width <= 0 || p.Height <= 0 {
			return out, ErrStudyInvalid
		}
		for _, w := range p.Words {
			if len(out.Boxes) > 20000 {
				return out, ErrStudyLimit
			}
			if out.Text != "" {
				out.Text += " "
				offset++
			}
			start := offset
			out.Text += w.Text
			offset += len(utf16.Encode([]rune(w.Text)))
			out.Boxes = append(out.Boxes, StudyTextBox{start, offset, w.X1 / p.Width, w.Y1 / p.Height, (w.X2 - w.X1) / p.Width, (w.Y2 - w.Y1) / p.Height})
		}
	}
	return out, nil
}
func (l *Library) StudyPDFPage(ctx context.Context, lecture, source string, page int) (StudyPDFPage, error) {
	var out StudyPDFPage
	if page < 1 || page > 5000 || path.Base(source) != "source.pdf" {
		return out, ErrStudyInvalid
	}
	f, e := l.StudySource(ctx, lecture, source)
	if e != nil {
		return out, e
	}
	defer f.Close()
	root, e := os.OpenRoot(l.Root)
	if e != nil {
		return out, e
	}
	defer root.Close()
	dir := path.Dir(source)
	cached := dir + "/page-" + strconv.Itoa(page) + ".json"
	if b, e := root.ReadFile(cached); e == nil && len(b) < 2<<20 {
		if json.Unmarshal(b, &out) == nil {
			if _, e = root.Stat(out.File); e == nil {
				return out, nil
			}
		}
	}
	temp, e := os.MkdirTemp("", "look-pdf-page-")
	if e != nil {
		return out, e
	}
	defer os.RemoveAll(temp)
	out, e = renderStudyPage(ctx, "", temp, page, f)
	if e != nil {
		return out, e
	}
	image, e := os.ReadFile(filepath.Join(temp, out.File))
	if e != nil {
		return out, e
	}
	if len(image) > 8<<20 {
		return out, ErrStudyLimit
	}
	out.File = dir + "/" + out.File
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	if e = writeStudyBytes(root, out.File, image); e != nil {
		return out, e
	}
	b, e := json.Marshal(out)
	if e != nil {
		return out, e
	}
	e = writeStudyBytes(root, cached, b)
	// Keep the current saved page and at most 32 recent page images in this document's cache.
	entries, _ := fs.ReadDir(root.FS(), dir)
	type cachedPage struct {
		name string
		at   int64
	}
	var candidates []cachedPage
	pinned := map[string]bool{out.File: true}
	if lec, err := l.Store.Lecture(ctx, lecture); err == nil {
		if doc, err := readStudy(root, lec.Dir+"/study-canvas.json"); err == nil {
			for _, o := range doc.Objects {
				pinned[o.Path] = true
			}
		}
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "page-") && strings.HasSuffix(entry.Name(), ".png") && !pinned[dir+"/"+entry.Name()] {
			if info, err := entry.Info(); err == nil {
				candidates = append(candidates, cachedPage{entry.Name(), info.ModTime().UnixNano()})
			}
		}
	}
	sort.Slice(candidates, func(i, j int) bool { return candidates[i].at > candidates[j].at })
	for i := 32; i < len(candidates); i++ {
		root.Remove(dir + "/" + candidates[i].name)
		root.Remove(dir + "/" + strings.TrimSuffix(candidates[i].name, ".png") + ".json")
	}

	return out, e
}
