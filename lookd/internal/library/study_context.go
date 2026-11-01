package library

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"unicode/utf16"
)

type StudyAnchor struct {
	SourceLectureID string    `json:"source_lecture_id,omitempty"`
	OriginalPath    string    `json:"original_path,omitempty"`
	ID              string    `json:"id"`
	WorkspaceID     string    `json:"workspace_id"`
	ObjectID        string    `json:"object_id"`
	Kind            string    `json:"kind"`
	DocumentID      string    `json:"document_id,omitempty"`
	Page            int       `json:"page,omitempty"`
	Start           int       `json:"start,omitempty"`
	End             int       `json:"end,omitempty"`
	TimeStartMs     int64     `json:"time_start_ms,omitempty"`
	TimeEndMs       int64     `json:"time_end_ms,omitempty"`
	Fingerprint     string    `json:"fingerprint,omitempty"`
	Quote           string    `json:"quote,omitempty"`
	Region          []float64 `json:"region,omitempty"`
	StrokeIDs       []string  `json:"stroke_ids,omitempty"`
}
type StudyBrush struct {
	Family    string  `json:"family"`
	Opacity   float64 `json:"opacity"`
	Pressure  float64 `json:"pressure"`
	Smoothing float64 `json:"smoothing"`
	SquareTip bool    `json:"square_tip"`
}
type StudyBlock struct {
	Type     string     `json:"type"`
	Text     string     `json:"text,omitempty"`
	Items    []string   `json:"items,omitempty"`
	Columns  []string   `json:"columns,omitempty"`
	Rows     [][]string `json:"rows,omitempty"`
	Language string     `json:"language,omitempty"`
	Hint     string     `json:"hint,omitempty"`
	Answer   string     `json:"answer,omitempty"`
}
type StudyConnection struct {
	ID    string `json:"id"`
	From  string `json:"from"`
	To    string `json:"to"`
	Label string `json:"label"`
}
type StudySelection struct {
	ObjectID  string    `json:"object_id"`
	Start     int       `json:"start"`
	End       int       `json:"end"`
	Region    []float64 `json:"region"`
	StrokeIDs []string  `json:"stroke_ids"`
}
type StudyContextRequest struct {
	Selections    map[string]StudySelection `json:"selections,omitempty"`
	ObjectPages   map[string]int            `json:"object_pages,omitempty"`
	VideoRanges   map[string][]int64        `json:"video_ranges,omitempty"`
	Revision      int64                     `json:"revision"`
	Objects       []string                  `json:"objects"`
	Selection     StudySelection            `json:"selection"`
	IncludeVideo  bool                      `json:"include_video"`
	VideoMs       int64                     `json:"video_ms"`
	FromMs        int64                     `json:"from_ms"`
	ToMs          int64                     `json:"to_ms"`
	ObjectVideoMs map[string]int64          `json:"object_video_ms"`
}
type StudyContextSource struct {
	ID           string      `json:"id"`
	Label        string      `json:"label"`
	Kind         string      `json:"kind"`
	Availability string      `json:"availability"`
	Text         string      `json:"text"`
	ImagePath    string      `json:"image_path,omitempty"`
	Anchor       StudyAnchor `json:"anchor"`
}
type StudyContext struct {
	WorkspaceID string               `json:"workspace_id"`
	Revision    int64                `json:"revision"`
	Sources     []StudyContextSource `json:"sources"`
	EditableIDs []string             `json:"editable_ids"`
	ObjectIDs   []string             `json:"object_ids"`
}

func studyHash(s string) string { return fmt.Sprintf("%x", sha256.Sum256([]byte(s))) }
func studyText(o StudyObject) string {
	if len(o.Blocks) == 0 {
		return o.Text
	}
	lines := []string{}
	for _, b := range o.Blocks {
		parts := append([]string{b.Text}, b.Items...)
		parts = append(parts, strings.Join(b.Columns, " | "))
		for _, r := range b.Rows {
			parts = append(parts, strings.Join(r, " | "))
		}
		parts = append(parts, b.Hint, b.Answer)
		nonempty := []string{}
		for _, v := range parts {
			if v != "" {
				nonempty = append(nonempty, v)
			}
		}
		lines = append(lines, strings.Join(nonempty, "\n"))
	}
	text := strings.Join(lines, "\n")
	if len(o.Responses) > 0 {
		keys := []string{}
		for k := range o.Responses {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		text += "\n用户作答"
		for _, k := range keys {
			text += "\n" + k + ": " + o.Responses[k]
		}
	}
	return text
}
func validRegion(r []float64, normalized bool) bool {
	if len(r) == 0 {
		return true
	}
	if len(r) != 4 {
		return false
	}
	for _, v := range r {
		if !finite(v) {
			return false
		}
	}
	if r[2] <= 0 || r[3] <= 0 {
		return false
	}
	return !normalized || (r[0] >= 0 && r[1] >= 0 && r[0]+r[2] <= 1.000001 && r[1]+r[3] <= 1.000001)
}
func validateStudyContent(o StudyObject) error {
	bad := func() error { return fmt.Errorf("%w：知识结构或来源无效", ErrStudyInvalid) }
	if len(o.Responses) > 32 {
		return bad()
	}
	for k, v := range o.Responses {
		i, e := strconv.Atoi(k)
		if e != nil || i < 0 || i >= len(o.Blocks) || o.Blocks[i].Type != "exercise" || len(v) > 16000 {
			return bad()
		}
	}
	if len(o.Blocks) > 32 || len(o.Sources) > 24 || o.Page < 0 || o.Page > 100000 || len(o.DocumentID) > 1000 || len(o.Generation) > 100 {
		return bad()
	}
	for _, b := range o.Blocks {
		switch b.Type {
		case "heading", "paragraph", "list", "steps", "table", "code", "math", "exercise":
		default:
			return bad()
		}
		if len(b.Text)+len(b.Hint)+len(b.Answer) > 48000 || len(b.Items) > 30 || len(b.Columns) > 8 || len(b.Rows) > 30 || len(b.Language) > 80 {
			return bad()
		}
		for _, v := range append(append([]string{}, b.Items...), b.Columns...) {
			if len(v) > 8000 {
				return bad()
			}
		}
		if b.Type == "table" && len(b.Columns) == 0 {
			return bad()
		}
		for _, row := range b.Rows {
			if len(row) != len(b.Columns) {
				return bad()
			}
			for _, v := range row {
				if len(v) > 8000 {
					return bad()
				}
			}
		}
	}
	for _, a := range o.Sources {
		if !validStudyID(strings.TrimPrefix(a.ID, "object-")) || len(a.WorkspaceID) > 100 || (a.ObjectID != "" && !validStudyID(a.ObjectID)) || len(a.DocumentID) > 1000 || a.Start < 0 || a.End < a.Start || a.End > 1000000 || a.TimeStartMs < 0 || a.TimeEndMs < a.TimeStartMs || a.TimeEndMs > 7*24*3600*1000 || len(a.Fingerprint) > 100 || len(a.Quote) > 8000 || len(a.StrokeIDs) > 500 || !validRegion(a.Region, a.ObjectID != "") {
			return bad()
		}
		switch a.Kind {
		case "pdf", "text", "image", "video", "ink", "note", "explanation", "knowledge", "practice":
		default:
			return bad()
		}
		for _, id := range a.StrokeIDs {
			if !validStudyID(id) {
				return bad()
			}
		}
	}
	return nil
}

// UTF-16 offsets are shared by SelectableText and JavaScript. Never split a surrogate pair.
func studySlice(text string, start, end int) (string, error) {
	units := utf16.Encode([]rune(text))
	if start < 0 || end < start || end > len(units) {
		return "", ErrStudyInvalid
	}
	boundary := func(i int) bool {
		return i == 0 || i == len(units) || !(units[i] >= 0xdc00 && units[i] <= 0xdfff && units[i-1] >= 0xd800 && units[i-1] <= 0xdbff)
	}
	if !boundary(start) || !boundary(end) {
		return "", ErrStudyInvalid
	}
	return string(utf16.Decode(units[start:end])), nil
}

// StudyContext resolves only explicitly reviewed, visible identifiers against one saved revision.
func (l *Library) StudyContext(ctx context.Context, id string, q StudyContextRequest) (StudyContext, error) {
	out := StudyContext{WorkspaceID: id, Sources: []StudyContextSource{}, EditableIDs: []string{}, ObjectIDs: []string{}}
	if len(q.Selections) > 12 || len(q.ObjectPages) > 12 || len(q.VideoRanges) > 12 || len(q.Objects) > 12 || len(q.Selection.StrokeIDs) > 500 || q.VideoMs < 0 || q.VideoMs > 7*24*3600*1000 {
		return out, ErrStudyLimit
	}
	if len(q.ObjectVideoMs) > 12 {
		return out, ErrStudyLimit
	}
	for _, ms := range q.ObjectVideoMs {
		if ms < 0 || ms > 7*24*3600*1000 {
			return out, ErrStudyInvalid
		}
	}
	d, e := l.StudyCanvas(ctx, id)
	if e != nil {
		return out, e
	}
	out.Revision = d.Revision
	if q.Revision != d.Revision {
		return out, ErrStudyConflict
	}
	visible := map[string]bool{}
	editable := map[string]bool{}
	for _, a := range d.Layers {
		visible[a.ID] = a.Visible
		editable[a.ID] = a.Visible && !a.Locked
	}
	chosen := map[string]bool{}
	for _, v := range q.Objects {
		chosen[v] = true
	}
	objects := map[string]StudyObject{}
	for _, o := range d.Objects {
		objects[o.ID] = o
	}
	if q.Selection.ObjectID != "" && !chosen[q.Selection.ObjectID] {
		return out, ErrStudyInvalid
	}
	for key, selection := range q.Selections {
		if !chosen[key] || selection.ObjectID != key || len(selection.StrokeIDs) > 0 {
			return out, ErrStudyInvalid
		}
	}
	budget := 24000
	for _, oid := range q.Objects {
		o, ok := objects[oid]
		if !ok || !visible[o.Layer] {
			return out, ErrStudyInvalid
		}
		out.ObjectIDs = append(out.ObjectIDs, oid)
		if o.Generation != "" && editable[o.Layer] {
			out.EditableIDs = append(out.EditableIDs, oid)
		}
		if o.Type == "lecture" {
			continue
		}
		if page := q.ObjectPages[o.ID]; page > 0 {
			o.Page = page
		}
		if o.Type == "pdfdoc" {
			page, err := l.StudyPDFPage(ctx, id, o.Source, o.Page)
			if err != nil {
				return out, err
			}
			o.Text = page.Text
			o.Path = page.File
		}
		selection := q.Selection
		if scoped, ok := q.Selections[o.ID]; ok {
			selection = scoped
		}
		text := studyText(o)
		anchor := StudyAnchor{ID: "object-" + o.ID, WorkspaceID: id, ObjectID: o.ID, Kind: o.Type, DocumentID: o.DocumentID, Page: o.Page, SourceLectureID: o.SourceLectureID, OriginalPath: o.OriginalPath, Fingerprint: studyHash(text)}
		if (o.Type == "pdf" || o.Type == "pdfdoc") && anchor.DocumentID == "" {
			anchor.DocumentID = o.Source
		}
		if (o.Type == "pdf" || o.Type == "pdfdoc") && anchor.Page == 0 {
			fmt.Sscanf(pathBase(o.Path), "page-%d.png", &anchor.Page)
		}
		if selection.ObjectID == o.ID {
			if !validRegion(selection.Region, true) {
				return out, ErrStudyInvalid
			}
			anchor.Region = selection.Region
			if selection.End > selection.Start {
				text, e = studySlice(text, selection.Start, selection.End)
				if e != nil {
					return out, e
				}
				anchor.Start = selection.Start
				anchor.End = selection.End
			} else if len(anchor.Region) > 0 {
				text = ""
			}
		}
		units := utf16.Encode([]rune(text))
		if len(units) > budget {
			limit := budget
			if limit > 0 && units[limit-1] >= 0xd800 && units[limit-1] <= 0xdbff {
				limit--
			}
			text = string(utf16.Decode(units[:limit]))
		}
		budget -= len(utf16.Encode([]rune(text)))
		if budget < 0 {
			budget = 0
		}
		if anchor.End == 0 {
			anchor.End = len(utf16.Encode([]rune(text)))
		}
		anchor.Quote = text
		if len([]rune(anchor.Quote)) > 1500 {
			anchor.Quote = string([]rune(anchor.Quote)[:1500])
		}
		availability := "text"
		if text == "" && len(anchor.Region) > 0 {
			availability = "vision_required"
		}
		image := ""
		if (o.Type == "pdf" || o.Type == "pdfdoc") || o.Type == "image" {
			asset, e := l.StudySource(ctx, id, o.Path)
			if e != nil {
				return out, e
			}
			asset.Close()
			image = o.Path
			if strings.TrimSpace(text) == "" {
				availability = "vision_required"
			}
		}
		if o.Type == "video" {
			availability = "transcript_missing; selected local clip can be transcribed on demand"
			at := q.ObjectVideoMs[o.ID]
			anchor.TimeStartMs = int64(math.Max(0, float64(at-45000)))
			anchor.TimeEndMs = at + 15000
			if span := q.VideoRanges[o.ID]; len(span) == 2 {
				anchor.TimeStartMs = span[0]
				anchor.TimeEndMs = span[1]
			}
			if anchor.TimeStartMs < 0 || anchor.TimeEndMs <= anchor.TimeStartMs || anchor.TimeEndMs-anchor.TimeStartMs > 180000 {
				return out, ErrStudyInvalid
			}
			image = ""
			if clip, ok := l.CachedStudyClip(ctx, id, o.ID, anchor.TimeStartMs, anchor.TimeEndMs); ok {
				text = clip.Text
				image = clip.ImagePath
				availability = clip.Availability
				anchor.Fingerprint = clip.Fingerprint
			}
		}
		out.Sources = append(out.Sources, StudyContextSource{ID: anchor.ID, Label: o.Title, Kind: o.Type, Availability: availability, Text: text, ImagePath: image, Anchor: anchor})
	}
	if len(q.Selection.StrokeIDs) > 0 {
		wanted := map[string]bool{}
		for _, v := range q.Selection.StrokeIDs {
			wanted[v] = true
		}
		selected := []StudyStroke{}
		for _, s := range d.Strokes {
			if wanted[s.ID] && visible[s.Layer] {
				selected = append(selected, s)
				delete(wanted, s.ID)
			}
		}
		if len(wanted) > 0 || !validRegion(q.Selection.Region, q.Selection.ObjectID != "") {
			return out, ErrStudyInvalid
		}
		raw, _ := json.Marshal(selected)
		a := StudyAnchor{ID: "selected-ink", WorkspaceID: id, ObjectID: q.Selection.ObjectID, Kind: "ink", Region: q.Selection.Region, StrokeIDs: q.Selection.StrokeIDs, Fingerprint: studyHash(string(raw))}
		if len(selected) > 0 {
			a.Page = selected[0].Page
		}
		out.Sources = append(out.Sources, StudyContextSource{ID: a.ID, Label: "选中的手写与圈画", Kind: "ink", Availability: "vision_required", Anchor: a})
	}
	if q.IncludeVideo {
		from, to := q.FromMs, q.ToMs
		if to == 0 {
			from = int64(math.Max(0, float64(q.VideoMs-45000)))
			to = q.VideoMs + 15000
		}
		if from < 0 || to <= from || to-from > 180000 || to > 7*24*3600*1000 {
			return out, ErrStudyInvalid
		}
		segments, e := l.Store.Segments(ctx, id, from, to)
		if e != nil {
			return out, e
		}
		var b strings.Builder
		for _, s := range segments {
			line := fmt.Sprintf("[%d–%d ms] %s\n", s.StartMs, s.EndMs, s.Text)
			if b.Len()+len(line) > 24000 {
				break
			}
			b.WriteString(line)
		}
		text := b.String()
		availability := "timestamped_transcript"
		if text == "" {
			availability = "transcript_missing; start transcription in the existing player"
		}
		image := ""
		fingerprint := studyHash(text)
		if clip, ok := l.CachedStudyClip(ctx, id, "lecture", from, to); ok {
			image = clip.ImagePath
			if text == "" {
				text = clip.Text
				availability = clip.Availability
				fingerprint = clip.Fingerprint
			}
		}
		a := StudyAnchor{ID: "lecture-video", WorkspaceID: id, ObjectID: "lecture", Kind: "video", TimeStartMs: from, TimeEndMs: to, Fingerprint: fingerprint}
		out.Sources = append(out.Sources, StudyContextSource{ID: a.ID, Label: "当前课程视频的邻近讲解", Kind: "video", Availability: availability, Text: text, ImagePath: image, Anchor: a})
	}
	return out, nil
}
func pathBase(p string) string { parts := strings.Split(p, "/"); return parts[len(parts)-1] }
