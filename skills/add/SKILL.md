---
name: add
description: "Add supplementary materials (PDF, PPTX, DOCX, images) to a lecture session. Converts to Markdown via MarkItDown and indexes into the course wiki — without triggering transcription or slide download."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.1"
---

# Add Materials

Attach supplementary materials to a lecture session.

## When to Use

- User says `/add` or "add this material to the course".
- After transcribing a lecture, adding additional PDFs/PPTs/docs.
- User wants materials indexed into the wiki without re-running transcription.

## Workflow

1. Import materials:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" add \
  --course-id "<ID>" --sub-id "<ID>" \
  --material "handout=/path/to/file.pdf"
```

2. The CLI copies files into the session's `materials/<name>/` directory.
3. MarkItDown auto-converts supported formats to Markdown.
4. The course wiki index is updated automatically.

## Supported Formats

- PDF (.pdf), PPTX (.pptx), DOCX (.docx) — via MarkItDown
- Images (.png, .jpg, .webp) — copied as-is
- Text/Code (.txt, .md, .py, .js) — copied as-is

## Difference from `/note --material`

`/add` only imports materials + updates the index. It does NOT trigger transcription or slide download.

## Where `<SKILL_DIR>` Points

`<SKILL_DIR>` is the directory containing this `SKILL.md`. Shared scripts (`look_tongji.py`, `timeline_tools.py`, `tongji_backend/`) and references live two levels up in the repository root (`<SKILL_DIR>/../../scripts/` and `<SKILL_DIR>/../../references/`).
