<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-06-13 | Updated: 2026-06-13 -->

# Look-Tongji-Notes

## Purpose
Root of the Look Tongji Notes skill repository. Provides a multi-agent skill + CLI for processing lectures from Tongji Look (`look.tongji.edu.cn`): IAM SSO login, course listing, lecture transcription (SRT/TXT via BcutASR), slide snapshot download, supplementary material import, timeline outline generation, Markdown study-note writing, and static course knowledge-base site generation via the vendored `llm-wiki` library. Packaged as both a standalone CLI and an installable skill for Claude Code, Codex CLI, Cursor, Gemini CLI, OpenClaw, OpenCode, Hermes Agent, and GitHub Copilot.

## Key Files

| File | Description |
|------|-------------|
| `LICENSE` | MIT license |
| `README.md` | English project overview, install/usage instructions, compliance notes |
| `README_ZH.md` | Chinese project overview with multi-agent skill structure documentation |
| `SKILL.md` | Agent skill definition with CLI workflow commands, prompt templates, output conventions |
| `requirements.txt` | Python dependencies (requests, playwright, python-dotenv, markdown, markitdown) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `agents/` | OpenAI/Codex agent interface descriptor (`openai.yaml`) |
| `.agents/plugins/` | Generic agents marketplace manifest (`marketplace.json`) for Copilot and other platforms |
| `.claude-plugin/` | Claude Code platform manifest (`plugin.json` + `marketplace.json`) |
| `.codex-plugin/` | Codex CLI platform manifest (`plugin.json`) |
| `.cursor-plugin/` | Cursor platform manifest (`plugin.json` + `marketplace.json`) |
| `.gemini-plugin/` | Gemini CLI platform manifest (`plugin.json`) |
| `.openclaw-plugin/` | OpenClaw platform manifest (`plugin.json`) |
| `.opencode-plugin/` | OpenCode platform manifest (`plugin.json`) |
| `.hermes-agent-plugin/` | Hermes Agent platform manifest (`plugin.json`) |
| `images/` | Branding assets (logo SVG) and usage guide screenshots |
| `llmwiki/` | Vendored `llm-wiki` Python package for building static knowledge-base sites from session data |
| `references/` | Security, troubleshooting, and URL-format reference documentation for agent consumption |
| `scripts/` | CLI entry point (`look_tongji.py`) and backend modules for auth, API client, transcription, slide download, and workspace management |
| `skills/` | 8 atomic per-command skill files (`skills/<name>/SKILL.md`) with `manifest.yaml` each, for multi-agent platforms |
| `CheatingSheetTemplate/` | LaTeX template + fonts for cheat sheet generation (also referenced via `.mock-wiki/CheatingSheetTemplate/`) |
| `.trash/` | Preserved legacy files (recoverable); non-runtime directory |
| `.omc/` | OMC workflow metadata (plans, state, logs); non-runtime directory |

## For AI Agents

### Working In This Directory
- This is the source repository root. The 8 installable command skills live under `skills/<name>/SKILL.md` in flat layout.
- `SKILL.md` is the primary compatibility index: it maps `/command` trigger phrases (`/setup`, `/list`, `/trans`, `/note`, `/wiki`, `/add`, `/cheatsheet`, `/ralphtrans`) to CLI commands.
- Credentials are stored in `<skill_root>/.env` (auto-ignored by `.gitignore`). Auth cache goes in `<skill_root>/state/`.
- The workspace config (course wiki path) is stored outside the skill tree so skill updates do not destroy it.
- Lecture artifacts follow this layout: `raw/<course_name>/<session>/原始数据/{transcript,slides,materials,manifest.json}`.

### Testing Requirements
- Full end-to-end testing requires a valid Tongji IAM account and access to `look.tongji.edu.cn`.
- Unit-testable components: URL parsing (`_extract_ids_from_url`), timeline normalization (`scripts/timeline_tools.py`), env-file parsing (`_parse_env_lines`), agent-name normalization (`_normalize_agent_name`).
- Slide download can be tested for concurrency/throttling behavior with `--concurrency 2 --retries 5`.
- ASR testing requires actual lecture media with audio streams.

### Common Patterns
- `SKILL.md` defines agent-facing workflow. CLI commands in `scripts/look_tongji.py` are the backend.
- Lecture identification: prefer `--lecture-url` for best-effort parsing, or explicit `--course-id` + `--sub-id`.
- Course search: prefer `list --all --query "<keyword>"` for accuracy over the recent-courses list.
- The `note` command runs transcript + slide download in parallel by default.
- Notes are written by the AI agent after CLI artifacts complete; the CLI never generates study-note content itself.
- Site rebuild: run `index` then `build` after writing notes, then `serve --port 8765` for local preview.

## Dependencies

### Internal
- `scripts/tongji_backend/` provides auth, client, transcriber, workspace, and site-builder modules consumed by `scripts/look_tongji.py`.
- `llmwiki/` (vendored) provides the static site generator consumed by workspace helpers.
- `scripts/timeline_tools.py` provides SRT sampling and timeline normalization utilities.

### External
- `requests` — HTTP client for Tongji API and slide downloads
- `playwright` — Browser automation for IAM SSO login
- `python-dotenv` — `.env` file loading
- `markdown` / `markitdown[all]` — Supplementary material Markdown conversion
- `ffmpeg` (system) — Audio extraction from lecture video streams
- `BcutASR` (Bilibili cloud API) — Free cloud speech-to-text for transcription

<!-- MANUAL: -->
