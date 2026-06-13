# Look Tongji Notes Skill Catalog

Version: **0.2.0**

This repository follows the multi-agent skill catalog shape used by the MATLAB Agentic Toolkit. Eight atomic `/command` skills replace the legacy `look-tongji:` prefix system.

- `core/look-tongji-setup` — `/setup`: configure credentials, check dependencies (Python, Node.js, ffmpeg, vision-support, TeX), set workspace.
- `core/look-tongji-transcribe` — `/trans`: transcribe a single lecture (SRT + TXT), optionally download slides in parallel.
- `core/look-tongji-note` — `/note`: generate timeline outline + study notes from transcript and slides.
- `core/look-tongji-add` — `/add`: import supplementary materials (PDF, PPTX, DOCX) without triggering transcription.
- `core/look-tongji-wiki` — `/wiki`: build and locally serve the static course knowledge base.
- `core/look-tongji-page` — `/page`: deploy the course wiki to GitHub Pages (agent-driven, gh CLI).
- `core/look-tongji-cheatsheet` — `/cheatsheet`: generate exam cheat sheets (LaTeX or HTML output).
- `core/look-tongji-ralphtrans` — `/ralphtrans`: batch transcribe an entire course with checkpoint/resume.

The top-level `SKILL.md` serves as a compatibility index for agents that only support a single skill file.
