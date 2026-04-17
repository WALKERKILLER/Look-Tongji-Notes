<p align="center">
  <strong>English</strong> | <a href="README_ZH.md"><strong>中文</strong></a>
</p>

<p align="center">
  <a href="LOGO"><img src="images/logo.svg"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
</p>

This is an agent skill + CLI for Tongji Look (`look.tongji.edu.cn`):
- login via Tongji IAM SSO (Playwright),
- list courses (recent list or full search),
- transcribe a lecture to `SRT` + `TXT`,
- then let the current agent write a Markdown study note from the transcript.

## Install

### Method 1

Copy the repo link to your agent and say: `help me install this skill`.

### Method 2

Copy the whole `look-tongji-notes/` folder into your skills directory:
- Codex: `~/.codex/skills/look-tongji-notes`
- Claude Code: `~/.codex/skills/look-tongji-notes`

### Method 3 (Codex)

Open Codex and run:

```text
$skill-installer install https://github.com/walkerkiller/look-tongji-notes
```

### Method 4 (Claude Code)

Open Claude Code and run:

```text
/plugin marketplace add https://github.com/walkerkiller/look-tongji-notes
/plugin install look-tongji-notes
```

## Usage (CLI)

`<SKILL_DIR>` is the folder that contains `SKILL.md`.

Setup credentials (recommended):

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" setup
```

List recent courses:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list
```

Search courses by name (recommended for accuracy, calls `get_all_courses` internally):

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" list --all --query "<COURSE_NAME_KEYWORD>"
```

Transcribe a lecture:

```bash
python "<SKILL_DIR>/scripts/look_tongji.py" note --lecture-url "<LECTURE_URL>"
```

Artifacts are written to `./tongji-output/` under your current working directory.

## Agent Note

When a user says `look-tongji:setup` / `look-tongji:list` / `look-tongji:note`, follow `SKILL.md` and run the matching CLI commands in `scripts/look_tongji.py`.
If the user provides a course name, prefer `list --all --query ...` to avoid missing courses that are not in the recent list.

## Notice / Compliance

> [!CAUTION]
> It is strongly recommended to set your Tongji account/password via the CLI (`setup`) before asking the agent to generate notes. Do not paste passwords into chat.

> [!NOTE]
> - Inspiration and parts of the code are from: https://github.com/LeafCreeper/Fudan_iCourse_Subscriber
> - This project is intended for **personal learning and review** only, and for technical communication. It does not save full video files by default.
> - Users must comply with the relevant platform rules and school policies. Any misuse (including re-distribution of copyrighted course videos/audios) is the user's responsibility.
> - When logging in outside the campus network (or without Tongji VPN), enhanced authentication may be triggered. Keep this in mind if you run the agent remotely.

## ToDo

- [ ] Build a course dashboard frontend (videos, timeline, subtitles, notes).
- [ ] Support login flows with enhanced authentication.
- [ ] Add course-level LLM wiki + notes database for review workflows.
- [ ] Build a standalone TUI/GUI tool for manual transcription/notes/Q&A.

## Best practices

- Generate subtitles + notes for the latest lecture:
  - `/look-tongji-notes help me generate subtitles and notes for the latest lecture`
  
- Generate subtitles + notes for a named course:
  - `/look-tongji-notes help me generate subtitles and notes for today's Advanced Mathematics lecture`
  
- List recent courses and let the user choose:
  - `/look-tongji-notes list recent courses and let me choose one to process`
  
- If the agent cannot find the course:

  Use `list --all --query "<keyword>"` to search the full course list, or open the platform and copy the lecture URL.

  ![example_link](images/example_link.png)

  then say: ``/look-tongji-notes here is the link，generate note``

## Contributing

Coming soon.
