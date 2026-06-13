<p align="center">
  <strong>English</strong> | <a href="README_ZH.md"><strong>中文</strong></a>
</p>

<p align="center">
  <a href="#"><img src="images/logo.svg"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
  <a href="SKILL.md"><img src="https://img.shields.io/badge/Version-1.1.1-7C3AED.svg?style=for-the-badge" alt="Version 1.1.1"></a>
</p>

This is an agent skill suite (9 atomic `/command` skills) + CLI for Tongji Look (`look.tongji.edu.cn`):
- login via Tongji IAM SSO (Playwright),
- list courses (recent list or full search),
- transcribe a lecture to `SRT` + `TXT`,
- generate a lecture timeline outline (`*_timeline.txt`) from `SRT` (agent-generated, Simplified Chinese),
- download lecture slide snapshots (filename includes snapshot time),
- then let the current agent write a Markdown study note from transcript + slide images.

## Commands

| Command | Description |
|---------|-------------|
| `/setup` | Configure credentials, check dependencies (Python, Node.js, ffmpeg, vision-support, TeX), set workspace |
| `/list` | List courses, search by keyword, interactive selection |
| `/trans` | Transcribe one lecture to SRT + TXT; optionally download slides in parallel |
| `/note` | Generate study notes + timeline outline from transcript + slides |
| `/add` | Import supplementary materials (PDF, PPTX, DOCX) into a lecture session |
| `/wiki` | Build and locally serve the static course knowledge base |
| `/page` | Deploy the built course wiki to GitHub Pages via gh CLI |
| `/cheatsheet` | Generate A4 cheat sheet (LaTeX or HTML) from course notes |
| `/ralphtrans` | Batch transcribe all lectures in a course with checkpoint/resume |

## Install

### Recommended: npx skills

If your agent supports the [skills](https://github.com/topics/skills) protocol:

```bash
npx skills install https://github.com/walkerkiller/look-tongji-notes
```

### Claude Code Marketplace

In Claude Code:

```text
/plugin marketplace add https://github.com/walkerkiller/look-tongji-notes
/plugin install look-tongji-notes
```

### Other Platforms

| Platform | How |
|----------|-----|
| Claude Code | Marketplace (above) or point plugin root to this repo |
| Codex CLI | `.codex-plugin/plugin.json` → `./skills/` |
| Cursor | `.cursor-plugin/plugin.json` → `./skills/` |
| Gemini CLI / OpenClaw / OpenCode / Hermes Agent | `plugin.json` → `./skills/` |

## Usage (CLI)

`<SKILL_DIR>` is the folder that contains `SKILL.md`.

Setup credentials (recommended):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" setup
```

List recent courses:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list
```

Search courses by name (recommended for accuracy, calls `get_all_courses` internally):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list --all --query "<COURSE_NAME_KEYWORD>"
```

Transcript only (`transcribe`, aliases `transcript` / `trans`):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" transcribe --lecture-url "<LECTURE_URL>"
```

Combined mode (`note`, runs transcript + slide in parallel by default):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note --lecture-url "<LECTURE_URL>"
```

Note style (affects how the generated note is formatted):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" note --lecture-url "<LECTURE_URL>" --note-style dialogue
```
Supports `standard` (lecture notes, default) and `dialogue` (Q&A format).

> [!TIP]
> The CLI detects lectures shorter than 1 hour and prints a non-blocking warning: `[Warning] 课时不足1小时` — suggesting a retry, as very short lectures may indicate an incomplete recording or playback error.

Download slide snapshots for a lecture:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" slide --lecture-url "<LECTURE_URL>"
```

If throttling is suspected, reduce concurrency:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" slide --course-id "<COURSE_ID>" --sub-id "<SUB_ID>" --concurrency 2 --retries 5
```
In the `/note` workflow, the agent generates a timeline outline after the `SRT` subtitle file is produced:
- File: `./tongji-output/<course_id>_<sub_id>_timeline.txt`
- One line per segment (Simplified Chinese), format: `Start-Over：Stage Main Content`
  - Example: `00:00-05:30：Course Orientation and Assessment Description`
- Skip only if the user explicitly says: `no outline` / `no timeline`.

Artifacts are written to the configured course-wiki workspace by default.

## Agent Note

When a user says `/setup` / `/list` / `/trans` / `/note` / `/wiki` / `/add` / `/page` / `/cheatsheet` / `/ralphtrans`, follow the corresponding `skills/<name>/SKILL.md` and run the matching CLI commands in `scripts/look_tongji.py`.
For `/note`, default to running transcript + slide download in parallel; only skip slide download when the user explicitly asks not to download slides/PPT.
When writing notes, use both transcript output and slide images by default.
If the user provides a course name, prefer `list --all --query ...` to avoid missing courses that are not in the recent list.

After notes are generated or updated, rebuild and preview the site with:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" index
python "<SKILL_DIR>/../../scripts/look_tongji.py" build
python "<SKILL_DIR>/../../scripts/look_tongji.py" serve --port 8765
```

The generated workspace can also become the user's own GitHub Pages repository. It includes:

- `llmwiki/`
- `index.py`
- `build.sh`
- `serve.sh`
- `.github/workflows/wiki-checks.yml`
- `.github/workflows/pages.yml`

## Notice / Compliance

> [!CAUTION]
> It is strongly recommended to set your Tongji account/password via the CLI (`setup`) before asking the agent to generate notes. Do not paste passwords into chat.

> [!NOTE]
> - Inspiration and parts of the code are from: [Fudan_iCourse_Subscriber](https://github.com/LeafCreeper/Fudan_iCourse_Subscriber)
> - This project is intended for **personal learning and review** only, and for technical communication. It does not save full video files by default.
> - Users must comply with the relevant platform rules and school policies. Any misuse (including re-distribution of copyrighted course videos/audios) is the user's responsibility.
> - When logging in outside the campus network (or without Tongji VPN), enhanced authentication may be triggered. Keep this in mind if you run the agent remotely.

## ToDo

- [x] Generate course knowledge base static site skeleton (courses, sessions, video, timeline, i18n controls).
- [ ] Support login flows with enhanced authentication.
- [x] Add course-level LLM wiki + notes database foundation.

- [ ] Build a standalone TUI/GUI tool for manual transcription/notes/Q&A.

## Best practices

- Generate subtitles + notes for the latest lecture:
  - `/note help me generate subtitles and notes for the latest lecture`
  
- Generate subtitles + notes for a named course:
  - `/note help me generate subtitles and notes for today's Advanced Mathematics lecture`
  
- List recent courses and let the user choose:
  - `/trans list recent courses and let me choose one to process`
  
- If the agent cannot find the course:

  Use `list --all --query "<keyword>"` to search the full course list, or open the platform and copy the lecture URL.

  ![example_link](images/example_link.png)

  then say: ``/trans here is the link，generate note``

## Contributing

Coming soon.
