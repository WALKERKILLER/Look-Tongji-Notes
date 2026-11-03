package datasync

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestFolderThreeDeviceOfflineEditsAndDeletion(t *testing.T) {
	for _, order := range [][]int{{0, 1, 2}, {0, 2, 1}, {1, 0, 2}, {1, 2, 0}, {2, 0, 1}, {2, 1, 0}} {
		t.Run(fmt.Sprint(order), func(t *testing.T) {
			remote := t.TempDir()
			devices := make([]*Service, 3)
			for i := range devices {
				devices[i], _ = folderFixture(t)
				configureTest(t, devices[i], remote)
			}
			rel := "courses/pilot/note.md"
			writeFolderTest(t, devices[0].Roots.Library, "courses/pilot/course.json", `{"id":"local-pilot"}`)
			writeFolderTest(t, devices[0].Roots.Library, rel, "base")
			for round := 0; round < 2; round++ {
				for _, d := range devices {
					runFolderTest(t, d)
				}
			}
			for i, d := range devices {
				writeFolderTest(t, d.Roots.Library, rel, fmt.Sprintf("offline-%d", i))
				stamp := time.Unix(1700000000+int64(i), 0)
				if err := os.Chtimes(filepath.Join(d.Roots.Library, rel), stamp, stamp); err != nil {
					t.Fatal(err)
				}
			}
			converge := func() {
				for round := 0; round < 3; round++ {
					for _, i := range order {
						runFolderTest(t, devices[i])
					}
				}
			}
			converge()
			for _, d := range devices {
				assertFolderBytes(t, d.Roots.Library, rel, "offline-2")
			}
			if err := os.Remove(filepath.Join(devices[0].Roots.Library, rel)); err != nil {
				t.Fatal(err)
			}
			writeFolderTest(t, devices[1].Roots.Library, rel, "edited while peer deleted")
			converge()
			for _, d := range devices {
				assertFolderBytes(t, d.Roots.Library, rel, "edited while peer deleted")
			}
		})
	}
}

type failedFolderReader struct{ sent bool }

func (r *failedFolderReader) Read(p []byte) (int, error) {
	if !r.sent {
		r.sent = true
		return copy(p, []byte("incomplete")), nil
	}
	return 0, io.ErrUnexpectedEOF
}

func TestFolderInterruptedPublicationKeepsPreviousManifest(t *testing.T) {
	root, err := os.OpenRoot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	f := &folderStorage{root: root}
	ctx := context.Background()
	path := "devices/abc.json"
	if err := f.put(ctx, path, strings.NewReader("previous")); err != nil {
		t.Fatal(err)
	}
	if err := f.put(ctx, path, &failedFolderReader{}); !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatal(err)
	}
	b, err := f.get(ctx, path)
	if err != nil || string(b) != "previous" {
		t.Fatal(string(b), err)
	}
	dir, err := root.Open("devices")
	if err != nil {
		t.Fatal(err)
	}
	defer dir.Close()
	entries, err := dir.ReadDir(-1)
	if err != nil || len(entries) != 1 {
		t.Fatal("temporary upload leaked", entries, err)
	}
	if err := f.put(ctx, path, strings.NewReader("complete retry")); err != nil {
		t.Fatal(err)
	}
	b, err = f.get(ctx, path)
	if err != nil || string(b) != "complete retry" {
		t.Fatal(string(b), err)
	}
}

func TestFolderRenameFailureDoesNotRemoveExistingTarget(t *testing.T) {
	root, err := os.OpenRoot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	if err := root.MkdirAll("devices/abc.json", 0700); err != nil {
		t.Fatal(err)
	}
	f := &folderStorage{root: root}
	if err := f.put(context.Background(), "devices/abc.json", strings.NewReader("replacement")); err == nil {
		t.Fatal("rename failure bypassed by deleting the target")
	}
	st, err := root.Stat("devices/abc.json")
	if err != nil || !st.IsDir() {
		t.Fatal("existing target was removed", st, err)
	}
}
