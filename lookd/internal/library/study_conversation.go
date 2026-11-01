package library

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path"
	"strings"
)

// Conversation history is independent of layout undo; deleting a card retains its recoverable sidecar.
type StudyTurn struct {
	ID         string          `json:"id"`
	Question   string          `json:"question"`
	Answer     string          `json:"answer"`
	ContextKey string          `json:"context_key"`
	State      string          `json:"state"`
	Error      string          `json:"error,omitempty"`
	Result     json.RawMessage `json:"result,omitempty"`
}
type StudyConversation struct {
	Version     int                 `json:"version"`
	Revision    int64               `json:"revision"`
	ID          string              `json:"id"`
	Draft       string              `json:"draft"`
	Query       StudyContextRequest `json:"query"`
	AllowImages bool                `json:"allow_images"`
	Turns       []StudyTurn         `json:"turns"`
}

func readStudyConversation(root *os.Root, name, id string) (StudyConversation, error) {
	out := StudyConversation{Version: 1, ID: id, Turns: []StudyTurn{}}
	b, e := root.ReadFile(name)
	if os.IsNotExist(e) {
		return out, nil
	}
	if e != nil {
		return out, e
	}
	if len(b) > 4<<20 {
		return out, ErrStudyLimit
	}
	e = json.Unmarshal(b, &out)
	return out, e
}
func (l *Library) StudyConversation(ctx context.Context, lecture, id string, next *StudyConversation) (StudyConversation, error) {
	if !validStudyID(id) {
		return StudyConversation{}, ErrStudyInvalid
	}
	l.studyMu.Lock()
	defer l.studyMu.Unlock()
	root, dir, e := l.studyRoot(ctx, lecture)
	if e != nil {
		return StudyConversation{}, e
	}
	defer root.Close()
	if e = checkedStudyDir(root, dir+"/study-conversations", true); e != nil {
		return StudyConversation{}, e
	}
	name := dir + "/study-conversations/" + id + ".json"
	old, e := readStudyConversation(root, name, id)
	if e != nil || next == nil {
		return old, e
	}
	if next.ID != id || next.Version != 1 || next.Revision < 0 || len(next.Draft) > 16000 || len(next.Turns) > 300 || len(next.Query.Objects) > 12 {
		return old, ErrStudyInvalid
	}
	if next.Revision != old.Revision {
		return old, ErrStudyConflict
	}
	seen := map[string]bool{}
	for _, t := range next.Turns {
		if !validStudyID(t.ID) || seen[t.ID] || len(t.Question) > 16000 || len(t.Answer) > 48000 || len(t.ContextKey) > 128 || len(t.Error) > 4000 || len(t.Result) > 400000 {
			return old, ErrStudyInvalid
		}
		seen[t.ID] = true
		switch t.State {
		case "preparing", "running", "done", "error", "cancelled", "interrupted", "pending", "applied":
		default:
			return old, ErrStudyInvalid
		}
	}
	next.Revision++
	b, e := json.Marshal(next)
	if e != nil {
		return old, e
	}
	if len(b) > 4<<20 {
		return old, ErrStudyLimit
	}
	if e = writeStudyBytes(root, name, b); e != nil {
		return old, e
	}
	return *next, nil
}

// Course material selection must resolve an indexed file in the workspace's own course.
// Original bytes are never changed. External imports still use the existing managed asset boundary.
func (l *Library) ImportStudyMaterial(ctx context.Context, lecture, rel string) (StudyImport, error) {
	var out StudyImport
	lec, e := l.Store.Lecture(ctx, lecture)
	if e != nil {
		return out, e
	}
	items, e := l.CourseCatalog(ctx, lec.CourseID)
	if e != nil {
		return out, e
	}
	var item *CatalogItem
	for i := range items {
		if items[i].Path == rel {
			item = &items[i]
			break
		}
	}
	if item == nil {
		return out, fmt.Errorf("%w：资料不属于当前课程", ErrStudyInvalid)
	}
	root, e := os.OpenRoot(l.Root)
	if e != nil {
		return out, e
	}
	defer root.Close()
	if path.Clean(rel) != rel || strings.Contains(rel, "\\") || checkedStudyDir(root, path.Dir(rel), false) != nil {
		return out, ErrStudyInvalid
	}
	st, e := root.Lstat(rel)
	if e != nil || !st.Mode().IsRegular() {
		return out, ErrStudyInvalid
	}
	if item.FileType == "mp4" || item.FileType == "mov" || item.FileType == "mkv" || item.FileType == "webm" {
		return StudyImport{Objects: []StudyObject{{ID: studyID(), Type: "video", Layer: "main", W: 640, H: 440, Title: item.Name, OriginalPath: item.Path, SourceLectureID: item.LectureID}}}, nil
	}
	f, e := root.Open(rel)
	if e != nil {
		return out, e
	}
	defer f.Close()
	out, e = l.ImportStudyModule(ctx, lecture, path.Base(item.Path), f)
	if e == nil {
		for i := range out.Objects {
			out.Objects[i].SourceLectureID = item.LectureID
			out.Objects[i].OriginalPath = item.Path
		}
	}
	return out, e
}

// Material references stay confined to the indexed course and never relocate large recordings.
func (l *Library) StudyCourseSource(ctx context.Context, lecture, rel string) (*os.File, error) {
	lec, e := l.Store.Lecture(ctx, lecture)
	if e != nil {
		return nil, e
	}
	course, e := l.Store.Course(ctx, lec.CourseID)
	if e != nil {
		return nil, e
	}
	if course.Dir == "" || !strings.HasPrefix(rel, course.Dir+"/") || path.Clean(rel) != rel || strings.Contains(rel, "\\") {
		return nil, ErrStudyInvalid
	}
	for _, part := range strings.Split(rel, "/") {
		if strings.HasPrefix(part, ".") {
			return nil, ErrStudyInvalid
		}
	}
	root, e := os.OpenRoot(l.Root)
	if e != nil {
		return nil, e
	}
	defer root.Close()
	if checkedStudyDir(root, path.Dir(rel), false) != nil {
		return nil, ErrStudyInvalid
	}
	st, e := root.Lstat(rel)
	if e != nil || !st.Mode().IsRegular() {
		return nil, ErrStudyInvalid
	}
	return root.Open(rel)
}
func (l *Library) StudyVideoSource(ctx context.Context, lecture, object string) (*os.File, error) {
	return l.studyMediaFile(ctx, lecture, object)
}
