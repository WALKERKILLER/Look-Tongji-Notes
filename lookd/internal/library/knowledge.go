package library

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"strings"

	"lookstudio/lookd/internal/portable"
	"lookstudio/lookd/internal/store"
)

// KnowledgeDoc is one page of a knowledge-base export that is organised as
// a tree of pages rather than files (Notion). Containers (courses, lectures)
// are written once when created; leaves (notes, transcripts) follow the
// library.
// Contract: docs/specs/0013-notion-sync.md
type KnowledgeDoc struct {
	Key       string `json:"key"`    // course:<id>, lecture:<id>, note:<id>, transcript:<lecture id>
	Parent    string `json:"parent"` // key of the parent page; "" for the export root
	Title     string `json:"title"`
	Body      string `json:"body"` // Markdown without front matter or title
	Container bool   `json:"container"`
}

// noFiles makes link conversion keep only labels for library files: the
// target cannot reach them.
type noFiles struct{}

func (noFiles) SlidePath(string, int) string { return "" }
func (noFiles) FileExists(string) bool       { return false }

// KnowledgeDocs lists the pages for a page-tree export, parents first:
// courses and lectures that have notes or a transcript, their notes, and one
// transcript page per lecture with its outline and schedule. Links to library
// files keep only their label and timestamps stay plain text, since such
// targets accept only web links.
func (l *Library) KnowledgeDocs(ctx context.Context) ([]KnowledgeDoc, error) {
	st := l.Store
	conv := &portable.Converter{Lib: noFiles{}, Place: func(rel string) string { return rel }, Use: func(string) {}, NoDeepLinks: true}
	courses, err := st.Courses(ctx)
	if err != nil {
		return nil, err
	}
	all, err := st.Notes(ctx, "", "")
	if err != nil {
		return nil, err
	}
	byLecture, byCourse := map[string][]store.Note{}, map[string][]store.Note{}
	var loose []store.Note
	for _, n := range all {
		switch {
		case n.LectureID != "":
			byLecture[n.LectureID] = append(byLecture[n.LectureID], n)
		case n.CourseID != "":
			byCourse[n.CourseID] = append(byCourse[n.CourseID], n)
		default:
			loose = append(loose, n)
		}
	}
	var out []KnowledgeDoc
	note := func(n store.Note, parent string, meta ...string) (KnowledgeDoc, error) {
		full, err := st.Note(ctx, n.ID)
		if err != nil {
			return KnowledgeDoc{}, err
		}
		if d := unixISO(n.UpdatedAt); d != "" {
			meta = append(meta, "更新于 "+d[:10])
		}
		head := joinNonEmpty(" · ", meta...)
		body := conv.Markdown(full.Body, portable.Doc{LectureID: n.LectureID})
		return KnowledgeDoc{Key: "note:" + n.ID, Parent: parent, Title: orDefault(n.Title, "笔记"),
			Body: "*" + head + "*\n\n" + strings.TrimLeft(body, "\n")}, nil
	}
	for _, c := range courses {
		if c.Dir == "" {
			continue
		}
		lectures, err := st.Lectures(ctx, c.ID)
		if err != nil {
			return nil, err
		}
		sched, _ := st.Schedule(ctx, store.ScheduleQuery{CourseID: c.ID})
		ck := "course:" + c.ID
		var docs []KnowledgeDoc
		for _, lec := range lectures {
			if lec.Dir == "" {
				continue
			}
			raw, err := os.ReadFile(l.Abs(lec.Dir + "/transcript.md"))
			if err != nil && !errors.Is(err, fs.ErrNotExist) {
				return nil, err
			}
			notes := byLecture[lec.ID]
			if len(raw) == 0 && len(notes) == 0 {
				continue
			}
			lk := "lecture:" + lec.ID
			duration := ""
			if lec.DurationS > 0 {
				duration = "时长 " + fmtClock(lec.DurationS*1000)
			}
			docs = append(docs, KnowledgeDoc{Key: lk, Parent: ck, Title: lec.Title, Container: true,
				Body: joinNonEmpty(" · ", lec.Date, lec.Lecturer, lec.Room, duration) + "\n"})
			for _, n := range notes {
				d, err := note(n, lk, courseName(c), lec.Title)
				if err != nil {
					return nil, err
				}
				docs = append(docs, d)
			}
			if len(raw) > 0 {
				docs = append(docs, KnowledgeDoc{Key: "transcript:" + lec.ID, Parent: lk, Title: "转写稿 · " + lec.Title,
					Body: l.knowledgeTranscript(ctx, conv, lec, sched, string(raw))})
			}
		}
		for _, n := range byCourse[c.ID] {
			d, err := note(n, ck, courseName(c), "课程笔记")
			if err != nil {
				return nil, err
			}
			docs = append(docs, d)
		}
		if len(docs) == 0 {
			continue
		}
		out = append(out, KnowledgeDoc{Key: ck, Title: courseName(c), Container: true,
			Body: joinNonEmpty(" · ", c.Teacher, c.College, c.Term) + "\n"})
		out = append(out, docs...)
	}
	for _, n := range loose {
		d, err := note(n, "")
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, nil
}

// knowledgeTranscript is a lecture's transcript page: outline, schedule and
// courseware names, then the transcript.
func (l *Library) knowledgeTranscript(ctx context.Context, conv *portable.Converter, lec store.Lecture, sched []store.ScheduleItem, raw string) string {
	var b strings.Builder
	if chs, _ := l.Store.Timeline(ctx, lec.ID); len(chs) > 0 {
		b.WriteString("## 大纲\n\n")
		for _, ch := range chs {
			fmt.Fprintf(&b, "- `%s` %s\n", fmtClock(ch.StartMs), ch.Title)
		}
		b.WriteString("\n")
	}
	var items []string
	for _, it := range sched {
		if it.LectureID != lec.ID {
			continue
		}
		box := " "
		if it.Done {
			box = "x"
		}
		items = append(items, fmt.Sprintf("- [%s] %s %s", box, strings.TrimSpace(it.DueDate+" "+it.DueTime), it.Title))
	}
	if len(items) > 0 {
		b.WriteString("## 日程\n\n" + strings.Join(items, "\n") + "\n\n")
	}
	if cw, _ := l.Courseware(ctx, lec.ID); len(cw) > 0 {
		b.WriteString("## 课件\n\n")
		for _, a := range cw {
			b.WriteString("- " + path.Base(a.Path) + "\n")
		}
		b.WriteString("\n")
	}
	b.WriteString("## 转写稿\n\n")
	b.WriteString(conv.Markdown(transcriptBody(raw), portable.Doc{LectureID: lec.ID}))
	return b.String()
}
