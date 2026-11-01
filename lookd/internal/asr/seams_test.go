package asr

import "testing"

func TestMergeChunkSeamsKeepsOtherSpeech(t *testing.T) {
	phrase := "相同内容也可能在课堂中被重复讲述。"
	for _, tc := range []struct {
		name string
		a, b Utterance
	}{
		{"same chunk", Utterance{StartMs: 1000, EndMs: 18000, Text: phrase}, Utterance{StartMs: 12000, EndMs: 22000, Text: phrase}},
		{"different times", Utterance{StartMs: 1180000, EndMs: 1190000, Text: phrase}, Utterance{StartMs: 1205000, EndMs: 1210000, Text: phrase}},
		{"different content", Utterance{StartMs: 1190000, EndMs: 1209000, Text: phrase}, Utterance{StartMs: 1205000, EndMs: 1220000, Text: "下一部分介绍完全不同的知识内容。"}},
		{"short phrase", Utterance{StartMs: 1190000, EndMs: 1209000, Text: "可以。"}, Utterance{StartMs: 1205000, EndMs: 1220000, Text: "可以。"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := MergeChunkSeams([]Utterance{tc.a, tc.b})
			if len(got) != 2 || got[0] != tc.a || got[1] != tc.b {
				t.Fatalf("unrelated speech changed: %+v", got)
			}
		})
	}
}

func TestMergeChunkSeamsContainedSentence(t *testing.T) {
	us := []Utterance{
		{StartMs: 1190000, EndMs: 1209000, Text: "我们介绍地址转换。这是一个完整的重复句子。然后继续。"},
		{StartMs: 1205000, EndMs: 1208500, Text: "这是一个完整的重复句子。"},
	}
	got := MergeChunkSeams(us)
	if len(got) != 1 || got[0] != us[0] {
		t.Fatalf("contained duplicate remains: %+v", got)
	}
}

func TestSeamTailPreservesEnglishWordBoundary(t *testing.T) {
	tail, ok := seamTail("Use the shared buffer", "the shared buffer with care.")
	if !ok || tail != " with care." {
		t.Fatalf("words joined: %q %v", tail, ok)
	}
}

func TestSeamTailKeepsOpeningPunctuation(t *testing.T) {
	tail, ok := seamTail("共同的说明文字已经超过十个汉字。", "共同的说明文字已经超过十个汉字，（保留括号）。")
	if !ok || tail != "（保留括号）。" {
		t.Fatalf("opening punctuation dropped: %q %v", tail, ok)
	}
}

func TestMergeChunkSeamsReversedMidpoints(t *testing.T) {
	us := []Utterance{
		{StartMs: 1191000, EndMs: 1211000, Text: "先介绍地址转换。这是一个完整的重复句子。然后继续。"},
		{StartMs: 1194000, EndMs: 1204000, Text: "这是一个完整的重复句子。"},
	}
	got := MergeChunkSeams(us)
	if len(got) != 1 || got[0] != us[0] {
		t.Fatalf("reversed seam ownership duplicated speech: %+v", got)
	}
}
