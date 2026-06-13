# Changelog

All notable changes to Look-Tongji-Notes.

---

## [1.1.0] - 2026-06-13

### Added
- **`gh` CLI detection** in `/setup` — checks if `gh` is installed for `/page` GitHub Pages deployment, with install guidance if missing.
- **Node.js version check** in `/setup` — parses `node --version` and warns when below v18 (required by `vision-support`).

### Fixed
- **[CRITICAL] CI blind spot** — `skills/page/` was missing from CI trigger paths and validation loop; the `/page` skill could change without any CI verification. Now all 9 skills are validated.
- **Documentation count errors** — `README_ZH.md` stated "8 skills/commands" while listing 9; corrected all 3 occurrences to "9".
- **`AGENTS.md` command map** — `/page` was absent from the enumerated `/command` trigger list; added.
- **Version metadata inconsistency** — 8 per-command skills had `version: "1.0"` in their YAML frontmatter while the plugin manifests declared `1.1.0`; unified to `1.1` across all 9 skills' `SKILL.md` and `manifest.yaml`.
- **Backtick escaping** — 5 SKILL.md files used `\`` (backslash-escaped backticks) in "Where `<SKILL_DIR>` Points" sections, causing inconsistent Markdown rendering; normalized to plain backticks.
- **Truncated path guidance** — `skills/page/SKILL.md` "Where" section lacked the shared-path context present in every other skill; expanded with explanation and full path reference.

### Changed
- **CI step name**: `Validate skills/ flat structure (8 skills)` → `(9 skills)`.
- **`skills/page/` tracked in git** — previously existed on disk but was never committed; now properly version-controlled with all other skills.

---

## [1.0.0] - 2026-06-13

### Added
- **Flat per-command skill layout** — replaced the hierarchical `skills-catalog/core/look-tongji-<name>/` structure with a flat `skills/<name>/SKILL.md` layout (9 skills: `setup`, `list`, `trans`, `note`, `add`, `wiki`, `page`, `cheatsheet`, `ralphtrans`).
- **`manifest.yaml` per skill** — each `skills/<name>/` directory now contains a `manifest.yaml` with name, description, license, and version metadata.
- **CheatingSheetTemplate** — LaTeX template, fonts (PingFang SC + SF Compact Text), and HTML dual-output support for A4 cheat sheet generation.
- **4 new plugin manifests** — `.gemini-plugin/`, `.hermes-agent-plugin/`, `.openclaw-plugin/`, `.opencode-plugin/` — bringing total platform support to 8 (Claude Code, Codex, Cursor, Gemini CLI, Hermes Agent, OpenClaw, OpenCode, Copilot/Agents).
- **CI skill validation** — `skill-packaging.yml` validates all 10 JSON plugin manifests and the flat `skills/` structure (SKILL.md + manifest.yaml + name grep per skill).
- **`/list` as 9th command** — dedicated skill for course discovery with keyword search and interactive selection.
- **`SKILL_DIR` references** in all plugin descriptions and OpenAI agent descriptor.

### Changed
- **Plugin versions bumped to 1.0.0** — all manifests updated from legacy versions.
- **Descriptions updated** to reflect the 9-command suite across all manifests, `openai.yaml`, and documentation.
- **`README.md` / `README_ZH.md`** — rewritten command tables, install instructions, and multi-agent skill structure documentation.
- **`SKILL.md` (root)** — reorganized as a compatibility index mapping each `/command` to its `skills/<name>/SKILL.md`.

### Removed
- **`skills-catalog/`** — legacy hierarchical skill structure replaced by flat `skills/` layout.

---

## [0.2.0] - 2026-06 (prior)

### Changed
- **Atomized monolithic SKILL.md** into 8 per-command skill files under `skills-catalog/core/`.
- CI integration via GitHub Actions for JSON manifest validation and Python smoke tests.

---

## [0.1.0] - 2025 (prior)

### Added
- Initial release: Tongji Look IAM SSO login, lecture transcription (BcutASR), slide download, Markdown note generation, llm-wiki site builder.
- Claude Code + Codex plugin manifests.
- CLI entry point (`scripts/look_tongji.py`).
