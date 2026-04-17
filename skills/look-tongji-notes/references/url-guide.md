# Tongji Look URL guide

The `note` command needs two IDs:
- `course_id`
- `sub_id` (lecture id)

## How to get a lecture URL

1) Open `https://look.tongji.edu.cn` in a browser and log in.
2) Go to the target course, then open a specific lecture that has playback.
3) Copy the lecture page URL from the browser address bar.

## What formats the CLI can parse

The CLI tries best-effort parsing from:

- Query string:
  - `...?course_id=...&sub_id=...`
- Fragment query:
  - `...#/play?...course_id=...&sub_id=...`
- Fragment path (sub_id only):
  - `...#/play/123456` -> `sub_id=123456`

If parsing fails, use explicit IDs:

- `python "<SKILL_DIR>/scripts/look_tongji.py" note --course-id "<COURSE_ID>" --sub-id "<SUB_ID>"`

## If you only know course_id

You can provide only `course_id` and select the lecture interactively:

- `python "<SKILL_DIR>/scripts/look_tongji.py" note --course-id "<COURSE_ID>"`
