"""Multi-agent skill installer (v1.0 · #160).

Installs llmwiki's skill definitions into the agent directories used by
Claude Code, Codex CLI, and other agents that follow the kepano/
obsidian-skills convention.

Target directories (created if missing):
  - ``.claude/skills/``  (Claude Code, already exists in the repo)
  - ``.codex/skills/``   (Codex CLI)
  - ``.agents/skills/``  (universal standard proposed in issue #31005)

Strategy: copy-once from the canonical ``.claude/skills/`` into the
other two locations, preserving the SKILL.md files. A future sync
step can be wired into ``llmwiki init`` or the SessionStart hook.

Usage::

    from llmwiki.skill_installer import install_all, list_targets

    count = install_all(source=Path(".claude/skills"))
    print(f"Installed to {count} target directories")
"""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Optional

from llmwiki import REPO_ROOT

CANONICAL_SKILLS_DIR = REPO_ROOT / ".claude" / "skills"

# Target directories where skills should be mirrored. Each agent discovers
# skills in its own directory; we install to all so a single source of
# truth propagates everywhere.
AGENT_TARGETS: list[str] = [
    ".codex/skills",
    ".agents/skills",
]


def list_targets(repo_root: Optional[Path] = None) -> list[Path]:
    """Return the absolute paths of all agent skill target directories."""
    root = repo_root or REPO_ROOT
    return [root / t for t in AGENT_TARGETS]


def install_skill(
    skill_name: str,
    *,
    source: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> int:
    """Copy one skill into every agent target. Returns targets updated."""
    src = source or CANONICAL_SKILLS_DIR
    skill_src = src / skill_name
    if not skill_src.is_dir():
        return 0

    updated = 0
    for target_dir in list_targets(repo_root):
        target_dir.mkdir(parents=True, exist_ok=True)
        dest = target_dir / skill_name
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(skill_src, dest)
        updated += 1
    return updated


def install_all(
    *,
    source: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> int:
    """Copy every skill from ``source`` into every agent target.

    Returns the total count of skill-target combinations updated.
    """
    src = source or CANONICAL_SKILLS_DIR
    if not src.is_dir():
        return 0

    total = 0
    for skill_dir in sorted(src.iterdir()):
        if not skill_dir.is_dir():
            continue
        if not (skill_dir / "SKILL.md").is_file():
            continue
        total += install_skill(
            skill_dir.name, source=src, repo_root=repo_root,
        )
    return total


def list_installed(
    *,
    repo_root: Optional[Path] = None,
) -> dict[str, list[str]]:
    """Return a map of ``{target_dir: [skill_names]}`` for each target."""
    result: dict[str, list[str]] = {}
    for target in list_targets(repo_root):
        if not target.is_dir():
            result[str(target)] = []
            continue
        skills = sorted(
            p.name for p in target.iterdir()
            if p.is_dir() and (p / "SKILL.md").is_file()
        )
        result[str(target)] = skills
    return result
