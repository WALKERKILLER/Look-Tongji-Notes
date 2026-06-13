---
name: look-tongji-wiki
description: "Build and serve the static course knowledge base locally. Rebuilds from workspace data and starts an HTTP server on port 8765."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Look Tongji Wiki

Build and locally serve the course knowledge base.

## When to Use

- User says `/wiki` or "open the course wiki" or "serve the wiki".
- After writing notes, to preview the generated site.

## Workflow

1. Serve (build + start HTTP server):

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" serve --port 8765
```

2. Build only (no server):

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" build
```

## Page Structure

Each session page follows this layout:
1. **Lecture Video** — embedded player area (when video metadata is available)
2. **Resources** — supplementary materials, slides, and transcript download links
3. **Note** — pure Markdown study content (no task-oriented descriptions)

## Duration Check

- Sessions with duration < 1 hour (3600s) are marked with a warning badge.
- The agent should suggest re-transcription for short sessions.

## Validation

- The generated site uses the vendored llm-wiki frontend.
- UI chrome (language toggle, navigation) is handled by the frontend; content is from workspace data.
