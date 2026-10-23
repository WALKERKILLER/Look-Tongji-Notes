// Package localasr installs the sherpa-onnx recogniser and offline speech
// models into Look Studio's data directory and runs them as the "local"
// transcription channel, so long lectures need no free cloud quota.
// Contract: docs/specs/0009-local-asr-models.md
package localasr

import (
	"path/filepath"
	"strings"
)

// Source: https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.8
// (Apache-2.0); sizes and digests from the GitHub release API.
const EngineVersion = "1.13.8"

// File is one downloadable file. Path is where it lands inside the install
// directory; Remote, when set, is its path on the source instead.
type File struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"-"`
	Remote string `json:"-"`
}

type archive struct {
	name string
	File
}

var engines = map[string]archive{
	"linux/amd64":   {"sherpa-onnx-v1.13.8-linux-x64-shared-no-tts", File{Size: 24802494, SHA256: "d0f96c8b65c6cd0974fada22737e337de81bc8cd2abbec2e39caf358b1eec5fc"}},
	"darwin/arm64":  {"sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts", File{Size: 18252168, SHA256: "91b96512c4fa1960f8a9ed5360a6c8dda53a4b5015d0590244f14086a234557a"}},
	"darwin/amd64":  {"sherpa-onnx-v1.13.8-osx-x64-shared-no-tts", File{Size: 20646120, SHA256: "03fd4cffd98b239d74b9253c270ff637661adb4d51a5a6c9e1f7486e48306db3"}},
	"windows/amd64": {"sherpa-onnx-v1.13.8-win-x64-shared-MT-Release-no-tts", File{Size: 23271851, SHA256: "4b0a94f7b5c606b1b64a19a831c2127559e4b3d34e195465ebc7be73d9ed4783"}},
}

func engineURL(proxy, name string) string {
	return proxy + "https://github.com/k2-fsa/sherpa-onnx/releases/download/v" + EngineVersion + "/" + name + ".tar.bz2"
}

// Source is where model files come from.
type Source struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Note string `json:"note"`
}

var Sources = []Source{
	{"hf-mirror", "HF-Mirror", "hf-mirror.com 的 Hugging Face 镜像，国内可直连，推荐"},
	{"modelscope", "ModelScope 魔搭", "魔搭社区镜像；只有与原文件逐字节相同的模型才走这里，其余自动改用 HF-Mirror"},
	{"huggingface", "Hugging Face", "官方源，国内通常需要代理"},
	{"custom", "自定义地址", "任意 Hugging Face 兼容镜像，填写含 {repo} 和 {file} 的地址模板"},
}

// msMirror is a ModelScope repository holding byte-identical copies.
type msMirror struct {
	repo  string
	paths map[string]string // install path -> path in the ModelScope repo
}

// pack is a set of files from one repository.
type pack struct {
	repo  string // Hugging Face repo
	ms    *msMirror
	files []File
}

func (p pack) size() int64 {
	var n int64
	for _, f := range p.files {
		n += f.Size
	}
	return n
}

// url resolves a file on a source; ok is false when the source lacks it.
func (p pack) url(source, custom string, f File) (u string, ok bool) {
	switch source {
	case "huggingface":
		return "https://huggingface.co/" + p.repo + "/resolve/main/" + f.Path, true
	case "modelscope":
		if p.ms == nil {
			return "", false
		}
		return "https://modelscope.cn/models/" + p.ms.repo + "/resolve/master/" + p.ms.paths[f.Path], true
	case "custom":
		return strings.NewReplacer("{repo}", p.repo, "{file}", f.Path).Replace(custom), true
	}
	return "https://hf-mirror.com/" + p.repo + "/resolve/main/" + f.Path, true
}

// Bench is a published accuracy figure: character error rate on
// WenetSpeech test_meeting (far-field meetings, the closest public set to
// classroom audio). Figures come from different papers, so treat small gaps
// as noise.
type Bench struct {
	CER       float64 `json:"cer"`
	Source    string  `json:"source"`
	SourceURL string  `json:"source_url"`
	Note      string  `json:"note,omitempty"`
}

// Measured is speed and memory on the reference machine (Reference), with
// four threads, including model loading.
type Measured struct {
	RTF    float64 `json:"rtf"` // processing seconds per audio second
	PeakMB int     `json:"peak_mb"`
}

// Reference describes where Measured comes from.
var Reference = map[string]string{
	"machine": "Intel Core i7-13650HX · 4 线程 · Linux",
	"clip":    "5.4 分钟中文普通话测试音频（sherpa-onnx 模型自带的测试句拼接）",
	"date":    "2026-10",
}

type Model struct {
	ID         string   `json:"id"`
	Name       string   `json:"name"`
	Org        string   `json:"org"`
	Summary    string   `json:"summary"`
	Langs      string   `json:"langs"`
	Punct      bool     `json:"punct"` // the model writes punctuation itself
	License    string   `json:"license"`
	LicenseURL string   `json:"license_url"`
	Upstream   string   `json:"upstream"`
	Tags       []string `json:"tags"` // recommended | fast | accurate
	Bench      Bench    `json:"bench"`
	Measured   Measured `json:"measured"`

	pack pack
	args func(dir string) []string
}

func j(dir, name string) string { return filepath.Join(dir, filepath.FromSlash(name)) }

// Sources for Bench: FunAudioLLM https://arxiv.org/abs/2407.04051 (Table 6),
// Qwen3-ASR https://arxiv.org/abs/2601.21337, Fun-ASR https://arxiv.org/abs/2509.12508,
// FireRedASR2S https://arxiv.org/abs/2603.10420. Files and digests from the
// Hugging Face API of each repo.
var Models = []Model{
	{
		ID: "sensevoice-small", Name: "SenseVoice Small", Org: "阿里通义实验室", Langs: "按普通话识别",
		Summary: "体积小、速度极快，笔记本上几乎不占资源；本身不输出标点，会自动配上标点模型",
		License: "FunASR Model License", LicenseURL: "https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE",
		Upstream: "https://huggingface.co/FunAudioLLM/SenseVoiceSmall", Tags: []string{"fast"},
		Bench:    Bench{CER: 7.44, Source: "FunAudioLLM 技术报告", SourceURL: "https://arxiv.org/abs/2407.04051"},
		Measured: Measured{RTF: 0.023, PeakMB: 472},
		pack: pack{repo: "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09", files: []File{
			{Path: "model.int8.onnx", Size: 237115547, SHA256: "12ca1a2ae7ecf3e0019ef2822307ee0b5cadc9196569e379b4c4026f8205276d"},
			{Path: "tokens.txt", Size: 315894, SHA256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"},
		}},
		args: func(d string) []string {
			return []string{"--tokens=" + j(d, "tokens.txt"), "--sense-voice-model=" + j(d, "model.int8.onnx"),
				"--sense-voice-use-itn=1", "--sense-voice-language=zh"}
		},
	},
	{
		ID: "paraformer-zh", Name: "Paraformer 中文", Org: "阿里达摩院", Langs: "中 · 英",
		Summary: "中文专用的经典模型，速度与 SenseVoice 相当；本身不输出标点，会自动配上标点模型",
		License: "Apache-2.0", LicenseURL: "https://huggingface.co/funasr/paraformer-zh",
		Upstream: "https://huggingface.co/funasr/paraformer-zh", Tags: []string{"fast"},
		Bench:    Bench{CER: 6.97, Source: "FunAudioLLM 技术报告", SourceURL: "https://arxiv.org/abs/2407.04051"},
		Measured: Measured{RTF: 0.021, PeakMB: 479},
		pack: pack{repo: "csukuangfj/sherpa-onnx-paraformer-zh-int8-2025-10-07", files: []File{
			{Path: "model.int8.onnx", Size: 238429929, SHA256: "53813ee1d41722cc6370a571c887e6d0b391d25b8312cf714a31af85ea603812"},
			{Path: "tokens.txt", Size: 75756, SHA256: "59aba8873a2ed1e122c25fee421e25f283b63290efbde85c1f01a853d83cb6e6"},
		}},
		args: func(d string) []string {
			return []string{"--tokens=" + j(d, "tokens.txt"), "--paraformer=" + j(d, "model.int8.onnx")}
		},
	},
	{
		ID: "qwen3-asr-0.6b", Name: "Qwen3-ASR 0.6B", Org: "阿里通义千问", Langs: "30 种语言 · 22 种方言", Punct: true,
		Summary: "准确率与速度最均衡，自带标点，适合大多数笔记本；需要约 2.4 GB 内存",
		License: "Apache-2.0", LicenseURL: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B",
		Upstream: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B", Tags: []string{"recommended"},
		Bench:    Bench{CER: 6.88, Source: "Qwen3-ASR 技术报告", SourceURL: "https://arxiv.org/abs/2601.21337"},
		Measured: Measured{RTF: 0.158, PeakMB: 2364},
		pack: pack{repo: "csukuangfj2/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25",
			ms: &msMirror{repo: "zengshuishui/Qwen3-ASR-onnx", paths: map[string]string{
				"conv_frontend.onnx": "model_0.6B/conv_frontend.onnx", "encoder.int8.onnx": "model_0.6B/encoder.int8.onnx",
				"decoder.int8.onnx": "model_0.6B/decoder.int8.onnx", "tokenizer/merges.txt": "tokenizer/merges.txt",
				"tokenizer/vocab.json": "tokenizer/vocab.json", "tokenizer/tokenizer_config.json": "tokenizer/tokenizer_config.json",
			}},
			files: []File{
				{Path: "conv_frontend.onnx", Size: 44148281, SHA256: "d22dc4423e0940e49884e903d2ea2f7e5567c14fc1aed97e4e26d6b8f208ef9e"},
				{Path: "encoder.int8.onnx", Size: 182491662, SHA256: "60748d3e6744a57c9c91e1b17424a6c2990567e8adceb0783940c03ed98fa9d9"},
				{Path: "decoder.int8.onnx", Size: 755914231, SHA256: "4f6885be5959ae26af3089d38ee7972c5fafbeeb1cf8d5e76eab6d8b61ca5771"},
				{Path: "tokenizer/merges.txt", Size: 1671853, SHA256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"},
				{Path: "tokenizer/vocab.json", Size: 2776833, SHA256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"},
				{Path: "tokenizer/tokenizer_config.json", Size: 12487, SHA256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"},
			}},
		args: func(d string) []string {
			return []string{"--qwen3-asr-conv-frontend=" + j(d, "conv_frontend.onnx"), "--qwen3-asr-encoder=" + j(d, "encoder.int8.onnx"),
				"--qwen3-asr-decoder=" + j(d, "decoder.int8.onnx"), "--qwen3-asr-tokenizer=" + j(d, "tokenizer"), "--qwen3-asr-max-new-tokens=256"}
		},
	},
	{
		ID: "fun-asr-nano", Name: "Fun-ASR-Nano", Org: "阿里通义实验室", Langs: "中 · 英 · 日 · 方言", Punct: true,
		Summary: "基于大模型解码，自带标点，专有名词识别较好；速度与内存和 Qwen3-ASR 相近",
		License: "Apache-2.0", LicenseURL: "https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512",
		Upstream: "https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512",
		Bench: Bench{CER: 8.78, Source: "Fun-ASR 技术报告", SourceURL: "https://arxiv.org/abs/2509.12508",
			Note: "不同论文给出 6.29–8.78，这里取官方最新版本"},
		Measured: Measured{RTF: 0.119, PeakMB: 2154},
		pack: pack{repo: "csukuangfj/sherpa-onnx-funasr-nano-int8-2025-12-30", files: []File{
			{Path: "embedding.int8.onnx", Size: 155584380, SHA256: "95e61cd0c9c3b9543339a4cf973c95c116815e745ccc1e0285cbd81f76d18644"},
			{Path: "encoder_adaptor.int8.onnx", Size: 237792748, SHA256: "f36dea2e30fbc33b5db1d7a7265cc976c5e5586c77b042d5adb1ad27c72db422"},
			{Path: "llm.int8.onnx", Size: 600356593, SHA256: "dfbf9aa3be41bccc257587f151e15c63fbe1b549f2b517f5ccd5bdce3bf4322a"},
			{Path: "Qwen3-0.6B/merges.txt", Size: 1671853, SHA256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"},
			{Path: "Qwen3-0.6B/tokenizer.json", Size: 11422654, SHA256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"},
			{Path: "Qwen3-0.6B/vocab.json", Size: 2776833, SHA256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"},
		}},
		args: func(d string) []string {
			return []string{"--funasr-nano-encoder-adaptor=" + j(d, "encoder_adaptor.int8.onnx"), "--funasr-nano-llm=" + j(d, "llm.int8.onnx"),
				"--funasr-nano-embedding=" + j(d, "embedding.int8.onnx"), "--funasr-nano-tokenizer=" + j(d, "Qwen3-0.6B")}
		},
	},
	{
		ID: "firered-asr2-aed", Name: "FireRedASR2 AED", Org: "小红书 FireRed", Langs: "中 · 英 · 方言",
		Summary: "公开测试里中文最准，但最慢、最占空间；本身不输出标点，会自动配上标点模型",
		License: "Apache-2.0", LicenseURL: "https://huggingface.co/FireRedTeam/FireRedASR2-AED",
		Upstream: "https://huggingface.co/FireRedTeam/FireRedASR2-AED", Tags: []string{"accurate"},
		Bench:    Bench{CER: 4.53, Source: "FireRedASR2S 技术报告", SourceURL: "https://arxiv.org/abs/2603.10420"},
		Measured: Measured{RTF: 0.257, PeakMB: 1938},
		pack: pack{repo: "csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26", files: []File{
			{Path: "encoder.int8.onnx", Size: 817286833, SHA256: "54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82"},
			{Path: "decoder.int8.onnx", Size: 417291928, SHA256: "b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff"},
			{Path: "tokens.txt", Size: 79172, SHA256: "1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b"},
		}},
		args: func(d string) []string {
			return []string{"--tokens=" + j(d, "tokens.txt"), "--fire-red-asr-encoder=" + j(d, "encoder.int8.onnx"),
				"--fire-red-asr-decoder=" + j(d, "decoder.int8.onnx")}
		},
	},
	{
		ID: "whisper-large-v3-turbo", Name: "Whisper Large v3 Turbo", Org: "OpenAI", Langs: "约 100 种语言",
		Summary: "多语种通用，适合外语课；中文会漏字，准确率明显低于中文专用模型；会自动配上标点模型",
		License: "MIT", LicenseURL: "https://huggingface.co/openai/whisper-large-v3-turbo",
		Upstream: "https://huggingface.co/openai/whisper-large-v3-turbo",
		Bench: Bench{CER: 18.87, Source: "FunAudioLLM 技术报告", SourceURL: "https://arxiv.org/abs/2407.04051",
			Note: "论文测的是 Whisper Large v3，Turbo 版未单独公布"},
		Measured: Measured{RTF: 0.188, PeakMB: 1880},
		pack: pack{repo: "csukuangfj/sherpa-onnx-whisper-turbo", files: []File{
			{Path: "turbo-encoder.int8.onnx", Size: 674716297, SHA256: "b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b"},
			{Path: "turbo-decoder.int8.onnx", Size: 361080764, SHA256: "20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547"},
			{Path: "turbo-tokens.txt", Size: 816730, SHA256: "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"},
		}},
		args: func(d string) []string {
			return []string{"--tokens=" + j(d, "turbo-tokens.txt"), "--whisper-encoder=" + j(d, "turbo-encoder.int8.onnx"),
				"--whisper-decoder=" + j(d, "turbo-decoder.int8.onnx"), "--whisper-task=transcribe", "--whisper-tail-paddings=300"}
		},
	},
}

// vad splits speech from silence before recognition (Silero VAD v4, MIT).
var vad = pack{repo: "csukuangfj/vad",
	ms:    &msMirror{repo: "pengzhendong/silero-vad", paths: map[string]string{"silero_vad.onnx": "v4/silero_vad.onnx"}},
	files: []File{{Path: "silero_vad.onnx", Size: 1807522, SHA256: "a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28"}}}

// punct restores punctuation for models that do not write it
// (CT-Transformer from FunASR, exported by sherpa-onnx).
var punct = pack{repo: "csukuangfj/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12", files: []File{
	{Path: "model.onnx", Size: 294372519, SHA256: "e93593a6dbd69a07f8734ef269dbe861a379755f8d1c8354719432116f2c44bd"},
	{Path: "tokens.json", Size: 4207480, SHA256: "c960ab87bccea4aa15cf49a59f71973c2c330b46668048cd8da253749ec71ee3"},
}}

// Find returns the catalog entry for id.
func Find(id string) (Model, bool) {
	for _, m := range Models {
		if m.ID == id {
			return m, true
		}
	}
	return Model{}, false
}
