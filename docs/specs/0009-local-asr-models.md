# Local speech recognition models

Artifact-Version: 1
Status: Approved

## Intent
Transcription relies on two free cloud channels (必剪, 剪映) whose rate limits and 12-hour quotas stall long lectures. Users with a reasonable laptop should be able to download an offline model once and transcribe on their own machine, choosing the model with an honest comparison of accuracy, speed and memory.

Outcome: Settings → 转写 opens a page with a benchmark board and a model list; one click downloads the recogniser and a model into Look Studio's data directory from a chosen source, and the model becomes the `local` channel of the existing ASR pool.

This downloads and runs executables and large files from third parties, so every file has a pinned size and SHA-256, sources are a fixed list plus one user template, and nothing is installed system-wide. Recogniser: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache-2.0) command-line programs; the reference project VideoCaptioner (GPL-3.0) inspired the feature only, no code is taken from it.

Non-goals: GPU providers, streaming/live captions, model fine-tuning, automatic engine updates, speaker diarization.

## Contract

### Catalog
`lookd/internal/localasr/catalog.go` lists the engine archive per platform (`linux/amd64`, `darwin/arm64`, `darwin/amd64`, `windows/amd64`; others are unsupported) and six models: SenseVoice Small, Paraformer 中文, Qwen3-ASR 0.6B (recommended), Fun-ASR-Nano, FireRedASR2 AED, Whisper Large v3 Turbo. Each model carries files (path, size, SHA-256), languages, whether it writes punctuation, license and upstream links, a published CER on WenetSpeech test_meeting with its paper, and RTF/peak memory measured on the reference machine with four threads. Silero VAD is always installed; the CT-Transformer punctuation model is installed for models that do not punctuate.

### Sources
`asr.local.source` (setting): `hf-mirror` (default, `https://hf-mirror.com/<repo>/resolve/main/<file>`), `huggingface`, `modelscope` (only packs with a byte-identical ModelScope copy: Qwen3-ASR 0.6B from `zengshuishui/Qwen3-ASR-onnx`, Silero VAD from `pengzhendong/silero-vad`; other packs fall back to hf-mirror with a progress note), `custom` (`asr.local.custom_url`, an `http(s)` template containing `{file}` and optionally `{repo}`). The engine comes from GitHub Releases, optionally prefixed by `asr.local.github_proxy`.

### API
- `GET /api/asr/local` → `{status: {supported, platform, engine, models: [catalog fields + size, extra, installed, sources], sources, install, reference, cpus, location: {dir, default, custom, used, free}}, active, source, custom_url, github_proxy, threads}`; `free` is the space available on that disk, -1 when unknown.
- `POST /api/asr/local/install {model}` starts a background install with the current source settings; unknown model or bad template → 400; 409 while one runs. Progress `{state: running|done|failed|canceled, model, source, step, done, total, speed, note, error}` is published as `asr_local` events.
- `POST /api/asr/local/cancel` stops it; partial files are kept and the next install resumes them with HTTP Range.
- `DELETE /api/asr/local/models/{id}` removes a model (409 while it downloads); removing the active model clears `asr.local.model`.
- `PUT /api/asr/local/location {dir, move}` changes the storage folder (`""` = default). 400 for a relative path, an unwritable folder, or with `move` a folder inside the current one or containing it; 409 while an install or move runs or while a local transcription is running. The local channel leaves the pool first, so no transcription starts meanwhile. Without `move` the switch is immediate and old files stay; models already in the new folder count as installed. With `move` the engine and models move in the background (a rename on the same disk, otherwise a copy that keeps symbolic links, then a delete; entries already in the target are kept), reported as `asr_local` progress with an empty `model`; the channel comes back when it ends. The choice is kept in `<data>/asr/location.json`; only `engine`, `models`, `vad` and `punct` are managed there.
- Settings `asr.local.model` (active id, `""` = off) and `asr.local.threads` (default min(4, cores/2)). The first finished install becomes active if none is.

### Integrity and layout
Files land in `<root>/{engine/v<version>, vad, punct, models/<id>}`, where the root is `<data>/asr` or the folder the user picked, and a directory counts as installed only after every file matched its size and SHA-256 and a `.complete` marker was written. A response larger than the pinned size, a short body or a digest mismatch fails the install and deletes the bad part. The engine archive is extracted to a temporary directory (only `bin/` and `lib/`; absolute paths, `..` and escaping links are refused) and renamed into place.

### Recognition
The active model joins the ASR pool as channel `local`: listed first, one chunk at a time, no quota, same cooldown on failure; the cloud channels keep their own toggles and the pool strategy can prefer `local`. A chunk is converted to 16 kHz mono WAV with ffmpeg and run through `sherpa-onnx-vad-with-offline-asr` (VAD threshold 0.3, segments ≤ 20 s); output lines `start -- end: text` become utterances. For models without punctuation, the joined text of the chunk goes once through `sherpa-onnx-offline-punctuation` and the marks are mapped back onto the segments; if the result changes any non-punctuation character, the unpunctuated text is kept.

### App
Settings → 转写 shows an entry card (status of the local channel) that opens 本地识别模型: hero status, a benchmark board (rows = models; small multiples for 错字率, 90 分钟课的转写用时, 峰值内存; sortable; footnotes name the paper and the reference machine), model cards with download/pause/resume/use/stop/delete and live progress, source choice with a guide per source and the GitHub prefix, and a thread slider. The local channel card hides the quota bar.

## Plan
`asr.Pool.SetLocal` adds the channel; `localasr` holds catalog, manager and recogniser; `server/localasr.go` maps settings to the pool and exposes the routes; `app/lib/features/settings/{local_asr_page,asr_bench}.dart` render the page.

## Verification
- `go test ./internal/localasr ./internal/asr`: line parsing, punctuation realignment, resume + digest + oversize checks, archive path checks, catalog completeness, local channel without quota.
- `flutter test test/local_asr_test.dart`: board sorting and semantics, download → progress → use, custom source template.
- Manual: install SenseVoice from hf-mirror into a scratch directory and transcribe a test clip through the pool.

## Evidence
- [localasr tests](../../lookd/internal/localasr/localasr_test.go), [location tests](../../lookd/internal/localasr/location_test.go), [pool test](../../lookd/internal/asr/pool_test.go), [app tests](../../app/test/local_asr_test.dart).
- Reference measurements (i7-13650HX, 4 threads, 5.4 min clip): SenseVoice RTF 0.023 / 0.5 GB, Paraformer 0.021 / 0.5 GB, Fun-ASR-Nano 0.119 / 2.1 GB, Qwen3-ASR 0.158 / 2.3 GB, Whisper Turbo 0.188 / 1.8 GB, FireRedASR2 0.257 / 1.9 GB.
