package library

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"lookstudio/lookd/internal/store"
)

// CoursewareExts are the document types users can attach to a lecture.
var CoursewareExts = map[string]bool{
	".pdf": true, ".ppt": true, ".pptx": true, ".doc": true, ".docx": true,
	".xls": true, ".xlsx": true, ".png": true, ".jpg": true, ".jpeg": true, ".webp": true,
}

// ParseInfo records the MinerU result of one courseware file.
type ParseInfo struct {
	State string `json:"state"` // done | failed
	Pages int    `json:"pages,omitempty"`
	MD    string `json:"md,omitempty"` // library path of full.md
	Mode  string `json:"mode,omitempty"`
	Error string `json:"error,omitempty"`
	At    int64  `json:"at"`
}

type CoursewareMeta struct {
	Name     string     `json:"name"`
	Uploaded bool       `json:"uploaded,omitempty"`
	Parse    *ParseInfo `json:"parse,omitempty"`
}

// ParsedDir is where a courseware file's Markdown and images go.
func ParsedDir(rel string) string { return rel + ".parsed" }

// ImportCourseware copies an uploaded document into the lecture's
// courseware/ folder and indexes it.
func (l *Library) ImportCourseware(ctx context.Context, lectureID, name string, r io.Reader, limit int64) (store.Asset, error) {
	ext := strings.ToLower(filepath.Ext(name))
	if !CoursewareExts[ext] {
		return store.Asset{}, fmt.Errorf("不支持的文件类型 %s（支持 PDF、PPT、Word、Excel 和图片）", ext)
	}
	_, _, dir, err := l.EnsureLecture(ctx, lectureID)
	if err != nil {
		return store.Asset{}, err
	}
	stem := Sanitize(strings.TrimSuffix(filepath.Base(name), filepath.Ext(name)), "课件")
	if err := os.MkdirAll(l.Abs(dir+"/courseware"), 0o755); err != nil {
		return store.Asset{}, err
	}
	rel := dir + "/courseware/" + stem + ext
	for i := 2; ; i++ {
		if _, err := os.Stat(l.Abs(rel)); errors.Is(err, os.ErrNotExist) {
			break
		}
		rel = fmt.Sprintf("%s/courseware/%s (%d)%s", dir, stem, i, ext)
	}
	tmp := l.Abs(rel) + ".upload"
	f, err := os.Create(tmp)
	if err != nil {
		return store.Asset{}, err
	}
	n, err := io.Copy(f, io.LimitReader(r, limit+1))
	f.Close()
	switch {
	case err != nil:
		os.Remove(tmp)
		return store.Asset{}, err
	case n > limit:
		os.Remove(tmp)
		return store.Asset{}, fmt.Errorf("文件超过 %d MB", limit>>20)
	case n == 0:
		os.Remove(tmp)
		return store.Asset{}, errors.New("文件是空的")
	}
	if err := os.Rename(tmp, l.Abs(rel)); err != nil {
		return store.Asset{}, err
	}
	meta, _ := json.Marshal(CoursewareMeta{Name: filepath.Base(name), Uploaded: true})
	a := store.Asset{LectureID: lectureID, Kind: "courseware", Path: rel, Bytes: n, Meta: meta}
	if err := l.Store.PutAsset(ctx, a); err != nil {
		return a, err
	}
	return a, l.WriteLectureJSON(ctx, lectureID)
}

// Courseware lists a lecture's courseware files with their parse state.
func (l *Library) Courseware(ctx context.Context, lectureID string) ([]store.Asset, error) {
	as, err := l.Store.Assets(ctx, lectureID)
	if err != nil {
		return nil, err
	}
	out := []store.Asset{}
	for _, a := range as {
		if a.Kind == "courseware" {
			out = append(out, a)
		}
	}
	return out, nil
}

func CoursewareInfo(a store.Asset) CoursewareMeta {
	var m CoursewareMeta
	json.Unmarshal(a.Meta, &m)
	if m.Name == "" {
		m.Name = filepath.Base(a.Path)
	}
	return m
}

// SetParse records a parse result on a courseware asset.
func (l *Library) SetParse(ctx context.Context, a store.Asset, p *ParseInfo) error {
	m := CoursewareInfo(a)
	m.Parse = p
	a.Meta, _ = json.Marshal(m)
	if err := l.Store.PutAsset(ctx, a); err != nil {
		return err
	}
	return l.WriteLectureJSON(ctx, a.LectureID)
}

// RemoveCourseware deletes one courseware file and its parsed output.
func (l *Library) RemoveCourseware(ctx context.Context, lectureID, rel string) (int64, error) {
	as, err := l.Courseware(ctx, lectureID)
	if err != nil {
		return 0, err
	}
	for _, a := range as {
		if a.Path != rel {
			continue
		}
		freed := l.DiskUsage(a.Path) + l.DiskUsage(ParsedDir(a.Path))
		os.Remove(l.Abs(a.Path))
		os.RemoveAll(l.Abs(ParsedDir(a.Path)))
		if err := l.Store.DeleteAsset(ctx, lectureID, "courseware", a.Path); err != nil {
			return freed, err
		}
		return freed, l.WriteLectureJSON(ctx, lectureID)
	}
	return 0, fmt.Errorf("没有这个课件")
}
