package server

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"lookstudio/lookd/internal/canvas"
	"lookstudio/lookd/internal/fudan"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/store"
	"lookstudio/lookd/internal/tongji"
)

// School is a supported university and how Look Studio reaches its tools.
// Contract: docs/specs/0011-canvas-and-schools.md
type School struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Canvas    string `json:"canvas"`     // Canvas site
	SSO       string `json:"sso"`        // how "sso" mode signs in: look | uis
	Look      bool   `json:"look"`       // lecture replays in Look Studio (sign-in at POST /api/auth/login)
	EmblemURL string `json:"emblem_url"` // vector emblem, fetched by the app
	Note      string `json:"note,omitempty"`
}

var schools = []School{
	{ID: "tongji", Name: "同济大学", Canvas: "https://canvas.tongji.edu.cn", SSO: "look", Look: true,
		EmblemURL: "https://upload.wikimedia.org/wikipedia/zh/f/f8/Tongji_University_Emblem.svg"},
	{ID: "fudan", Name: "复旦大学", Canvas: "https://elearning.fudan.edu.cn", SSO: "uis", Look: true,
		EmblemURL: "https://upload.wikimedia.org/wikipedia/commons/4/44/Fudan_University_Logo.svg"},
}

const canvasEvery = 15 * time.Minute

// tongjiCanvas signs in to Canvas through Tongji IAM with the session that
// already keeps Look signed in.
type tongjiCanvas struct {
	sess *tongji.Session
	base string
}

func (a tongjiCanvas) Client() *http.Client { return a.sess.Client() }

func (a tongjiCanvas) SignIn(ctx context.Context) error {
	err := canvas.OIDCSignIn(ctx, a.sess.Client(), a.base)
	if !errors.Is(err, canvas.ErrIdP) {
		return err
	}
	if a.sess.State().Status == "signed_out" || a.sess.School() != tongji.Tongji {
		return errors.New("请先在 Look Studio 登录同济统一身份认证")
	}
	// The IAM session lapsed: renew it the way Look's token is renewed
	// (silent SSO, then the remembered password) and try once more.
	if err := a.sess.Renew(ctx); err != nil {
		return fmt.Errorf("同济统一身份认证已失效，请先在 Look Studio 重新登录: %w", err)
	}
	if err := canvas.OIDCSignIn(ctx, a.sess.Client(), a.base); err != nil {
		if errors.Is(err, canvas.ErrIdP) {
			return errors.New("同济统一身份认证没有放行 Canvas 登录，请稍后重试或改用访问令牌")
		}
		return err
	}
	return nil
}

// fudanCanvas signs in to Fudan's Canvas through UIS with the sealed
// password; its cookies live in memory only.
type fudanCanvas struct {
	hc             *http.Client
	base, user, pw string
}

func (a *fudanCanvas) Client() *http.Client { return a.hc }

func (a *fudanCanvas) SignIn(ctx context.Context) error {
	pw, err := tongji.Unseal(a.pw)
	if a.user == "" || a.pw == "" || err != nil {
		return errors.New("需要复旦 UIS 学号和密码")
	}
	return (&fudan.UIS{HC: a.hc}).Login(ctx, a.base+"/login/cas", a.user, pw)
}

// CanvasAuth picks the single sign-on for a configuration.
func (s *Server) CanvasAuth(c canvas.Config) canvas.Auth {
	switch c.School {
	case "tongji":
		return tongjiCanvas{s.Sess, c.Base}
	case "fudan":
		jar, _ := cookiejar.New(nil)
		return &fudanCanvas{hc: &http.Client{Jar: jar, Timeout: 40 * time.Second, Transport: s.Sess.Transport()}, base: c.Base, user: c.Username, pw: c.Password}
	}
	return nil
}

func (s *Server) canvasStatus(http.ResponseWriter, *http.Request) (any, error) {
	return map[string]any{"status": s.Canvas.Status(), "schools": schools}, nil
}

func canvasErr(err error) error {
	switch {
	case errors.Is(err, canvas.ErrBadInput):
		return badRequest(strings.TrimPrefix(err.Error(), canvas.ErrBadInput.Error()+": "))
	case errors.Is(err, canvas.ErrNotFound):
		return apiError{http.StatusNotFound, err.Error()}
	case errors.Is(err, canvas.ErrNotConnected):
		return apiError{http.StatusConflict, err.Error()}
	case errors.Is(err, fudan.ErrBadCredentials), errors.Is(err, canvas.ErrAuth):
		return apiError{http.StatusUnauthorized, err.Error()}
	}
	return err
}

func (s *Server) canvasConnect(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in canvas.ConnectIn
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	for _, sc := range schools {
		if sc.ID == in.School && strings.TrimSpace(in.Base) == "" {
			in.Base = sc.Canvas
		}
	}
	st, err := s.Canvas.Connect(r.Context(), in)
	if err != nil {
		return nil, canvasErr(err)
	}
	go s.canvasSync(s.Ctx)
	return st, nil
}

func (s *Server) canvasDisconnect(_ http.ResponseWriter, r *http.Request) (any, error) {
	s.Canvas.Disconnect(r.Context())
	return s.Canvas.Status(), nil
}

func (s *Server) canvasSyncNow(http.ResponseWriter, *http.Request) (any, error) {
	if !s.Canvas.Connected() {
		return nil, canvasErr(canvas.ErrNotConnected)
	}
	go s.canvasSync(s.Ctx)
	st := s.Canvas.Status()
	st.Syncing = true
	return st, nil
}

// canvasSync syncs Canvas and links its courses to Look courses by name.
func (s *Server) canvasSync(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	s.canvasLink(ctx)
	err := s.Canvas.Sync(ctx)
	if s.canvasLink(ctx) {
		s.Bus.Publish("schedule_changed", map[string]string{"id": "canvas"})
	}
	return err
}

func (s *Server) canvasLink(ctx context.Context) bool {
	cs, err := s.St.Courses(ctx)
	if err != nil {
		return false
	}
	refs := make([]canvas.Ref, 0, len(cs))
	for _, c := range cs {
		t := c.Title
		if c.Alias != "" {
			t = c.Alias
		}
		refs = append(refs, canvas.Ref{ID: c.ID, Title: t})
	}
	return s.Canvas.AutoLink(refs)
}

func (s *Server) canvasSetLink(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Course string `json:"course"`
		Auto   bool   `json:"auto"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Course != "" {
		if _, err := s.St.Course(r.Context(), in.Course); err != nil {
			return nil, badRequest("没有这门 Look 课程")
		}
	}
	if err := s.Canvas.SetLink(r.PathValue("id"), in.Course, in.Auto); err != nil {
		return nil, canvasErr(err)
	}
	if in.Auto {
		s.canvasLink(r.Context())
	}
	s.Bus.Publish("canvas_changed", map[string]string{"what": "links"})
	s.Bus.Publish("schedule_changed", map[string]string{"id": "canvas"})
	return s.Canvas.Status(), nil
}

func (s *Server) canvasCourse(_ http.ResponseWriter, r *http.Request) (any, error) {
	d, err := s.Canvas.Detail(r.PathValue("id"))
	return d, canvasErr(err)
}

func (s *Server) canvasFiles(_ http.ResponseWriter, r *http.Request) (any, error) {
	fs, err := s.Canvas.Files(r.Context(), r.PathValue("id"))
	if err != nil {
		return nil, canvasErr(err)
	}
	return fs, nil
}

// canvasDownload saves a file into the linked Look course's folder
// (<course>/Canvas/), or canvas/<Canvas course>/ when not linked.
func (s *Server) canvasDownload(_ http.ResponseWriter, r *http.Request) (any, error) {
	ctx := r.Context()
	var in struct {
		Course string `json:"course"` // Canvas course id
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	name := s.Canvas.CourseName(in.Course)
	if name == "" {
		return nil, apiError{http.StatusNotFound, "没有这门 Canvas 课程"}
	}
	rel := "canvas/" + library.Sanitize(name, "课程-"+in.Course)
	if look := s.Canvas.LinkedCourse(in.Course); look != "" {
		if dir, err := s.Lib.EnsureCourse(ctx, look); err == nil {
			rel = dir + "/Canvas"
		}
	}
	// Finish the file even if the app stops waiting.
	dctx, cancel := context.WithTimeout(s.Ctx, 15*time.Minute)
	defer cancel()
	p, err := s.Canvas.Download(dctx, r.PathValue("id"), s.Lib.Abs(rel))
	if err != nil {
		return nil, canvasErr(err)
	}
	return map[string]string{"path": rel + "/" + filepath.Base(p)}, nil
}

// ---- schedule merge ----

// canvasItems returns Canvas assignments as read-only schedule entries.
func (s *Server) canvasItems(ctx context.Context, q store.ScheduleQuery) []store.ScheduleItem {
	if s.Canvas == nil || q.LectureID != "" {
		return nil
	}
	titles := map[string]string{}
	if cs, err := s.St.Courses(ctx); err == nil {
		for _, c := range cs {
			titles[c.ID] = c.Title
			if c.Alias != "" {
				titles[c.ID] = c.Alias
			}
		}
	}
	var out []store.ScheduleItem
	for _, it := range s.Canvas.Items() {
		switch {
		case q.From != "" && it.DueDate < q.From, q.To != "" && it.DueDate > q.To,
			q.CourseID != "" && it.CourseID != q.CourseID, q.Open && it.Done:
			continue
		}
		title := titles[it.CourseID]
		if title == "" {
			title = it.CourseName
		}
		out = append(out, store.ScheduleItem{ID: it.ID, Kind: "homework", Title: it.Title, Detail: it.Detail, DueDate: it.DueDate,
			DueTime: it.DueTime, CourseID: it.CourseID, TMs: -1, Source: "canvas", Done: it.Done, CreatedAt: it.UpdatedAt,
			UpdatedAt: it.UpdatedAt, CourseTitle: title, URL: it.URL})
	}
	return out
}

func mergeSchedule(a, b []store.ScheduleItem) []store.ScheduleItem {
	if len(b) == 0 {
		return a
	}
	out := append(a, b...)
	sort.SliceStable(out, func(i, j int) bool {
		x, y := out[i], out[j]
		if x.DueDate != y.DueDate {
			return x.DueDate < y.DueDate
		}
		if (x.DueTime == "") != (y.DueTime == "") {
			return x.DueTime == ""
		}
		if x.DueTime != y.DueTime {
			return x.DueTime < y.DueTime
		}
		return x.CreatedAt < y.CreatedAt
	})
	return out
}

func isCanvasItem(id string) bool { return strings.HasPrefix(id, "canvas:") }

func (s *Server) canvasScheduleItem(ctx context.Context, id string) (store.ScheduleItem, error) {
	for _, it := range s.canvasItems(ctx, store.ScheduleQuery{}) {
		if it.ID == id {
			return it, nil
		}
	}
	return store.ScheduleItem{}, canvasErr(canvas.ErrNotFound)
}

// patchCanvasItem changes only local state of a Canvas assignment: done, or
// hidden: false to undo a delete.
func (s *Server) patchCanvasItem(r *http.Request, id string) (any, error) {
	var p map[string]any
	if err := decode(r, &p); err != nil {
		return nil, err
	}
	done, isDone := p["done"].(bool)
	hidden, isHidden := p["hidden"].(bool)
	var err error
	switch {
	case len(p) == 1 && isDone:
		_, err = s.Canvas.SetDone(id, done)
	case len(p) == 1 && isHidden && !hidden:
		err = s.Canvas.Unhide(id)
	default:
		return nil, badRequest("Canvas 作业只能标记完成；请在 Canvas 中修改其他内容")
	}
	if err != nil {
		return nil, canvasErr(err)
	}
	s.Bus.Publish("schedule_changed", map[string]string{"id": id})
	return s.canvasScheduleItem(r.Context(), id)
}
