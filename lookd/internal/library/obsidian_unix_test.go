//go:build unix

package library

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"lookstudio/lookd/internal/store"
)

// A FIFO planted in place of the manifest or a document makes the export
// fail fast instead of blocking forever.
func TestExportObsidianDoesNotBlockOnFIFO(t *testing.T) {
	lib, ctx := newTestLibrary(t)
	if _, err := lib.SaveNote(ctx, store.Note{Title: "n", Body: "x"}); err != nil {
		t.Fatal(err)
	}
	vault := t.TempDir()
	out := filepath.Join(vault, ObsidianFolder)
	if err := os.MkdirAll(out, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := syscall.Mkfifo(filepath.Join(out, "课程库.md"), 0o644); err != nil {
		t.Skip("no FIFOs here:", err)
	}
	if err := syscall.Mkfifo(filepath.Join(out, obsidianManifest), 0o644); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { _, err := lib.ExportObsidian(ctx, vault, ""); done <- err }()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("export wrote over a FIFO")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("export blocked on a FIFO")
	}
}
