---
name: wiki
description: "Build and serve the static course knowledge base locally. Rebuilds from workspace data and starts an HTTP server on port 8765."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.1"
---

# Wiki

Build and locally serve the course knowledge base.

## When to Use

- User says `/wiki` or "open the course wiki" or "serve the wiki".
- After writing notes, to preview the generated site.

## Workflow

1. Serve (build + start HTTP server):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" serve --port 8765
```

2. Build only (no server):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" build
```

## Page Structure

Each session page follows this layout (top to bottom):

1. **Lecture Video** (top) — embedded player area when video metadata is available, or a direct video link
2. **Resources** (middle) — supplementary materials, slide download links, and transcript download links
3. **Note** (bottom) — pure Markdown study content without task-oriented meta-descriptions

## Duration Check

- Sessions with `duration_seconds < 3600` are flagged with a warning indicator in the wiki UI.
- The agent should suggest re-transcription for short sessions.

## Note Cleanliness

- Notes must be pure knowledge content without task-oriented meta-descriptions.
- See `/note` skill for the full list of forbidden phrases.

## Validation

- The generated site uses the vendored llm-wiki frontend.
- UI chrome (language toggle, navigation) is handled by the frontend; content is from workspace data.

## Where `<SKILL_DIR>` Points

`<SKILL_DIR>` is the directory containing this `SKILL.md`. Shared scripts (`look_tongji.py`, `timeline_tools.py`, `tongji_backend/`) and references live two levels up in the repository root (`<SKILL_DIR>/../../scripts/` and `<SKILL_DIR>/../../references/`).
