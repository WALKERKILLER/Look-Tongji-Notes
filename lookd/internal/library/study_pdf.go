package library

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image/png"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"time"
)

// macOS uses the bundled PDFKit helper; the Android Ubuntu workspace uses
// Poppler's documented CLI: https://manpages.ubuntu.com/manpages/noble/man1/pdftoppm.1.html
func renderStudyPDF(ctx context.Context, source, output string) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	if runtime.GOOS == "linux" {
		return renderStudyPoppler(ctx, source, output)
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	_, err = studyPDFCommand(ctx, filepath.Join(filepath.Dir(exe), "look-study-pdf"), source, output)
	return err
}

type studyPDFPage struct {
	File   string `json:"file"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Text   string `json:"text"`
}

// limitedPDFOutput stops malformed files or tools from allocating unbounded output.
type limitedPDFOutput struct{ bytes.Buffer }

func (w *limitedPDFOutput) Write(p []byte) (int, error) {
	if w.Len()+len(p) > 1<<20 {
		return 0, ErrStudyLimit
	}
	return w.Buffer.Write(p)
}

func studyPDFCommand(ctx context.Context, name string, args ...string) ([]byte, error) {
	return studyPDFCommandFiles(ctx, nil, name, args...)
}
func studyPDFCommandFiles(ctx context.Context, files []*os.File, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.ExtraFiles = files
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	var out limitedPDFOutput
	cmd.Stdout, cmd.Stderr = &out, io.Discard
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("PDF 处理超时或已取消：%w", ctx.Err())
		}
		// Tool output can contain the document's text or filesystem paths.
		return nil, fmt.Errorf("%w：PDF 处理失败，文件可能损坏、加密或超过限制", ErrStudyInvalid)
	}
	return out.Bytes(), nil
}

var studyPDFPages = regexp.MustCompile(`(?m)^Pages:\s+([0-9]+)\s*$`)

func renderStudyPoppler(ctx context.Context, source, output string) error {
	for _, tool := range []string{"pdfinfo", "pdftoppm", "pdftotext"} {
		if _, err := exec.LookPath(tool); err != nil {
			return fmt.Errorf("PDF 组件未安装：请到设置 → 诊断安装 PDF 组件（poppler-utils）")
		}
	}
	info, err := studyPDFCommand(ctx, "pdfinfo", source)
	if err != nil {
		return err
	}
	m := studyPDFPages.FindSubmatch(info)
	if len(m) != 2 {
		return ErrStudyInvalid
	}
	n, _ := strconv.Atoi(string(m[1]))
	if n < 1 || n > 100 {
		return fmt.Errorf("%w：PDF 须为 1–100 页，请拆分后导入", ErrStudyLimit)
	}
	pages := make([]studyPDFPage, 0, n)
	var total int64
	for page := 1; page <= n; page++ {
		number := strconv.Itoa(page)
		file := "page-" + number + ".png"
		prefix := filepath.Join(output, "page-"+number)
		// Render one page at a time, with at most 1400px on either axis.
		if _, err = studyPDFCommand(ctx, "pdftoppm", "-f", number, "-l", number, "-singlefile", "-scale-to", "1400", "-png", source, prefix); err != nil {
			return err
		}
		f, err := os.Open(prefix + ".png")
		if err != nil {
			return err
		}
		cfg, decodeErr := png.DecodeConfig(io.LimitReader(f, 1<<20))
		st, statErr := f.Stat()
		f.Close()
		if decodeErr != nil || statErr != nil || cfg.Width < 1 || cfg.Height < 1 || cfg.Width > 1400 || cfg.Height > 1400 {
			return ErrStudyLimit
		}
		total += st.Size()
		if total > StudyAssetLimit {
			return ErrStudyLimit
		}
		text, err := studyPDFCommand(ctx, "pdftotext", "-f", number, "-l", number, "-enc", "UTF-8", source, "-")
		if err != nil {
			return err
		}
		if len(text) > 800000 {
			return ErrStudyLimit
		}
		pages = append(pages, studyPDFPage{file, cfg.Width, cfg.Height, string(text)})
	}
	b, err := json.Marshal(pages)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(output, "pages.json"), b, 0600)
}
