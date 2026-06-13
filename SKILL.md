---
name: look-tongji-notes
description: "9-command agent skill suite for Tongji Look (look.tongji.edu.cn): setup, list, transcribe, take notes, manage materials, build course wiki, deploy to GitHub Pages, create cheat sheets, and batch-process entire courses."
---

# Look Tongji Notes

## Commands

| Command | What It Does | SKILL.md |
|---------|-------------|----------|
| `/setup` | Configure credentials, check dependencies (Python, Node.js, ffmpeg, vision-support, TeX), set workspace | `skills/setup/SKILL.md` |
| `/list` | List courses, search by keyword, interactive selection | `skills/list/SKILL.md` |
| `/trans` | Transcribe one lecture to SRT + TXT; optionally download slides in parallel | `skills/trans/SKILL.md` |
| `/note` | Generate study notes + timeline outline from transcript + slides | `skills/note/SKILL.md` |
| `/add` | Import supplementary materials (PDF, PPTX, DOCX) into a lecture session | `skills/add/SKILL.md` |
| `/wiki` | Build and locally serve the static course knowledge base | `skills/wiki/SKILL.md` |
| `/page` | Deploy the course wiki to GitHub Pages (gh CLI, agent-driven) | `skills/page/SKILL.md` |
| `/cheatsheet` | Generate A4 cheat sheet (LaTeX or HTML) from course notes | `skills/cheatsheet/SKILL.md` |
| `/ralphtrans` | Batch transcribe all lectures in a course with checkpoint/resume | `skills/ralphtrans/SKILL.md` |

Each command has its own `skills/<name>/SKILL.md` with detailed workflow instructions.

## Shared Conventions

### Credentials & Auth
- Credentials stored in `<SKILL_DIR>/.env` (git-ignored).
- Auth cache in `<SKILL_DIR>/state/`.
- Workspace config stored outside the skill tree for persistence across updates.

### Agent-Content Boundary
- The CLI fetches, transcribes, downloads, and converts artifacts.
- The agent generates timeline outlines, study notes, and cheat sheet content.
- Never pass passwords in chat. Use interactive terminal input.

## Quick Start

```
/setup                   # first time only
/list                    # discover courses
/trans --course-id X     # transcribe one lecture
/note --course-id X      # generate notes for one lecture
/wiki                    # serve local course wiki
```
