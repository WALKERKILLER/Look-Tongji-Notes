---
name: look-tongji-note
description: "Generate study notes from a lecture transcript and slides. Runs transcript + slide download in parallel, then writes a Markdown note with timeline outline."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Look Tongji Note

Generate detailed study notes from lecture transcript and slides.

## When to Use

- User says `/note` or "write notes for this lecture".
- After transcribing a lecture, the user wants a structured Markdown study note.

## Workflow

1. Default combined command:

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" note --course-id "<ID>" --sub-id "<ID>"
```

2. With supplementary materials:

```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" note \
  --course-id "<ID>" --sub-id "<ID>" \
  --material "slides-from-teacher=/path/to/file.pdf"
```

3. The CLI runs transcript + slide in parallel, then the **agent** writes notes.

## Agent Responsibilities

After the CLI finishes, the agent must:

### A. Generate Timeline Outline
- Use SRT subtitles to produce a concise timeline in Simplified Chinese.
- Format: `MM:SS-MM:SS：课程阶段内容`
- 10-20 segments for a typical 60-120 min lecture.
- Validate with: `python "<SKILL_DIR>/../../../scripts/timeline_tools.py" timeline-normalize`

### B. Write Study Notes (Markdown)
- Ask the user for their preferred note style (unless they already stated one). Options:
  - **standard** (default): Traditional lecture notes with `###` headings.
  - **dialogue**: Conversational Q&A between 老师 and 学生.
- **CRITICAL: Notes must be PURE knowledge content.** No task-oriented meta descriptions.
- **FORBIDDEN phrases and patterns:**
  - "本节课将学习..."、"以下是笔记内容..."、"这里我使用了..."
  - "本笔记基于..."、"根据ASR转录..."、"从幻灯片中可以看到..."
  - Any meta-commentary about the note-taking process itself
- Read transcript TXT (not JSON) and slide images directly.
- For standard style: Output ONLY structured Markdown starting from `###` level.
  For dialogue style: Use the Q&A format described in the dialogue prompt.
- Use LaTeX `$...$` / `$$...$$` for formulas.
- If slides and transcript conflict, prefer slide text.

### C. Rebuild Wiki
- After notes are written, run:
```bash
python "<SKILL_DIR>/../../../scripts/look_tongji.py" index
python "<SKILL_DIR>/../../../scripts/look_tongji.py" build
```

## Artifacts

- `<course_id>_<sub_id>_timeline.txt` — timeline outline
- `<course_id>_<sub_id>_notes.md` — study notes (standard style)
- `<course_id>_<sub_id>_dialogue.md` — study notes (dialogue style)
