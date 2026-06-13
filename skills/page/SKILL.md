---
name: page
description: "Deploy the built course wiki site/ to GitHub Pages via gh CLI. Pre-checks gh auth status and site/ existence."
license: MIT
metadata:
  author: WALKERKILLER
  version: "1.1"
---

# Page (GitHub Pages 部署)

将已构建的课程 wiki 静态站点部署到 GitHub Pages。

## When to Use

- User says `/page` or "deploy to pages" or "publish wiki".
- After running `/wiki build` and the `site/` directory is ready.

## Workflow

### 1. 前置检查 A: gh CLI 已安装

```bash
gh --version
```

如未安装，输出安装指引，引导用户访问 https://cli.github.com/ 安装。

### 2. 前置检查 B: gh 已认证

```bash
gh auth status
```

如未认证，引导用户执行 `gh auth login` 完成 GitHub 认证。

### 3. 前置检查 C: site/ 已构建

检查 workspace 的 `site/index.html` 是否存在：

```bash
ls <WORKSPACE_ROOT>/site/index.html
```

如 `site/` 不存在或为空，引导先运行 `/wiki build` 构建站点。

### 4. 确定部署目标 repo

优先使用环境变量 `GH_PAGES_REPO`：

```bash
echo $GH_PAGES_REPO
```

如果未设置，从当前 git remote 推断：

```bash
git remote get-url origin
```

用户可在 `.env` 中设置 `GH_PAGES_REPO=owner/repo` 来指定目标仓库。

### 5. 部署到 gh-pages 分支

```bash
gh pages deploy <WORKSPACE_ROOT>/site/ --repo <TARGET_REPO> --branch gh-pages
```

要求 gh CLI 版本 >= 2.29.0。

### 6. 输出结果

部署完成后，GitHub Pages URL 格式为 `https://<owner>.github.io/<repo>/`。

## Requirements

- gh CLI >= 2.29.0（安装: https://cli.github.com/）
- 已完成 `gh auth login`
- workspace 的 `site/` 已通过 `/wiki build` 构建
- 目标 GitHub repo 已启用 GitHub Pages

## Where `<SKILL_DIR>` Points

`<SKILL_DIR>` is the directory containing this `SKILL.md`. The `/page` command uses the `gh` CLI directly (no shared Python scripts needed). For other skills, shared scripts (`look_tongji.py`, `timeline_tools.py`, `tongji_backend/`) and references live two levels up in the repository root (`<SKILL_DIR>/../../scripts/` and `<SKILL_DIR>/../../references/`).
