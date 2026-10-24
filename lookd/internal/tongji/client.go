package tongji

import (
	"context"
	"crypto/md5"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Client wraps the look REST API on top of an auto-renewing Session.
type Client struct {
	S *Session

	mu   sync.Mutex
	user *UserInfo
}

type UserInfo struct {
	ID       int64  `json:"id"`
	TenantID int64  `json:"tenant_id"`
	Account  string `json:"account"`
	Realname string `json:"realname"`
	Avatar   string `json:"avatar"`
	Phone    string `json:"-"`
}

// flex decodes JSON values that the API returns as either string or number.
type flex string

func (f *flex) UnmarshalJSON(b []byte) error {
	if string(b) == "null" {
		*f = ""
		return nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		*f = flex(s)
		return nil
	}
	*f = flex(strings.Trim(string(b), `"`))
	return nil
}
func (f flex) Int() int64     { n, _ := strconv.ParseInt(string(f), 10, 64); return n }
func (f flex) String() string { return string(f) }

func (c *Client) getJSON(ctx context.Context, path string, q url.Values, out any) error {
	u := c.S.Base() + path
	if len(q) > 0 {
		u += "?" + q.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	resp, err := c.S.Do(ctx, req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("%s: HTTP %d", path, resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, out); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

func okCode(v any) bool {
	switch fmt.Sprint(v) {
	case "0", "200", "1000":
		return true
	}
	return false
}

func (c *Client) UserInfo(ctx context.Context) (*UserInfo, error) {
	c.mu.Lock()
	if c.user != nil {
		u := c.user
		c.mu.Unlock()
		return u, nil
	}
	c.mu.Unlock()
	var r struct {
		Code   any `json:"code"`
		Params struct {
			ID       int64  `json:"id"`
			TenantID int64  `json:"tenant_id"`
			Account  string `json:"account"`
			Realname string `json:"realname"`
			Avatar   string `json:"avatar"`
			Phone    flex   `json:"phone"`
		} `json:"params"`
	}
	if err := c.getJSON(ctx, "/userapi/v1/infosimple", nil, &r); err != nil {
		return nil, err
	}
	if !okCode(r.Code) {
		return nil, fmt.Errorf("userinfo code=%v", r.Code)
	}
	p := r.Params
	u := &UserInfo{ID: p.ID, TenantID: p.TenantID, Account: p.Account, Realname: p.Realname, Avatar: p.Avatar, Phone: p.Phone.String()}
	c.mu.Lock()
	c.user = u
	c.mu.Unlock()
	return u, nil
}

// ResetUser drops cached identity (after logout or account switch).
func (c *Client) ResetUser() { c.mu.Lock(); c.user = nil; c.mu.Unlock() }

type Teacher struct {
	Username string `json:"username"`
	Realname string `json:"realname"`
}

type Course struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Teacher     string    `json:"teacher"`
	Teachers    []Teacher `json:"teachers"`
	College     string    `json:"college"`
	Term        string    `json:"term"`
	Thumb       string    `json:"thumb"`
	StartAt     int64     `json:"start_at"`
	EndAt       int64     `json:"end_at"`
	Total       int       `json:"lecture_total"`
	Progress    float64   `json:"progress"`
	LastSubID   string    `json:"last_sub_id"`
	LastLearnAt string    `json:"last_learn_at"`
}

// Courses lists every enrolled course ("我的课程"), all pages.
func (c *Client) Courses(ctx context.Context) ([]Course, error) {
	var out []Course
	seen := map[string]bool{}
	for page := 1; page <= 20; page++ {
		var r struct {
			Params struct {
				Result struct {
					Total int `json:"total"`
					Data  []struct {
						ID       flex   `json:"Id"`
						Title    string `json:"Title"`
						Teacher  string `json:"Teacher"`
						Teachers []struct {
							Username string `json:"Username"`
							Realname string `json:"Realname"`
						} `json:"Teachers"`
						College  string `json:"KkxyName"`
						TermName string `json:"TermName"`
						Thumb    string `json:"Thumb"`
						StartAt  int64  `json:"StartAt"`
						EndAt    int64  `json:"EndAt"`
						Progress struct {
							SubjectNum      int     `json:"subjectNum"`
							SubjectProgress float64 `json:"subjectProgress"`
						} `json:"progress"`
						PrevSubjectID flex   `json:"PrevSubjectId"`
						PrevLearnTime string `json:"PrevLearnTime"`
					} `json:"data"`
				} `json:"result"`
			} `json:"params"`
		}
		q := url.Values{"nowpage": {strconv.Itoa(page)}, "per-page": {"100"}}
		if err := c.getJSON(ctx, "/personal/courseapi/vlabpassportapi/v1/account-profile/course", q, &r); err != nil {
			if page == 1 {
				return nil, err
			}
			break
		}
		items := r.Params.Result.Data
		for _, it := range items {
			id := it.ID.String()
			if id == "" || seen[id] {
				continue
			}
			seen[id] = true
			co := Course{ID: id, Title: it.Title, Teacher: it.Teacher, College: it.College, Term: it.TermName,
				Thumb: it.Thumb, StartAt: it.StartAt, EndAt: it.EndAt, Total: it.Progress.SubjectNum,
				Progress: it.Progress.SubjectProgress, LastSubID: it.PrevSubjectID.String(), LastLearnAt: it.PrevLearnTime}
			if co.LastSubID == "0" {
				co.LastSubID = ""
			}
			for _, t := range it.Teachers {
				co.Teachers = append(co.Teachers, Teacher{t.Username, t.Realname})
			}
			out = append(out, co)
		}
		if len(items) == 0 || page*100 >= r.Params.Result.Total {
			break
		}
	}
	return out, nil
}

type Lecture struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Date        string `json:"date"`
	BeginAt     int64  `json:"begin_at"`
	EndAt       int64  `json:"end_at"`
	Lecturer    string `json:"lecturer"`
	Room        string `json:"room"`
	HasPlayback bool   `json:"has_playback"`
}

type CourseDetail struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	Teacher  string    `json:"teacher"`
	College  string    `json:"college"`
	Term     string    `json:"term"`
	Thumb    string    `json:"thumb"`
	Lectures []Lecture `json:"lectures"`
}

type rawLecture struct {
	ID         flex   `json:"id"`
	SubTitle   string `json:"sub_title"`
	ClassBegin flex   `json:"class_begin"`
	ClassOver  flex   `json:"class_over"`
	Lecturer   string `json:"lecturer_name"`
	Room       string `json:"room_name"`
	Playback   flex   `json:"playback_status"`
	Date       string `json:"date"`
}

func (c *Client) CourseDetail(ctx context.Context, courseID string) (*CourseDetail, error) {
	var r struct {
		Code any `json:"code"`
		Data struct {
			ID       flex            `json:"id"`
			Title    string          `json:"title"`
			Realname string          `json:"realname"`
			Kkxy     string          `json:"kkxy_name"`
			TermName string          `json:"term_name"`
			Thumb    string          `json:"thumb"`
			SubList  json.RawMessage `json:"sub_list"`
		} `json:"data"`
	}
	q := url.Values{"course_id": {courseID}, "tenant_code": {TenantCode}}
	if err := c.getJSON(ctx, "/courseapi/v3/multi-search/get-course-detail", q, &r); err != nil {
		return nil, err
	}
	if !okCode(r.Code) {
		return nil, fmt.Errorf("course detail code=%v", r.Code)
	}
	d := &CourseDetail{ID: courseID, Title: r.Data.Title, Teacher: r.Data.Realname, College: r.Data.Kkxy, Term: r.Data.TermName, Thumb: r.Data.Thumb}
	add := func(rl rawLecture, date string) {
		if rl.ID == "" {
			return
		}
		l := Lecture{ID: rl.ID.String(), Title: rl.SubTitle, BeginAt: rl.ClassBegin.Int(), EndAt: rl.ClassOver.Int(),
			Lecturer: rl.Lecturer, Room: rl.Room, HasPlayback: rl.Playback == "1", Date: date}
		// class_begin is authoritative; the nested sub_list keys are not calendar dates.
		if l.BeginAt > 0 {
			l.Date = time.Unix(l.BeginAt, 0).In(shanghai).Format("2006-01-02")
		} else if rl.Date != "" {
			l.Date = rl.Date
		}
		d.Lectures = append(d.Lectures, l)
	}
	// sub_list is either {year:{month:{day:[...]}}} or a flat list.
	var nested map[string]map[string]map[string][]rawLecture
	var flat []rawLecture
	if json.Unmarshal(r.Data.SubList, &nested) == nil {
		for y, ms := range nested {
			for m, ds := range ms {
				for day, items := range ds {
					for _, it := range items {
						add(it, fmt.Sprintf("%s-%s-%s", y, pad2(m), pad2(day)))
					}
				}
			}
		}
	} else if json.Unmarshal(r.Data.SubList, &flat) == nil {
		for _, it := range flat {
			add(it, "")
		}
	}
	sort.Slice(d.Lectures, func(i, j int) bool {
		if d.Lectures[i].BeginAt != d.Lectures[j].BeginAt {
			return d.Lectures[i].BeginAt > d.Lectures[j].BeginAt
		}
		return d.Lectures[i].ID > d.Lectures[j].ID
	})
	return d, nil
}

var shanghai = func() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}()

func pad2(s string) string {
	if len(s) == 1 {
		return "0" + s
	}
	return s
}

// Stream is one playable camera/screen view of a lecture.
type Stream struct {
	Label    string `json:"label"` // 教师 / 学生 / 屏幕
	URL      string `json:"url"`   // signed
	RawURL   string `json:"raw_url"`
	Thumb    string `json:"thumb"`
	Duration int64  `json:"duration"`
}

type Courseware struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

type Media struct {
	Streams    []Stream     `json:"streams"`
	Duration   int64        `json:"duration"`
	Courseware []Courseware `json:"courseware"`
	AllowDrag  bool         `json:"allow_drag"`
	Headers    http.Header  `json:"-"`
}

type rawVideo struct {
	PreviewURL string `json:"preview_url"`
	Thumb      string `json:"thumb"`
	Duration   flex   `json:"duration"`
}

// LectureMedia resolves signed stream URLs and attachments for a lecture.
func (c *Client) LectureMedia(ctx context.Context, courseID, subID string) (*Media, error) {
	var r struct {
		Code any `json:"code"`
		Data struct {
			VideoList   map[string]rawVideo `json:"video_list"`
			SegmentList map[string]struct {
				Teacher json.RawMessage `json:"teacher_list"`
				Student json.RawMessage `json:"student_list"`
				PPT     json.RawMessage `json:"ppt_list"`
			} `json:"segment_video_list"`
			PlayURL   map[string]any `json:"playurl"`
			Now       flex           `json:"now"`
			Duration  flex           `json:"duration"`
			AllowDrag flex           `json:"is_allow_video_drag"`
		} `json:"data"`
	}
	q := url.Values{"course_id": {courseID}, "sub_id": {subID}, "tenant_code": {TenantCode}}
	if err := c.getJSON(ctx, "/courseapi/v3/portal-home-setting/get-sub-info", q, &r); err != nil {
		return nil, err
	}
	if !okCode(r.Code) {
		return nil, fmt.Errorf("sub info code=%v", r.Code)
	}
	m := &Media{Duration: r.Data.Duration.Int(), AllowDrag: r.Data.AllowDrag != "0"}
	seen := map[string]bool{}
	addStream := func(label string, v rawVideo) {
		u := v.PreviewURL
		if u == "" || seen[u] || !(strings.Contains(u, ".mp4") || strings.Contains(u, ".m3u8")) {
			return
		}
		seen[u] = true
		m.Streams = append(m.Streams, Stream{Label: label, RawURL: u, Thumb: v.Thumb, Duration: v.Duration.Int()})
	}
	keys := make([]string, 0, len(r.Data.SegmentList))
	for k := range r.Data.SegmentList {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		seg := r.Data.SegmentList[k]
		for _, pair := range []struct {
			label string
			raw   json.RawMessage
		}{{"教师", seg.Teacher}, {"屏幕", seg.PPT}, {"学生", seg.Student}} {
			var v rawVideo
			if json.Unmarshal(pair.raw, &v) == nil {
				addStream(pair.label, v)
			}
		}
	}
	vkeys := make([]string, 0, len(r.Data.VideoList))
	for k := range r.Data.VideoList {
		vkeys = append(vkeys, k)
	}
	sort.Strings(vkeys)
	for _, k := range vkeys {
		addStream("视频", r.Data.VideoList[k])
	}
	if len(m.Streams) == 0 {
		for k, v := range r.Data.PlayURL {
			if s, ok := v.(string); ok && k != "now" {
				addStream("视频", rawVideo{PreviewURL: s})
			}
		}
	}
	now := r.Data.Now.Int()
	for i := range m.Streams {
		signed, err := c.Sign(ctx, m.Streams[i].RawURL, now)
		if err != nil {
			return nil, err
		}
		m.Streams[i].URL = c.S.URL(signed)
		if m.Streams[i].Duration == 0 {
			m.Streams[i].Duration = m.Duration
		}
	}
	if m.Duration == 0 && len(m.Streams) > 0 {
		m.Duration = m.Streams[0].Duration
	}
	m.Courseware, _ = c.courseware(ctx, courseID, subID)
	for i := range m.Courseware {
		m.Courseware[i].URL = c.S.URL(m.Courseware[i].URL)
	}
	m.Headers = c.S.Header()
	return m, nil
}

func (c *Client) courseware(ctx context.Context, courseID, subID string) ([]Courseware, error) {
	var r struct {
		Data struct {
			Content struct {
				Download map[string]struct {
					FileName string `json:"file_name"`
					PathName string `json:"path_name"`
				} `json:"download"`
			} `json:"content"`
		} `json:"data"`
	}
	q := url.Values{"course_id": {courseID}, "sub_id": {subID}, "tenant_code": {TenantCode}}
	if err := c.getJSON(ctx, "/courseapi/v3/multi-search/get-sub-detail", q, &r); err != nil {
		return nil, err
	}
	var out []Courseware
	for _, d := range r.Data.Content.Download {
		if d.PathName != "" {
			out = append(out, Courseware{Name: d.FileName, URL: d.PathName})
		}
	}
	return out, nil
}

// StreamURL signs a media address afresh and returns where the daemon
// fetches it (see Session.URL).
func (c *Client) StreamURL(ctx context.Context, raw string) (string, error) {
	signed, err := c.Sign(ctx, raw, 0)
	if err != nil {
		return "", err
	}
	return c.S.URL(signed), nil
}

// Sign adds look CDN authentication (clientUUID + t) to a media URL.
func (c *Client) Sign(ctx context.Context, raw string, now int64) (string, error) {
	if strings.Contains(raw, "clientUUID=") {
		return raw, nil
	}
	u, err := c.UserInfo(ctx)
	if err != nil {
		return "", err
	}
	if now == 0 {
		now = time.Now().Unix()
	}
	pu, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	phone := []rune(u.Phone)
	for i, j := 0, len(phone)-1; i < j; i, j = i+1, j-1 {
		phone[i], phone[j] = phone[j], phone[i]
	}
	sum := md5.Sum([]byte(fmt.Sprintf("%s%d%d%s%d", pu.Path, u.ID, u.TenantID, string(phone), now)))
	t := fmt.Sprintf("%d-%d-%s", u.ID, now, hex.EncodeToString(sum[:]))
	sep := "?"
	if strings.Contains(raw, "?") {
		sep = "&"
	}
	return raw + sep + "clientUUID=" + uuid4() + "&t=" + t, nil
}

func uuid4() string {
	var b [16]byte
	rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	h := hex.EncodeToString(b[:])
	return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}

type SlideSnap struct {
	TSec     int64  `json:"t_sec"`
	ImageURL string `json:"image_url"`
	ThumbURL string `json:"thumb_url"`
	IsKey    bool   `json:"is_key"`
}

// Slides lists the PPT snapshots detected in a lecture, sorted by time.
func (c *Client) Slides(ctx context.Context, courseID, subID string) ([]SlideSnap, error) {
	var out []SlideSnap
	seen := map[string]bool{}
	for page := 1; page <= 30; page++ {
		var r struct {
			Code  any  `json:"code"`
			Total flex `json:"total"`
			List  []struct {
				Content    string `json:"content"`
				CreatedSec int64  `json:"created_sec"`
			} `json:"list"`
		}
		q := url.Values{"course_id": {courseID}, "sub_id": {subID}, "page": {strconv.Itoa(page)}, "per_page": {"100"}}
		if err := c.getJSON(ctx, "/pptnote/v1/schedule/search-ppt", q, &r); err != nil {
			return nil, err
		}
		if !okCode(r.Code) {
			return nil, fmt.Errorf("search-ppt code=%v", r.Code)
		}
		added := 0
		for _, it := range r.List {
			var ct struct {
				Img   string `json:"pptimgurl"`
				Thumb string `json:"pptthumb"`
				IsKey bool   `json:"is_key"`
			}
			json.Unmarshal([]byte(it.Content), &ct)
			img := ct.Img
			if img == "" {
				img = ct.Thumb
			}
			k := strconv.FormatInt(it.CreatedSec, 10) + img
			if img == "" || seen[k] {
				continue
			}
			seen[k] = true
			out = append(out, SlideSnap{TSec: it.CreatedSec, ImageURL: img, ThumbURL: ct.Thumb, IsKey: ct.IsKey})
			added++
		}
		if added == 0 || len(r.List) < 100 || (r.Total.Int() > 0 && len(out) >= int(r.Total.Int())) {
			break
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].TSec < out[j].TSec })
	return out, nil
}
