<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-13 | Updated: 2026-06-13 -->

# vision-support

## Purpose
Image recognition bridge skill for non-multimodal LLMs (e.g., DeepSeek, GLM). When the main model cannot process images, this skill delegates vision requests to a configured external vision model (OpenAI, Gemini, Qwen-VL, etc.), supports multi-image analysis, automatic fallback across multiple models, and 19+ API platforms. Includes an interactive `init` setup wizard and a comprehensive config management CLI.

## Key Files

| File | Description |
|------|-------------|
| `README.md` | English documentation with installation, usage, and configuration guide |
| `README.zh.md` | Chinese documentation (same content as README.md) |
| `SKILL.md` | Agent skill entry point: defines when/how the vision skill auto-triggers in agents |
| `package.json` | npm package definition with bin entry (`vision-support`), postinstall hook, and metadata |
| `config.example.json` | Configuration template with example model definitions (OpenAI, Gemini, Qwen-VL, GLM-4V) and proxy settings |
| `install.mjs` | Cross-platform Node.js installation script with interactive agent selection and uninstall support |
| `install.sh` | Mac/Linux/WSL shell installation script with git-based cloning |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `bin/` | npm CLI entry points: `cli.mjs` (global `vision-support` command) and `postinstall.mjs` (npm postinstall hook that auto-deploys skill files to known agent directories) |
| `scripts/` | Core vision logic: `vision.mjs` -- a zero-dependency Node.js script handling image loading, multi-provider API calls (openai/google/anthropic formats), automatic proxy detection, model fallback, and interactive config management |
| `references/` | Reference documentation: `supported-models.md` -- lists tested vision-capable models, provider types, API formats, and recommended configurations (budget, premium, local-only, Chinese providers) |
| `images/` | Screenshots used in README: `usage-recognize.png` (terminal running vision-support) and `usage-result.png` (recognition result output) |

## For AI Agents

### Working In This Directory
This directory is a standalone skill package cloned from `https://github.com/penfick/skills`. The core logic lives in `scripts/vision.mjs` (1300+ lines, zero external dependencies using only Node.js built-in modules). The `SKILL.md` defines when agents auto-trigger the skill (image attached, user mentions "screenshot"/"picture", manual `/vision-support` command). Configuration follows the iron rule: models configured here are used ONLY for image recognition and never participate in main logic reasoning.

### Testing Requirements
- After modifying `scripts/vision.mjs`, test with `node scripts/vision.mjs --help` for argument parsing
- Config commands can be tested: `node scripts/vision.mjs config list` (requires a config.json)
- Image recognition tests require a valid API key for at least one configured model
- The install scripts (`install.mjs`, `install.sh`) should be tested in a clean environment

### Common Patterns
- Zero-dependency pattern: all HTTP requests, image processing, and CLI interaction use Node.js built-in modules (`fetch`, `fs`, `path`, `readline`, `crypto`)
- Provider abstraction: `callModel()` dispatches to `callOpenAI()`, `callGoogle()`, or `callAnthropic()` based on the `provider` field
- Proxy auto-detection: environment variables -> Windows registry -> port probing, with CONNECT tunnel patching for HTTPS
- Model fallback chain: primary model first, then ordered fallbacks; `VISION_DEFAULT_MODEL` env var overrides the primary
- Configuration is synced across all installed skill locations when saved

## Dependencies

### Internal
- Referenced from `../repo/Look-Tongji-Notes/` as a supporting skill for slide image processing in the Tongji Look lecture pipeline

### External
- Node.js 18+ runtime only -- zero npm dependencies
- External API services: OpenAI, Google Gemini, Anthropic Claude, and other vision model providers (19+ platforms)
- Proxy detection: auto-detects Clash, V2Ray, Shadowsocks, and other local proxy ports

<!-- MANUAL: -->
