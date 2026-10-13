package library

import (
	"context"
	"encoding/json"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode"
)

// CoursewareHit is a passage of parsed courseware that matches a search.
type CoursewareHit struct {
	LectureID string   `json:"lecture_id"`
	File      string   `json:"file"` // courseware asset path
	Name      string   `json:"name"`
	Offset    int      `json:"offset"`         // rune offset into full.md
	Page      int      `json:"page,omitempty"` // 1-based, when MinerU reported pages
	Snippet   string   `json:"snippet"`
	Images    []string `json:"images,omitempty"` // library-relative, near the passage
	score     int
}

var mdImage = regexp.MustCompile(`!\[[^\]]*\]\(([^)\s]+)\)`)

// SearchCourseware finds passages in the parsed courseware of the given
// lectures. Query words are matched case-insensitively; passages with more
// distinct words rank first.
func (l *Library) SearchCourseware(ctx context.Context, lectureIDs []string, query string, limit int) ([]CoursewareHit, error) {
	terms := searchTerms(query)
	if len(terms) == 0 {
		return []CoursewareHit{}, nil
	}
	hits := []CoursewareHit{}
	for _, id := range lectureIDs {
		as, err := l.Courseware(ctx, id)
		if err != nil {
			return nil, err
		}
		for _, a := range as {
			m := CoursewareInfo(a)
			if m.Parse == nil || m.Parse.State != "done" || m.Parse.MD == "" {
				continue
			}
			b, err := os.ReadFile(l.Abs(m.Parse.MD))
			if err != nil {
				continue
			}
			pages := loadPages(filepath.Dir(l.Abs(m.Parse.MD)))
			for _, h := range searchBlocks(string(b), terms) {
				h.LectureID, h.File, h.Name = id, a.Path, m.Name
				dir := path.Dir(m.Parse.MD)
				for i, img := range h.Images {
					h.Images[i] = path.Clean(path.Join(dir, img))
				}
				h.Page = pages.find(h.Snippet, h.Images)
				hits = append(hits, h)
			}
		}
	}
	sort.SliceStable(hits, func(i, j int) bool { return hits[i].score > hits[j].score })
	if limit > 0 && len(hits) > limit {
		hits = hits[:limit]
	}
	return hits, nil
}

func searchTerms(q string) []string {
	var out []string
	for _, t := range strings.FieldsFunc(strings.ToLower(q), func(r rune) bool {
		return unicode.IsSpace(r) || strings.ContainsRune(",，。;；、|/", r)
	}) {
		if len([]rune(t)) >= 1 {
			out = append(out, t)
		}
	}
	return out
}

type block struct {
	start int // rune offset
	text  string
}

// searchBlocks scores blank-line separated blocks; a hit carries its block
// with the neighbours for context, and the images among them.
func searchBlocks(md string, terms []string) []CoursewareHit {
	var blocks []block
	off := 0
	for _, part := range strings.Split(md, "\n\n") {
		if strings.TrimSpace(part) != "" {
			blocks = append(blocks, block{off, part})
		}
		off += len([]rune(part)) + 2
	}
	var hits []CoursewareHit
	for i, b := range blocks {
		low := strings.ToLower(b.text)
		distinct, count := 0, 0
		for _, t := range terms {
			if n := strings.Count(low, t); n > 0 {
				distinct++
				count += n
			}
		}
		if distinct == 0 {
			continue
		}
		from, to := max(i-1, 0), min(i+2, len(blocks))
		var parts, imgs []string
		for _, nb := range blocks[from:to] {
			parts = append(parts, nb.text)
			for _, m := range mdImage.FindAllStringSubmatch(nb.text, -1) {
				if !strings.Contains(m[1], "://") {
					imgs = append(imgs, m[1])
				}
			}
		}
		snippet := []rune(strings.Join(parts, "\n\n"))
		if len(snippet) > 900 {
			snippet = append(snippet[:900], '…')
		}
		hits = append(hits, CoursewareHit{Offset: b.start, Snippet: string(snippet), Images: imgs, score: distinct*100 + min(count, 50)})
	}
	return hits
}

// pageIndex maps MinerU content blocks to pages (content_list.json).
type pageIndex []struct {
	Type string `json:"type"`
	Text string `json:"text"`
	Img  string `json:"img_path"`
	Page int    `json:"page_idx"`
}

func loadPages(dir string) pageIndex {
	ms, _ := filepath.Glob(filepath.Join(dir, "*content_list.json"))
	if len(ms) == 0 {
		return nil
	}
	b, err := os.ReadFile(ms[0])
	if err != nil {
		return nil
	}
	var p pageIndex
	json.Unmarshal(b, &p)
	return p
}

func squash(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) || unicode.IsPunct(r) || unicode.IsSymbol(r) {
			return -1
		}
		return unicode.ToLower(r)
	}, s)
}

func (p pageIndex) find(snippet string, imgs []string) int {
	for _, img := range imgs {
		for _, it := range p {
			if it.Img != "" && path.Base(it.Img) == path.Base(img) {
				return it.Page + 1
			}
		}
	}
	s := squash(snippet)
	for _, it := range p {
		t := []rune(squash(it.Text))
		if len(t) >= 6 && strings.Contains(s, string(t[:min(len(t), 24)])) {
			return it.Page + 1
		}
	}
	return 0
}
