package library

import "testing"

func TestTimelineRoundTrip(t *testing.T) {
	chs := ParseTimeline("1. 00:10-05:30：课程定位与考核说明\n- 05:00-40:00: 板块构造\n乱七八糟的一行\n40:00-95:30：洋中脊  扩张\n")
	if len(chs) != 3 {
		t.Fatalf("parsed %d chapters", len(chs))
	}
	out, err := NormalizeTimeline(chs, 100*60*1000)
	if err != nil {
		t.Fatal(err)
	}
	if out[0].StartMs != 0 || out[0].EndMs != 5*60*1000 || out[1].EndMs != 40*60*1000 || out[2].EndMs != 100*60*1000 {
		t.Fatalf("not tiled: %+v", out)
	}
	if out[2].Title != "洋中脊 扩张" {
		t.Fatalf("title %q", out[2].Title)
	}
	want := "00:00-05:00：课程定位与考核说明\n05:00-40:00：板块构造\n40:00-100:00：洋中脊 扩张\n"
	if got := FormatTimeline(out); got != want {
		t.Fatalf("format:\n%s", got)
	}
	if _, err := NormalizeTimeline(nil, 0); err == nil {
		t.Fatal("empty outline accepted")
	}
}
