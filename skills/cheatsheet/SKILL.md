---
name: cheatsheet
description: "Generate a high-density A4 cheat sheet for open-book exams. Two output paths: LaTeX (XeLaTeX) or self-contained HTML with CSS print layout. Both paths produce visually consistent results."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# Cheatsheet

Generate exam cheat sheets from course lecture notes.

## When to Use

- User says `/cheatsheet` or asks for an exam cheat sheet.
- After lecture notes have been written for relevant sessions.

## Workflow

1. Check environment:

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" cheatsheet --format html
```

2. The agent reads course notes and produces content organized into sections.
3. Two output paths:

### Path A — LaTeX (XeLaTeX available)
Uses `<SKILL_DIR>/../../.mock-wiki/CheatingSheetTemplate/CheatingSheet.tex`.
- 4 columns, 5pt body, A4 paper
- Compile: `xelatex -interaction=nonstopmode cheatsheet.tex`

### Path B — HTML (no XeLaTeX)
Self-contained HTML with CSS print layout.
- Same 4-column, 5pt typography
- Print to A4 PDF from browser

## Prompt Template

Read `<SKILL_DIR>/../../.mock-wiki/CheatingSheetTemplate/README.md` for the generation prompt and typographic specification.

## Where \`<SKILL_DIR>\` Points

\`<SKILL_DIR>\` is the directory containing this \`SKILL.md\`. Shared scripts (\`look_tongji.py\`, \`timeline_tools.py\`, \`tongji_backend/\`) and references live two levels up in the repository root (\`<SKILL_DIR>/../../scripts/\` and \`<SKILL_DIR>/../../references/\`).
