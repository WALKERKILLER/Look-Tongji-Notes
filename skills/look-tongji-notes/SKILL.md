---
name: look-tongji-notes
description: "CLI workflow for Tongji Look (look.tongji.edu.cn): store IAM credentials locally, list recent courses, transcribe a lecture video to SRT/TXT, and generate a Markdown study note from the transcript. Use when the user says `look-tongji:setup`, `look-tongji:list`, `look-tongji:note`, or asks to transcribe Tongji lecture recordings."
---

# Look Tongji Notes

## Overview

Use the bundled CLI to:
1) configure Tongji IAM credentials (saved in this skill folder only),
2) list recent courses after login,
3) transcribe a chosen lecture to `SRT` + `TXT`,
4) write a Markdown study note (by the current agent) using the transcript.

This skill is intentionally CLI-first (no frontend).

## Quick start (workflow)

When you see these trigger phrases, follow this mapping:

- `look-tongji:setup` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" setup`
- `look-tongji:list` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" list`
- `look-tongji:note` -> run `python "<SKILL_DIR>/scripts/look_tongji.py" note ...` then write notes

Where:
- `<SKILL_DIR>` is the directory that contains this `SKILL.md`.

## Output + storage conventions

- **Credentials**: saved to `<SKILL_DIR>/.env` (and ignored by `<SKILL_DIR>/.gitignore`).
- **Auth cache**: saved to `<SKILL_DIR>/state/` (JWT token cache and last selection).
- **Artifacts (subtitles + transcript + notes)**: saved to the agent working directory in `./tongji-output/` (relative to where the command is executed).

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

Goal: transcribe one lecture and write notes.

Preferred inputs (ask user for one of these):
- **Lecture page URL** from `look.tongji.edu.cn` (best effort parsing for `course_id` + `sub_id`)
- `course_id` + `sub_id` (most reliable)

Run with a lecture URL:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --lecture-url "<LECTURE_URL>"
```

Run with IDs:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --course-id "<COURSE_ID>" --sub-id "<SUB_ID>"
```

If only `course_id` is provided, the CLI can list the latest lectures and let you choose:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --course-id "<COURSE_ID>"
```

### Artifacts produced by the CLI

The CLI writes to `./tongji-output/` (relative to the current working directory):
- `<course_id>_<sub_id>.srt`
- `<course_id>_<sub_id>.txt`
- `<course_id>_<sub_id>.json` (metadata)

### Write the Markdown note (by the current agent)

After the CLI finishes, read the generated transcript `TXT` and write:
- `<course_id>_<sub_id>_notes.md` in the same `tongji-output/` folder.

Use the following note prompt and output **only Markdown** (notes content should be in Simplified Chinese):

```text
You are a professional course TA. Based on the provided ASR transcript, write detailed study notes in Markdown (notes content in Simplified Chinese).
Requirements:
1) Output notes directly. No polite preface. No "here is the summary" opener.
2) Make the text fluent and logically structured. Fix obvious ASR errors and repetitions, but do not fabricate content not present in the transcript.
3) Markdown formatting: only use headings starting from ### (allow ###/####/#####). Do not use # or ##. Use bold/lists/tables when appropriate; avoid overly fragmented bullet-only output.
4) If the lecture mentions assignments/exams/attendance/grouping, put a short "### Course Reminders" section at the very top.
5) Use LaTeX for variables and formulas: inline $...$, block $$...$$. Do not put non-ASCII characters inside LaTeX.
6) Be faithful to the transcript and include enough details so that a student can learn from the notes (not just an outline).
Now write the notes from the transcript:
```
