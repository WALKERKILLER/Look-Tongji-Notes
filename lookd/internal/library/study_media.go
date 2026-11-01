package library

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type StudyMediaClip struct {
	Text         string `json:"text"`
	ImagePath    string `json:"image_path,omitempty"`
	Fingerprint  string `json:"fingerprint"`
	Availability string `json:"availability"`
}

// Only a saved, explicit video object (or its lecture's indexed local video) may be processed.
func (l *Library) studyMediaFile(ctx context.Context, lecture, object string) (*os.File, error) {
	d, e := l.StudyCanvas(ctx, lecture)
	if e != nil {
		return nil, e
	}
	for _, o := range d.Objects {
		if o.ID != object {
			continue
		}
		if o.Type == "video" {
			if o.Path == "" && o.OriginalPath != "" {
				return l.StudyCourseSource(ctx, lecture, o.OriginalPath)
			}
			return l.StudySource(ctx, lecture, o.Path)
		}
		if o.Type == "lecture" {
			assets, e := l.Store.Assets(ctx, lecture)
			if e != nil {
				return nil, e
			}
			for _, a := range assets {
				if a.Kind == "video" {
					return l.StudySource(ctx, lecture, a.Path)
				}
			}
		}
	}
	return nil, fmt.Errorf("%w：此视频没有可读取的本地文件，请先下载；不会上传完整视频", ErrStudyInvalid)
}
func (l *Library) studyClipKey(ctx context.Context, lecture, object string, from, to int64) (*os.File, string, error) {
	if from < 0 || to <= from || to-from > 180000 || to > 7*24*3600*1000 {
		return nil, "", ErrStudyInvalid
	}
	f, e := l.studyMediaFile(ctx, lecture, object)
	if e != nil {
		return nil, "", e
	}
	st, e := f.Stat()
	if e != nil {
		f.Close()
		return nil, "", e
	}
	key := studyHash(fmt.Sprintf("%s|%s|%d|%d|%d|%d", lecture, object, st.Size(), st.ModTime().UnixNano(), from, to))
	return f, key, nil
}
func (l *Library) CachedStudyClip(ctx context.Context, lecture, object string, from, to int64) (StudyMediaClip, bool) {
	var out StudyMediaClip
	f, key, e := l.studyClipKey(ctx, lecture, object, from, to)
	if e != nil {
		return out, false
	}
	f.Close()
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	r, dir, e := l.studyRoot(ctx, lecture)
	if e != nil {
		return out, false
	}
	defer r.Close()
	b, e := r.ReadFile(dir + "/.study-cache/" + key + ".json")
	if e != nil || len(b) > 100000 {
		return out, false
	}
	e = json.Unmarshal(b, &out)
	return out, e == nil
}
func (l *Library) PrepareStudyClip(ctx context.Context, lecture, object string, from, to int64, render func(context.Context, *os.File, string) (StudyMediaClip, error)) (StudyMediaClip, error) {
	var out StudyMediaClip
	f, key, e := l.studyClipKey(ctx, lecture, object, from, to)
	if e != nil {
		return out, e
	}
	defer f.Close()
	temp, e := os.MkdirTemp("", "look-study-clip-")
	if e != nil {
		return out, e
	}
	defer os.RemoveAll(temp)
	out, e = render(ctx, f, temp)
	if e != nil {
		return out, e
	}
	if len(out.Text) > 80000 {
		return out, ErrStudyLimit
	}
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	r, dir, e := l.studyRoot(ctx, lecture)
	if e != nil {
		return out, e
	}
	defer r.Close()
	dir += "/.study-cache"
	if e = checkedStudyDir(r, dir, true); e != nil {
		return out, e
	}
	if out.ImagePath != "" {
		b, e := os.ReadFile(filepath.Join(temp, "frame.png"))
		if e != nil {
			return out, e
		}
		if len(b) > 3<<20 {
			return out, ErrStudyLimit
		}
		out.ImagePath = dir + "/" + key + ".png"
		if e = writeStudyBytes(r, out.ImagePath, b); e != nil {
			return out, e
		}
	}
	out.Fingerprint = studyHash(out.Text + key)
	b, e := json.Marshal(out)
	if e != nil {
		return out, e
	}
	e = writeStudyBytes(r, dir+"/"+key+".json", b)
	return out, e
}
