---
name: look-tongji-setup
description: "Configure Tongji Look credentials, check system dependencies (Python, Node.js, ffmpeg, vision-support, XeLaTeX), and set up the persistent course-wiki workspace."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Look Tongji Setup

Configure credentials, dependencies, and workspace for Look Tongji Notes.

## When to Use

- User says `/setup` or asks to configure the skill.
- First-time setup before transcribing lectures.
- User wants to change or migrate the course knowledge-base path.

## Workflow

1. Run setup:

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" setup
```

2. Non-interactive workspace options:

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" setup \
  --workspace-root "<COURSE_WIKI_ROOT>" \
  --owner-name "<OWNER_NAME>" \
  --site-name "<OWNER_NAME>的课程知识库"
```

3. The CLI checks: Python deps (requests, playwright, python-dotenv, markdown, markitdown), ffmpeg, Node.js, vision-support config, and optionally XeLaTeX.

### Vision Support

vision-support is a separately installed skill (not bundled in this repo). It lives at `~/.claude/skills/vision-support/` or `~/.agents/skills/vision-support/` depending on your platform.

The CLI detects it during setup by checking for `vision-support/config.json` at those paths.

If `vision-support/config.json` does not exist:

1. The CLI prints a one-liner initialization hint.
2. The agent should help the user configure a vision provider (OpenAI, Google, Anthropic, deepseek, dashscope, zhipuai, ollama, or custom).

Available providers: OpenAI, Google, Anthropic, deepseek, dashscope, zhipuai, ollama, or custom.

### Important Rules

- Never ask for passwords in chat. Use interactive terminal input or environment variables.
