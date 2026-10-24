// Package jobs schedules downloads and transcription with per-kind
// concurrency, pause/resume and persistence across restarts.
package jobs

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"lookstudio/lookd/internal/asr"
	"lookstudio/lookd/internal/dl"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/mineru"
	"lookstudio/lookd/internal/store"
	"lookstudio/lookd/internal/tongji"
)

// courseware fetches files the platform attaches (rare); parse turns uploaded
// courseware into Markdown with MinerU.
var Kinds = []string{"video", "slides", "courseware", "transcript", "parse"}

type Config struct {
	VideoParallel int    `json:"video_parallel"`
	Stream        string `json:"stream"` // preferred stream label, "" = first
	KeepAudio     bool   `json:"keep_audio"`
	// DeleteVideoAfterTranscript removes the lecture's downloaded video once
	// its transcript is saved, to save space.
	DeleteVideoAfterTranscript bool `json:"delete_video_after_transcript"`
	SlideParallel              int  `json:"slide_parallel"`
}

type Manager struct {
	St  *store.Store
	Lib *library.Library
	Cl  *tongji.Client
	Eng *dl.Engine
	ASR *asr.Pool
	Bus *events.Bus
	// MinerU parses uploaded courseware; set before Run.
	MinerU *mineru.Service

	cfg     atomic.Pointer[Config]
	mu      sync.Mutex
	running map[string]*runCtl
	live    map[string]*store.Job
	busy    map[string]int
	retry   map[string]retryState
	wake    chan struct{}
}

type runCtl struct {
	cancel context.CancelFunc
	reason atomic.Value // "paused" | "canceled"
}

func New(st *store.Store, lib *library.Library, cl *tongji.Client, eng *dl.Engine, a *asr.Pool, bus *events.Bus) *Manager {
	m := &Manager{St: st, Lib: lib, Cl: cl, Eng: eng, ASR: a, Bus: bus,
		running: map[string]*runCtl{}, live: map[string]*store.Job{}, busy: map[string]int{}, retry: map[string]retryState{}, wake: make(chan struct{}, 1)}
	m.SetConfig(Config{VideoParallel: 2, SlideParallel: 8})
	return m
}

func (m *Manager) SetConfig(c Config) {
	if c.VideoParallel <= 0 {
		c.VideoParallel = 2
	}
	if c.SlideParallel <= 0 {
		c.SlideParallel = 8
	}
	m.cfg.Store(&c)
	m.poke()
}

func (m *Manager) limit(kind string) int {
	c := m.cfg.Load()
	switch kind {
	case "video":
		return c.VideoParallel
	case "transcript":
		return 2
	case "parse":
		return 1
	default:
		return 3
	}
}

func (m *Manager) poke() {
	select {
	case m.wake <- struct{}{}:
	default:
	}
}

func jobID(lectureID, kind string) string { return lectureID + "-" + kind }

// Enqueue queues the given artifact kinds for a lecture (idempotent). A
// paused, failed or canceled job is queued again with its progress, and its
// download resumes from the checkpoint.
func (m *Manager) Enqueue(ctx context.Context, lectureID string, kinds []string) ([]store.Job, error) {
	lec, err := m.St.Lecture(ctx, lectureID)
	if err != nil {
		return nil, fmt.Errorf("未知节次 %s", lectureID)
	}
	c, _ := m.St.Course(ctx, lec.CourseID)
	var out []store.Job
	for _, k := range kinds {
		valid := false
		for _, v := range Kinds {
			valid = valid || v == k
		}
		if !valid {
			return nil, fmt.Errorf("未知任务类型 %s", k)
		}
		id := jobID(lectureID, k)
		m.clearRetry(id)
		if j, err := m.St.Job(ctx, id); err == nil && j.State != "done" {
			if j.State != "running" && j.State != "queued" {
				j.State, j.Error = "queued", ""
				if err := m.St.PutJob(ctx, j); err != nil {
					return nil, err
				}
				m.Bus.Publish("job", j)
			}
			out = append(out, j)
			continue
		}
		j := store.Job{ID: id, CourseID: lec.CourseID, LectureID: lectureID, Kind: k, State: "queued",
			Title: strings.TrimSpace(c.Title + " · " + lec.Title)}
		if err := m.St.PutJob(ctx, j); err != nil {
			return nil, err
		}
		j, _ = m.St.Job(ctx, id)
		m.Bus.Publish("job", j)
		out = append(out, j)
	}
	m.poke()
	return out, nil
}

// List merges persisted jobs with live speed/stage information.
func (m *Manager) List(ctx context.Context) ([]store.Job, error) {
	js, err := m.St.Jobs(ctx)
	if err != nil {
		return nil, err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := range js {
		if l, ok := m.live[js[i].ID]; ok {
			js[i] = *l
		} else if r, ok := m.retry[js[i].ID]; ok && js[i].State == "queued" {
			js[i].RetryAt = r.at.Unix()
		}
	}
	return js, nil
}

func (m *Manager) clearRetry(id string) {
	m.mu.Lock()
	delete(m.retry, id)
	m.mu.Unlock()
}

// Bulk pauses every queued or running job, resumes every paused one,
// retries every failed one or cancels every unfinished one; ids, when
// given, limit it to those jobs. It
// returns how many jobs it changed.
func (m *Manager) Bulk(ctx context.Context, action string, ids []string) (int, error) {
	from := map[string][]string{"pause": {"queued", "running"}, "resume": {"paused"}, "retry": {"failed"}, "cancel": {"queued", "running", "paused"}}[action]
	if from == nil {
		return 0, fmt.Errorf("未知操作 %s", action)
	}
	js, err := m.St.Jobs(ctx, from...)
	if err != nil {
		return 0, err
	}
	only := map[string]bool{}
	for _, id := range ids {
		only[id] = true
	}
	n := 0
	for _, j := range js {
		if len(ids) > 0 && !only[j.ID] {
			continue
		}
		switch action {
		case "pause":
			err = m.Pause(ctx, j.ID)
		case "cancel":
			err = m.Cancel(ctx, j.ID)
		default:
			err = m.Resume(ctx, j.ID)
		}
		if err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

func (m *Manager) Pause(ctx context.Context, id string) error  { return m.stop(ctx, id, "paused") }
func (m *Manager) Cancel(ctx context.Context, id string) error { return m.stop(ctx, id, "canceled") }

func (m *Manager) stop(ctx context.Context, id, reason string) error {
	m.mu.Lock()
	rc := m.running[id]
	delete(m.retry, id)
	m.mu.Unlock()
	if rc != nil {
		rc.reason.Store(reason)
		rc.cancel()
		return nil
	}
	j, err := m.St.Job(ctx, id)
	if err != nil {
		return err
	}
	if j.State == "queued" || (reason == "canceled" && j.State != "done") {
		j.State = reason
		m.St.PutJob(ctx, j)
		m.Bus.Publish("job", j)
	}
	return nil
}

func (m *Manager) Resume(ctx context.Context, id string) error {
	j, err := m.St.Job(ctx, id)
	if err != nil {
		return err
	}
	if j.State == "running" || (j.State == "queued" && j.Error == "") {
		return nil
	}
	m.clearRetry(id) // a job waiting to retry runs now
	j.State, j.Error = "queued", ""
	if err := m.St.PutJob(ctx, j); err != nil {
		return err
	}
	m.Bus.Publish("job", j)
	m.poke()
	return nil
}

func (m *Manager) Remove(ctx context.Context, id string) error {
	m.stop(ctx, id, "canceled")
	if err := m.St.DeleteJob(ctx, id); err != nil {
		return err
	}
	m.Bus.Publish("job_removed", map[string]string{"id": id})
	return nil
}

// Run is the scheduler loop.
func (m *Manager) Run(ctx context.Context) {
	// Jobs interrupted by a previous shutdown go back to the queue.
	if js, err := m.St.Jobs(ctx, "running"); err == nil {
		for _, j := range js {
			j.State = "queued"
			m.St.PutJob(ctx, j)
		}
	}
	t := time.NewTicker(3 * time.Second)
	defer t.Stop()
	for {
		m.schedule(ctx)
		select {
		case <-ctx.Done():
			return
		case <-m.wake:
		case <-t.C:
		}
	}
}

func (m *Manager) schedule(ctx context.Context) {
	js, err := m.St.Jobs(ctx, "queued")
	if err != nil {
		return
	}
	// oldest first
	for i := len(js) - 1; i >= 0; i-- {
		j := js[i]
		m.mu.Lock()
		if _, ok := m.running[j.ID]; ok || m.busy[j.Kind] >= m.limit(j.Kind) || time.Now().Before(m.retry[j.ID].at) {
			m.mu.Unlock()
			continue
		}
		jctx, cancel := context.WithCancel(ctx)
		rc := &runCtl{cancel: cancel}
		m.running[j.ID] = rc
		m.busy[j.Kind]++
		jj := j
		jj.State, jj.Error = "running", ""
		m.live[j.ID] = &jj
		m.mu.Unlock()
		m.St.PutJob(ctx, jj)
		m.Bus.Publish("job", jj)
		go m.run(jctx, rc, jj)
	}
}

func (m *Manager) update(j *store.Job, f func(*store.Job)) {
	m.mu.Lock()
	f(j)
	cp := *j
	m.mu.Unlock()
	m.Bus.Publish("job", cp)
}

func (m *Manager) run(ctx context.Context, rc *runCtl, j store.Job) {
	m.mu.Lock()
	live := m.live[j.ID]
	m.mu.Unlock()
	var lastSave time.Time
	progress := func(f func(*store.Job)) {
		m.update(live, f)
		if time.Since(lastSave) > 2*time.Second {
			lastSave = time.Now()
			m.mu.Lock()
			cp := *live
			m.mu.Unlock()
			m.St.PutJob(context.Background(), cp)
		}
	}
	var err error
	switch j.Kind {
	case "video":
		err = m.runVideo(ctx, j, progress)
	case "slides":
		err = m.runSlides(ctx, j, progress)
	case "courseware":
		err = m.runCourseware(ctx, j, progress)
	case "transcript":
		err = m.runTranscript(ctx, j, progress)
	case "parse":
		err = m.runParse(ctx, j, progress)
	}
	m.mu.Lock()
	delete(m.running, j.ID)
	delete(m.live, j.ID)
	m.busy[j.Kind]--
	final := *live
	m.mu.Unlock()
	final.Speed, final.Conns, final.Stage = 0, 0, ""
	switch {
	case err == nil:
		final.State, final.Progress, final.Error = "done", 1, ""
		m.clearRetry(j.ID)
	case ctx.Err() != nil:
		reason, _ := rc.reason.Load().(string)
		if reason == "" {
			reason = "queued" // daemon shutdown: resume next start
		}
		final.State = reason
	default:
		m.mu.Lock()
		r := m.retry[j.ID]
		at, again := nextRetry(err, r.n, time.Now())
		if again {
			m.retry[j.ID] = retryState{n: r.n + 1, at: at}
		} else {
			delete(m.retry, j.ID)
		}
		m.mu.Unlock()
		if again {
			final.State, final.Error, final.RetryAt = "queued", fmt.Sprintf("网络中断，将自动重试（第 %d/%d 次）：%v", r.n+1, len(retryDelays), err), at.Unix()
			slog.Info("job will retry", "id", j.ID, "at", at, "err", err)
		} else {
			final.State, final.Error = "failed", err.Error()
			slog.Warn("job failed", "id", j.ID, "err", err)
		}
	}
	m.St.PutJob(context.Background(), final)
	m.Bus.Publish("job", final)
	if final.State == "done" {
		m.Bus.Publish("lecture_changed", map[string]string{"lecture_id": j.LectureID, "course_id": j.CourseID})
	}
	m.poke()
}

type progressFn func(func(*store.Job))

func pickStream(ss []tongji.Stream, pref string) (tongji.Stream, error) {
	if len(ss) == 0 {
		return tongji.Stream{}, errors.New("该节次没有可用的回放视频")
	}
	for _, s := range ss {
		if pref != "" && s.Label == pref {
			return s, nil
		}
	}
	return ss[0], nil
}

func (m *Manager) runVideo(ctx context.Context, j store.Job, p progressFn) error {
	_, _, dir, err := m.Lib.EnsureLecture(ctx, j.LectureID)
	if err != nil {
		return err
	}
	media, err := m.Cl.LectureMedia(ctx, j.CourseID, j.LectureID)
	if err != nil {
		return err
	}
	s, err := pickStream(media.Streams, m.cfg.Load().Stream)
	if err != nil {
		return err
	}
	rel := dir + "/video.mp4"
	err = m.Eng.Fetch(ctx, dl.Request{URL: s.URL, Header: media.Headers, Dest: m.Lib.Abs(rel),
		Refresh: func(ctx context.Context) (string, error) { return m.Cl.StreamURL(ctx, s.RawURL) },
	}, func(pr dl.Progress) {
		p(func(j *store.Job) {
			j.DoneBytes, j.TotalBytes, j.Speed, j.Conns, j.Stage = pr.Done, pr.Total, pr.Speed, pr.Conns, "下载中"
			if pr.Total > 0 {
				j.Progress = float64(pr.Done) / float64(pr.Total)
			}
		})
	})
	if err != nil {
		return err
	}
	fi, err := os.Stat(m.Lib.Abs(rel))
	if err != nil {
		return err
	}
	meta, _ := json.Marshal(map[string]any{"stream": s.Label, "duration": media.Duration})
	m.St.PutAsset(ctx, store.Asset{LectureID: j.LectureID, Kind: "video", Path: rel, Bytes: fi.Size(), Meta: meta})
	m.St.SetLectureMedia(ctx, j.LectureID, media.Duration, s.Thumb)
	return m.Lib.WriteLectureJSON(ctx, j.LectureID)
}

func clockName(sec int64) string {
	return fmt.Sprintf("%02d-%02d-%02d", sec/3600, sec%3600/60, sec%60)
}

func extOf(u string) string {
	u = strings.SplitN(u, "?", 2)[0]
	e := strings.ToLower(filepath.Ext(u))
	switch e {
	case ".jpg", ".jpeg", ".png", ".webp":
		return e
	}
	return ".jpg"
}

func (m *Manager) runSlides(ctx context.Context, j store.Job, p progressFn) error {
	_, _, dir, err := m.Lib.EnsureLecture(ctx, j.LectureID)
	if err != nil {
		return err
	}
	snaps, err := m.Cl.Slides(ctx, j.CourseID, j.LectureID)
	if err != nil {
		return err
	}
	if len(snaps) == 0 {
		return errors.New("该节次没有 PPT 快照")
	}
	slides := make([]store.Slide, len(snaps))
	var done, bytes atomic.Int64
	var firstErr atomic.Value
	sem := make(chan struct{}, m.cfg.Load().SlideParallel)
	var wg sync.WaitGroup
	h := m.Cl.S.Header()
	for i, s := range snaps {
		rel := fmt.Sprintf("%s/slides/%04d_t%s%s", dir, i+1, clockName(s.TSec), extOf(s.ImageURL))
		slides[i] = store.Slide{Idx: i + 1, TSec: s.TSec, IsKey: s.IsKey, RemoteURL: s.ImageURL}
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, url, rel string) {
			defer wg.Done()
			defer func() { <-sem }()
			n, err := m.Eng.FetchSmall(ctx, m.Cl.S.URL(url), h, m.Lib.Abs(rel))
			if err != nil {
				firstErr.CompareAndSwap(nil, err)
				return
			}
			slides[i].Path = rel
			bytes.Add(n)
			d := done.Add(1)
			p(func(j *store.Job) {
				j.Progress, j.DoneBytes, j.Stage = float64(d)/float64(len(snaps)), bytes.Load(), fmt.Sprintf("%d/%d 张", d, len(snaps))
			})
		}(i, s.ImageURL, rel)
	}
	wg.Wait()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err := m.St.ReplaceSlides(ctx, j.LectureID, slides); err != nil {
		return err
	}
	idx := make([]map[string]any, 0, len(slides))
	for _, s := range slides {
		if s.Path != "" {
			idx = append(idx, map[string]any{"idx": s.Idx, "t_sec": s.TSec, "file": filepath.Base(s.Path), "is_key": s.IsKey})
		}
	}
	b, _ := json.MarshalIndent(map[string]any{"schema": "look-studio/slides@1", "lecture_id": j.LectureID, "items": idx}, "", "  ")
	os.WriteFile(m.Lib.Abs(dir+"/slides/index.json"), b, 0o644)
	meta, _ := json.Marshal(map[string]any{"count": len(idx), "failed": len(snaps) - len(idx)})
	m.St.PutAsset(ctx, store.Asset{LectureID: j.LectureID, Kind: "slides", Path: dir + "/slides", Bytes: bytes.Load(), Meta: meta})
	m.Lib.WriteLectureJSON(ctx, j.LectureID)
	if e, _ := firstErr.Load().(error); e != nil && len(idx) == 0 {
		return e
	}
	return nil
}

func (m *Manager) runCourseware(ctx context.Context, j store.Job, p progressFn) error {
	_, _, dir, err := m.Lib.EnsureLecture(ctx, j.LectureID)
	if err != nil {
		return err
	}
	media, err := m.Cl.LectureMedia(ctx, j.CourseID, j.LectureID)
	if err != nil {
		return err
	}
	if len(media.Courseware) == 0 {
		return errors.New("老师未上传课件")
	}
	for i, cw := range media.Courseware {
		name := library.Sanitize(cw.Name, fmt.Sprintf("课件%d%s", i+1, filepath.Ext(cw.URL)))
		rel := dir + "/courseware/" + name
		err := m.Eng.Fetch(ctx, dl.Request{URL: cw.URL, Header: media.Headers, Dest: m.Lib.Abs(rel)}, func(pr dl.Progress) {
			p(func(j *store.Job) {
				j.DoneBytes, j.TotalBytes, j.Speed, j.Stage = pr.Done, pr.Total, pr.Speed, name
				if pr.Total > 0 {
					j.Progress = (float64(i) + float64(pr.Done)/float64(pr.Total)) / float64(len(media.Courseware))
				}
			})
		})
		if err != nil {
			return err
		}
		fi, _ := os.Stat(m.Lib.Abs(rel))
		meta, _ := json.Marshal(map[string]any{"name": cw.Name})
		m.St.PutAsset(ctx, store.Asset{LectureID: j.LectureID, Kind: "courseware", Path: rel, Bytes: fi.Size(), Meta: meta})
	}
	return m.Lib.WriteLectureJSON(ctx, j.LectureID)
}

// runParse converts the lecture's unparsed courseware with MinerU, one file
// at a time; a failing file does not stop the others.
func (m *Manager) runParse(ctx context.Context, j store.Job, p progressFn) error {
	if m.MinerU == nil {
		return errors.New("课件解析不可用")
	}
	all, err := m.Lib.Courseware(ctx, j.LectureID)
	if err != nil {
		return err
	}
	var todo []store.Asset
	for _, a := range all {
		if pi := library.CoursewareInfo(a).Parse; pi == nil || pi.State != "done" {
			todo = append(todo, a)
		}
	}
	if len(todo) == 0 {
		return errors.New("没有需要解析的课件，请先上传")
	}
	var failed []string
	for i, a := range todo {
		name := library.CoursewareInfo(a).Name
		pages, mode, err := m.MinerU.Parse(ctx, m.Lib.Abs(a.Path), m.Lib.Abs(library.ParsedDir(a.Path)), func(stage string, frac float64) {
			p(func(j *store.Job) {
				j.Stage = name + " · " + stage
				j.Progress = (float64(i) + min(frac, 1)) / float64(len(todo))
			})
		})
		if ctx.Err() != nil {
			return ctx.Err()
		}
		info := &library.ParseInfo{State: "done", Pages: pages, Mode: mode, At: time.Now().Unix(), MD: library.ParsedDir(a.Path) + "/full.md"}
		if err != nil {
			info = &library.ParseInfo{State: "failed", Mode: mode, Error: err.Error(), At: time.Now().Unix()}
			failed = append(failed, name+"："+err.Error())
		}
		m.Lib.SetParse(ctx, a, info)
		m.Bus.Publish("lecture_changed", map[string]string{"lecture_id": j.LectureID, "course_id": j.CourseID})
	}
	if len(failed) > 0 {
		return errors.New(strings.Join(failed, "；"))
	}
	return nil
}

// localVideo returns the library path of a downloaded video, if any.
func (m *Manager) localVideo(ctx context.Context, lectureID string) string {
	as, _ := m.St.Assets(ctx, lectureID)
	for _, a := range as {
		if a.Kind == "video" {
			if _, err := os.Stat(m.Lib.Abs(a.Path)); err == nil {
				return m.Lib.Abs(a.Path)
			}
		}
	}
	return ""
}

func (m *Manager) runTranscript(ctx context.Context, j store.Job, p progressFn) error {
	if !asr.HasFFmpeg() {
		return errors.New("未找到 ffmpeg，无法提取音频")
	}
	if _, _, _, err := m.Lib.EnsureLecture(ctx, j.LectureID); err != nil {
		return err
	}
	// If the video is being downloaded anyway, wait for it instead of fetching twice.
	for {
		vj, err := m.St.Job(ctx, jobID(j.LectureID, "video"))
		if err != nil || (vj.State != "queued" && vj.State != "running") {
			break
		}
		p(func(j *store.Job) { j.Stage = "等待视频下载完成" })
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
	cache := m.Lib.Abs(".cache")
	os.MkdirAll(cache, 0o755)
	src := m.localVideo(ctx, j.LectureID)
	tmpVideo := ""
	if src == "" {
		media, err := m.Cl.LectureMedia(ctx, j.CourseID, j.LectureID)
		if err != nil {
			return err
		}
		s, err := pickStream(media.Streams, m.cfg.Load().Stream)
		if err != nil {
			return err
		}
		tmpVideo = filepath.Join(cache, j.LectureID+".mp4")
		err = m.Eng.Fetch(ctx, dl.Request{URL: s.URL, Header: media.Headers, Dest: tmpVideo,
			Refresh: func(ctx context.Context) (string, error) { return m.Cl.StreamURL(ctx, s.RawURL) },
		}, func(pr dl.Progress) {
			p(func(j *store.Job) {
				j.DoneBytes, j.TotalBytes, j.Speed, j.Conns, j.Stage = pr.Done, pr.Total, pr.Speed, pr.Conns, "获取音视频"
				if pr.Total > 0 {
					j.Progress = 0.5 * float64(pr.Done) / float64(pr.Total)
				}
			})
		})
		if err != nil {
			return err
		}
		src = tmpVideo
	}
	mp3 := filepath.Join(cache, j.LectureID+".mp3")
	defer func() {
		if tmpVideo != "" {
			os.Remove(tmpVideo)
		}
		os.Remove(mp3)
	}()
	p(func(j *store.Job) { j.Stage, j.Speed, j.Conns, j.Progress = "提取音频", 0, 0, 0.55 })
	if err := asr.ExtractAudio(ctx, src, "", mp3); err != nil {
		return err
	}
	var utts []asr.Utterance
	var engine string
	var err error
	for attempt := 1; attempt <= 3; attempt++ {
		utts, engine, err = m.ASR.Transcribe(ctx, mp3, func(stage string, frac float64) {
			p(func(j *store.Job) { j.Stage, j.Progress = stage, 0.6+0.35*min(frac, 1) })
		})
		if err == nil || ctx.Err() != nil {
			break
		}
		p(func(j *store.Job) { j.Stage = fmt.Sprintf("识别失败，第 %d 次重试", attempt) })
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(attempt*10) * time.Second):
		}
	}
	if err != nil {
		return err
	}
	segs := make([]store.Segment, 0, len(utts))
	for _, u := range utts {
		if t := strings.TrimSpace(u.Text); t != "" {
			segs = append(segs, store.Segment{Idx: len(segs), StartMs: u.StartMs, EndMs: u.EndMs, Text: t})
		}
	}
	if err := m.Lib.SaveTranscript(ctx, j.LectureID, segs, engine); err != nil {
		return err
	}
	if m.cfg.Load().DeleteVideoAfterTranscript && m.localVideo(ctx, j.LectureID) != "" {
		p(func(j *store.Job) { j.Stage = "删除视频" })
		if freed, err := m.Lib.RemoveAsset(ctx, j.LectureID, "video"); err == nil {
			slog.Info("video removed after transcript", "lecture", j.LectureID, "bytes", freed)
			m.forget(ctx, jobID(j.LectureID, "video"))
		}
	}
	return nil
}

// forget drops a finished job record whose files no longer exist.
func (m *Manager) forget(ctx context.Context, id string) {
	if vj, err := m.St.Job(ctx, id); err == nil && vj.State == "done" {
		if m.St.DeleteJob(ctx, id) == nil {
			m.Bus.Publish("job_removed", map[string]string{"id": id})
		}
	}
}

// RemoveFiles deletes the artifact files a job produced and the job record.
func (m *Manager) RemoveFiles(ctx context.Context, id string) (int64, error) {
	j, err := m.St.Job(ctx, id)
	if err != nil {
		return 0, err
	}
	m.stop(ctx, id, "canceled")
	freed, err := m.Lib.RemoveAsset(ctx, j.LectureID, j.Kind)
	if err != nil {
		return freed, err
	}
	if err := m.Remove(ctx, id); err != nil {
		return freed, err
	}
	m.Bus.Publish("lecture_changed", map[string]string{"lecture_id": j.LectureID, "course_id": j.CourseID})
	return freed, nil
}
