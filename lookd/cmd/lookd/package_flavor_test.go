package main

import (
	"path/filepath"
	"testing"
)

func TestCanvasPackageDefaultsAreSeparate(t *testing.T) {
	previous := packageFlavor
	defer func() { packageFlavor = previous }()
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	packageFlavor = ""
	data, library := defaultDataDir(), defaultLibrary()
	packageFlavor = "canvas-test"
	if defaultDataDir() == data || defaultLibrary() == library || filepath.Base(defaultDataDir()) != "look-studio-canvas-test" || filepath.Base(defaultLibrary()) != "LookStudioCanvasTest" {
		t.Fatal("test build shares the normal application's default storage")
	}
	packageFlavor = ""
	if defaultDataDir() != data || defaultLibrary() != library {
		t.Fatal("normal package defaults changed")
	}
}
