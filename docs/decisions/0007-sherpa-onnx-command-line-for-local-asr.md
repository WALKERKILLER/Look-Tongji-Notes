# Local transcription runs sherpa-onnx's prebuilt command-line programs

## Status
Accepted
Class: architecture

## Context and Problem Statement
The free cloud ASR channels rate-limit and cap audio per 12 hours, so long lectures stall. Users asked for downloadable local models (see [local ASR spec](../specs/0009-local-asr-models.md)). lookd is a single static Go binary built for Linux, macOS and Windows; the recogniser must run well on an ordinary laptop CPU, cover the strongest current Chinese models, and not complicate the build.

## Decision Drivers
- Chinese accuracy on lecture-like audio and CPU speed on a laptop.
- No cgo or native toolchain in lookd's build; one prebuilt runtime per platform that can be verified by digest.
- A model list that can grow (new models appear monthly) without new code paths.
- Permissive licenses for everything shipped or downloaded by default.

## Considered Options
- A. sherpa-onnx prebuilt shared-library release, called through its `sherpa-onnx-vad-with-offline-asr` and `sherpa-onnx-offline-punctuation` programs.
- B. sherpa-onnx through its Go bindings (cgo).
- C. whisper.cpp binaries.
- D. faster-whisper or FunASR in a managed Python environment.

## Decision Outcome
Chosen option: A. One ~25 MB archive per platform runs SenseVoice, Paraformer, Qwen3-ASR, Fun-ASR-Nano, FireRedASR2 and Whisper with VAD segmentation, prints `start -- end: text` lines that are trivial to parse, and keeps lookd pure Go. Measured on the reference laptop it transcribes 90 minutes in 2–23 minutes depending on the model.

### Consequences
- Good: adding a model is a catalog entry (files, digests, flags); the engine is fetched once and verified by its GitHub release digest.
- Good: a crash or out-of-memory in the recogniser kills a child process, not lookd.
- Bad: each chunk pays model loading (≈1–5 s); acceptable with 20-minute chunks.
- Bad: no prebuilt Linux arm64 shared archive for this release, so that platform keeps cloud transcription only.

## Pros and Cons of the Options
- A: pure Go build, all current Chinese models, digest-verified runtime; per-chunk load cost.
- B: no process spawn per chunk, but cgo breaks the simple cross-compiled release and ties lookd to one library ABI.
- C: mature and fast for Whisper, but Whisper's Chinese accuracy is far behind Chinese-specific models (CER 18.9 vs 4.5–7.4 on WenetSpeech meeting).
- D: broadest model choice, but a Python runtime, PyTorch-sized downloads and package resolution on user machines.

## Links
- [Local ASR spec](../specs/0009-local-asr-models.md)
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
