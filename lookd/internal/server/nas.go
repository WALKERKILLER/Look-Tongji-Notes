package server

import (
	"context"
	"encoding/json"
	"io"
	"lookstudio/lookd/internal/nasbridge"
	"lookstudio/lookd/internal/store"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

func (s *Server) nas() *nasbridge.Bridge {
	s.nasOnce.Do(func() { s.nasClient = nasbridge.New() })
	return s.nasClient
}
func (s *Server) nasLinks(ctx context.Context) map[string]string {
	kv, err := s.St.Settings(ctx)
	r := map[string]string{}
	if err == nil {
		json.Unmarshal(kv["nas.course_links"], &r)
	}
	if r == nil {
		r = map[string]string{}
	}
	return r
}
func (s *Server) nasSnapshot(_ http.ResponseWriter, r *http.Request) (any, error) {
	b := s.nas()
	d := b.Snapshot(r.Context(), r.URL.Query().Get("refresh") == "1")
	files, err := b.Files()
	d["files"] = files
	attachNASReports(d, files, b.Root)
	if err != nil {
		d["files_error"] = "本机课程目录不可用或扫描不完整，请在课程同步里检查 WebDAV 连接"
	}
	deadlines, e := b.Deadlines()
	d["deadlines"] = deadlines
	if e != nil {
		d["calendar_error"] = "本机日历尚未同步"
	}
	d["course_links"] = s.nasLinks(r.Context())
	return d, nil
}
func (s *Server) nasLink(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Course        string `json:"course"`
		LectureCourse string `json:"icourse_id"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	files, err := s.nas().Files()
	if err != nil {
		return nil, badRequest("课程目录不可用")
	}
	found := false
	for _, f := range files {
		if f.Course == in.Course {
			found = true
			break
		}
	}
	if !found {
		return nil, badRequest("无效的 NAS 课程")
	}
	if in.LectureCourse != "" {
		if _, err := s.St.Course(r.Context(), in.LectureCourse); err != nil {
			return nil, badRequest("无效的录播课程")
		}
	}
	s.nasLinksMu.Lock()
	defer s.nasLinksMu.Unlock()
	links := s.nasLinks(r.Context())
	links[in.Course] = in.LectureCourse
	raw, _ := json.Marshal(links)
	if err := s.St.PutSettings(r.Context(), map[string]json.RawMessage{"nas.course_links": raw}); err != nil {
		return nil, err
	}
	s.Bus.Publish("schedule_changed", map[string]string{"id": "nas"})
	return links, nil
}
func (s *Server) nasAction(_ http.ResponseWriter, r *http.Request) (any, error) {
	v, err := s.nas().Start(r.Context(), r.PathValue("action"))
	if err != nil {
		return nil, badRequest(err.Error())
	}
	return v, nil
}
func (s *Server) nasText(_ http.ResponseWriter, r *http.Request) (any, error) {
	v, err := s.nas().Text(r.PathValue("id"))
	if err != nil {
		return nil, badRequest("文件不存在、未同步或不支持文本读取")
	}
	return v, nil
}
func (s *Server) nasFile(w http.ResponseWriter, r *http.Request) (any, error) {
	f, meta, err := s.nas().Open(r.PathValue("id"))
	if err != nil {
		return nil, apiError{404, "文件未同步或不可访问"}
	}
	defer f.Close()
	typ := mime.TypeByExtension(strings.ToLower(filepath.Ext(meta.Path)))
	if typ == "" {
		typ = "application/octet-stream"
	}
	if strings.Contains(typ, "html") || strings.Contains(typ, "svg") || strings.HasPrefix(typ, "text/") {
		typ = "text/plain; charset=utf-8"
	}
	w.Header().Set("Content-Type", typ)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "sandbox; default-src 'none'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cache-Control", "private, no-store")
	if typ != "application/pdf" && !strings.HasPrefix(typ, "text/") && !strings.HasPrefix(typ, "image/") {
		w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": filepath.Base(meta.Path)}))
	}
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	http.ServeContent(w, r, filepath.Base(meta.Path), st.ModTime(), f)
	return nil, nil
}

// nasSchedule merges by platform identity, leaving live Canvas state authoritative.
func (s *Server) nasSchedule(ctx context.Context, q store.ScheduleQuery, items []store.ScheduleItem) []store.ScheduleItem {
	if s.Sess == nil || s.Sess.School() != "fudan" || q.LectureID != "" {
		return items
	}
	ds, _ := s.nas().Deadlines()
	links := s.nasLinks(ctx)
	seen := map[string]bool{}
	for _, i := range items {
		seen[i.ID] = true
		if i.URL != "" {
			seen[i.URL] = true
		}
	}
	for _, d := range ds {
		due, err := time.Parse(time.RFC3339, d["due"])
		if err != nil {
			continue
		}
		due = due.In(time.FixedZone("Asia/Shanghai", 8*3600))
		date := due.Format("2006-01-02")
		course := links[d["course"]]
		if q.From != "" && date < q.From || q.To != "" && date > q.To || q.CourseID != "" && course != q.CourseID || q.Open && d["completed"] == "true" {
			continue
		}
		if seen[d["url"]] || d["assignment_id"] != "" && seen["canvas:"+d["assignment_id"]] {
			continue
		}
		seen[d["url"]] = d["url"] != ""
		if d["assignment_id"] != "" {
			seen["canvas:"+d["assignment_id"]] = true
		}
		items = append(items, store.ScheduleItem{ID: d["id"], Kind: "homework", Title: d["title"], DueDate: date, DueTime: due.Format("15:04"), CourseID: course, CourseTitle: d["course"], TMs: -1, Source: "nas", Done: d["completed"] == "true", URL: d["url"], Detail: "NAS 日历 · 提交状态以来源平台为准"})
	}
	return mergeSchedule(items, nil)
}

// Reports are linked only through the worker's published status manifest.
func attachNASReports(d map[string]any, files []nasbridge.File, root string) {
	dir, err := os.OpenRoot(root)
	if err != nil {
		return
	}
	defer dir.Close()
	f, err := dir.Open("自动做作业状态.md")
	if err != nil {
		return
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, (1<<20)+1))
	if err != nil || len(raw) > 1<<20 {
		return
	}
	indexed := map[string]nasbridge.File{}
	for _, f := range files {
		indexed[f.Path] = f
	}
	refs := regexp.MustCompile(`\[\[([^\]|]+)`)
	published := map[string][]map[string]any{}
	for _, line := range strings.Split(string(raw), "\n") {
		parts := strings.Split(line, "|")
		if len(parts) < 5 {
			continue
		}
		key := strings.TrimSpace(parts[1]) + "\x00" + strings.ToLower(strings.TrimSpace(parts[2]))
		for _, m := range refs.FindAllStringSubmatch(line, -1) {
			path := strings.TrimSuffix(m[1], "\\")
			if f, ok := indexed[path]; ok {
				published[key] = append(published[key], map[string]any{"id": f.ID, "path": f.Path, "available": true})
			} else {
				published[key] = append(published[key], map[string]any{"path": path, "available": false})
			}
		}
	}
	jobs, _ := d["jobs"].([]any)
	cloned := make([]any, 0, len(jobs))
	for _, v := range jobs {
		j, ok := v.(map[string]any)
		if !ok {
			continue
		}
		copy := map[string]any{}
		for k, v := range j {
			copy[k] = v
		}
		course, _ := j["course"].(string)
		name, _ := j["name"].(string)
		copy["reports"] = published[course+"\x00"+strings.ToLower(name)]
		cloned = append(cloned, copy)
	}
	d["jobs"] = cloned
}
