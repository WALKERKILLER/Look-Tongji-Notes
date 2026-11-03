package server

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"lookstudio/lookd/internal/library"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

type studyMediaTask struct {
	owner                       *Server
	lecture, id, state, message string
	result                      library.StudyMediaClip
	cancel                      context.CancelFunc
}

var studyMediaTasks = struct {
	sync.Mutex
	jobs map[string]*studyMediaTask
}{jobs: map[string]*studyMediaTask{}}

func (s *Server) studyMedia(w http.ResponseWriter, r *http.Request) (any, error) {
	var q struct {
		ObjectID   string `json:"object_id"`
		From       int64  `json:"from_ms"`
		To         int64  `json:"to_ms"`
		Frame      bool   `json:"frame"`
		Transcribe bool   `json:"transcribe"`
	}
	if r.Method != "POST" {
		studyMediaTasks.Lock()
		defer studyMediaTasks.Unlock()
		j := studyMediaTasks.jobs[r.PathValue("media")]
		if j == nil || j.owner != s || j.lecture != r.PathValue("id") {
			return nil, apiError{404, "片段任务不存在，请重试"}
		}
		if r.Method == "DELETE" {
			j.cancel()
			j.state = "cancelled"
		}
		return map[string]any{"id": j.id, "state": j.state, "message": j.message, "result": j.result}, nil
	}
	if e := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&q); e != nil || q.ObjectID == "" || q.From < 0 || q.To <= q.From || q.To-q.From > 180000 || q.To > 7*24*3600*1000 {
		return nil, badRequest("请选择不超过 180 秒的视频区间")
	}
	studyMediaTasks.Lock()
	defer studyMediaTasks.Unlock()
	active := 0
	for _, j := range studyMediaTasks.jobs {
		if j.owner == s && j.state == "running" {
			active++
		}
	}
	if active >= 2 {
		return nil, apiError{429, "已有两个片段正在处理"}
	}
	for id, j := range studyMediaTasks.jobs {
		if len(studyMediaTasks.jobs) >= 16 && j.state != "running" {
			delete(studyMediaTasks.jobs, id)
		}
	}
	b := make([]byte, 16)
	if _, e := rand.Read(b); e != nil {
		return nil, e
	}
	id := hex.EncodeToString(b)
	base := s.Ctx
	if base == nil {
		base = context.Background()
	}
	ctx, cancel := context.WithTimeout(base, 150*time.Second)
	job := &studyMediaTask{owner: s, lecture: r.PathValue("id"), id: id, state: "running", message: "读取选定的短片段", cancel: cancel}
	studyMediaTasks.jobs[id] = job
	go func() {
		defer cancel()
		result, e := s.Lib.PrepareStudyClip(ctx, job.lecture, q.ObjectID, q.From, q.To, func(ctx context.Context, f *os.File, temp string) (library.StudyMediaClip, error) {
			var out library.StudyMediaClip
			if _, e := exec.LookPath("ffmpeg"); e != nil {
				return out, fmt.Errorf("请在设置 → 诊断安装 ffmpeg")
			}
			run := func(args ...string) error {
				if _, e := f.Seek(0, 0); e != nil {
					return e
				}
				cmd := exec.CommandContext(ctx, "ffmpeg", args...)
				cmd.ExtraFiles = []*os.File{f}
				if e := cmd.Run(); e != nil {
					return fmt.Errorf("视频片段提取失败或已取消")
				}
				return nil
			}
			if q.Frame {
				if e := run("-v", "error", "-ss", fmt.Sprintf("%.3f", float64(q.From)/1000), "-i", "/dev/fd/3", "-frames:v", "1", "-vf", "scale=640:-2", "-y", filepath.Join(temp, "frame.png")); e == nil {
					out.ImagePath = "frame.png"
				}
			}
			if q.Transcribe {
				if s.Jobs == nil || s.Jobs.ASR == nil {
					return out, fmt.Errorf("请配置可用的转录服务")
				}
				_, channels, _ := s.Jobs.ASR.Status()
				ready := false
				for _, c := range channels {
					if c.Enabled {
						ready = true
					}
				}
				if !ready {
					return out, fmt.Errorf("请在设置中启用一个转录服务或本地语音模型")
				}
				audio := filepath.Join(temp, "clip.wav")
				if e := run("-v", "error", "-ss", fmt.Sprintf("%.3f", float64(q.From)/1000), "-i", "/dev/fd/3", "-t", fmt.Sprintf("%.3f", float64(q.To-q.From)/1000), "-vn", "-ac", "1", "-ar", "16000", "-y", audio); e != nil {
					return out, e
				}
				us, _, e := s.Jobs.ASR.Transcribe(ctx, audio, nil)
				if e != nil {
					return out, fmt.Errorf("片段转录失败，请检查转录服务后重试")
				}
				for _, u := range us {
					out.Text += fmt.Sprintf("[%d–%d ms] %s\n", q.From+u.StartMs, q.From+u.EndMs, u.Text)
				}
			}
			out.Availability = "timestamped_transcript"
			if out.Text == "" {
				out.Availability = "frame_only; transcript unavailable"
			}
			return out, nil
		})
		studyMediaTasks.Lock()
		defer studyMediaTasks.Unlock()
		if ctx.Err() != nil {
			job.state = "cancelled"
			job.message = "片段任务已取消或超时"
		} else if e != nil {
			job.state = "error"
			job.message = e.Error()
		} else {
			job.state = "done"
			job.message = "片段已缓存"
			job.result = result
		}
	}()
	return map[string]any{"id": id, "state": "running"}, nil
}

func (s *Server) studyMediaFile(w http.ResponseWriter, r *http.Request) {
	f, e := s.Lib.StudyVideoSource(r.Context(), r.PathValue("id"), r.PathValue("object"))
	if e != nil {
		http.Error(w, "视频文件不可用", 404)
		return
	}
	defer f.Close()
	st, e := f.Stat()
	if e != nil {
		http.Error(w, "视频文件不可用", 404)
		return
	}
	http.ServeContent(w, r, st.Name(), st.ModTime(), f)
}
