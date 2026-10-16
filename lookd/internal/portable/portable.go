// Package portable turns Look Studio Markdown into plain Markdown that other
// tools (Obsidian, static sites, ...) render without the app: look:// links
// become relative file links or lookstudio:// deep links, bare [mm:ss]
// timestamps become deep links, and \( \) / \[ \] math becomes $ / $$.
//
// The rules mirror prepareMarkdown and linkifyTimestamps in
// app/lib/widgets/look_markdown.dart and timestamp_links.dart.
package portable

import (
	"fmt"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
)

// Scheme is the URL scheme the app registers with the operating system, so a
// link clicked in another program opens Look Studio.
const Scheme = "lookstudio"

// LectureLink is the deep link that opens a lecture, at sec when sec >= 0.
func LectureLink(lectureID string, sec int64) string {
	u := Scheme + "://lecture/" + url.PathEscape(lectureID)
	if sec >= 0 {
		u += "?t=" + strconv.FormatInt(sec, 10)
	}
	return u
}

// Library answers questions about library files. Paths are slash paths
// relative to the library root; "" means the file is not available locally.
type Library interface {
	SlidePath(lectureID string, idx int) string
	FileExists(rel string) bool
}

// Converter rewrites documents of one export.
type Converter struct {
	Lib Library
	// Place maps a library path to its path in the export (slash, relative to
	// the export root).
	Place func(rel string) string
	// Use records a library file a converted document links to, so the
	// exporter can copy it.
	Use func(rel string)
}

// Doc identifies the document being converted.
type Doc struct {
	Path      string // export path of the document (slash, relative to the export root)
	LectureID string // lecture that bare timestamps refer to; "" when none
}

var fenceLine = regexp.MustCompile("^\\s*(```|~~~)")

// Markdown converts one document. Fenced code is copied unchanged.
func (c *Converter) Markdown(md string, doc Doc) string {
	var out, text strings.Builder
	fence := false
	flush := func() {
		out.WriteString(c.text(text.String(), doc))
		text.Reset()
	}
	lines := strings.SplitAfter(md, "\n")
	for _, line := range lines {
		isFence := fenceLine.MatchString(line)
		if fence || isFence {
			flush()
			out.WriteString(line)
			if isFence {
				fence = !fence
			}
		} else {
			text.WriteString(line)
		}
	}
	flush()
	return out.String()
}

// Regions that are copied (code, $ math) or converted (\( \), \[ \], bare
// environments) instead of link-rewritten. RE2 has no back-references, so a
// bare environment is matched by its \begin and closed by hand.
var regions = regexp.MustCompile(strings.Join([]string{
	`(\$\$[\s\S]*?\$\$)`, // 1 display $$
	`(\\\[[\s\S]*?\\\])`, // 2 display \[ \]
	`(\\\([\s\S]*?\\\))`, // 3 inline \( \)
	"(`[^`\n]*`)",        // 4 inline code
	`(\\begin\{((?:equation|align|gather|multline|aligned|gathered|alignat|cases|array|split|[pbvBV]?matrix)\*?)\})`, // 5 bare environment (6 = name)
	`(\$[^$\n]+?\$)`, // 7 inline $
}, "|"))

var (
	mathy = regexp.MustCompile(`[\\^_=]`)
	cjk   = regexp.MustCompile(`[\x{3400}-\x{9fff}]`)
)

func (c *Converter) text(s string, doc Doc) string {
	var b strings.Builder
	at := 0
	for at < len(s) {
		m := regions.FindStringSubmatchIndex(s[at:])
		if m == nil {
			break
		}
		start, end := at+m[0], at+m[1]
		group := func(i int) string {
			if m[2*i] < 0 {
				return ""
			}
			return s[at+m[2*i] : at+m[2*i+1]]
		}
		var repl string
		switch {
		case group(1) != "", group(4) != "":
			repl = s[start:end]
		case group(2) != "":
			g := group(2)
			repl = "$$" + g[2:len(g)-2] + "$$"
		case group(3) != "":
			g := group(3)
			repl = "$" + strings.TrimSpace(g[2:len(g)-2]) + "$"
		case group(5) != "":
			name := group(6)
			close := strings.Index(s[end:], `\end{`+name+`}`)
			if close < 0 {
				repl = s[start:end] // unclosed: leave as text
				break
			}
			end += close + len(`\end{`+name+`}`)
			repl = "\n$$\n" + s[start:end] + "\n$$\n"
		case group(7) != "":
			if start > 0 && s[start-1] == '\\' {
				// An escaped dollar is text; look again just after it.
				b.WriteString(c.links(s[at:start+1], doc))
				at = start + 1
				continue
			}
			g := group(7)
			body := g[1 : len(g)-1]
			repl = g
			// `$ x $` is not math in Obsidian; drop the padding when it clearly is.
			if t := strings.TrimSpace(body); t != body && mathy.MatchString(t) && !cjk.MatchString(t) {
				repl = "$" + t + "$"
			}
		}
		b.WriteString(c.links(s[at:start], doc))
		b.WriteString(repl)
		at = end
	}
	b.WriteString(c.links(s[at:], doc))
	return b.String()
}

var (
	lookLink = regexp.MustCompile(`(!?)\[([^\]\n]*)\]\((look://[^)\s]+)\)`)
	clock    = `(\d{1,2}:\d{2}(?::\d{2})?)`
	// A range `[a]–[b]` or a single `[a]`; one already followed by "(" is a link label.
	tsRef = regexp.MustCompile(`\[` + clock + `\](?:\s*[–—~-]\s*\[` + clock + `\])?`)
)

// links rewrites look:// links, then bare timestamps, in plain text.
func (c *Converter) links(s string, doc Doc) string {
	s = lookLink.ReplaceAllStringFunc(s, func(m string) string {
		g := lookLink.FindStringSubmatch(m)
		return c.link(g[1] == "!", g[2], g[3], doc)
	})
	if doc.LectureID == "" {
		return s
	}
	var b strings.Builder
	at := 0
	for _, m := range tsRef.FindAllStringSubmatchIndex(s, -1) {
		if m[1] < len(s) && s[m[1]] == '(' {
			continue
		}
		start, ok := ParseClock(s[m[2]:m[3]])
		if !ok {
			continue
		}
		label := s[m[2]:m[3]]
		if m[4] >= 0 {
			label += "–" + s[m[4]:m[5]]
		}
		b.WriteString(s[at:m[0]])
		fmt.Fprintf(&b, "[%s](%s)", label, LectureLink(doc.LectureID, start))
		at = m[1]
	}
	b.WriteString(s[at:])
	return b.String()
}

// ParseClock reads mm:ss or h:mm:ss as seconds.
func ParseClock(s string) (int64, bool) {
	var sec int64
	for _, p := range strings.Split(s, ":") {
		n, err := strconv.ParseInt(p, 10, 64)
		if err != nil {
			return 0, false
		}
		sec = sec*60 + n
	}
	return sec, true
}

// link rewrites one look:// link. A target that is not available outside the
// app keeps only its label, so the reader never meets a dead link.
func (c *Converter) link(image bool, label, raw string, doc Doc) string {
	u, err := url.Parse(raw)
	if err != nil {
		return label
	}
	seg := strings.Split(strings.Trim(u.Path, "/"), "/")
	q := u.Query()
	file := func(rel string) string {
		if rel == "" || strings.Contains(rel, "..") || !c.Lib.FileExists(rel) {
			return label
		}
		c.Use(rel)
		bang := ""
		if image {
			bang = "!"
		}
		return fmt.Sprintf("%s[%s](%s)", bang, label, Relative(doc.Path, c.Place(rel)))
	}
	switch u.Host {
	case "lecture", "seek":
		id := doc.LectureID
		if u.Host == "lecture" && seg[0] != "" {
			id = seg[0]
		}
		sec, err := strconv.ParseInt(q.Get("t"), 10, 64)
		if id == "" || err != nil {
			return label
		}
		return fmt.Sprintf("[%s](%s)", label, LectureLink(id, sec))
	case "slide":
		if len(seg) < 2 {
			return label
		}
		idx, err := strconv.Atoi(seg[1])
		if err != nil {
			return label
		}
		return file(c.Lib.SlidePath(seg[0], idx))
	case "file":
		rel, err := url.PathUnescape(strings.TrimPrefix(raw, "look://file/"))
		if err != nil {
			return label
		}
		return file(rel)
	case "courseware":
		return file(q.Get("file"))
	}
	return label
}

// Relative is the Markdown link target from document `from` to file `to`,
// both slash paths relative to the export root.
func Relative(from, to string) string {
	fromDir := strings.Split(path.Dir(from), "/")
	if path.Dir(from) == "." {
		fromDir = nil
	}
	toParts := strings.Split(to, "/")
	i := 0
	for i < len(fromDir) && i < len(toParts)-1 && fromDir[i] == toParts[i] {
		i++
	}
	parts := make([]string, 0, len(fromDir)-i+len(toParts)-i)
	for range fromDir[i:] {
		parts = append(parts, "..")
	}
	parts = append(parts, toParts[i:]...)
	return EscapePath(strings.Join(parts, "/"))
}

// EscapePath makes a relative path safe as a Markdown link target while
// keeping CJK readable: only characters that end or confuse a link are
// percent-encoded.
func EscapePath(p string) string {
	var b strings.Builder
	for _, r := range p {
		switch r {
		case ' ', '(', ')', '<', '>', '[', ']', '#', '?', '%', '^', '|', '\\':
			fmt.Fprintf(&b, "%%%02X", r)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
