---
name: note
description: "Generate study notes from a lecture transcript and slides. Runs transcript + slide download in parallel, then writes a Markdown note with timeline outline."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Note

Generate detailed study notes from lecture transcript and slides.

## When to Use

- User says `/note` or "write notes for this lecture".
- After transcribing a lecture, the user wants a structured Markdown study note.

## Workflow

1. Default combined command:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note --course-id "<ID>" --sub-id "<ID>"
```

2. With supplementary materials:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note \
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
- Validate with: `python "<SKILL_DIR>/../../scripts/timeline_tools.py" timeline-normalize`

### B. Write Study Notes (Markdown)

After the CLI finishes, ask the user for their preferred note style (unless they already stated one). Options:
- **standard** (default): Traditional lecture notes with `###` headings.
- **dialogue**: Conversational Q&A between 老师和学生.

Write notes into the session raw-data folder:
- standard style → `<course_id>_<sub_id>_notes.md`
- dialogue style → `<course_id>_<sub_id>_dialogue.md`

Also read supplementary material conversions when available:
- `materials/<name>/converted.md`

**CRITICAL: Notes must be PURE knowledge content.** No task-oriented meta descriptions.

**FORBIDDEN phrases and patterns:**
- "本节课将学习..."、"以下是笔记内容..."、"这里我使用了..."
- "本笔记基于..."、"根据ASR转录..."、"从幻灯片中可以看到..."
- Any meta-commentary about the note-taking process itself
- "接下来"、"首先"、"然后" as standalone paragraph openers (task-oriented sequencing)
- Sentences starting with "注意：" or "提示：" that are about the note-taking process rather than course content

**Self-check:** After writing notes, the agent MUST re-read the output and remove any sentence that describes HOW the notes were made rather than WHAT was learned.

Read transcript TXT (not JSON) and slide images directly.
Use LaTeX `$...$` / `$$...$$` for formulas.
If slides and transcript conflict, prefer slide text.

#### Important responsibility boundary
- The CLI only fetches/transcribes/downloads artifacts; it does **not** generate study-note Markdown content.
- The current AI agent must organize transcript + slides and write the final Markdown notes.

Use the appropriate note prompt based on the chosen style:

**If standard style** (default):
```text
You are a professional course TA. Based on the provided ASR transcript and lecture slide snapshots, write detailed study notes in Markdown (notes content in Simplified Chinese).
Requirements:
1) Output notes directly. No polite preface. No "here is the summary" opener.
2) Make the text fluent and logically structured. Fix obvious ASR errors and repetitions, but do not fabricate content not present in transcript/slides.
3) Markdown formatting: only use headings starting from ### (allow ###/####/#####). Do not use # or ##. Use bold/lists/tables when appropriate; avoid overly fragmented bullet-only output.
4) If the lecture mentions assignments/exams/attendance/grouping, put a short "### Course Reminders" section at the very top.
5) Use LaTeX for variables and formulas: inline $...$, block $$...$$. Do not put non-ASCII characters inside LaTeX.
6) Be faithful to transcript/slides and include enough details so that a student can learn from the notes (not just an outline).
7) If transcript and slides conflict, prefer slide text for terminology/spelling and briefly note uncertainty.
Now write the notes from transcript + slides:
```

**If dialogue style**:
```text
You are a professional course TA. Based on the provided ASR transcript and lecture slide snapshots, write study notes in **dialogue format** in Simplified Chinese.

CRITICAL OUTPUT RULES:
1) Output notes directly. No polite preface. No "here is the summary" opener.
2) Write in a natural Q&A conversation between "**老师**" (teacher) and "**学生**" (student):
   - "学生" raises questions that a real learner would have at each stage
   - "老师" answers using the lecture content and slides
   - Switch roles naturally as the lecture progresses through topics
3) Strict format for each exchange (one blank line between turns):
   **学生**：[学生提出的问题或疑惑]

   **老师**：[老师的解答和讲解，包含知识点、公式、示例]
4) Cover ALL major topics from the lecture in order. Do not skip sections.
5) Use LaTeX for variables and formulas: inline $...$, block $$...$$. Do not put non-ASCII characters inside LaTeX.
6) Be faithful to transcript/slides. Fix obvious ASR errors and repetitions, but do not fabricate content not present in transcript/slides.
7) If transcript and slides conflict, prefer slide text for terminology/spelling and briefly note uncertainty.
8) If the lecture mentions assignments/exams/attendance/grouping, include it naturally in the dialogue.
Now write the dialogue notes from transcript + slides:
```

### C. Rebuild Wiki
- After notes are written, run:
```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" index
python "<SKILL_DIR>/../../scripts/look_tongji.py" build
```

## Artifacts

- `<course_id>_<sub_id>_timeline.txt` — timeline outline
- `<course_id>_<sub_id>_notes.md` — study notes (standard style)
- `<course_id>_<sub_id>_dialogue.md` — study notes (dialogue style)
