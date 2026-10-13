package library

import "testing"

func TestSearchBlocks(t *testing.T) {
	md := "# 第二章 流体静力学\n\n静压强与作用面方位无关。\n\n![](images/a.jpg)\n\n欧拉平衡微分方程：$f_x = \\frac{1}{\\rho}\\frac{\\partial p}{\\partial x}$\n\n无关内容"
	hits := searchBlocks(md, searchTerms("欧拉 平衡微分方程"))
	if len(hits) != 1 {
		t.Fatalf("hits = %d", len(hits))
	}
	h := hits[0]
	if len(h.Images) != 1 || h.Images[0] != "images/a.jpg" {
		t.Fatalf("images = %v", h.Images)
	}
	if []rune(md)[h.Offset] != '欧' {
		t.Fatalf("offset points at %q", string([]rune(md)[h.Offset:h.Offset+4]))
	}
	p := pageIndex{{Type: "image", Img: "images/a.jpg", Page: 2}, {Type: "text", Text: "静压强与作用面方位无关。", Page: 1}}
	if got := p.find(h.Snippet, h.Images); got != 3 {
		t.Fatalf("page = %d", got)
	}
	if got := p.find("……静压强与作用面方位无关。", nil); got != 2 {
		t.Fatalf("text page = %d", got)
	}
}
