---
name: look-tongji-ralphtrans
description: "Batch transcribe ALL playable lectures for a course in a persistent loop. Uses a JSON state file for checkpoint/resume. Runs until every lecture is transcribed or marked failed."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Look Tongji Ralph Batch Transcribe

Batch transcribe all playable lectures for a course with checkpoint/resume.

## When to Use

- User says `/ralphtrans` or "batch transcribe this course".
- User wants to transcribe an entire course in one go.

## Workflow

1. Start batch transcription:

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" batch-transcribe --course-id "<ID>"
```

2. The CLI:
   - Loads all playable lectures for the course.
   - Creates/reads `batch_state.json` in the workspace to track progress.
   - Transcribes lectures one by one, updating state after each.
   - Retries failed lectures up to `--max-retries` times.
   - Prints a summary when all lectures are done or failed.

3. **Interrupt & Resume:**
   - Press Ctrl+C to safely stop. State is saved.
   - Re-run the same command to resume from pending lectures.

## State File

`batch_state.json` structure:
```json
{
  "course_id": "xxx",
  "started_at": "ISO8601",
  "updated_at": "ISO8601",
  "lectures": [
    {"sub_id": "xxx", "sub_title": "xxx", "status": "pending|done|failed", "attempts": 0, "error": null}
  ]
}
```

## After Completion

- Run `/note` for each transcribed lecture to generate study notes.
- Run `/wiki` to rebuild and serve the course site.
