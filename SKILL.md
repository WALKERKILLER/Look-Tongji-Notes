---
name: look-tongji-notes
description: "8-command agent skill suite for Tongji Look (look.tongji.edu.cn): setup, transcribe, take notes, manage materials, build course wiki, deploy to GitHub Pages, create cheat sheets, and batch-process entire courses."
---

# Look Tongji Notes

## Commands

| Command | What It Does |
|---------|-------------|
| `/setup` | Configure credentials, check dependencies (Python, Node.js, ffmpeg, vision-support, TeX), set workspace |
| `/trans` | Transcribe one lecture to SRT + TXT; optionally download slides in parallel |
| `/note` | Generate study notes + timeline outline from transcript + slides |
| `/add` | Import supplementary materials (PDF, PPTX, DOCX) into a lecture session |
| `/wiki` | Build and locally serve the static course knowledge base |
| `/page` | Deploy the course wiki to GitHub Pages (gh CLI, agent-driven) |
| `/cheatsheet` | Generate A4 cheat sheet (LaTeX or HTML) from course notes |
| `/ralphtrans` | Batch transcribe all lectures in a course with checkpoint/resume |

Each command has its own `skills/<name>/SKILL.md` with detailed workflow instructions.

> **Deprecated:** Old `look-tongji:xxx` trigger phrases (e.g., `look-tongji:setup`) still work but are deprecated. Use `/command` instead.

## Shared Conventions

### Credentials & Auth
- Credentials stored in `<SKILL_DIR>/.env` (git-ignored).
- Auth cache in `<SKILL_DIR>/state/`.
- Workspace config stored outside the skill tree for persistence across updates.

### Workspace Layout
```
<workspace_root>/
  raw/<course_name>/<session>/原始数据/
    <course_id>_<sub_id>.srt
    <course_id>_<sub_id>.txt
    <course_id>_<sub_id>.json
    <course_id>_<sub_id>_timeline.txt
    <course_id>_<sub_id>_notes.md
    <course_id>_<sub_id>_dialogue.md
    slides/
    materials/
  site/          # generated static wiki
  wiki/          # llm-wiki sources
```

### Agent-Content Boundary
- The CLI fetches, transcribes, downloads, and converts artifacts.
- The agent generates timeline outlines, study notes, and cheat sheet content.
- Never pass passwords in chat. Use interactive terminal input.

## References

- `<SKILL_DIR>/references/url-guide.md` — Lecture URL formats and parsing
- `<SKILL_DIR>/references/troubleshooting.md` — Common setup/login/ASR issues
- `<SKILL_DIR>/references/security.md` — Credential and output safety

## Quick Start

```
/setup                   # first time only
/trans --course-id X     # transcribe one lecture
/note --course-id X      # generate notes for one lecture
/wiki                    # serve local course wiki
```
