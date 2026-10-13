package asr

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

// fake "recognises" one utterance every 5 s of whatever audio it gets.
type fake struct {
	calls atomic.Int32
	fail  error
	after int32 // fail only once more than this many calls were made
}

func (f *fake) Transcribe(ctx context.Context, audio string, _ Stage) ([]Utterance, error) {
	if n := f.calls.Add(1); f.fail != nil && n > f.after {
		return nil, f.fail
	}
	var out []Utterance
	d := probeSeconds(ctx, audio)
	for t := 0.0; t+2 <= d; t += 5 {
		out = append(out, Utterance{StartMs: int64(t * 1000), EndMs: int64((t + 2) * 1000), Text: "x"})
	}
	return out, nil
}

func testAudio(t *testing.T, secs string) string {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not found")
	}
	p := filepath.Join(t.TempDir(), "a.mp3")
	out, err := exec.Command("ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono",
		"-t", secs, "-c:a", "libmp3lame", "-q:a", "9", "-y", p).CombinedOutput()
	if err != nil {
		t.Fatalf("ffmpeg: %v %s", err, out)
	}
	return p
}

func testPool(t *testing.T, a, b Engine) *Pool {
	p := newPool(filepath.Join(t.TempDir(), "usage.json"), []*channel{{id: "a", name: "A", slots: 2, eng: a}, {id: "b", name: "B", slots: 2, eng: b}})
	p.SetConfig(PoolConfig{Concurrency: 3})
	return p
}

func checkCoverage(t *testing.T, us []Utterance, total float64) {
	t.Helper()
	for i := 1; i < len(us); i++ {
		if us[i].StartMs <= us[i-1].StartMs {
			t.Fatalf("duplicate/out of order at %d: %d after %d", i, us[i].StartMs, us[i-1].StartMs)
		}
		if gap := us[i].StartMs - us[i-1].StartMs; gap > 5100 {
			t.Fatalf("gap of %d ms at %d ms", gap, us[i-1].StartMs)
		}
	}
	if last := float64(us[len(us)-1].StartMs) / 1000; last < total-10 {
		t.Fatalf("coverage ends at %.0fs of %.0fs", last, total)
	}
}

func TestPoolBalancesAndMerges(t *testing.T) {
	audio := testAudio(t, "1500")
	a, b := &fake{}, &fake{}
	p := testPool(t, a, b)
	us, engines, err := p.Transcribe(context.Background(), audio, nil)
	if err != nil {
		t.Fatal(err)
	}
	checkCoverage(t, us, 1500)
	if a.calls.Load() == 0 || b.calls.Load() == 0 || engines != "a+b" {
		t.Fatalf("not balanced: a=%d b=%d engines=%q", a.calls.Load(), b.calls.Load(), engines)
	}
	if _, err := os.Stat(p.state); err != nil {
		t.Fatal("usage not persisted")
	}
}

func TestPoolFailsOver(t *testing.T) {
	audio := testAudio(t, "2700")
	bad, good := &fake{fail: httpErr{path: "/x", code: 412}}, &fake{}
	p := testPool(t, bad, good)
	us, engines, err := p.Transcribe(context.Background(), audio, nil)
	if err != nil {
		t.Fatal(err)
	}
	checkCoverage(t, us, 2700)
	_, st, ev := p.Status()
	if engines != "b" || st[0].State != "cooling" || st[0].Fail == 0 || len(ev) == 0 {
		t.Fatalf("engines=%q status=%+v events=%d", engines, st[0], len(ev))
	}
}

func TestPoolAllDisabled(t *testing.T) {
	audio := testAudio(t, "30")
	p := testPool(t, &fake{}, &fake{})
	p.SetConfig(PoolConfig{Disabled: []string{"a", "b"}})
	if _, _, err := p.Transcribe(context.Background(), audio, nil); err == nil {
		t.Fatal("expected error with no channels")
	}
}

// A failed run keeps its finished chunks; the next run only redoes the rest.
func TestPoolResumesFinishedChunks(t *testing.T) {
	audio := testAudio(t, "3700") // 4 chunks
	f := &fake{fail: errors.New("boom"), after: 2}
	p := newPool("", []*channel{{id: "a", name: "A", slots: 1, eng: f}})
	p.SetConfig(PoolConfig{Concurrency: 1})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if _, _, err := p.Transcribe(ctx, audio, nil); err == nil {
		t.Fatal("expected failure")
	}
	if n := f.calls.Load(); n != 3 {
		t.Fatalf("first run made %d calls, want 3", n)
	}
	_, st, _ := p.Status()
	if st[0].State != "cooling" || st[0].Busy != 0 {
		t.Fatalf("status after failure: %+v", st[0])
	}
	p.chans[0].coolUntil = time.Time{}
	f.fail = nil
	us, _, err := p.Transcribe(context.Background(), audio, nil)
	if err != nil {
		t.Fatal(err)
	}
	checkCoverage(t, us, 3700)
	if n := f.calls.Load(); n != 5 {
		t.Fatalf("second run redid finished chunks: %d calls in total, want 5", n)
	}
	if len(p.cache) != 0 {
		t.Fatal("cache not cleared after success")
	}
}

// With every channel cooling, pick reports when to look again.
func TestPoolReportsCooldown(t *testing.T) {
	p := testPool(t, &fake{}, &fake{})
	soon := time.Now().Add(time.Minute)
	p.chans[0].coolUntil, p.chans[1].coolUntil = soon.Add(time.Minute), soon
	c, wake, at, err := p.pick(60, nil)
	if c != nil || wake == nil || err != nil || !at.Equal(soon) {
		t.Fatalf("pick = %v %v %v %v", c, wake, at, err)
	}
}
