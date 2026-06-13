"""Reverse-reference index for wiki pages (G-17 · #303).

A wiki page carries an implicit contract with the pages it links to:
if ``sources/a.md`` links to ``[[RAG]]`` and makes dated claims
("RAG latency is <100ms as of 2026-03"), the referring page may
become **stale** when the target page is updated later (the 100ms
number might no longer hold).

This module:

1. Builds a reverse-reference index — for every target, who links to it.
2. Detects *stale references* — referring pages with a ``last_updated``
   older than the target plus a dated claim about that target.
3. Backs the ``llmwiki references <entity>`` CLI so operators can
   answer "who still claims something about RAG?"

Reuses the same wikilink parser as ``llmwiki/graph.py`` (via
``llmwiki.lint.WIKILINK_RE``) so the graph viewer and lint rule
agree on what counts as a link.

Stdlib-only.  Fast enough to run on every build (O(pages × links)).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

from llmwiki import REPO_ROOT
from llmwiki.lint import WIKILINK_RE


# Dated-claim detection: human prose that commits to a specific moment
# in time. Captures the date so we can compare to the target's
# last_updated.  Matches:
#
#   as of 2026-03-15
#   as of March 2026
#   since v4.6
#   since 2026-01
#   (last checked 2026-02-10)
#
# The regex is deliberately loose — we'd rather flag too many than miss
# the thing that'll embarrass the user.
_DATED_CLAIM_RE = re.compile(
    r"""
    (?P<lead>
        (?:as\s+of|since|last\s+checked|current\s+as\s+of|through)
        [\s:]+
    )
    (?P<when>
        (?:\d{4}-\d{2}-\d{2})|(?:\d{4}-\d{2})|(?:\d{4})|
        (?:v?\d+(?:\.\d+){1,2})|
        (?:
            (?:January|February|March|April|May|June|July|August|
               September|October|November|December|
               Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)
            \s+\d{4}
        )
    )
    """,
    re.IGNORECASE | re.VERBOSE,
)


@dataclass(frozen=True)
class Reference:
    """One edge in the reverse-reference graph."""

    source: str    # rel path of the page doing the linking
    target: str    # wikilink target slug
    target_rel: Optional[str]  # resolved rel path (may be None for broken links)
    dated_claims: tuple[str, ...] = ()


@dataclass(frozen=True)
class StaleReference:
    """A reference that looks stale: target newer, source has a dated claim."""

    source: str
    source_last_updated: Optional[str]
    target: str
    target_last_updated: Optional[str]
    dated_claim: str


# ─── helpers ─────────────────────────────────────────────────────────────


def _rel_to_slug(rel: str) -> str:
    return rel.rsplit("/", 1)[-1].removesuffix(".md")


def _parse_date(value: Any) -> Optional[date]:
    """Accept ``date``, ``datetime``, ISO string, or raw string. Return
    the UTC date or ``None`` if we can't parse it."""
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    if not value:
        return None
    s = str(value).strip()
    # Handle "YYYY-MM-DD" and "YYYY-MM-DDTHH:MM:SSZ" both.
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def _extract_dated_claims(body: str, context_window: int = 80) -> list[str]:
    """Return short excerpts around every dated claim in ``body``.

    Each excerpt includes ``context_window`` chars before + after the
    match so the operator sees enough context to judge.
    """
    out: list[str] = []
    for m in _DATED_CLAIM_RE.finditer(body):
        start = max(0, m.start() - context_window)
        end = min(len(body), m.end() + context_window)
        excerpt = body[start:end].strip().replace("\n", " ")
        out.append(excerpt)
    return out


# ─── index building ──────────────────────────────────────────────────────


def build_index(pages: dict[str, dict]) -> dict[str, list[Reference]]:
    """Return ``{target_slug: [Reference, ...]}`` for every wikilink.

    ``pages`` has the shape ``{rel: {"meta": ..., "body": ..., ...}}``
    produced by ``llmwiki.lint.load_pages``.
    """
    # Map slug → rel so we can resolve wikilinks.
    slug_to_rel: dict[str, str] = {
        _rel_to_slug(rel): rel for rel in pages
    }
    idx: dict[str, list[Reference]] = {}
    for rel, page in pages.items():
        body = page.get("body") or ""
        dated = _extract_dated_claims(body)
        for raw_target in set(WIKILINK_RE.findall(body)):
            target = raw_target.split("#")[0].strip()
            if not target:
                continue
            target_rel = slug_to_rel.get(target)
            idx.setdefault(target, []).append(
                Reference(
                    source=rel,
                    target=target,
                    target_rel=target_rel,
                    dated_claims=tuple(dated),
                )
            )
    return idx


def find_references_to(
    target: str,
    pages: dict[str, dict],
) -> list[Reference]:
    """Return every page that links to ``target`` (case-sensitive slug)."""
    idx = build_index(pages)
    return idx.get(target, [])


def find_stale_references(
    pages: dict[str, dict],
) -> list[StaleReference]:
    """Return every (source, target) pair that looks stale.

    Stale = source links to target AND source's last_updated < target's
    last_updated AND source body contains at least one dated claim.

    The dated-claim guard is what keeps this rule from firing on every
    page that happens to link to something newer — without it every
    wikilink in a long-lived page would be "stale" the moment the
    target ever changes.
    """
    idx = build_index(pages)
    out: list[StaleReference] = []
    for target, refs in idx.items():
        target_rel = refs[0].target_rel if refs else None
        if target_rel is None:
            continue
        target_meta = pages.get(target_rel, {}).get("meta", {})
        target_updated = _parse_date(target_meta.get("last_updated"))
        if target_updated is None:
            continue
        for ref in refs:
            if not ref.dated_claims:
                continue
            source_meta = pages.get(ref.source, {}).get("meta", {})
            source_updated = _parse_date(source_meta.get("last_updated"))
            if source_updated is None:
                continue
            if source_updated < target_updated:
                out.append(
                    StaleReference(
                        source=ref.source,
                        source_last_updated=source_meta.get("last_updated"),
                        target=ref.target,
                        target_last_updated=target_meta.get("last_updated"),
                        dated_claim=ref.dated_claims[0],
                    )
                )
    return out


def format_references_table(refs: list[Reference]) -> str:
    """Plain-text table sorted by source for the ``references`` CLI."""
    if not refs:
        return "No references found."
    rows = [f"  {'source':<46}  target"]
    rows.append("  " + "-" * 46 + "  -------")
    for ref in sorted(refs, key=lambda r: r.source):
        rows.append(f"  {ref.source:<46}  {ref.target}")
    return "\n".join(rows)
