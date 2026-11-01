package library

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// A real two-page PDF with independent text streams; no model is used here.
func writeStudyPDFFixture(t *testing.T, p string) {
	t.Helper()
	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
		"",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 792 612] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
		"",
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
	}
	for i, text := range []string{"Canvas PDF first page", "Second page learning material"} {
		body := "BT /F1 24 Tf 72 500 Td (" + text + ") Tj ET\n"
		objects[3+2*i] = fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", len(body), body)
	}
	var b bytes.Buffer
	b.WriteString("%PDF-1.4\n")
	offsets := []int{0}
	for i, obj := range objects {
		offsets = append(offsets, b.Len())
		fmt.Fprintf(&b, "%d 0 obj\n%s\nendobj\n", i+1, obj)
	}
	xref := b.Len()
	fmt.Fprintf(&b, "xref\n0 %d\n0000000000 65535 f \n", len(offsets))
	for _, offset := range offsets[1:] {
		fmt.Fprintf(&b, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&b, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets), xref)
	if err := os.WriteFile(p, b.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
}

// Only absent external dependencies skip integration tests. Strict renderer
// verification fails instead; conversion errors always remain test failures.
func studyPDFDependencyMissing(t *testing.T, message string) {
	t.Helper()
	if os.Getenv("LOOK_REQUIRE_PDF_TESTS") == "1" {
		t.Fatal(message)
	}
	t.Skip(message + "; set LOOK_REQUIRE_PDF_TESTS=1 to require renderer coverage")
}

func requireStudyPoppler(t *testing.T) {
	t.Helper()
	for _, tool := range []string{"pdfinfo", "pdftoppm", "pdftotext"} {
		if _, err := exec.LookPath(tool); err != nil {
			studyPDFDependencyMissing(t, "Poppler integration requires "+tool+" (install poppler-utils)")
		}
	}
}

func TestStudyPopplerRealPDF(t *testing.T) {
	requireStudyPoppler(t)
	dir := t.TempDir()
	source := filepath.Join(dir, "source.pdf")
	writeStudyPDFFixture(t, source)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()
	if err := renderStudyPoppler(ctx, source, dir); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(dir, "pages.json"))
	if err != nil {
		t.Fatal(err)
	}
	var pages []studyPDFPage
	if err = json.Unmarshal(b, &pages); err != nil || len(pages) != 2 {
		t.Fatalf("invalid real pages: %v", err)
	}
	for i, text := range []string{"Canvas PDF first page", "Second page learning material"} {
		p := pages[i]
		if !strings.Contains(p.Text, text) || p.Width > 1400 || p.Height > 1400 || p.Width*p.Height < 1 {
			t.Fatalf("page %d content or bounds", i+1)
		}
		if st, err := os.Stat(filepath.Join(dir, p.File)); err != nil || st.Size() < 500 {
			t.Fatalf("page %d missing raster", i+1)
		}
	}
	if _, err = studyPDFCommand(ctx, "pdfinfo", filepath.Join(dir, "missing.pdf")); err == nil || strings.Contains(err.Error(), dir) {
		t.Fatal("PDF failures must redact filesystem paths")
	}
}

func TestStudyPDFMissingToolsAndOutputBound(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	err := renderStudyPoppler(t.Context(), "source.pdf", t.TempDir())
	if err == nil || !strings.Contains(err.Error(), "设置 → 诊断") {
		t.Fatal("missing dependency must provide a setup action")
	}
	var output limitedPDFOutput
	if _, err := output.Write(make([]byte, 1<<20)); err != nil {
		t.Fatal(err)
	}
	if _, err := output.Write([]byte("x")); err != ErrStudyLimit || output.Len() != 1<<20 {
		t.Fatal("oversized subprocess output was retained")
	}
}

func TestStudyPDFPageLimitBeforeRasterization(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "rendered")
	for _, name := range []string{"pdfinfo", "pdftoppm", "pdftotext"} {
		body := "#!/bin/sh\nprintf 'Pages: 101\\n'\n"
		if name != "pdfinfo" {
			body = "#!/bin/sh\nprintf x > '" + marker + "'\n"
		}
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0700); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
	if err := renderStudyPoppler(t.Context(), "source.pdf", dir); err == nil || !strings.Contains(err.Error(), "1–100") {
		t.Fatal("oversized PDF was not rejected")
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatal("oversized PDF was rasterized before checking the page count")
	}
}

func TestStudyPagedPDFRealSelectionAndRestore(t *testing.T) {
	if runtime.GOOS == "darwin" {
		exe, _ := os.Executable()
		if _, e := os.Stat(filepath.Join(filepath.Dir(exe), "look-study-pdf")); e != nil {
			studyPDFDependencyMissing(t, "run compiled library.test beside the built PDFKit helper")
		}
	} else {
		requireStudyPoppler(t)
	}
	l, _ := reviewFixture(t)
	ctx := t.Context()
	source := filepath.Join(t.TempDir(), "two.pdf")
	writeStudyPDFFixture(t, source)
	f, e := os.Open(source)
	if e != nil {
		t.Fatal(e)
	}
	defer f.Close()
	out, e := l.ImportStudyModule(ctx, "one", "two.pdf", f)
	if e != nil {
		t.Fatal(e)
	}
	if len(out.Objects) != 1 || out.Objects[0].Type != "pdfdoc" || out.Objects[0].PageCount != 2 || len(out.Objects[0].TextBoxes) == 0 {
		t.Fatal("not a paged document with real text geometry", out)
	}
	first := out.Objects[0]
	if _, e = os.Stat(filepath.Join(l.Root, filepath.Dir(first.Path), "page-2.png")); !os.IsNotExist(e) {
		t.Fatal("second page rendered eagerly", e)
	}
	d, _ := l.StudyCanvas(ctx, "one")
	d.Objects = append(d.Objects, first)
	d.Version = 3
	d, e = l.SaveStudyCanvas(ctx, "one", d)
	if e != nil {
		t.Fatal(e)
	}
	second, e := l.StudyPDFPage(ctx, "one", first.Source, 2)
	if e != nil || !strings.Contains(second.Text, "Second") || len(second.Boxes) == 0 {
		t.Fatal(e, second)
	}
	context, e := l.StudyContext(ctx, "one", StudyContextRequest{Revision: d.Revision, Objects: []string{first.ID}, ObjectPages: map[string]int{first.ID: 2}, Selection: StudySelection{ObjectID: first.ID, Start: 0, End: 6}})
	if e != nil || len(context.Sources) != 1 || context.Sources[0].Text != "Second" || context.Sources[0].Anchor.Page != 2 {
		t.Fatal(e, context)
	}
	if _, e = l.StudyPDFPage(ctx, "one", first.Source, 3); e == nil {
		t.Fatal("accepted out-of-range page")
	}
}
