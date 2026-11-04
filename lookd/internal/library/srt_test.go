package library

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"lookstudio/lookd/internal/store"
)

func TestParseSRTReadsLeadingZerosAsDecimal(t *testing.T) {
	got := ParseSRT("1\n00:01:08,100 --> 00:01:09,840\n角度\n\n2\n00:08:59,016 --> 00:09:08,5\n指向性\n")
	want := []store.Segment{
		{Idx: 0, StartMs: 68100, EndMs: 69840, Text: "角度"},
		{Idx: 1, StartMs: 539016, EndMs: 548500, Text: "指向性"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v", got)
	}
}

func TestRepairTranscriptsRereadsMisplacedCues(t *testing.T) {
	lib, _ := reviewFixture(t)
	ctx := context.Background()
	segs := []store.Segment{
		{Idx: 0, StartMs: 478740, EndMs: 481980, Text: "这个位置能收到一个信号"},
		{Idx: 1, StartMs: 482016, EndMs: 483980, Text: "那个位置也能收到"},
	}
	if e := lib.SaveTranscript(ctx, "one", segs, "bcut"); e != nil {
		t.Fatal(e)
	}
	// What the octal parse stored: minute 08 read as 0.
	bad := []store.Segment{
		{Idx: 0, StartMs: 478740, EndMs: 1980, Text: segs[0].Text},
		{Idx: 1, StartMs: 2016, EndMs: 3980, Text: segs[1].Text},
	}
	if e := lib.Store.ReplaceSegments(ctx, "one", bad); e != nil {
		t.Fatal(e)
	}
	n, e := lib.RepairTranscripts(ctx)
	if e != nil || n != 1 {
		t.Fatalf("repaired %d, %v", n, e)
	}
	got, _ := lib.Store.Segments(ctx, "one", 0, 0)
	if !reflect.DeepEqual(got, segs) {
		t.Fatalf("got %+v", got)
	}
	if n, _ := lib.RepairTranscripts(ctx); n != 0 {
		t.Fatalf("repaired a sound transcript again: %d", n)
	}
}

// Every clock SaveTranscript can write must read back unchanged.
func TestSRTRoundTripsEveryClock(t *testing.T) {
	var segs []store.Segment
	for ms := int64(0); ms < 3*3600000; ms += 61007 {
		segs = append(segs, store.Segment{Idx: len(segs), StartMs: ms, EndMs: ms + 9009, Text: "x"})
	}
	var b strings.Builder
	for i, g := range segs {
		fmt.Fprintf(&b, "%d\n%s --> %s\n%s\n\n", i+1, fmtSRT(g.StartMs), fmtSRT(g.EndMs), g.Text)
	}
	if got := ParseSRT(b.String()); !reflect.DeepEqual(got, segs) {
		for i := range segs {
			if i >= len(got) || got[i] != segs[i] {
				t.Fatalf("cue %d: got %+v, want %+v", i, got[i], segs[i])
			}
		}
		t.Fatalf("got %d cues, want %d", len(got), len(segs))
	}
}
