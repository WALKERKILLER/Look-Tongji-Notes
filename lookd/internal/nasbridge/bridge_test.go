package nasbridge

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func fixture(t *testing.T, root, rel, text string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(text), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestUnconfiguredBridgeDoesNotUseImplicitHostOrFolders(t *testing.T) {
	t.Setenv("LOOK_NAS_HOST", "")
	t.Setenv("LOOK_NAS_COURSES", "")
	t.Setenv("LOOK_NAS_CALENDAR", "")
	b := New()
	if b.Root != "" || b.Calendar != "" || b.Alias != "" {
		t.Fatal("personal deployment defaults must not be inferred")
	}
	if _, err := b.run(context.Background(), "python3 -", probe); err == nil {
		t.Fatal("unconfigured SSH must be refused before starting a process")
	}
	d := b.Snapshot(context.Background(), false)
	if d["online"] != false || !strings.Contains(d["error"].(string), "LOOK_NAS_HOST") {
		t.Fatal("missing configuration is not actionable", d)
	}
}

func TestSnapshotPreservesObservationOfflineAndNeverStarts(t *testing.T) {
	calls := 0
	b := &Bridge{Run: func(ctx context.Context, command, input string) ([]byte, error) {
		calls++
		if command != "python3 -" || input != probe {
			t.Fatal("unexpected remote command")
		}
		if calls > 1 {
			return nil, errors.New("private error content")
		}
		return []byte(`{"observed_at":"2026-10-24T00:00:00Z","jobs":[{"generation_state":"failed","submission_state":"unconfirmed"}],"services":[{"result":"success"}]}`), nil
	}}
	a := b.Snapshot(context.Background(), false)
	if a["online"] != true {
		t.Fatal(a)
	}
	b.Snapshot(context.Background(), true)
	if calls != 1 {
		t.Fatal("refresh ignored throttle")
	}
	b.attempted = time.Now().Add(-time.Minute)
	a = b.Snapshot(context.Background(), false)
	if a["online"] != false || a["observed_at"] != "2026-10-24T00:00:00Z" || len(a["jobs"].([]any)) != 1 {
		t.Fatal(a)
	}
	if strings.Contains(a["error"].(string), "private") {
		t.Fatal("raw transport error exposed")
	}
}

func TestStartAllowlistDuplicateActiveAndUnknown(t *testing.T) {
	for _, tc := range []struct {
		name, state string
		fail        bool
		starts      int
	}{
		{"accepted", "inactive", false, 1}, {"active", "activating", false, 0}, {"unknown", "inactive", true, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			starts := 0
			b := &Bridge{Run: func(ctx context.Context, command, input string) ([]byte, error) {
				if strings.Contains(command, "show") {
					return []byte(tc.state), nil
				}
				if command != "systemctl --user start --no-block course-homework.service" || input != "" {
					t.Fatal(command)
				}
				starts++
				if tc.fail {
					return nil, context.DeadlineExceeded
				}
				return nil, nil
			}}
			if _, err := b.Start(context.Background(), "homework; touch /tmp/bad"); err == nil {
				t.Fatal("arbitrary command accepted")
			}
			result, err := b.Start(context.Background(), "homework")
			if tc.starts == 0 && err == nil {
				t.Fatal("running task accepted")
			}
			if tc.fail && (err != nil || result["state"] != "unknown") {
				t.Fatal("lost ambiguous outcome", result, err)
			}
			b.Start(context.Background(), "homework")
			if starts != tc.starts {
				t.Fatalf("got %d starts", starts)
			}
		})
	}
}

func TestConcurrentStartOnlyOnce(t *testing.T) {
	starts := 0
	b := &Bridge{Run: func(ctx context.Context, command, input string) ([]byte, error) {
		if strings.Contains(command, "show") {
			return []byte("inactive"), nil
		}
		starts++
		return nil, nil
	}}
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); b.Start(context.Background(), "calendar") }()
	}
	wg.Wait()
	if starts != 1 {
		t.Fatal(starts)
	}
}

func TestFileRootsAndBoundedUnicode(t *testing.T) {
	root, outside := t.TempDir(), t.TempDir()
	fixture(t, root, "C/3.课程资料/notes.md", strings.Repeat("中", 13000))
	fixture(t, root, "C/3.课程资料/.env", "private")
	fixture(t, root, "C/3.课程资料/.cache/secret.md", "private")
	fixture(t, root, "C/3.课程资料/node_modules/secret.md", "private")
	fixture(t, root, "C/private/secret.md", "private")
	fixture(t, outside, "secret.md", "outside")
	if err := os.Symlink(filepath.Join(outside, "secret.md"), filepath.Join(root, "C/3.课程资料/link.md")); err != nil {
		t.Fatal(err)
	}
	b := &Bridge{Root: root}
	files, err := b.Files()
	if err != nil || len(files) != 1 {
		t.Fatal(files, err)
	}
	d, err := b.Text(files[0].ID)
	if err != nil || d["truncated"] != true || len([]rune(d["text"].(string))) != 12000 {
		t.Fatal(err)
	}
	if _, _, err = b.Open("../../secret.md"); err == nil {
		t.Fatal("path escape accepted")
	}
	os.Remove(filepath.Join(root, files[0].Path))
	os.Symlink(filepath.Join(outside, "secret.md"), filepath.Join(root, files[0].Path))
	if f, _, err := b.Open(files[0].ID); err == nil {
		f.Close()
		t.Fatal("replacement symlink accepted")
	}
}

func TestDeadlineMidnightAndInvalidFiles(t *testing.T) {
	root := t.TempDir()
	fixture(t, root, "a.md", "---\ntitle: \"Course · HW\"\ncourse: \"C\"\ndue: \"2026-10-26T00:00:00+08:00\"\ncompleted: false\ngenerated_key: stable\n---\nhttps://elearning.fudan.edu.cn/courses/123/assignments/456\n")
	fixture(t, root, "invalid.md", "---\ndue: tomorrow\n---")
	fixture(t, root, ".private.md", "---\ndue: 2026-10-25T00:00:00+08:00\n---")
	ds, err := (&Bridge{Calendar: root}).Deadlines()
	if err != nil || len(ds) != 1 {
		t.Fatal(ds, err)
	}
	if ds[0]["due"] != "2026-10-26T00:00:00+08:00" || ds[0]["assignment_id"] != "456" || ds[0]["id"] != "nas:stable" {
		t.Fatal(ds)
	}
}

func TestBoundedTransportAndCancellation(t *testing.T) {
	var w bounded
	if _, err := w.Write(make([]byte, 2<<20)); err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("x")); err == nil {
		t.Fatal("unbounded response")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	b := &Bridge{Alias: "does-not-exist"}
	if _, err := b.run(ctx, "python3 -", probe); err == nil {
		t.Fatal("cancelled SSH succeeded")
	}
}

func TestFilesReportsUnreadableSubdirectory(t *testing.T) {
	root := t.TempDir()
	fixture(t, root, "A/3.课程资料/visible.md", "visible")
	fixture(t, root, "B/3.课程资料/blocked/hidden.md", "unreadable")
	blocked := filepath.Join(root, "B/3.课程资料/blocked")
	if err := os.Chmod(blocked, 0000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(blocked, 0700) })
	if _, err := os.ReadDir(blocked); err == nil {
		t.Skip("filesystem/user does not enforce directory read permissions")
	}
	files, err := (&Bridge{Root: root}).Files()
	if err == nil {
		t.Fatal("partial scan reported success")
	}
	if len(files) != 1 || files[0].Course != "A" {
		t.Fatalf("expected partial prefix plus error, got %v, %v", files, err)
	}
}
