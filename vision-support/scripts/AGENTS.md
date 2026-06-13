<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-13 | Updated: 2026-06-13 -->

# scripts

## Purpose
Contains the core vision-support CLI script (`vision.mjs`), a zero-dependency Node.js CLI tool that bridges non-multimodal AI models with image recognition capabilities. Supports multiple provider APIs (OpenAI-compatible, Google Gemini, Anthropic Claude) with automatic proxy detection, model configuration management, and fallback retry logic.

## Key Files

| File | Description |
|------|-------------|
| `vision.mjs` | Zero-dependency Node.js CLI for multi-provider image recognition; supports 18+ model providers, interactive configuration, proxy auto-detection, and multi-image analysis with fallback |

## Subdirectories

*None.*

## For AI Agents

### Working In This Directory
- `vision.mjs` is a self-contained script with no dependencies beyond Node.js 18+ built-in modules
- The `--use-env-proxy` flag enables proxy mode via child process spawn; the primary proxy approach patches `globalThis.fetch` in-process
- Configuration is managed via `config.json` in the parent directory; the `VISION_CONFIG_PATH` env var overrides the path

### Testing Requirements
- Test configuration commands: `init`, `config add`, `config list`, `config remove`, `config test`
- Test image recognition with local image files and remote URLs
- Test proxy detection on platforms with and without proxy configurations
- Verify fallback behavior when primary model fails (timeout, auth error, empty response)
- Test multi-image input with optional custom prompt

### Common Patterns
- CLI subcommand dispatch using `process.argv` switch statements
- Provider API abstraction via a common `callModel()` dispatch function that delegates to format-specific callers (`callOpenAI`, `callGoogle`, `callAnthropic`)
- Interactive prompts via Node.js `readline` module for `init`, `config add`, `config edit`
- Proxy auto-detection with layered strategy (env var, config file, Windows registry, port probing)
- Config persisted as JSON and auto-synced to multiple skill installation directories

## Dependencies

### Internal
- `../config.json` — runtime configuration file (models, default prompt, proxy settings)
- `../config.example.json` — fallback config template if `config.json` is absent

### External
- Node.js 18+ (built-in modules only: `fs`, `path`, `url`, `readline`, `child_process`, `http`, `https`, `tls`, `os`, `net`)
- No npm dependencies — intentionally zero-dependency by design

<!-- MANUAL: -->
