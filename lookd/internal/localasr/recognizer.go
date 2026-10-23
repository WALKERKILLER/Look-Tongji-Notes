package localasr

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"lookstudio/lookd/internal/asr"
)

// Recognizer runs one installed model through sherpa-onnx's command-line
// VAD + offline recogniser. It implements asr.Engine.
type Recognizer struct {
	Model   Model
	Threads int
	engine  string // engine directory
	vad     string
	punct   string // punctuation model dir, "" when the model writes punctuation
	dir     string
	plat    string
}

// DefaultThreads leaves half the cores to the rest of the machine.
func DefaultThreads() int { return min(4, max(1, runtime.NumCPU()/2)) }

// Recognizer returns a runner for an installed model.
func (m *Manager) Recognizer(id string, threads int) (*Recognizer, error) {
	md, ok := Find(id)
	if !ok {
		return nil, fmt.Errorf("未知的模型 %q", id)
	}
	if !m.Installed(id) {
		return nil, fmt.Errorf("模型 %s 尚未下载完成", md.Name)
	}
	if threads <= 0 || threads > runtime.NumCPU() {
		threads = DefaultThreads()
	}
	r := &Recognizer{Model: md, Threads: threads, engine: m.engineDir(), vad: filepath.Join(m.vadDir(), "silero_vad.onnx"),
		dir: m.modelDir(id), plat: m.platform()}
	if !md.Punct {
		r.punct = m.punctDir()
	}
	return r, nil
}

func (r *Recognizer) command(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, filepath.Join(r.engine, "bin", exe(r.plat, name)), args...)
	lib := filepath.Join(r.engine, "lib")
	env := os.Environ()
	switch {
	case strings.HasPrefix(r.plat, "darwin/"):
		env = append(env, "DYLD_LIBRARY_PATH="+lib)
	case strings.HasPrefix(r.plat, "windows/"):
		env = append(env, "PATH="+lib+string(os.PathListSeparator)+filepath.Join(r.engine, "bin")+string(os.PathListSeparator)+os.Getenv("PATH"))
	default:
		env = append(env, "LD_LIBRARY_PATH="+lib)
	}
	cmd.Env = env
	return cmd
}

// line is one recognised segment: "1.542 -- 7.116: text".
var line = regexp.MustCompile(`^\s*(\d+(?:\.\d+)?)\s+--\s+(\d+(?:\.\d+)?):\s?(.*)$`)

func (r *Recognizer) Transcribe(ctx context.Context, audio string, onStage asr.Stage) ([]asr.Utterance, error) {
	tmp, err := os.MkdirTemp("", "look-local-asr-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)
	wav := filepath.Join(tmp, "audio.wav")
	conv := exec.CommandContext(ctx, "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-i", audio,
		"-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-y", wav)
	if out, err := conv.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("转换音频: %v %s", err, bytes.TrimSpace(out))
	}
	args := []string{"--silero-vad-model=" + r.vad, "--silero-vad-threshold=0.3", "--silero-vad-max-speech-duration=20",
		"--num-threads=" + strconv.Itoa(r.Threads)}
	args = append(args, r.Model.args(r.dir)...)
	args = append(args, wav)
	cmd := r.command(ctx, "sherpa-onnx-vad-with-offline-asr", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil {
		return nil, fmt.Errorf("本地识别失败: %v %s", err, tail(stderr.String(), 300))
	}
	us := parse(out)
	if r.punct != "" && len(us) > 0 {
		if p, err := r.punctuate(ctx, us); err == nil {
			us = p
		}
	}
	return us, nil
}

func parse(out []byte) []asr.Utterance {
	us := []asr.Utterance{}
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		m := line.FindStringSubmatch(sc.Text())
		if m == nil {
			continue
		}
		text := strings.TrimSpace(m[3])
		if text == "" {
			continue
		}
		a, _ := strconv.ParseFloat(m[1], 64)
		b, _ := strconv.ParseFloat(m[2], 64)
		us = append(us, asr.Utterance{StartMs: int64(a * 1000), EndMs: int64(b * 1000), Text: text})
	}
	return us
}

func tail(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	cut := len(s) - n
	for cut < len(s) && !utf8.RuneStart(s[cut]) {
		cut++
	}
	return "…" + s[cut:]
}

// punctuate runs the punctuation model once over the joined text and maps
// the inserted marks back onto each segment.
func (r *Recognizer) punctuate(ctx context.Context, us []asr.Utterance) ([]asr.Utterance, error) {
	texts := make([]string, len(us))
	for i, u := range us {
		texts[i] = u.Text
	}
	cmd := r.command(ctx, "sherpa-onnx-offline-punctuation", "--num-threads=2",
		"--ct-transformer="+filepath.Join(r.punct, "model.onnx"), strings.Join(texts, ""))
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	got, ok := realign(texts, strings.TrimSpace(string(out)))
	if !ok {
		return nil, errors.New("标点结果无法对齐")
	}
	res := make([]asr.Utterance, len(us))
	for i, u := range us {
		u.Text = got[i]
		res[i] = u
	}
	return res, nil
}

// realign distributes punctuated text over the original segments. The
// punctuation model only inserts marks (and may change letter case or drop
// spaces); any other change makes the result untrustworthy, so ok is false.
func realign(segs []string, punctuated string) ([]string, bool) {
	var orig []rune
	var owner []int
	for i, s := range segs {
		for _, c := range s {
			orig = append(orig, c)
			owner = append(owner, i)
		}
	}
	out := make([]strings.Builder, len(segs))
	p, prev := 0, 0
	for _, c := range punctuated {
		for p < len(orig) && unicode.IsSpace(orig[p]) && orig[p] != c {
			out[owner[p]].WriteRune(orig[p])
			p++
		}
		switch {
		case p < len(orig) && unicode.ToLower(c) == unicode.ToLower(orig[p]):
			out[owner[p]].WriteRune(orig[p])
			prev = owner[p]
			p++
		case unicode.IsPunct(c) || unicode.IsSpace(c):
			if !unicode.IsSpace(c) {
				out[prev].WriteRune(c)
			}
		default:
			return nil, false
		}
	}
	for ; p < len(orig); p++ {
		if !unicode.IsSpace(orig[p]) {
			return nil, false
		}
	}
	res := make([]string, len(segs))
	for i := range out {
		res[i] = strings.TrimSpace(out[i].String())
	}
	return res, true
}
