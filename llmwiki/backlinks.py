"""Backlink injection: every wiki page that's linked-to gets a managed
``## Referenced by`` section listing its referrers (#328).

Today a source page links out to ``[[Pratiyush]]`` but the
``entities/Pratiyush.md`` page doesn't know about it — 95% of pages
end up as graph orphans (575 / 596 sources with zero inbound links).

This module rebuilds the reverse-reference index
(:func:`llmwiki.references.build_index`) and injects a managed
section into each target page bounded by HTML-comment sentinels so
rerun is idempotent:

    <!-- BACKLINKS:START -->
    ## Referenced by

    - [[session-slug-1]] — Session: title 1 (2026-04-19)
    - [[session-slug-2]] — Session: title 2 (2026-04-18)
    - …
    <!-- BACKLINKS:END -->

Characteristics:

* Stdlib-only.
* Safe on every page — we only write inside the sentinels; everything
  else is preserved verbatim.
* Skips pages that are already inside a ``wiki/archive/`` subtree.
* Caps each list at 50 entries so model entity pages don't balloon
  (the full list stays reachable via the graph + ``llmwiki references
  <slug>``).
* Sorts by date descending when the referrer has a ``date:`` field,
  otherwise alphabetically by title.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

from llmwiki import REPO_ROOT


_START = "<!-- BACKLINKS:START -->"
_END = "<!-- BACKLINKS:END -->"
_BACKLINK_BLOCK_RE = re.compile(
    re.escape(_START) + r".*?" + re.escape(_END) + r"\s*",
    re.DOTALL,
)
DEFAULT_MAX_ENTRIES = 50


@dataclass
class BacklinkEntry:
    """One row in a ``## Referenced by`` list."""

    slug: str
    title: str
    date: str  # may be empty

    def sort_key(self) -> tuple[str, str]:
        # Newest-first when date is ISO-8601; alphabetical by title otherwise.
        return (self.date or "", self.title.lower())


def _parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
    if not m:
        return {}, text
    fm: dict[str, str] = {}
    for line in m.group(1).splitlines():
        mm = re.match(r"^([a-zA-Z_][\w-]*):\s*(.*)$", line)
        if mm:
            fm[mm.group(1)] = mm.group(2).strip().strip("'\"")
    return fm, m.group(2)


def _collect_pages(wiki_dir: Path) -> dict[str, dict[str, Any]]:
    """Gather every wiki page into ``{slug: {path, meta, body}}``.

    Skips ``wiki/archive/`` (deprecated) and ``_context.md`` stubs —
    neither wants a backlinks block.
    """
    out: dict[str, dict[str, Any]] = {}
    if not wiki_dir.is_dir():
        return out
    for p in sorted(wiki_dir.rglob("*.md")):
        if "archive" in p.parts:
            continue
        if p.name == "_context.md":
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        meta, body = _parse_frontmatter(text)
        out[p.stem] = {"path": p, "meta": meta, "body": body, "text": text}
    return out


# Match `[[wikilink]]` or `[[wikilink|display]]` targets.
_WIKILINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]")


def build_reverse_index(pages: dict[str, dict[str, Any]]) -> dict[str, list[BacklinkEntry]]:
    """Return ``{target_slug: [BacklinkEntry(referrer)]}``.

    An entry is produced for every ``[[Target]]`` occurrence in any
    page's body (even if the Target doesn't exist — the graph's
    broken-link checker handles that separately).  Self-references are
    skipped (a page never appears in its own backlinks list).
    """
    rev: dict[str, list[BacklinkEntry]] = {}
    for slug, page in pages.items():
        body = page["body"]
        for target in set(_WIKILINK_RE.findall(body)):
            t = target.split("#")[0].strip()
            if not t or t == slug:
                continue
            rev.setdefault(t, []).append(
                BacklinkEntry(
                    slug=slug,
                    title=page["meta"].get("title", slug),
                    date=page["meta"].get("date", ""),
                )
            )
    return rev


def _render_block(entries: list[BacklinkEntry], *, max_entries: int) -> str:
    """Render the sentinel-bounded ``## Referenced by`` block."""
    ordered = sorted(entries, key=lambda e: e.sort_key(), reverse=True)
    truncated = len(ordered) > max_entries
    ordered = ordered[:max_entries]
    lines = [_START, "", "## Referenced by", ""]
    for e in ordered:
        suffix = f" — {e.title}" if e.title and e.title != e.slug else ""
        if e.date:
            suffix = f"{suffix} ({e.date})" if suffix else f" ({e.date})"
        lines.append(f"- [[{e.slug}]]{suffix}")
    if truncated:
        lines.append(f"")
        lines.append(
            f"*…and {len(entries) - max_entries} more referrer(s) — "
            f"run `llmwiki references <slug>` for the full list.*"
        )
    lines.append("")
    lines.append(_END)
    return "\n".join(lines) + "\n"


def inject_block(text: str, block: str) -> str:
    """Replace or append the backlinks block in ``text``.

    Finds the existing sentinel-bounded section and swaps it; appends
    to the end of the file with a leading blank line when the sentinels
    aren't present.  Idempotent.
    """
    stripped = text.rstrip()
    if _START in text and _END in text:
        new_text = _BACKLINK_BLOCK_RE.sub(block, text, count=1)
        # Normalise trailing newlines.
        if not new_text.endswith("\n"):
            new_text += "\n"
        return new_text
    return stripped + "\n\n" + block


def remove_block(text: str) -> str:
    """Strip any existing backlinks block (used by ``--prune``)."""
    if _START not in text:
        return text
    return _BACKLINK_BLOCK_RE.sub("", text).rstrip() + "\n"


def inject_all(
    wiki_dir: Optional[Path] = None,
    *,
    max_entries: int = DEFAULT_MAX_ENTRIES,
    dry_run: bool = False,
) -> dict[str, int]:
    """Walk ``wiki_dir`` and inject backlinks into every target page.

    Returns ``{slug: num_backlinks}`` for every page that got an
    (added, updated, or unchanged) block.
    """
    root = wiki_dir or (REPO_ROOT / "wiki")
    pages = _collect_pages(root)
    rev = build_reverse_index(pages)
    results: dict[str, int] = {}
    for target_slug, entries in rev.items():
        target = pages.get(target_slug)
        if not target:
            # Broken wikilink — skip.
            continue
        block = _render_block(entries, max_entries=max_entries)
        new_text = inject_block(target["text"], block)
        if new_text != target["text"] and not dry_run:
            target["path"].write_text(new_text, encoding="utf-8")
        results[target_slug] = len(entries)
    return results


def prune_all(
    wiki_dir: Optional[Path] = None, *, dry_run: bool = False
) -> int:
    """Strip backlink blocks from every page. Returns count touched."""
    root = wiki_dir or (REPO_ROOT / "wiki")
    count = 0
    for p in root.rglob("*.md"):
        if "archive" in p.parts:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        if _START not in text:
            continue
        new_text = remove_block(text)
        if new_text != text:
            count += 1
            if not dry_run:
                p.write_text(new_text, encoding="utf-8")
    return count
