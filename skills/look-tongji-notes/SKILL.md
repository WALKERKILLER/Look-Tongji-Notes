---
name: look-tongji-notes
description: "CLI workflow for Tongji Look (look.tongji.edu.cn): store IAM credentials locally, list recent courses, transcribe a lecture video to SRT/TXT, download lecture slide snapshots, and let the agent generate a timeline outline + Markdown study note from transcript + slides."
---

# Look Tongji Notes

## Overview

Use the bundled CLI to:
1) configure Tongji IAM credentials (saved in this skill folder only),
2) list recent courses after login,
3) transcribe a chosen lecture to `SRT` + `TXT`,
4) download lecture slide snapshots to local files,
5) write a Markdown study note (by the current agent) using transcript + slide images.

This skill is intentionally CLI-first (no frontend).

## Quick start (workflow)

When you see these trigger phrases, follow this mapping:

- `look-tongji:setup` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" setup`
- `look-tongji:list` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" list`
- `look-tongji:slide` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" slide ...`
- `look-tongji:transcribe` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" transcribe ...` (aliases: `transcript`, `trans`)
- `look-tongji:note` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" note ...` (default: transcript + slide in parallel)

Where:
- `<SKILL_DIR>` is the directory that contains this `SKILL.md`.

## Output + storage conventions

- **Credentials**: saved to `<SKILL_DIR>/.env` (and ignored by `<SKILL_DIR>/.gitignore`).
- **Auth cache**: saved to `<SKILL_DIR>/state/` (JWT token cache and last selection).
- **Artifacts (subtitles + transcript + slides + notes)**: saved to the agent working directory in `./tongji-output/` (relative to where the command is executed).

Never ask the user to paste passwords into chat. Prefer interactive terminal input (or environment variables) and keep `.env` out of version control.

## References

When you need more details, read:

- `references/url-guide.md` for how to obtain and parse lecture URLs
- `references/troubleshooting.md` for common setup/login/ASR issues
- `references/security.md` for credential/cache/output safety notes

## Command: `look-tongji:setup`

Goal: verify basic dependencies and store credentials in `<SKILL_DIR>/.env`.

Run:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" setup
```

Non-interactive options (avoid passing passwords via CLI when possible):

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" setup --username "<YOUR_ID>" --password "<YOUR_PASSWORD>" --overwrite
```

If dependencies are missing, install them from `<SKILL_DIR>/requirements.txt`.
Also install the Playwright Chromium browser once:

```bash
python -m playwright install chromium
```

`ffmpeg` must be available on `PATH` for transcription.

## Command: `look-tongji:list`

Goal: login and list recent courses with indices.

Run:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list
```

If you need to search a course by *name* (and it may not appear in "recent"),
use the full course list method `TongjiClient.get_all_courses()` for higher accuracy.

CLI shortcut:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list --all --query "<COURSE_NAME_KEYWORD>"
```

If you already know which course index to choose (for non-interactive runs):

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list --choose 1
```

This saves the selected course to `<SKILL_DIR>/state/last_course.json`.

## Command: `look-tongji:note`

Goal: default workflow for one lecture: transcribe + download slides + write notes.

Preferred inputs (ask user for one of these):
- **Lecture page URL** from `look.tongji.edu.cn` (best effort parsing for `course_id` + `sub_id`)
- `course_id` + `sub_id` (most reliable)

Transcript-only command with a lecture URL:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" transcribe --lecture-url "<LECTURE_URL>"
```

Transcript-only command with IDs:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" transcribe --course-id "<COURSE_ID>" --sub-id "<SUB_ID>"
```

If only `course_id` is provided, the CLI can list the latest lectures and let you choose:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" transcribe --course-id "<COURSE_ID>"
```

### Default agent behavior for `look-tongji:note`

Unless the user explicitly says "不要下载PPT/slide" (or equivalent):
1) Run `note` command for the same `course_id` + `sub_id` (internally does transcript + slide in parallel).
2) Unless the user explicitly says "不要大纲/不要时间线/no outline/no timeline" (or equivalent), generate a **timeline outline** from the `SRT` subtitles and write:
   - `<course_id>_<sub_id>_timeline.txt` in the same `tongji-output/` folder.
3) After both finish, write notes using both transcript and slide images.
4) If slide download fails but transcript succeeds, still produce notes and mention slide failure briefly.

Default combined command:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --course-id "<COURSE_ID>" --sub-id "<SUB_ID>"
```

If user explicitly requests transcript only:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --no-slide
# or:
python "<SKILL_DIR>/scripts/look_tongji.py" transcribe --course-id "<COURSE_ID>" --sub-id "<SUB_ID>"
```

### Artifacts produced by the CLI

The CLI writes to `./tongji-output/` (relative to the current working directory):
- `<course_id>_<sub_id>.srt`
- `<course_id>_<sub_id>.txt`
- `<course_id>_<sub_id>.json` (metadata)
- `slide_<course_id>_<sub_id>/` (slide images + `index.json`)

### Additional artifact written by the agent (timeline outline)

By default (unless the user asks not to generate an outline), after the CLI writes `SRT`,
generate a timeline outline file for quick video overview:
- `<course_id>_<sub_id>_timeline.txt`

Stabilize timeline input before generation:
- If the SRT is too long to fit in context, run `python "<SKILL_DIR>/scripts/timeline_tools.py" srt-sample --srt "<SRT_PATH>" --out "<SAMPLED_SRT_PATH>" --max-chars 15000` and only use the sampled output as the timeline context.

Format requirement (strict): each line must be:
- `起始时间-结束时间：课程阶段内容`

Use the following timeline prompt (output must be in Simplified Chinese; output **only** the timeline lines):

```text
You are a course TA. Your job is to turn the provided SRT subtitles into a concise video timeline outline for quick overview.

CRITICAL OUTPUT RULES:
1) Output ONLY the timeline lines. No title, no explanations, no Markdown, no numbering, no blank lines.
2) One line per segment, STRICTLY in this format (use the full-width Chinese colon '：'):
   MM:SS-MM:SS：<课程阶段内容（简体中文）>
3) Time format is MM:SS (minutes may exceed 59; seconds are always 2 digits; minutes are at least 2 digits and can be 3+ digits when needed). Examples:
   00:00-05:30：课程定位与考核说明
   05:30-12:00：电路理论学科体系介绍
   92:45-98:10：案例推导与易错点总结
4) The timeline MUST start at 00:00. Segments must be strictly increasing AND contiguous:
   - Previous end time == next start time
   - No overlaps, no gaps
5) Cover the whole lecture. Let the last segment end at (or very close to) the last subtitle end time.

CONTENT RULES:
6) Segment summaries must be in Simplified Chinese short phrases, using course terminology.
7) Fix obvious ASR typos/homophones when the meaning is clear, but DO NOT fabricate content not present in subtitles.
8) If a segment includes important admin items (assignment / exam / attendance / grouping / bonus points / deadlines), explicitly mention it in that segment.

GRANULARITY:
9) Prefer 10–20 segments for a typical 60–120 minute lecture; each segment usually 3–10 minutes.
10) Make segments shorter only when there is a clear topic shift or a key announcement.

Now generate the timeline outline from the SRT below:
```

SRT handling note (when context is limited):
- If the SRT is too long to fit in context, sample subtitle blocks uniformly across the whole file (do not only take the beginning), then generate the outline.

Post-processing / strict validation:
- After the agent produces timeline text, validate and normalize it using:
  - `python "<SKILL_DIR>/scripts/timeline_tools.py" timeline-normalize --input "<TIMELINE_TXT>" --srt "<SRT_PATH>" --tolerance 1`
- This enforces: starts at `00:00`, segments are contiguous (no overlaps/gaps), and the last segment end is close to the last subtitle end time.

Important transcript-reading rule:
- For note writing, **do not use** `<course_id>_<sub_id>.json` as the main transcript source (JSON ASR payloads are noisy).
- Always prioritize:
  1) `<course_id>_<sub_id>.txt` (preferred when timestamps are not required),
  2) `<course_id>_<sub_id>.srt` (use when timeline/timestamp context is needed).

Important slide-reading rule:
- For note writing, **do not use** `slide_<course_id>_<sub_id>/index.json` as the main slide timeline source (often noisy).
- Read slide image files directly and parse ordering/time from filenames.
- Filename format example: `0102_t01-32-45_s005565.jpg`
  - `0102`: slide sequence number
  - `t01-32-45`: timestamp `hh-mm-ss`
  - `s005565`: total seconds from lecture start (`1*3600 + 32*60 + 45 = 5565`)

### Write the Markdown note (by the current agent)

After the CLI finishes, read transcript `TXT` plus slide metadata/images and write:
- `<course_id>_<sub_id>_notes.md` in the same `tongji-output/` folder.

Important responsibility boundary:
- The CLI only fetches/transcribes/downloads artifacts; it does **not** generate study-note Markdown content.
- The current AI agent must organize transcript + slides and write the final Markdown notes.

Use the following note prompt and output **only Markdown** (notes content should be in Simplified Chinese):

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

## Command: `look-tongji:slide`

Goal: download detected slide snapshots for one lecture.

Run with a lecture URL:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" slide --lecture-url "<LECTURE_URL>"
```

Run with IDs:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>"
```

Download slides, export a PDF, and parse selected pages with MinerU OpenAPI
(Markdown output only):

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --to-pdf --mineru --mineru-pages "17-24"
```

`--mineru-pages` uses natural 1-based page numbers. The output Markdown is
written under `./tongji-output/slide-pdf/mineru_<course_id>_<sub_id>/`.

If throttling is suspected, reduce concurrency:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --concurrency 2 --retries 5
```
