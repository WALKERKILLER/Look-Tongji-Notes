package library

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"lookstudio/lookd/internal/store"
)

const LocalVideoLimit int64 = 4 << 30

var ErrLocalInvalid = errors.New("本地课程输入无效")
var ErrLocalLimit = errors.New("视频超过 4 GiB")

func localID() (string, error) {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "local-" + hex.EncodeToString(b), nil
}

func (l *Library) CreateLocalCourse(ctx context.Context, title, teacher string) (store.Course, error) {
	title, teacher = strings.TrimSpace(title), strings.TrimSpace(teacher)
	if title == "" || utf8.RuneCountInString(title) > 200 || utf8.RuneCountInString(teacher) > 100 {
		return store.Course{}, fmt.Errorf("%w：请填写 1–200 字的课程名称", ErrLocalInvalid)
	}
	id, err := localID()
	if err != nil {
		return store.Course{}, err
	}
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	c := store.Course{ID: id, Title: title, Teacher: teacher, Term: "local", Teachers: json.RawMessage("[]")}
	c.Dir = "courses/" + Sanitize(title, "本地课程") + " (" + id + ")"
	root, err := os.OpenRoot(l.Root)
	if err != nil {
		return c, err
	}
	defer root.Close()
	if err := root.Mkdir(c.Dir, 0755); err != nil {
		return c, err
	}
	if err := l.writeCourseJSON(c); err != nil {
		root.Remove(c.Dir)
		return c, err
	}
	if err := l.Store.AdoptCourse(ctx, c); err != nil {
		return c, err
	}
	return l.Store.Course(ctx, id)
}

// ImportLocalVideo publishes one complete lesson. Failed uploads leave no
// manifest or index row; published manifests can rebuild the index after a crash.
func (l *Library) ImportLocalVideo(ctx context.Context, courseID, name string, input io.Reader) (store.Lecture, error) {
	if !store.IsLocalCourse(courseID) {
		return store.Lecture{}, fmt.Errorf("%w：只能向本地课程添加视频", ErrLocalInvalid)
	}
	if name == "" || filepath.Base(name) != name || strings.ContainsAny(name, "\\\x00") {
		return store.Lecture{}, fmt.Errorf("%w：视频文件名无效", ErrLocalInvalid)
	}
	ext := strings.ToLower(filepath.Ext(name))
	if !map[string]bool{".mp4": true, ".mov": true, ".m4v": true, ".mkv": true, ".webm": true}[ext] {
		return store.Lecture{}, fmt.Errorf("%w：支持 MP4、MOV、M4V、MKV、WebM 视频", ErrLocalInvalid)
	}
	if err := ctx.Err(); err != nil {
		return store.Lecture{}, err
	}
	c, err := l.Store.Course(ctx, courseID)
	if err != nil {
		return store.Lecture{}, err
	}
	root, err := os.OpenRoot(l.Root)
	if err != nil {
		return store.Lecture{}, err
	}
	defer root.Close()
	// Refuse redirected course directories, including symlinked ancestors.
	parts := strings.Split(filepath.ToSlash(c.Dir), "/")
	if len(parts) != 2 || parts[0] != "courses" || parts[1] == "" || parts[1] == ".." {
		return store.Lecture{}, fmt.Errorf("%w：课程目录无效", ErrLocalInvalid)
	}
	for i := range parts {
		fi, err := root.Lstat(strings.Join(parts[:i+1], "/"))
		if err != nil {
			return store.Lecture{}, err
		}
		if !fi.IsDir() || fi.Mode()&os.ModeSymlink != 0 {
			return store.Lecture{}, fmt.Errorf("%w：课程目录不可为符号链接", ErrLocalInvalid)
		}
	}
	id, err := localID()
	if err != nil {
		return store.Lecture{}, err
	}
	// Monotonic timestamps in identities preserve import order without class dates.
	id = fmt.Sprintf("local-%019d-%s", time.Now().UnixNano(), strings.TrimPrefix(id, "local-"))
	tmp := ".local-upload-" + id
	if err := root.Mkdir(tmp, 0700); err != nil {
		return store.Lecture{}, err
	}
	defer root.RemoveAll(tmp)
	f, err := root.OpenFile(tmp+"/video"+ext, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return store.Lecture{}, err
	}
	digest := sha256.New()
	n, copyErr := io.Copy(io.MultiWriter(f, digest), io.LimitReader(localUploadReader{ctx, input}, LocalVideoLimit+1))
	closeErr := f.Close()
	if copyErr != nil {
		return store.Lecture{}, copyErr
	}
	if closeErr != nil {
		return store.Lecture{}, closeErr
	}
	if n > LocalVideoLimit {
		return store.Lecture{}, ErrLocalLimit
	}
	if err := ctx.Err(); err != nil {
		return store.Lecture{}, err
	}
	if n == 0 {
		return store.Lecture{}, fmt.Errorf("%w：视频文件为空", ErrLocalInvalid)
	}
	duration, err := localVideoDuration(ctx, l.Abs(tmp+"/video"+ext))
	if err != nil {
		return store.Lecture{}, err
	}
	title := strings.TrimSpace(strings.TrimSuffix(name, filepath.Ext(name)))
	if title == "" {
		title = "视频"
	}
	lec := store.Lecture{ID: id, CourseID: c.ID, Title: title, Lecturer: c.Teacher, HasPlayback: true, DurationS: duration}
	lec.Dir = c.Dir + "/" + Sanitize(title, "视频") + " (" + id + ")"
	checksum := hex.EncodeToString(digest.Sum(nil))
	meta, _ := json.Marshal(map[string]any{"name": name, "uploaded": true, "sha256": checksum})
	a := store.Asset{LectureID: id, Kind: "video", Path: lec.Dir + "/video" + ext, Bytes: n, Meta: meta}
	manifest := map[string]any{"schema": "look-studio/lecture@1", "id": id, "course_id": c.ID,
		"course_title": c.Title, "title": title, "date": "", "begin_at": "", "end_at": "",
		"lecturer": c.Teacher, "duration_seconds": duration, "source": "local", "source_url": "",
		"files": []map[string]any{{"kind": "video", "path": "video" + ext, "bytes": n, "meta": json.RawMessage(meta)}}}
	if err := writeJSON(l.Abs(tmp+"/lecture.json"), manifest); err != nil {
		return store.Lecture{}, err
	}
	l.mirrorMu.Lock()
	defer l.mirrorMu.Unlock()
	// Retrying an upload after a lost response reuses the published lesson.
	previous, err := l.Store.Lectures(ctx, courseID)
	if err != nil {
		return store.Lecture{}, err
	}
	for _, existing := range previous {
		assets, err := l.Store.Assets(ctx, existing.ID)
		if err != nil {
			return store.Lecture{}, err
		}
		for _, asset := range assets {
			var m struct {
				Name   string `json:"name"`
				SHA256 string `json:"sha256"`
			}
			if asset.Kind == "video" && json.Unmarshal(asset.Meta, &m) == nil && m.Name == name && m.SHA256 == checksum {
				if fi, err := root.Stat(asset.Path); err == nil && fi.Mode().IsRegular() {
					return existing, nil
				}
			}
		}
	}
	if err := ctx.Err(); err != nil {
		return store.Lecture{}, err
	}
	if err := root.Rename(tmp, lec.Dir); err != nil {
		return store.Lecture{}, err
	}
	if err := l.Store.AdoptLecture(ctx, lec); err != nil {
		return lec, err
	}
	if err := l.Store.PutAsset(ctx, a); err != nil {
		return lec, err
	}
	return l.Store.Lecture(ctx, id)
}

func localVideoDuration(ctx context.Context, filename string) (int64, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_type:format=duration", "-of", "json", filename)
	var out localProbeOutput
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			return 0, errors.New("无法导入视频：请先在设置中安装 ffmpeg（包含 ffprobe）")
		}
		return 0, fmt.Errorf("%w：无法读取视频，请确认文件可播放", ErrLocalInvalid)
	}
	var info struct {
		Streams []struct {
			Type string `json:"codec_type"`
		} `json:"streams"`
		Format struct {
			Duration string `json:"duration"`
		} `json:"format"`
	}
	if json.Unmarshal(out, &info) != nil || len(info.Streams) == 0 {
		return 0, fmt.Errorf("%w：文件没有视频轨道", ErrLocalInvalid)
	}
	duration, err := strconv.ParseFloat(info.Format.Duration, 64)
	if err != nil || math.IsNaN(duration) || math.IsInf(duration, 0) || duration <= 0 || duration > 365*86400 {
		return 0, fmt.Errorf("%w：视频时长无效", ErrLocalInvalid)
	}
	return int64(math.Ceil(duration)), nil
}

type localProbeOutput []byte

type localUploadReader struct {
	ctx   context.Context
	input io.Reader
}

func (r localUploadReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.input.Read(p)
}

func (b *localProbeOutput) Write(p []byte) (int, error) {
	if len(*b)+len(p) > 16384 {
		return 0, errors.New("video metadata exceeds limit")
	}
	*b = append(*b, p...)
	return len(p), nil
}
