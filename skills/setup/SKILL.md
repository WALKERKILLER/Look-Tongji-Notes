---
name: setup
description: "Configure Tongji Look credentials, check system dependencies (Python, Node.js, ffmpeg, vision-support, XeLaTeX), and set up the persistent course-wiki workspace."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Setup

Configure credentials, dependencies, and workspace for Look Tongji Notes.

## When to Use

- User says `/setup` or asks to configure the skill.
- First-time setup before transcribing lectures.
- User wants to change or migrate the course knowledge-base path.

## Workflow

1. Run setup:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" setup
```

2. Non-interactive workspace options:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" setup \
  --workspace-root "<COURSE_WIKI_ROOT>" \
  --owner-name "<OWNER_NAME>" \
  --site-name "<OWNER_NAME>的课程知识库"
```

3. The CLI checks: Python deps (requests, playwright, python-dotenv, markdown, markitdown), ffmpeg, Node.js, vision-support config, and optionally XeLaTeX.

4. **Vision Support setup:** If `vision-support/config.json` does not exist, the CLI prints a one-liner initialization command. The agent should then help the user configure a vision provider (OpenAI, Google, Anthropic, deepseek, dashscope, zhipuai, ollama, or custom).

5. Never ask for passwords in chat. Use interactive terminal input or environment variables.

## Where `<SKILL_DIR>` Points

`<SKILL_DIR>` is the directory containing this `SKILL.md`. Shared scripts (`look_tongji.py`, `timeline_tools.py`, `tongji_backend/`) and references live two levels up in the repository root (`<SKILL_DIR>/../../scripts/` and `<SKILL_DIR>/../../references/`).
