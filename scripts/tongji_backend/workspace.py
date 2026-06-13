"""Workspace helpers for Look Tongji Notes.

This module keeps all path and storage decisions in one place:
- persistent user config outside the skill tree,
- course/session directory layout,
- supplementary material import and MarkItDown conversion,
- llm-wiki workspace scaffolding + source-session synchronization.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


_CONFIG_ENV = "LOOK_TONGJI_CONFIG_PATH"
_WORKSPACE_ENV = "LOOK_TONGJI_WORKSPACE_ROOT"
_OWNER_ENV = "LOOK_TONGJI_OWNER_NAME"
_SITE_NAME_ENV = "LOOK_TONGJI_SITE_NAME"


def _home_dir() -> Path:
    return Path.home()


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _config_dir() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("APPDATA", str(_home_dir() / "AppData" / "Roaming")))
        return base / "look-tongji"
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return Path(xdg) / "look-tongji"
    return _home_dir() / ".config" / "look-tongji"


def _config_path() -> Path:
    explicit = os.environ.get(_CONFIG_ENV, "").strip()
    if explicit:
        return Path(explicit).expanduser().resolve()
    return _config_dir() / "config.json"


def _read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _prompt(message: str, *, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    raw = input(f"{message}{suffix}: ").strip()
    return raw or default


def _prompt_yes_no(message: str, *, default: bool = True) -> bool:
    label = "Y/n" if default else "y/N"
    raw = input(f"{message} ({label}): ").strip().lower()
    if not raw:
        return default
    return raw in {"y", "yes", "1", "true", "t", "是", "确认", "继续"}


def sanitize_path_component(value: str, *, fallback: str = "未命名") -> str:
    """Keep Chinese characters, remove path separators and control chars."""
    text = unicodedata.normalize("NFKC", str(value or "").strip())
    text = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", text)
    text = re.sub(r"\s+", " ", text).strip(" ._")
    if not text:
        return fallback
    return text[:80].rstrip(" ._") or fallback


def _ascii_slug(value: str, *, fallback: str) -> str:
    normalized = unicodedata.normalize("NFKD", str(value or ""))
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", ascii_only.strip().lower())
    cleaned = re.sub(r"-{2,}", "-", cleaned).strip("-._")
    return cleaned or fallback


def _ensure_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def _normalize_agent_name(value: str) -> str:
    raw = re.sub(r"[\s_-]+", "", str(value or "").strip().lower())
    if not raw:
        return ""
    mapping = {
        "codex": "codex",
        "codexcli": "codex",
        "claude": "claude",
        "claudecode": "claude",
        "claudecodecli": "claude",
        "copilot": "copilot",
        "githubcopilot": "copilot",
        "copilotchat": "copilot",
        "copilotcli": "copilot",
        "cursor": "cursor",
        "gemini": "gemini-cli",
        "geminicli": "gemini-cli",
        "openclaw": "openclaw",
        "opencode": "opencode",
        "hermes": "hermes-agent",
        "hermesagent": "hermes-agent",
    }
    return mapping.get(raw, raw)


def _normalize_agent_sequence(value: Any) -> list[str]:
    if isinstance(value, list):
        raw_items = value
    elif isinstance(value, str):
        raw_items = [part.strip() for part in value.split(",")]
    else:
        raw_items = []
    seen: set[str] = set()
    result: list[str] = []
    for item in raw_items:
        agent = _normalize_agent_name(str(item or ""))
        if agent and agent not in seen:
            seen.add(agent)
            result.append(agent)
    return result


def _write_if_missing(path: Path, content: str) -> None:
    if path.exists():
        return
    _ensure_text(path, content)


def _llmwiki_source_dir() -> Path:
    path = _repo_root() / "llmwiki"
    if not path.is_dir():
        raise RuntimeError(f"Missing vendored llmwiki package at {path}")
    return path


def _workspace_llmwiki_dir(root: Path) -> Path:
    return root / "llmwiki"


def _copy_llmwiki_package(root: Path) -> None:
    shutil.copytree(_llmwiki_source_dir(), _workspace_llmwiki_dir(root), dirs_exist_ok=True)


def _copy_site_assets(root: Path) -> None:
    """Copy site assets (images, stacked-paper hero SVG) from the repo to the
    workspace so ``llmwiki build`` finds them when it runs inside the workspace.

    Without this, the built site is missing its brand logo, hero illustration,
    favicon, and image directory — the build step copies from ``images/`` and
    loads ``stacked-paper.svg`` by walking parent directories of ``build.py``,
    neither of which exist in a freshly-scaffolded workspace.
    """
    repo = _repo_root()
    # Copy images directory (logo.svg, web.svg, example_link.png, …)
    src_images = repo / "images"
    if src_images.exists():
        dst_images = root / "images"
        dst_images.mkdir(parents=True, exist_ok=True)
        for item in src_images.iterdir():
            if item.is_file():
                dst = dst_images / item.name
                if not dst.exists():
                    shutil.copy2(item, dst)
    # Copy stacked-paper.svg (hero illustration, at the outer project root)
    for parent in repo.parents:
        candidate = parent / "stacked-paper.svg"
        if candidate.exists():
            dst = root / "stacked-paper.svg"
            if not dst.exists():
                shutil.copy2(candidate, dst)
            break


def _run_llmwiki(root: Path, *args: str) -> None:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(root) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        [sys.executable, "-m", "llmwiki", *args],
        cwd=root,
        env=env,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(detail or f"llmwiki {' '.join(args)} failed")


def _pages_workflow() -> str:
    return """
name: Deploy wiki to GitHub Pages

on:
  push:
    branches: ["main", "master"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v6
        with:
          python-version: "3.12"

      - name: Install deps
        run: python -m pip install markdown

      - name: Index lesson manifests
        run: python ./index.py

      - name: Build static site
        run: |
          python ./index.py
          python -m llmwiki build --out ./site
          touch ./site/.nojekyll

      - name: Setup Pages
        uses: actions/configure-pages@v5

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v4
        with:
          path: ./site

  deploy:
    runs-on: ubuntu-latest
    needs: build
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v5
"""


def _wiki_checks_workflow() -> str:
    return """
name: Wiki checks

on:
  push:
    branches: ["main", "master"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  wiki-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v6
        with:
          python-version: "3.12"

      - name: Install deps
        run: python -m pip install markdown

      - name: Index lesson manifests
        run: python ./index.py

      - name: llmwiki lint
        run: |
          python -m llmwiki lint --fail-on-errors || {
            echo "::warning::llmwiki lint found errors. Review output above."
            exit 1
          }

      - name: llmwiki build
        run: |
          python ./index.py
          python -m llmwiki build --out /tmp/site-test
          test -f /tmp/site-test/index.html || {
            echo "::error::build did not produce index.html"
            exit 1
          }
          test -f /tmp/site-test/style.css
          test -f /tmp/site-test/script.js
"""


def _workspace_readme(config: "WorkspaceConfig") -> str:
    return f"""
# {config.site_name}

这个仓库保存课程原始资料、Obsidian 风格知识库，以及直接复用 `llm-wiki` 的静态站点输出。

- `raw/`：课程原始数据与 `llmwiki` 源会话输入。
- `wiki/`：可编辑的知识库页面与课程配置。
- `site/`：`python -m llmwiki build` 生成的静态站点。
- `llmwiki/`：从 skill 同步进来的前端与构建包。

常用命令：

```bash
python "<SKILL_DIR>/../../scripts/look_tongji.py" index --workspace-root "$(pwd)"
python "<SKILL_DIR>/../../scripts/look_tongji.py" build --workspace-root "$(pwd)"
python "<SKILL_DIR>/../../scripts/look_tongji.py" serve --workspace-root "$(pwd)" --port 8765
```

GitHub Pages 已通过 `.github/workflows/pages.yml` 预置。
如果这是你自己的 wiki 仓库，提交 `raw/`、`wiki/`、`llmwiki/`、`.github/workflows/` 后启用 Actions Pages 即可持续部署。
"""


def _workspace_json(config: "WorkspaceConfig") -> str:
    return json.dumps(
        {"owner_name": config.owner_name, "site_name": config.site_name},
        ensure_ascii=False,
        indent=2,
    )


def _build_sh() -> str:
    return """#!/usr/bin/env bash
set -euo pipefail
PYTHONPATH=. python -m llmwiki build --out ./site
"""


def _serve_sh() -> str:
    return """#!/usr/bin/env bash
set -euo pipefail
PYTHONPATH=. python -m llmwiki serve --dir ./site --port "${1:-8765}"
"""


def _index_py() -> str:
    return """#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path


def _ascii_slug(value: str, fallback: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip().lower())
    cleaned = re.sub(r"-{2,}", "-", cleaned).strip("-._")
    return cleaned or fallback


def _normalize_agent_name(value: str) -> str:
    raw = re.sub(r"[\\s_-]+", "", str(value or "").strip().lower())
    if not raw:
        return ""
    mapping = {
        "codex": "codex",
        "codexcli": "codex",
        "claude": "claude",
        "claudecode": "claude",
        "copilot": "copilot",
        "githubcopilot": "copilot",
        "cursor": "cursor",
        "gemini": "gemini-cli",
        "geminicli": "gemini-cli",
        "openclaw": "openclaw",
        "opencode": "opencode",
        "hermes": "hermes-agent",
        "hermesagent": "hermes-agent",
    }
    return mapping.get(raw, raw)


def _normalize_agent_sequence(data: dict) -> list[str]:
    raw_agents = data.get("agents")
    if isinstance(raw_agents, list):
        items = raw_agents
    elif data.get("agent"):
        items = [data.get("agent")]
    else:
        items = []
    result = []
    seen = set()
    for item in items:
        agent = _normalize_agent_name(str(item or ""))
        if agent and agent not in seen:
            seen.add(agent)
            result.append(agent)
    return result


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\\n", encoding="utf-8")


def main() -> int:
    root = Path.cwd()
    manifests = sorted(root.glob("raw/*/*/原始数据/manifest.json"))
    if not manifests:
        print("no manifests found; skipping llm-wiki source generation")
        return 0

    for manifest_path in manifests:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        raw_root = manifest_path.parent
        course_title = str(data.get("course_title") or manifest_path.parents[2].name)
        session_title = str(data.get("session_title") or manifest_path.parent.name)
        course_id = str(data.get("course_id") or "")
        sub_id = str(data.get("sub_id") or "")
        project_slug = _ascii_slug(course_id, fallback="course")
        session_slug = _ascii_slug(f"{sub_id or session_title}", fallback="session")
        source_path = root / "raw" / "sessions" / project_slug / f"{session_slug}.md"
        notes_name = f"{data.get('base_name', '')}_notes.md"
        notes_path = raw_root / notes_name
        notes_text = notes_path.read_text(encoding="utf-8", errors="replace").strip() if notes_path.exists() else ""
        subtitle_path = Path(str((data.get("artifacts") or {}).get("subtitle_srt") or ""))
        timeline_path = Path(str((data.get("artifacts") or {}).get("timeline_txt") or ""))
        agents = _normalize_agent_sequence(data)
        primary_agent = agents[0] if agents else _normalize_agent_name(str(data.get("agent") or "")) or "codex"
        rel_subtitle = subtitle_path.relative_to(root).as_posix() if subtitle_path.exists() else ""
        rel_timeline = timeline_path.relative_to(root).as_posix() if timeline_path.exists() else ""
        body = f\"\"\"---
title: "Lesson: {session_title}"
type: source
date: {str(data.get("generated_at") or "1970-01-01")[:10]}
source_file: raw/sessions/{project_slug}/{session_slug}.md
agent: {primary_agent}
agents: [{", ".join(agents)}]
sessionId: {data.get("base_name") or session_slug}
slug: {session_slug}
project: {project_slug}
started: {data.get("generated_at") or "1970-01-01T00:00:00+08:00"}
ended: {data.get("generated_at") or "1970-01-01T00:00:00+08:00"}
course_title: "{course_title}"
session_title: "{session_title}"
duration_seconds: {int(data.get("duration_seconds") or 0)}
subtitle_word_count: {int(data.get("subtitle_word_count") or 0)}
look_tongji_video_url: "{str(data.get("video_url") or "")}"
look_tongji_timeline: "{rel_timeline}"
look_tongji_subtitle: "{rel_subtitle}"
---

# {session_title}

## Summary

{notes_text or session_title}
\"\"\"
        _write_text(source_path, body)
        project_profile = root / "wiki" / "projects" / f"{project_slug}.md"
        if not project_profile.exists():
            _write_text(
                project_profile,
                f\"\"\"---
title: "{course_title}"
type: project
description: "课程：{course_title}"
---

# {course_title}
\"\"\",
            )
    print(f"indexed {len(manifests)} lesson manifest(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
"""


def _seed_project_profile(root: Path, project_slug: str, course_title: str) -> None:
    profile = root / "wiki" / "projects" / f"{project_slug}.md"
    if profile.exists():
        return
    _ensure_text(
        profile,
        f"""---
title: "{course_title}"
type: project
description: "课程：{course_title}"
topics: [tongji, course]
---

# {course_title}

这是 `{course_title}` 的课程主页。
""",
    )


def _seed_empty_source(root: Path) -> None:
    return


def ensure_workspace_scaffold(config: "WorkspaceConfig") -> None:
    """Create llm-wiki-compatible scaffolding in the note workspace."""
    root = config.workspace_root
    root.mkdir(parents=True, exist_ok=True)
    _write_if_missing(
        root / ".gitignore",
        """
.env
state/
__pycache__/
*.pyc
.DS_Store
""",
    )
    _write_if_missing(root / ".nojekyll", "")
    _write_if_missing(root / "README.md", _workspace_readme(config))
    _write_if_missing(root / "workspace.json", _workspace_json(config))
    _write_if_missing(
        root / ".obsidian" / "app.json",
        """
{
  "readableLineLength": true,
  "showLineNumber": false
}
""",
    )
    _copy_llmwiki_package(root)
    _copy_site_assets(root)
    _run_llmwiki(root, "init")
    _write_if_missing(root / ".github" / "workflows" / "pages.yml", _pages_workflow())
    _write_if_missing(root / ".github" / "workflows" / "wiki-checks.yml", _wiki_checks_workflow())
    _write_if_missing(root / "build.sh", _build_sh())
    _write_if_missing(root / "serve.sh", _serve_sh())
    _write_if_missing(root / "index.py", _index_py())


@dataclass(frozen=True)
class WorkspaceConfig:
    workspace_root: Path
    owner_name: str
    site_name: str
    config_path: Path = field(repr=False)


@dataclass(frozen=True)
class LectureWorkspace:
    workspace_root: Path
    course_id: str
    sub_id: str
    course_title: str
    course_slug: str
    session_title: str
    session_slug: str
    llmwiki_project_slug: str
    llmwiki_session_slug: str
    raw_root: Path
    raw_materials_dir: Path
    raw_slides_dir: Path
    wiki_root: Path
    site_root: Path
    manifest_path: Path
    source_dir: Path
    source_markdown_path: Path


@dataclass(frozen=True)
class MaterialInput:
    name: str
    path: Path


def load_workspace_config() -> WorkspaceConfig | None:
    raw = _read_json(_config_path())
    workspace_root = str(raw.get("workspace_root") or "").strip()
    if not workspace_root:
        return None
    owner_name = str(raw.get("owner_name") or os.environ.get(_OWNER_ENV, "") or "WALKERKILLER").strip()
    site_name = str(raw.get("site_name") or os.environ.get(_SITE_NAME_ENV, "") or f"{owner_name}的课程知识库").strip()
    return WorkspaceConfig(
        workspace_root=Path(workspace_root).expanduser().resolve(),
        owner_name=owner_name or "WALKERKILLER",
        site_name=site_name or "课程知识库",
        config_path=_config_path(),
    )


def save_workspace_config(config: WorkspaceConfig) -> None:
    _write_json(
        config.config_path,
        {
            "workspace_root": str(config.workspace_root),
            "owner_name": config.owner_name,
            "site_name": config.site_name,
        },
    )


def migrate_workspace_root(old_root: Path, new_root: Path) -> list[Path]:
    """Move generated trees from an old workspace to a new one."""
    moved: list[Path] = []
    if old_root == new_root:
        return moved
    new_root.mkdir(parents=True, exist_ok=True)
    for name in ("raw", "wiki", "site", "llmwiki", ".github", ".obsidian", "workspace.json", "README.md"):
        src = old_root / name
        dst = new_root / name
        if not src.exists() or dst.exists():
            continue
        try:
            shutil.move(str(src), str(dst))
            moved.append(dst)
        except Exception:
            if src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
            moved.append(dst)
    return moved


def ensure_workspace_config(
    *,
    workspace_root: str | None = None,
    owner_name: str | None = None,
    site_name: str | None = None,
    interactive: bool = True,
) -> WorkspaceConfig:
    """Load or create the persistent workspace config."""
    existing = load_workspace_config()

    env_root = os.environ.get(_WORKSPACE_ENV, "").strip()
    if workspace_root:
        env_root = workspace_root.strip()

    if existing is None and not env_root:
        if not interactive:
            raise RuntimeError("Missing workspace root. Set LOOK_TONGJI_WORKSPACE_ROOT or run setup once.")
        env_root = _prompt("课程知识库要保存到哪个本地路径", default=str(_home_dir() / "look-tongji-notes"))

    if existing is None:
        owner = (owner_name or os.environ.get(_OWNER_ENV, "") or "").strip()
        if not owner and interactive:
            owner = _prompt("仓库主人名怎么显示", default="WALKERKILLER")
        owner = owner or "WALKERKILLER"
        site = (site_name or os.environ.get(_SITE_NAME_ENV, "") or "").strip() or f"{owner}的课程知识库"
        config = WorkspaceConfig(
            workspace_root=Path(env_root).expanduser().resolve(),
            owner_name=owner,
            site_name=site,
            config_path=_config_path(),
        )
        save_workspace_config(config)
        ensure_workspace_scaffold(config)
        return config

    target_root = Path(env_root).expanduser().resolve() if env_root else existing.workspace_root
    target_owner = (owner_name or os.environ.get(_OWNER_ENV, "") or existing.owner_name).strip() or existing.owner_name
    target_site = (site_name or os.environ.get(_SITE_NAME_ENV, "") or existing.site_name).strip() or existing.site_name
    changed = (
        target_root != existing.workspace_root
        or target_owner != existing.owner_name
        or target_site != existing.site_name
    )

    if changed and interactive:
        if not _prompt_yes_no("检测到工作区配置变化，是否更新并迁移已有内容", default=True):
            ensure_workspace_scaffold(existing)
            return existing

    if changed:
        if target_root != existing.workspace_root:
            migrate_workspace_root(existing.workspace_root, target_root)
        config = WorkspaceConfig(
            workspace_root=target_root,
            owner_name=target_owner,
            site_name=target_site,
            config_path=existing.config_path,
        )
        save_workspace_config(config)
        ensure_workspace_scaffold(config)
        return config

    ensure_workspace_scaffold(existing)
    return existing


def _lecture_folder_name(lecture: dict[str, Any]) -> str:
    date = sanitize_path_component(str(lecture.get("date") or "").strip(), fallback="")
    title = sanitize_path_component(str(lecture.get("sub_title") or "").strip(), fallback="")
    sub_id = sanitize_path_component(str(lecture.get("sub_id") or "").strip(), fallback="节次")
    if date and title:
        return sanitize_path_component(f"{date} {title}", fallback=sub_id)
    if title:
        return title
    if date:
        return date
    return f"节次-{sub_id}"


def prepare_lecture_workspace(
    config: WorkspaceConfig,
    *,
    course_detail: dict[str, Any],
    lecture: dict[str, Any],
) -> LectureWorkspace:
    ensure_workspace_scaffold(config)
    course_title = sanitize_path_component(
        str(course_detail.get("title") or course_detail.get("course_title") or "课程").strip(),
        fallback="课程",
    )
    session_title = sanitize_path_component(
        str(lecture.get("sub_title") or lecture.get("title") or lecture.get("sub_id") or "节次").strip(),
        fallback="节次",
    )
    course_id = str(course_detail.get("course_id") or course_detail.get("id") or "").strip()
    sub_id = str(lecture.get("sub_id") or "").strip()
    project_slug = _ascii_slug(course_id, fallback=f"course-{abs(hash(course_title)) % 10_000_000}")
    session_slug = _lecture_folder_name(lecture)
    source_slug = _ascii_slug(
        f"{lecture.get('date') or ''}-{sub_id or session_slug}",
        fallback=f"{project_slug}-{sub_id or 'session'}",
    )

    raw_root = config.workspace_root / "raw" / course_title / session_slug / "原始数据"
    raw_materials_dir = raw_root / "materials"
    raw_slides_dir = raw_root / "slides"
    wiki_root = config.workspace_root / "wiki"
    site_root = config.workspace_root / "site"
    manifest_path = raw_root / "manifest.json"
    source_dir = config.workspace_root / "raw" / "sessions" / project_slug
    source_markdown_path = source_dir / f"{source_slug}.md"

    for path in (raw_root, raw_materials_dir, raw_slides_dir, wiki_root, site_root, source_dir):
        path.mkdir(parents=True, exist_ok=True)
    _seed_project_profile(config.workspace_root, project_slug, course_title)

    return LectureWorkspace(
        workspace_root=config.workspace_root,
        course_id=course_id,
        sub_id=sub_id,
        course_title=course_title,
        course_slug=course_title,
        session_title=session_title,
        session_slug=session_slug,
        llmwiki_project_slug=project_slug,
        llmwiki_session_slug=source_slug,
        raw_root=raw_root,
        raw_materials_dir=raw_materials_dir,
        raw_slides_dir=raw_slides_dir,
        wiki_root=wiki_root,
        site_root=site_root,
        manifest_path=manifest_path,
        source_dir=source_dir,
        source_markdown_path=source_markdown_path,
    )


def load_markitdown() -> Any | None:
    try:
        from markitdown import MarkItDown  # type: ignore
        return MarkItDown
    except Exception:
        repo_root = _repo_root().parents[1]
        local_src = repo_root / "markitdown" / "packages" / "markitdown" / "src"
        if local_src.exists():
            if str(local_src) not in sys.path:
                sys.path.insert(0, str(local_src))
            try:
                from markitdown import MarkItDown  # type: ignore
                return MarkItDown
            except Exception:
                return None
        return None


def convert_source_to_markdown(source_path: Path) -> str:
    """Convert an arbitrary file to markdown text when possible."""
    suffix = source_path.suffix.lower()
    if suffix in {".md", ".markdown", ".txt", ".rst", ".csv", ".json", ".xml", ".yaml", ".yml"}:
        try:
            return source_path.read_text(encoding="utf-8")
        except Exception:
            return source_path.read_text(encoding="utf-8", errors="replace")

    markitdown_cls = load_markitdown()
    if markitdown_cls is not None:
        try:
            md = markitdown_cls(enable_plugins=True)
            result = md.convert(source_path)
            text = getattr(result, "text_content", "") or ""
            if text.strip():
                return text
        except Exception:
            pass

    try:
        return source_path.read_text(encoding="utf-8")
    except Exception:
        return source_path.read_text(encoding="utf-8", errors="replace")


def import_materials(
    workspace: LectureWorkspace,
    materials: Iterable[MaterialInput],
) -> list[dict[str, Any]]:
    """Copy supplementary files into the lecture workspace and convert them."""
    imported: list[dict[str, Any]] = []
    for item in materials:
        source = item.path.expanduser().resolve()
        if not source.exists() or not source.is_file():
            continue

        dest_dir = workspace.raw_materials_dir / sanitize_path_component(item.name or source.stem, fallback=source.stem)
        dest_dir.mkdir(parents=True, exist_ok=True)

        copied_path = dest_dir / f"source{source.suffix.lower() or '.bin'}"
        shutil.copy2(source, copied_path)

        md_text = convert_source_to_markdown(source)
        md_path = dest_dir / "converted.md"
        md_path.write_text(md_text.strip() + "\n", encoding="utf-8")

        imported.append(
            {
                "name": item.name,
                "source_path": str(source),
                "copied_path": str(copied_path),
                "markdown_path": str(md_path),
            }
        )

    return imported


def _summary_from_text(text: str, *, limit: int = 180) -> str:
    cleaned = re.sub(r"\s+", " ", (text or "").strip())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 3].rstrip() + "..."


def _collect_material_sections(raw_materials_dir: Path) -> tuple[str, list[str]]:
    bullets: list[str] = []
    sections: list[str] = []
    if not raw_materials_dir.exists():
        return "", []
    for item in sorted(p for p in raw_materials_dir.iterdir() if p.is_dir()):
        name = item.name
        bullets.append(f"- {name}")
        converted = item / "converted.md"
        if converted.exists():
            sections.append(f"### {name}\n\n{converted.read_text(encoding='utf-8', errors='replace').strip()}")
    return "\n".join(bullets), sections


def _render_llmwiki_source(manifest_path: Path, manifest: dict[str, Any], *, site_name: str) -> tuple[str, str, str]:
    raw_root = manifest_path.parent
    artifacts = manifest.get("artifacts") or {}
    course_title = str(manifest.get("course_title") or raw_root.parents[2].name)
    session_title = str(manifest.get("session_title") or raw_root.parent.name)
    course_id = str(manifest.get("course_id") or "")
    sub_id = str(manifest.get("sub_id") or "")
    lecture_url = str(manifest.get("lecture_url") or "")
    video_url = str(manifest.get("video_url") or "")
    generated_at = str(manifest.get("generated_at") or "")
    agents = _normalize_agent_sequence(manifest.get("agents"))
    primary_agent = _normalize_agent_name(str(manifest.get("agent") or ""))
    if primary_agent and primary_agent not in agents:
        agents.insert(0, primary_agent)
    if not agents:
        agents = [primary_agent or "codex"]
    primary_agent = agents[0]
    date = ""
    session_folder = raw_root.parent.name
    date_match = re.match(r"^(\d{4}-\d{2}-\d{2})", session_folder)
    if date_match:
        date = date_match.group(1)
    elif generated_at:
        date = generated_at[:10]
    project_slug = _ascii_slug(course_id, fallback=f"course-{abs(hash(course_title)) % 10_000_000}")
    session_slug = _ascii_slug(
        f"{date or generated_at[:10]}-{sub_id or session_title}",
        fallback=f"{project_slug}-{sub_id or 'session'}",
    )

    notes_path = raw_root / f"{manifest.get('base_name', '')}_notes.md"
    if not notes_path.exists():
        notes_path = raw_root / "notes.md"
    transcript_path = Path(str(artifacts.get("transcript_txt") or raw_root / f"{manifest.get('base_name', '')}.txt"))
    timeline_path = Path(str(artifacts.get("timeline_txt") or raw_root / f"{manifest.get('base_name', '')}_timeline.txt"))
    srt_path = Path(str(artifacts.get("subtitle_srt") or raw_root / f"{manifest.get('base_name', '')}.srt"))
    slides_dir = Path(str(artifacts.get("slides_dir") or raw_root / "slides"))
    rel_manifest = manifest_path.relative_to(raw_root.parents[3])
    rel_timeline = timeline_path.relative_to(raw_root.parents[3]) if timeline_path.exists() else None
    rel_subtitle = srt_path.relative_to(raw_root.parents[3]) if srt_path.exists() else None

    notes_text = notes_path.read_text(encoding="utf-8", errors="replace").strip() if notes_path.exists() else ""
    transcript_text = transcript_path.read_text(encoding="utf-8", errors="replace").strip() if transcript_path.exists() else ""
    timeline_text = timeline_path.read_text(encoding="utf-8", errors="replace").strip() if timeline_path.exists() else ""
    materials_bullets, material_sections = _collect_material_sections(raw_root / "materials")
    slide_files = sorted(slides_dir.glob("*")) if slides_dir.exists() else []
    slide_preview = "\n".join(f"- {path.name}" for path in slide_files[:12])
    summary = _summary_from_text(notes_text or transcript_text or session_title or course_title, limit=180) or session_title

    body_parts = [
        f"# {session_title}",
        "",
        "## Summary",
        "",
        summary,
        "",
        "## Course Info",
        "",
        f"- 课程：{course_title}",
        f"- 节次：{session_title}",
    ]
    if course_id:
        body_parts.append(f"- `course_id`：{course_id}")
    if sub_id:
        body_parts.append(f"- `sub_id`：{sub_id}")
    if lecture_url:
        body_parts.append(f"- `lecture_url`：{lecture_url}")
    if video_url:
        body_parts.append(f"- `video_url`：{video_url}")

    if timeline_text:
        body_parts.extend(["", "## Timeline", "", timeline_text])
    if notes_text:
        body_parts.extend(["", "## Notes", "", notes_text])
    elif transcript_text:
        body_parts.extend(["", "## Transcript", "", transcript_text])
    if slide_preview:
        body_parts.extend(["", "## Slides", "", slide_preview])
    if materials_bullets:
        body_parts.extend(["", "## Supplementary Materials", "", materials_bullets])
    if material_sections:
        body_parts.append("")
        body_parts.extend(material_sections)
    if srt_path.exists():
        body_parts.extend(["", "## Subtitle File", "", f"- {srt_path.name}"])

    source_file = f"raw/sessions/{project_slug}/{session_slug}.md"
    frontmatter = [
        "---",
        f'title: "Session: {session_title} — {date or "undated"}"',
        "type: source",
        "tags: [tongji-look, course-session]",
        f"date: {date or '1970-01-01'}",
        f"source_file: {source_file}",
        f"sessionId: {manifest.get('base_name') or session_slug}",
        f"slug: {session_slug}",
        f"project: {project_slug}",
        f"started: {generated_at or f'{date or '1970-01-01'}T00:00:00+08:00'}",
        f"ended: {generated_at or f'{date or '1970-01-01'}T00:00:00+08:00'}",
        f"cwd: {raw_root}",
        "gitBranch: main",
        "permissionMode: default",
        'model: "Tongji Look"',
        "user_messages: 0",
        "tool_calls: 0",
        "tools_used: [TongjiLook]",
        'tool_counts: {"TongjiLook": 0}',
        'token_totals: {"input": 0, "cache_creation": 0, "cache_read": 0, "output": 0}',
        "turn_count: 0",
        f"agent: {primary_agent}",
        f"agents: [{', '.join(agents)}]",
        f"duration_seconds: {int(manifest.get('duration_seconds') or 0)}",
        "is_subagent: false",
        f'description: "{course_title} · {session_title}"',
        f'site_name: "{site_name}"',
        f'course_title: "{course_title}"',
        f'session_title: "{session_title}"',
        f"subtitle_word_count: {int(manifest.get('subtitle_word_count') or 0)}",
        f'look_tongji_manifest: "{rel_manifest.as_posix()}"',
        f'look_tongji_video_url: "{video_url}"',
        f'look_tongji_timeline: "{rel_timeline.as_posix() if rel_timeline else ""}"',
        f'look_tongji_subtitle: "{rel_subtitle.as_posix() if rel_subtitle else ""}"',
        "---",
        "",
    ]
    return project_slug, session_slug, "\n".join(frontmatter + body_parts).rstrip() + "\n"


def sync_manifest_to_llmwiki_source(config: WorkspaceConfig, manifest_path: Path) -> Path:
    ensure_workspace_scaffold(config)
    manifest = _read_json(manifest_path)
    if not manifest:
        raise RuntimeError(f"Invalid manifest: {manifest_path}")
    project_slug, session_slug, source_text = _render_llmwiki_source(
        manifest_path,
        manifest,
        site_name=config.site_name,
    )
    _seed_project_profile(
        config.workspace_root,
        project_slug,
        str(manifest.get("course_title") or manifest_path.parents[2].name),
    )
    out_path = config.workspace_root / "raw" / "sessions" / project_slug / f"{session_slug}.md"
    _ensure_text(out_path, source_text)
    return out_path


def sync_all_manifests_to_llmwiki(config: WorkspaceConfig) -> list[Path]:
    synced: list[Path] = []
    raw_root = config.workspace_root / "raw"
    if not raw_root.exists():
        return synced
    for manifest_path in sorted(raw_root.glob("*/**/原始数据/manifest.json")):
        try:
            synced.append(sync_manifest_to_llmwiki_source(config, manifest_path))
        except Exception:
            continue
    return synced


def index_workspace_wiki(config: WorkspaceConfig) -> list[Path]:
    ensure_workspace_scaffold(config)
    synced = sync_all_manifests_to_llmwiki(config)
    return synced


def build_workspace_wiki(config: WorkspaceConfig) -> Path:
    synced = index_workspace_wiki(config)
    site_dir = config.workspace_root / "site"
    if not synced:
        site_dir.mkdir(parents=True, exist_ok=True)
        (site_dir / "index.html").write_text(
            "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n<meta charset=\"utf-8\">\n"
            "<title>" + (config.site_name or "Course Wiki") + "</title>\n"
            "</head>\n<body>\n<h1>" + (config.site_name or "Course Knowledge Base") + "</h1>\n"
            "<p>No lectures indexed yet. Transcribe a lecture with /trans or /note to populate the wiki.</p>\n"
            "</body>\n</html>\n",
            encoding="utf-8",
        )
        return site_dir
    _run_llmwiki(config.workspace_root, "build", "--out", str(site_dir), "--seed-project-stubs")
    return site_dir


def serve_workspace_wiki(
    config: WorkspaceConfig,
    *,
    port: int = 8765,
    host: str = "127.0.0.1",
    open_browser: bool = False,
) -> int:
    ensure_workspace_scaffold(config)
    env = os.environ.copy()
    env["PYTHONPATH"] = str(config.workspace_root) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    return subprocess.call(
        [
            sys.executable,
            "-m",
            "llmwiki",
            "serve",
            "--dir",
            str(config.workspace_root / "site"),
            "--port",
            str(port),
            "--host",
            str(host),
            *([] if not open_browser else ["--open"]),
        ],
        cwd=config.workspace_root,
        env=env,
    )


def write_manifest(workspace: LectureWorkspace, manifest: dict[str, Any]) -> None:
    workspace.manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    config = load_workspace_config()
    if config is None:
        return
    sync_manifest_to_llmwiki_source(config, workspace.manifest_path)
