"""Category page generator (v1.0 · #154).

Generates per-tag index pages (`wiki/categories/<tag>.md`) from the
`tags:` field in wiki page frontmatter.

Two output modes:

  - **Dataview** (``generate_dataview_categories``) — pages contain a
    live Dataview query that Obsidian renders dynamically.
  - **Static** (``generate_static_categories``) — pages contain a
    pre-rendered markdown list for use in the static HTML site.

Both modes work from the same page scan; the user picks which mode
fits their workflow (Obsidian users → Dataview; GitHub Pages users →
static).

Usage::

    from llmwiki.categories import scan_tags, generate_static_categories
    pages = load_pages()
    counts = scan_tags(pages)
    generate_static_categories(pages, out_dir, min_count=2)
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Optional

# Shared tag parser + NOISE_TAGS live in llmwiki.tag_utils so
# llmwiki/search_facets.py uses the same implementation.
from llmwiki.tag_utils import NOISE_TAGS, parse_tags_field as _parse_tags, scan_tags


# ─── Dataview output ──────────────────────────────────────────────────

def dataview_page(tag: str) -> str:
    """Render the Dataview query page body for a tag."""
    return f"""---
title: "Category: {tag}"
type: navigation
tag: {tag}
---

# Category: {tag}

Pages tagged with `{tag}`.

```dataview
TABLE type, confidence, last_updated
FROM "sources" OR "entities" OR "concepts" OR "syntheses"
WHERE contains(tags, "{tag}")
SORT last_updated DESC
```

## Connections

- [[index]] — full catalog
- [[dashboard]] — live overview
"""


# ─── Static output ────────────────────────────────────────────────────

def _page_slug(rel: str) -> str:
    return rel.rsplit("/", 1)[-1].removesuffix(".md")


def _page_title(pages: dict[str, dict[str, Any]], rel: str) -> str:
    return pages[rel]["meta"].get("title", _page_slug(rel))


def static_page(
    tag: str,
    page_rels: list[str],
    pages: dict[str, dict[str, Any]],
) -> str:
    """Render a static category page body for GitHub Pages."""
    lines = [
        "---",
        f'title: "Category: {tag}"',
        "type: navigation",
        f"tag: {tag}",
        "---",
        "",
        f"# Category: {tag}",
        "",
        f"{len(page_rels)} pages tagged with `{tag}`.",
        "",
    ]
    # Group by top-level folder
    by_folder: dict[str, list[str]] = {}
    for rel in page_rels:
        folder = rel.split("/", 1)[0] if "/" in rel else "root"
        by_folder.setdefault(folder, []).append(rel)

    for folder in sorted(by_folder):
        lines.append(f"## {folder}")
        lines.append("")
        for rel in by_folder[folder]:
            slug = _page_slug(rel)
            title = _page_title(pages, rel)
            lines.append(f"- [[{slug}|{title}]]")
        lines.append("")

    lines.extend([
        "## Connections",
        "",
        "- [[index]] — full catalog",
        "- [[dashboard]] — live overview",
        "",
    ])
    return "\n".join(lines)


# ─── Generators ──────────────────────────────────────────────────────

def generate_dataview_categories(
    tags: dict[str, list[str]],
    out_dir: Path,
    *,
    min_count: int = 2,
) -> list[Path]:
    """Write Dataview category pages for every tag with >= ``min_count`` pages.

    Returns the list of written paths.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for tag, page_rels in sorted(tags.items()):
        if len(page_rels) < min_count:
            continue
        slug = re.sub(r"[^a-z0-9_-]+", "-", tag)
        path = out_dir / f"{slug}.md"
        path.write_text(dataview_page(tag), encoding="utf-8")
        written.append(path)
    return written


def generate_static_categories(
    pages: dict[str, dict[str, Any]],
    out_dir: Path,
    *,
    min_count: int = 2,
) -> list[Path]:
    """Write static category pages (no Dataview) for every tag."""
    tags = scan_tags(pages)
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for tag, page_rels in sorted(tags.items()):
        if len(page_rels) < min_count:
            continue
        slug = re.sub(r"[^a-z0-9_-]+", "-", tag)
        path = out_dir / f"{slug}.md"
        path.write_text(static_page(tag, page_rels, pages), encoding="utf-8")
        written.append(path)
    return written
