---
name: page
description: "Guide the user through deploying the course knowledge base to GitHub Pages using the gh CLI. Pure agent workflow — no CLI subcommand needed."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.0"
---

# GitHub Pages

Deploy the course knowledge base to GitHub Pages.

## When to Use

- User says `/page` or "deploy to GitHub Pages".
- After the course wiki has been built and the user wants it publicly accessible.

## Workflow (Pure Agent, No CLI Subcommand)

1. **Ensure the wiki is built:**
```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" build
```

2. **Repository setup (one-time):**
   - Create a GitHub repo (public or private) via `gh repo create`.
   - Initialize git in the workspace and push.

3. **GitHub Pages configuration:**
   - Enable Pages in repo Settings > Pages, Source = "GitHub Actions".
   - The `.github/workflows/pages.yml` handles deployment.

4. **Verify deployment:**
   - Check Actions tab for successful workflow run.
   - Visit `https://<user>.github.io/<repo>/` to verify.

5. **Custom domain (optional):**
   - Configure in Settings > Pages, add CNAME file if needed.

## Security

- Never commit `.env`, `state/`, or JWT cache to public repos.
- Add these to `.gitignore` before pushing.
