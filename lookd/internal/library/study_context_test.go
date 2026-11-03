package library

import (
	"context"
	"errors"
	"lookstudio/lookd/internal/store"
	"strings"
	"testing"
)

func TestStudyContextSelectionTimesAndVisibility(t *testing.T) {
	l, _ := reviewFixture(t)
	ctx := context.Background()
	imported, e := l.ImportStudyAsset(ctx, "one", "selection.md", strings.NewReader("前😀后选中内容\n不要把未选段送给模型"))
	if e != nil {
		t.Fatal(e)
	}
	d, _ := l.StudyCanvas(ctx, "one")
	d.Version = 2
	source := imported.Objects[0]
	source.ID = "selection"
	source.Title = "实验要求"
	d.Objects = append(d.Objects, source)
	hidden := source
	hidden.ID = "hidden"
	hidden.Layer = "hidden"
	hidden.Text = "不应读取的秘密课程内容"
	d.Objects = append(d.Objects, hidden)
	d.Layers = append(d.Layers, StudyLayer{ID: "hidden", Name: "隐藏"})
	d, e = l.SaveStudyCanvas(ctx, "one", d)
	if e != nil {
		t.Fatal(e)
	}
	e = l.Store.ReplaceSegments(ctx, "one", []store.Segment{{Idx: 0, StartMs: 0, EndMs: 5000, Text: "很久以前的讲解"}, {Idx: 1, StartMs: 512000, EndMs: 550000, Text: "缓存失效需读取主存"}})
	if e != nil {
		t.Fatal(e)
	}
	q := StudyContextRequest{Revision: d.Revision, Objects: []string{"selection"}, Selection: StudySelection{ObjectID: "selection", Start: 3, End: 6}, IncludeVideo: true, VideoMs: 530000}
	c, e := l.StudyContext(ctx, "one", q)
	if e != nil {
		t.Fatal(e)
	}
	if len(c.Sources) != 2 || c.Sources[0].Text != "后选中" || !strings.Contains(c.Sources[1].Text, "缓存失效") || strings.Contains(c.Sources[1].Text, "以前") {
		t.Fatalf("context: %+v", c)
	}
	a := c.Sources[0].Anchor
	if a.WorkspaceID != "one" || a.ObjectID != "selection" || a.Start != 3 || a.End != 6 || a.Fingerprint == "" {
		t.Fatal(a)
	}
	d.Camera.X += 900
	d.Camera.Z = 2
	d, e = l.SaveStudyCanvas(ctx, "one", d)
	if e != nil {
		t.Fatal(e)
	}
	q.Revision = d.Revision
	c2, e := l.StudyContext(ctx, "one", q)
	if e != nil || c2.Sources[0].Anchor.Fingerprint != a.Fingerprint {
		t.Fatal(e, c2)
	}
	q.Objects = []string{"hidden"}
	q.Selection = StudySelection{}
	if _, e = l.StudyContext(ctx, "one", q); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal("hidden material exposed", e)
	}
	q.Objects = []string{"selection"}
	q.Selection = StudySelection{ObjectID: "selection", Start: 2, End: 3}
	if _, e = l.StudyContext(ctx, "one", q); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal("split surrogate accepted", e)
	}
	q.Selection = StudySelection{ObjectID: "selection", Region: []float64{.1, .1, .3, .3}}
	c, e = l.StudyContext(ctx, "one", q)
	if e != nil || c.Sources[0].Text != "" || c.Sources[0].Availability != "vision_required" {
		t.Fatal("region leaked entire text", e, c)
	}
	q.Revision--
	if _, e = l.StudyContext(ctx, "one", q); !errors.Is(e, ErrStudyConflict) {
		t.Fatal("stale context accepted", e)
	}
}

func TestStudyKnowledgeAndBrushPersistence(t *testing.T) {
	l, _ := reviewFixture(t)
	ctx := context.Background()
	d, _ := l.StudyCanvas(ctx, "one")
	d.Version = 2
	d.Objects = append(d.Objects, StudyObject{ID: "generated", Type: "practice", Layer: "main", X: 900, W: 520, H: 440, Title: "练习", Generation: "run-id", Blocks: []StudyBlock{{Type: "exercise", Text: "缓存命中和失效的路径有何不同？", Hint: "访问层级", Answer: "失效需访问下一层。"}}, Sources: []StudyAnchor{{ID: "video", WorkspaceID: "one", ObjectID: "lecture", Kind: "video", TimeStartMs: 512000, TimeEndMs: 550000}}})
	d.Connections = []StudyConnection{{ID: "link", From: "lecture", To: "generated", Label: "讲解依据"}}
	d.Strokes = []StudyStroke{{ID: "s", Gesture: "gesture", Layer: "main", Tool: "pen", Width: 3, Color: 0xff111111, Points: [][3]float64{{1, 2, .5}}, Brush: &StudyBrush{Family: "pencil", Opacity: .6, Pressure: .8, Smoothing: .2}}}
	d, e := l.SaveStudyCanvas(ctx, "one", d)
	if e != nil {
		t.Fatal(e)
	}
	restored, e := l.StudyCanvas(ctx, "one")
	if e != nil || restored.Version != 2 || restored.Objects[1].Blocks[0].Answer == "" || restored.Objects[1].Sources[0].TimeStartMs != 512000 || len(restored.Connections) != 1 || restored.Strokes[0].Brush.Family != "pencil" || restored.Strokes[0].Gesture != "gesture" {
		t.Fatal(e, restored)
	}
	restored.Connections[0].To = "missing"
	if _, e = l.SaveStudyCanvas(ctx, "one", restored); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal("dangling relation accepted", e)
	}
	restored.Connections = d.Connections
	restored.Strokes[0].Brush.Opacity = 3
	if _, e = l.SaveStudyCanvas(ctx, "one", restored); !errors.Is(e, ErrStudyInvalid) {
		t.Fatal("invalid brush accepted", e)
	}
}
