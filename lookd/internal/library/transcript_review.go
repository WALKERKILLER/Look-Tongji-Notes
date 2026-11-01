package library

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"lookstudio/lookd/internal/store"
)

var ErrReviewConflict = errors.New("文字稿或审校任务已变化，请刷新后重试")

type TranscriptSuggestion struct {
	ID        string `json:"id"`
	Segment   int    `json:"segment"`
	Original  string `json:"original"`
	Guess     string `json:"guess"`
	Reason    string `json:"reason"`
	Evidence  string `json:"evidence"`
	Dismissed bool   `json:"dismissed"`
}

type TranscriptReview struct {
	RunID       string                 `json:"run_id"`
	Fingerprint string                 `json:"fingerprint"`
	State       string                 `json:"state"`
	Model       string                 `json:"model"`
	Completed   int                    `json:"completed"`
	Rejected    int                    `json:"rejected"`
	Total       int                    `json:"total"`
	Updated     int64                  `json:"updated"`
	Error       string                 `json:"error,omitempty"`
	Stale       bool                   `json:"stale"`
	Suggestions []TranscriptSuggestion `json:"suggestions"`
}

func TranscriptFingerprint(segs []store.Segment) string {
	b, _ := json.Marshal(segs)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func (l *Library) reviewRoot(ctx context.Context, id string) (*os.Root, string, []store.Segment, error) {
	lec, err := l.Store.Lecture(ctx, id)
	if err != nil {
		return nil, "", nil, err
	}
	if lec.Dir == "" || path.Clean(lec.Dir) != lec.Dir || !strings.HasPrefix(lec.Dir, "courses/") {
		return nil, "", nil, fmt.Errorf("课次尚无本机目录")
	}
	segs, err := l.Store.Segments(ctx, id, 0, 0)
	if err != nil {
		return nil, "", nil, err
	}
	root, err := os.OpenRoot(l.Root)
	return root, path.Join(lec.Dir, "transcript-review.json"), segs, err
}

func readReview(root *os.Root, rel string) (TranscriptReview, error) {
	empty := TranscriptReview{State: "none", Suggestions: []TranscriptSuggestion{}}
	f, e := root.Open(rel)
	if os.IsNotExist(e) {
		return empty, nil
	}
	if e != nil {
		return empty, e
	}
	defer f.Close()
	b, e := io.ReadAll(io.LimitReader(f, 1<<20+1))
	if e != nil {
		return empty, e
	}
	if len(b) > 1<<20 {
		return empty, fmt.Errorf("审校文件超过限制")
	}
	var r TranscriptReview
	e = json.Unmarshal(b, &r)
	return r, e
}

func (l *Library) TranscriptReview(ctx context.Context, id string) (TranscriptReview, error) {
	l.reviewMu.Lock()
	defer l.reviewMu.Unlock()
	root, rel, segs, e := l.reviewRoot(ctx, id)
	if e != nil {
		return TranscriptReview{}, e
	}
	defer root.Close()
	r, e := readReview(root, rel)
	if e != nil {
		return r, e
	}
	current := TranscriptFingerprint(segs)
	if r.Fingerprint == "" {
		r.Fingerprint = current
	}
	r.Stale = r.Fingerprint != current
	return r, nil
}

// ValidateSuggestions anchors each guess to one unique original span. Model
// output never contains markup, offsets or instructions that are executed.
func ValidateSuggestions(segs []store.Segment, in []TranscriptSuggestion) ([]TranscriptSuggestion, error) {
	if len(in) > 2000 {
		return nil, fmt.Errorf("审校建议超过 2000 条")
	}
	byIdx := map[int]string{}
	for _, s := range segs {
		byIdx[s.Idx] = s.Text
	}
	type span struct{ start, end int }
	occupied := map[int][]span{}
	out := append([]TranscriptSuggestion{}, in...)
	for i := range out {
		a := &out[i]
		text, ok := byIdx[a.Segment]
		if !ok || strings.TrimSpace(a.Original) == "" || utf8.RuneCountInString(a.Original) > 120 || strings.Count(text, a.Original) != 1 {
			return nil, fmt.Errorf("第 %d 条建议原词无法唯一匹配原文", i+1)
		}
		if strings.TrimSpace(a.Guess) == "" || a.Guess == a.Original || utf8.RuneCountInString(a.Guess) > 120 || strings.ContainsAny(a.Guess, "\r\n") {
			return nil, fmt.Errorf("第 %d 条候选词无效", i+1)
		}
		if strings.TrimSpace(a.Reason) == "" || strings.TrimSpace(a.Evidence) == "" || utf8.RuneCountInString(a.Reason) > 500 || utf8.RuneCountInString(a.Evidence) > 700 {
			return nil, fmt.Errorf("第 %d 条建议缺少有界的理由与依据", i+1)
		}
		start := strings.Index(text, a.Original)
		end := start + len(a.Original)
		for _, p := range occupied[a.Segment] {
			if start < p.end && end > p.start {
				return nil, fmt.Errorf("同一原文位置存在重叠建议")
			}
		}
		occupied[a.Segment] = append(occupied[a.Segment], span{start, end})
		h := sha256.Sum256([]byte(fmt.Sprintf("%d:%d:%s:%s", a.Segment, start, a.Original, a.Guess)))
		a.ID = hex.EncodeToString(h[:8])
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Segment != out[j].Segment {
			return out[i].Segment < out[j].Segment
		}
		return strings.Index(byIdx[out[i].Segment], out[i].Original) < strings.Index(byIdx[out[j].Segment], out[j].Original)
	})
	return out, nil
}

func writeReview(root *os.Root, rel string, r TranscriptReview) error {
	b, e := json.MarshalIndent(r, "", "  ")
	if e != nil {
		return e
	}
	if len(b) > 1<<20 {
		return fmt.Errorf("审校旁注超过 1 MiB")
	}
	// A unique temporary file makes concurrent readers see either complete version.
	tmp := fmt.Sprintf("%s.%d.tmp", rel, time.Now().UnixNano())
	f, e := root.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		return e
	}
	defer root.Remove(tmp)
	if _, e = f.Write(b); e != nil {
		f.Close()
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	return root.Rename(tmp, rel)
}

func (l *Library) SaveTranscriptReview(ctx context.Context, id, baseRun string, in TranscriptReview) (TranscriptReview, error) {
	l.reviewMu.Lock()
	defer l.reviewMu.Unlock()
	root, rel, segs, e := l.reviewRoot(ctx, id)
	if e != nil {
		return in, e
	}
	defer root.Close()
	old, e := readReview(root, rel)
	if e != nil {
		return in, e
	}
	if in.Fingerprint != TranscriptFingerprint(segs) || (old.RunID != in.RunID && old.RunID != baseRun) {
		return in, ErrReviewConflict
	}
	if len(segs) == 0 || in.RunID == "" || len(in.RunID) > 100 || len(in.Model) > 200 || len(in.Error) > 2000 || in.Total < 1 || in.Total > 200 || in.Completed < 0 || in.Completed > in.Total || in.Rejected < 0 || in.Rejected > 6000 {
		return in, fmt.Errorf("无效的审校任务")
	}
	switch in.State {
	case "running", "completed", "cancelled", "error", "interrupted":
	default:
		return in, fmt.Errorf("无效的审校状态")
	}
	if in.State == "completed" && in.Completed != in.Total {
		return in, fmt.Errorf("尚未检查整节课")
	}
	in.Suggestions, e = ValidateSuggestions(segs, in.Suggestions)
	if e != nil {
		return in, e
	}
	// Dismissing a suggestion during a model call survives its subsequent checkpoint.
	if old.RunID == in.RunID {
		dismissed := map[string]bool{}
		for _, a := range old.Suggestions {
			dismissed[a.ID] = a.Dismissed
		}
		for i := range in.Suggestions {
			in.Suggestions[i].Dismissed = dismissed[in.Suggestions[i].ID]
		}
	}
	in.Stale = false
	in.Updated = time.Now().Unix()
	e = writeReview(root, rel, in)
	return in, e
}

func (l *Library) DismissTranscriptSuggestion(ctx context.Context, id, suggestion string) (TranscriptReview, error) {
	l.reviewMu.Lock()
	defer l.reviewMu.Unlock()
	root, rel, segs, e := l.reviewRoot(ctx, id)
	if e != nil {
		return TranscriptReview{}, e
	}
	defer root.Close()
	r, e := readReview(root, rel)
	if e != nil {
		return r, e
	}
	if r.Fingerprint != TranscriptFingerprint(segs) {
		return r, ErrReviewConflict
	}
	found := false
	for i := range r.Suggestions {
		if r.Suggestions[i].ID == suggestion {
			r.Suggestions[i].Dismissed = true
			found = true
		}
	}
	if !found {
		return r, fmt.Errorf("找不到这条审校建议")
	}
	r.Updated = time.Now().Unix()
	return r, writeReview(root, rel, r)
}
