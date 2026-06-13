---
name: trans
description: "Transcribe a single Tongji Look lecture video to SRT + TXT, optionally download slide snapshots in parallel."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Transcribe

Transcribe one lecture video from look.tongji.edu.cn and optionally download slide snapshots.

## When to Use

- User says `/trans` or "transcribe this lecture".
- User provides a lecture URL or course_id + sub_id.

## Workflow

1. Resolve lecture with URL or IDs:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" transcribe --lecture-url "<LECTURE_URL>"
```

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" transcribe --course-id "<ID>" --sub-id "<ID>"
```

2. Transcribe + download slides in one run:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" transcribe --course-id "<ID>" --sub-id "<ID>" --slide
```

3. The CLI prints real-time progress. Stdout contains result paths.

## Artifacts

- `<course_id>_<sub_id>.srt` — subtitle with timestamps
- `<course_id>_<sub_id>.txt` — plain text transcript
- `<course_id>_<sub_id>.json` — metadata
- `slides/` — slide images + index.json (if --slide)

## One Session Per Call

For batch transcribing, use `/ralphtrans`.
