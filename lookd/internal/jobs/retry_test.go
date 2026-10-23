package jobs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/store"
)

func TestTransientFailuresRetryWithGrowingDelays(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	offline := &url.Error{Op: "Get", URL: "https://look.tongji.edu.cn/x", Err: &net.OpError{Op: "dial", Err: syscall.ECONNREFUSED}}
	for name, err := range map[string]error{
		"offline":   offline,
		"wrapped":   fmt.Errorf("lecture media: %w", offline),
		"reset":     fmt.Errorf("read: %w", syscall.ECONNRESET),
		"short":     io.ErrUnexpectedEOF,
		"deadline":  context.DeadlineExceeded,
		"unwritten": fmt.Errorf("x: %w", syscall.EPIPE),
	} {
		at, ok := nextRetry(err, 0, now)
		if !ok || at.Sub(now) != retryDelays[0] {
			t.Errorf("%s: retry %v at +%v", name, ok, at.Sub(now))
		}
	}
	prev := time.Duration(0)
	for n := range retryDelays {
		at, ok := nextRetry(offline, n, now)
		if !ok || at.Sub(now) <= prev {
			t.Fatalf("retry %d: %v +%v", n, ok, at.Sub(now))
		}
		prev = at.Sub(now)
	}
	if _, ok := nextRetry(offline, len(retryDelays), now); ok {
		t.Fatal("retried past the last delay")
	}
	for name, err := range map[string]error{
		"no video":  errors.New("该节次没有可用的回放视频"),
		"canceled":  context.Canceled,
		"disk full": fmt.Errorf("write: %w", syscall.ENOSPC),
		"nil":       nil,
	} {
		if _, ok := nextRetry(err, 0, now); ok {
			t.Errorf("%s retried", name)
		}
	}
}

func TestBulkActionsAndRequeueKeepProgress(t *testing.T) {
	ctx := context.Background()
	st, err := store.Open(filepath.Join(t.TempDir(), "library.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	st.UpsertCourse(ctx, store.Course{ID: "C1", Title: "数据结构"})
	st.UpsertLectures(ctx, []store.Lecture{{ID: "L1", CourseID: "C1", Title: "栈"}, {ID: "L2", CourseID: "C1", Title: "队列"}})
	m := New(st, nil, nil, nil, nil, events.New())
	put := func(id, state string) {
		st.PutJob(ctx, store.Job{ID: id, CourseID: "C1", LectureID: id[:2], Kind: id[3:], State: state, DoneBytes: 500, TotalBytes: 1000, Progress: 0.5})
	}
	put("L1-video", "failed")
	put("L2-video", "paused")
	put("L1-slides", "queued")
	state := func(id string) store.Job { j, _ := st.Job(ctx, id); return j }

	if n, err := m.Bulk(ctx, "retry", nil); err != nil || n != 1 || state("L1-video").State != "queued" {
		t.Fatalf("retry: %d %v %s", n, err, state("L1-video").State)
	}
	if n, _ := m.Bulk(ctx, "pause", []string{"L1-slides"}); n != 1 || state("L1-slides").State != "paused" || state("L1-video").State != "queued" {
		t.Fatalf("pause one: %d", n)
	}
	if n, _ := m.Bulk(ctx, "resume", nil); n != 2 || state("L2-video").State != "queued" {
		t.Fatalf("resume: %d", n)
	}
	if n, _ := m.Bulk(ctx, "cancel", []string{"L2-video"}); n != 1 || state("L2-video").State != "canceled" || state("L1-video").State != "queued" {
		t.Fatalf("cancel one: %d %s", n, state("L2-video").State)
	}
	if _, err := m.Bulk(ctx, "explode", nil); err == nil {
		t.Fatal("unknown action accepted")
	}

	// Queuing a paused lecture again keeps its progress for the resume.
	m.Pause(ctx, "L2-video")
	if _, err := m.Enqueue(ctx, "L2", []string{"video"}); err != nil {
		t.Fatal(err)
	}
	if j := state("L2-video"); j.State != "queued" || j.DoneBytes != 500 || j.Progress != 0.5 {
		t.Fatalf("requeued: %+v", j)
	}

	// A job waiting to retry is skipped until its time, and shows when.
	put("L2-video", "paused")
	put("L1-slides", "paused")
	m.retry["L1-video"] = retryState{n: 1, at: time.Now().Add(time.Hour)}
	m.schedule(ctx)
	if _, running := m.running["L1-video"]; running {
		t.Fatal("ran before its retry time")
	}
	js, _ := m.List(ctx)
	for _, j := range js {
		if j.ID == "L1-video" && j.RetryAt == 0 {
			t.Fatal("retry time not listed")
		}
	}
	// Retrying by hand runs it now.
	st.PutJob(ctx, store.Job{ID: "L1-video", CourseID: "C1", LectureID: "L1", Kind: "video", State: "queued", Error: "网络中断"})
	m.Resume(ctx, "L1-video")
	if _, waiting := m.retry["L1-video"]; waiting {
		t.Fatal("manual retry kept the wait")
	}
}
