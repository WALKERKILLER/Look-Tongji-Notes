package portable

import (
	"strings"
	"testing"
)

type fakeLib map[string]bool

func (f fakeLib) SlidePath(lectureID string, idx int) string {
	if lectureID == "L1" && idx == 12 {
		return "courses/课/第一讲/slides/0012_t00-12-03.jpg"
	}
	return ""
}
func (f fakeLib) FileExists(rel string) bool { return f[rel] }

func converter(used *[]string) *Converter {
	return &Converter{
		Lib: fakeLib{
			"courses/课/第一讲/slides/0012_t00-12-03.jpg":                 true,
			"courses/课/第一讲/courseware/讲义 (1).pdf":                     true,
			"courses/课/第一讲/courseware/讲义 (1).pdf.parsed/images/a.jpg": true,
		},
		Place: func(rel string) string { return strings.TrimPrefix(rel, "courses/") },
		Use:   func(rel string) { *used = append(*used, rel) },
	}
}

func TestMarkdown(t *testing.T) {
	doc := Doc{Path: "课/第一讲/notes/笔记.md", LectureID: "L1"}
	cases := []struct{ name, in, want string }{
		{"bare timestamp", "见 [12:03] 处", "见 [12:03](lookstudio://lecture/L1?t=723) 处"},
		{"range", "[1:00]–[1:30]", "[1:00–1:30](lookstudio://lecture/L1?t=60)"},
		{"seek link", "[这里](look://seek?t=5)", "[这里](lookstudio://lecture/L1?t=5)"},
		{"other lecture", "[02:00](look://lecture/L9?t=120)", "[02:00](lookstudio://lecture/L9?t=120)"},
		{"slide", "![PPT 12](look://slide/L1/12)", "![PPT 12](../slides/0012_t00-12-03.jpg)"},
		{"missing slide keeps label", "![PPT 3](look://slide/L1/3)", "PPT 3"},
		{"courseware", "[课件·p.3](look://courseware/L1?file=courses%2F%E8%AF%BE%2F%E7%AC%AC%E4%B8%80%E8%AE%B2%2Fcourseware%2F%E8%AE%B2%E4%B9%89%20%281%29.pdf&q=x)",
			"[课件·p.3](../courseware/讲义%20%281%29.pdf)"},
		{"unescaped space is not a link", "![插图](look://file/courses/课/第一讲/courseware/讲义 (1).pdf.parsed/images/a.jpg)", "![插图](look://file/courses/课/第一讲/courseware/讲义 (1).pdf.parsed/images/a.jpg)"},
		{"file escaped", "![插图](look://file/courses/%E8%AF%BE/%E7%AC%AC%E4%B8%80%E8%AE%B2/courseware/%E8%AE%B2%E4%B9%89%20%281%29.pdf.parsed/images/a.jpg)",
			"![插图](../courseware/讲义%20%281%29.pdf.parsed/images/a.jpg)"},
		{"inline math", `动能 \( E=\frac12 mv^2 \) 守恒`, `动能 $E=\frac12 mv^2$ 守恒`},
		{"display math", "\\[\na^2+b^2=c^2\n\\]", "$$\na^2+b^2=c^2\n$$"},
		{"padded dollar", `$ x^2 $`, `$x^2$`},
		{"dollar money stays", `花了 $ 5 元 $`, `花了 $ 5 元 $`},
		{"timestamp inside math untouched", `$[1:00]$`, `$[1:00]$`},
		{"code untouched", "`[12:03]` 与 `look://seek?t=1`", "`[12:03]` 与 `look://seek?t=1`"},
		{"environment", `\begin{aligned} a&=b \end{aligned}`, "\n$$\n\\begin{aligned} a&=b \\end{aligned}\n$$\n"},
	}
	for _, c := range cases {
		var used []string
		if got := converter(&used).Markdown(c.in, doc); got != c.want {
			t.Errorf("%s:\n got %q\nwant %q", c.name, got, c.want)
		}
	}
}

func TestFencesAndUse(t *testing.T) {
	var used []string
	in := "```\n[12:03] \\(x\\)\n```\n![PPT 12](look://slide/L1/12)\n"
	got := converter(&used).Markdown(in, Doc{Path: "课/第一讲/第一讲.md", LectureID: "L1"})
	want := "```\n[12:03] \\(x\\)\n```\n![PPT 12](slides/0012_t00-12-03.jpg)\n"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	if len(used) != 1 || used[0] != "courses/课/第一讲/slides/0012_t00-12-03.jpg" {
		t.Fatalf("used = %v", used)
	}
}

func TestNoLectureLeavesTimestamps(t *testing.T) {
	var used []string
	in := "[12:03] 和 [这里](look://seek?t=5)"
	if got := converter(&used).Markdown(in, Doc{Path: "未归类笔记/a.md"}); got != "[12:03] 和 这里" {
		t.Fatalf("got %q", got)
	}
}
