---
name: list
description: "Discover and select courses from Tongji Look (look.tongji.edu.cn). Lists recent or all courses, filters by keyword, and saves the chosen course for use with /trans, /note, and other commands. Prerequisite for all lecture workflows."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.1"
---

# List

Discover and select courses from Tongji Look.

## When to Use

- User says `/list` or "show my courses" or "find a course".
- Before transcribing or taking notes, to discover available course IDs and names.
- User wants to search courses by keyword in title or teacher name.

## Workflow

1. List recent courses (default, fast):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list
```

2. Search with keyword filter:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list --query "<KEYWORD>"
```

3. Show all courses (slower but complete):

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" list --all
```

## Options

| Flag | Description |
|------|-------------|
| `--limit LIMIT` | Number of courses to show (0 = all) |
| `--all` | List all courses (slower but more complete) |
| `--query QUERY` | Filter courses by keyword in title/teacher (case-insensitive) |
| `--choose CHOOSE` | Auto-select course number (1-based) for non-interactive use |
| `--force-login` | Ignore cached JWT and login again |

## Interactive Selection

When run without `--choose`, the CLI prints a numbered list of courses and prompts the user to select one. The selected course's ID is then available for use with `/trans`, `/note`, and other commands.

## Where `<SKILL_DIR>` Points

`<SKILL_DIR>` is the directory containing this `SKILL.md`. Shared scripts (`look_tongji.py`, `timeline_tools.py`, `tongji_backend/`) and references live two levels up in the repository root (`<SKILL_DIR>/../../scripts/` and `<SKILL_DIR>/../../references/`).
