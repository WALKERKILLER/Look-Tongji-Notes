package library

import (
	"context"
	"encoding/json"
	"errors"
	"lookstudio/lookd/internal/store"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestStudyCanvasPersistenceRevisionAndLimits(t *testing.T) {
	l, _ := reviewFixture(t)
	ctx := context.Background()
	d, e := l.StudyCanvas(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	if d.Revision != 0 || len(d.Objects) != 1 {
		t.Fatal(d)
	}
	d.Objects[0].PDFColumn = "column-owner"
	d.Strokes = []StudyStroke{{ID: "s", Layer: "main", Tool: "pen", Color: 0xff111111, Width: 3, Points: [][3]float64{{1, 2, .5}, {5, 6, 1}}}}
	saved, e := l.SaveStudyCanvas(ctx, "one", d)
	if e != nil || saved.Revision != 1 {
		t.Fatal(e, saved)
	}
	if _, e = l.SaveStudyCanvas(ctx, "one", d); !errors.Is(e, ErrStudyConflict) {
		t.Fatal("lost update accepted", e)
	}
	again, e := l.StudyCanvas(ctx, "one")
	if e != nil || len(again.Strokes) != 1 || again.Strokes[0].Points[1][0] != 5 || again.Objects[0].PDFColumn != "column-owner" {
		t.Fatal(e, again)
	}
	invalid := again
	invalid.Strokes[0].Points[0][2] = 2
	if _, e = l.SaveStudyCanvas(ctx, "one", invalid); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal("pressure accepted", e)
	}
	invalid = again
	invalid.Strokes = nil
	invalid.Layers = make([]StudyLayer, 33)
	if _, e = l.SaveStudyCanvas(ctx, "one", invalid); !errors.Is(e, ErrStudyLimit) {
		t.Fatal("layers accepted", e)
	}
	if _, e = l.StudyCanvas(ctx, "missing"); e == nil {
		t.Fatal("missing lecture accepted")
	}
}

func TestStudyCanvasFirstUseSurvivesIndexRebuild(t *testing.T) {
	l, _ := reviewFixture(t)
	ctx := context.Background()
	if e := l.Store.UpsertCourse(ctx, store.Course{ID: "stream-course", Title: "流媒体课程"}); e != nil {
		t.Fatal(e)
	}
	if e := l.Store.UpsertLectures(ctx, []store.Lecture{{ID: "stream-lecture", CourseID: "stream-course", Title: "尚未下载的课次", HasPlayback: true}}); e != nil {
		t.Fatal(e)
	}
	d, e := l.StudyCanvas(ctx, "stream-lecture")
	if e != nil {
		t.Fatal(e)
	}
	d, e = l.SaveStudyCanvas(ctx, "stream-lecture", d)
	if e != nil {
		t.Fatal(e)
	}
	rebuilt, e := store.Open(filepath.Join(t.TempDir(), "rebuilt.db"))
	if e != nil {
		t.Fatal(e)
	}
	defer rebuilt.Close()
	restored, e := Open(l.Root, rebuilt)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = restored.Reindex(ctx); e != nil {
		t.Fatal(e)
	}
	again, e := restored.StudyCanvas(ctx, "stream-lecture")
	if e != nil || again.Revision != d.Revision {
		t.Fatal("streamed lecture canvas lost", e, again)
	}
}
func TestStudyCanvasConcurrentSaveAndSafeAssets(t *testing.T) {
	l, _ := reviewFixture(t)
	ctx := context.Background()
	d, e := l.StudyCanvas(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	for range 2 {
		wg.Go(func() { _, e := l.SaveStudyCanvas(ctx, "one", d); errs <- e })
	}
	wg.Wait()
	close(errs)
	wins, conflicts := 0, 0
	for e := range errs {
		if e == nil {
			wins++
		} else if errors.Is(e, ErrStudyConflict) {
			conflicts++
		} else {
			t.Fatal(e)
		}
	}
	if wins != 1 || conflicts != 1 {
		t.Fatal(wins, conflicts)
	}
	a, e := l.ImportStudyAsset(ctx, "one", "说明.md", strings.NewReader("# 课程\n测试"))
	if e != nil || len(a.Objects) != 1 || a.Objects[0].Text != "# 课程\n测试" {
		t.Fatal(a, e)
	}
	d, e = l.StudyCanvas(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	d.Objects = append(d.Objects, a.Objects...)
	d, e = l.SaveStudyCanvas(ctx, "one", d)
	if e != nil {
		t.Fatal(e)
	}
	source, e := l.StudySource(ctx, "one", a.Objects[0].Source)
	if e != nil {
		t.Fatal(e)
	}
	source.Close()
	if _, e = l.StudySource(ctx, "one", "../../outside"); e == nil {
		t.Fatal("traversal accepted")
	}
	_, lec, _, e := l.EnsureLecture(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	os.Symlink(t.TempDir(), l.Abs(lec.Dir+"/study-assets/linked"))
	d.Objects[1].Source = lec.Dir + "/study-assets/linked/private.txt"
	if _, e = l.SaveStudyCanvas(ctx, "one", d); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal("symlink accepted", e)
	}
	d, e = l.StudyCanvas(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	os.Symlink(t.TempDir(), l.Abs(lec.Dir+"/unsafe"))
	if _, e = l.StudySource(ctx, "one", lec.Dir+"/unsafe/file.md"); e == nil {
		t.Fatal("symlink source accepted")
	}
	if _, e = l.ImportStudyAsset(ctx, "one", "bad.md", strings.NewReader(string([]byte{0xff}))); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal(e)
	}
	if _, e = l.ImportStudyAsset(ctx, "one", "large.txt", strings.NewReader(strings.Repeat("a", 800001))); !errors.Is(e, ErrStudyLimit) {
		t.Fatal(e)
	}
}

func TestStudyCanvasSameRevisionRemoteReplacementCannotOverwrite(t *testing.T) {
	l, _ := reviewFixture(t)
	ctx := context.Background()
	d, e := l.StudyCanvas(ctx, "one")
	if e != nil {
		t.Fatal(e)
	}
	d, e = l.SaveStudyCanvas(ctx, "one", d)
	if e != nil {
		t.Fatal(e)
	}
	remote := d
	remote.Objects = append([]StudyObject{}, d.Objects...)
	remote.Objects[0].Title = "other device"
	remote.BaseHash = ""
	b, e := json.Marshal(remote)
	if e != nil {
		t.Fatal(e)
	}
	lec, _ := l.Store.Lecture(ctx, "one")
	p := filepath.Join(l.Root, lec.Dir, "study-canvas.json")
	os.WriteFile(p, b, 0600)
	if _, e = l.SaveStudyCanvas(ctx, "one", d); !errors.Is(e, ErrStudyConflict) {
		t.Fatal("same revision but different content was overwritten", e)
	}
	got, _ := os.ReadFile(p)
	if string(got) != string(b) {
		t.Fatal("remote content changed on rejection")
	}
}
