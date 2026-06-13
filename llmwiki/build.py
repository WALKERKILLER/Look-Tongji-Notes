"""llmwiki — static HTML site builder.

Reads converted markdown sources under `raw/` and produces a complete static
site under `site/` with:

- Home + projects index + sessions index + per-project + per-session pages
- Inter + JetBrains Mono typography, purple accent (#7C3AED)
- Light / dark theme toggle (data-theme + system preference + localStorage)
- Global search index (site/search-index.json) — client-side fuzzy matcher
- Cmd+K command palette (vanilla JS, no framework)
- Keyboard shortcuts: /, g h, g p, g s, j/k, ?
- highlight.js client-side syntax highlighting (CDN, light + dark themes)
- Collapsible tool-result sections (<details>) for long outputs
- Copy-as-markdown + copy-code buttons (Clipboard API + execCommand fallback)
- Breadcrumbs + reading progress bar
- Filter bar on the sessions table
- Mobile-responsive, print-friendly
- ARIA focus rings and prefers-reduced-motion support

Stdlib + `markdown` (required). No optional deps — highlight.js loads from CDN.
Usage:
    python3 -m llmwiki build [--synthesize] [--out <dir>]
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import markdown
from markdown.preprocessors import Preprocessor

from llmwiki import REPO_ROOT
from llmwiki.changelog_timeline import (
    extract_price_points,
    find_recently_updated,
    parse_changelog,
    render_changelog_timeline,
    render_price_sparkline,
    render_recent_activity,
    render_recently_updated,
)
from llmwiki.log_reader import recent_events as _recent_log_events
from llmwiki.context_md import is_context_file
from llmwiki.freshness import freshness_badge, load_freshness_config
from llmwiki.project_topics import (
    extract_session_topics,
    get_project_topics,
    load_project_profile,
    render_topic_chips,
)
from llmwiki.viz_heatmap import collect_session_counts, render_heatmap
from llmwiki.viz_tokens import (
    render_project_token_card,
    render_session_token_card,
    render_site_token_stats,
)
from llmwiki.viz_tools import (
    render_project_tool_chart,
    render_session_tool_chart,
)

# ─── paths ─────────────────────────────────────────────────────────────────

RAW_DIR = REPO_ROOT / "raw"
RAW_SESSIONS = RAW_DIR / "sessions"
DEFAULT_OUT_DIR = REPO_ROOT / "site"
# v0.7+: optional per-project metadata (topics, description, homepage).
# Users drop a `wiki/projects/<slug>.md` file with frontmatter.
PROJECTS_META_DIR = REPO_ROOT / "wiki" / "projects"


# ─── frontmatter ───────────────────────────────────────────────────────────

# #409 / #423: build.py used to ship a divergent regex (LF-only, no BOM
# handling, simpler list parser) which silently dropped frontmatter on
# Windows-authored files. Unified to the canonical parser in
# `_frontmatter.py`. Re-exported under the historical name so external
# consumers (and `tests/test_render_split.py`) keep working.
from llmwiki._frontmatter import (  # noqa: E402
    _FRONTMATTER_RE,
    parse_frontmatter,
)


# ─── discovery ─────────────────────────────────────────────────────────────


# #405 path-traversal guard. Site paths are composed by joining `out_dir`
# with `project_slug` and other slug values from frontmatter. A poisoned
# `project: ../../etc/passwd` would otherwise write outside `out_dir`.
_SAFE_SLUG_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def _safe_slug(value: str | None, *, fallback: str = "_unknown") -> str:
    """Return a path-safe single-segment slug.

    Rejects empty values, traversal segments (``..``), absolute paths
    (leading ``/`` or backslash), null bytes, and anything containing
    characters outside ``[A-Za-z0-9._-]``. Falls back to ``fallback`` so
    the build keeps going on poisoned frontmatter — the offending
    session lands under a clearly abnormal slug rather than escaping
    ``out_dir``.
    """
    if not value:
        return fallback
    s = str(value).strip()
    # Strip surrounding quotes leaked from naive YAML parsers.
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        s = s[1:-1]
    if not s or s in (".", ".."):
        return fallback
    if "/" in s or "\\" in s or "\x00" in s:
        return fallback
    if not _SAFE_SLUG_RE.match(s):
        return fallback
    return s


def _is_subagent(meta: dict[str, Any], path: Path) -> bool:
    """Return True iff a session is a sub-agent run (#492 / #406).

    Prefers the adapter-written ``is_subagent`` frontmatter field
    (canonical contract since #406). Falls back to the legacy
    ``"subagent" in path.name`` substring check ONLY if the field is
    missing — needed to keep pre-#406 raw files classified correctly
    until they're re-synced.

    Accepts the field as either a real bool or one of the
    case-insensitive strings ``"true"`` / ``"false"`` since
    frontmatter parsers historically coerced inconsistently.
    """
    raw = meta.get("is_subagent")
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, str):
        s = raw.strip().lower()
        if s in ("true", "yes", "1"):
            return True
        if s in ("false", "no", "0"):
            return False
    # Field absent or unrecognised — fall back to the legacy heuristic
    # so pre-#406 raw files (no is_subagent field) still get the right
    # answer. The renderer renames sub-agent slugs to
    # `<slug>-subagent-<id>`, so the substring match is correct on
    # canonically-renamed files even when meta is missing.
    return "subagent" in path.name


def discover_sources(root: Path) -> list[tuple[Path, dict[str, Any], str]]:
    out: list[tuple[Path, dict[str, Any], str]] = []
    if not root.exists():
        return out
    for p in sorted(root.rglob("*.md")):
        # v0.5 (#60): `_context.md` files are folder metadata for LLM
        # navigation, not pages. Skip them so they never appear in the
        # session index, search index, or AI-consumable exports.
        if is_context_file(p):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        meta, body = parse_frontmatter(text)
        # #405: sanitize the frontmatter values that compose output paths.
        # Original values stay available via meta.get(); the *_safe_*
        # versions are what every path-composition site downstream uses.
        meta["project"] = _safe_slug(
            meta.get("project") or p.parent.name,
            fallback=_safe_slug(p.parent.name, fallback="_unknown"),
        )
        if "slug" in meta:
            meta["slug"] = _safe_slug(meta["slug"], fallback=p.stem)
        out.append((p, meta, body))
    return out


def group_by_project(
    sources: list[tuple[Path, dict[str, Any], str]],
) -> dict[str, list[tuple[Path, dict[str, Any], str]]]:
    g: dict[str, list[tuple[Path, dict[str, Any], str]]] = defaultdict(list)
    for p, meta, body in sources:
        project = str(meta.get("project") or p.parent.name)
        g[project].append((p, meta, body))
    for k in g:
        g[k].sort(key=lambda t: str(t[1].get("started", t[0].name)))
    return g


_SLUG_SPLIT_RE = re.compile(r"[-_]+")


def _humanize_slug(slug: str) -> str:
    """Turn a kebab/snake-case slug into a human-readable title.

    `my-cool-project` → `My Cool Project`. Single-letter parts are
    upper-cased the same way as multi-letter parts. Empty / whitespace
    input returns the original (callers handle the empty case).
    """
    parts = [p for p in _SLUG_SPLIT_RE.split(slug.strip()) if p]
    if not parts:
        return slug.strip()
    return " ".join(p[:1].upper() + p[1:] for p in parts)


def _derive_stub_description(
    sessions: list[tuple[Path, dict[str, Any], str]],
) -> str:
    """Pick a sensible description from the most-recent session.

    Prefers an explicit `summary` (truncated to ~140 chars), then the
    humanised session slug, then empty. `sessions` arrives sorted oldest
    → newest by `discover_sources`/grouping, so we walk the tail.
    """
    for _path, meta, _body in reversed(sessions):
        summary = meta.get("summary")
        if isinstance(summary, str) and summary.strip():
            text = summary.strip().splitlines()[0].strip()
            if len(text) > 140:
                text = text[:137].rstrip() + "..."
            return text
        raw_slug = meta.get("slug")
        if isinstance(raw_slug, str) and raw_slug.strip():
            humanised = _humanize_slug(raw_slug)
            if humanised:
                return humanised
    return ""


def _derive_stub_topics(
    sessions: list[tuple[Path, dict[str, Any], str]],
    max_topics: int = 6,
) -> list[str]:
    """Aggregate topics from session frontmatter, then `tools_used` as a
    secondary source. Uses `extract_session_topics` for the tags path so
    the noise filter stays in sync with `project_topics.py`. Falls back
    to `min_count=1` because most projects have only a few sessions and
    the `min_count=2` default in `extract_session_topics` would suppress
    nearly everything at seed time. Returns at most `max_topics` topics.
    """
    metas = [meta for _path, meta, _body in sessions]
    topics = extract_session_topics(metas, max_topics=max_topics, min_count=1)
    if topics:
        return topics
    # Fallback: tools_used aggregation (filtered by the same noise set).
    from llmwiki.project_topics import _NOISE_TAGS
    counts: dict[str, int] = {}
    for meta in metas:
        raw = meta.get("tools_used")
        if isinstance(raw, list):
            items = raw
        elif isinstance(raw, dict):
            items = list(raw.keys())
        else:
            items = []
        for item in items:
            tag = str(item).strip().lower()
            if tag and tag not in _NOISE_TAGS:
                counts[tag] = counts.get(tag, 0) + 1
    ordered = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    return [tag for tag, _ in ordered[:max_topics]]


def _format_topics_yaml(topics: list[str]) -> str:
    """Inline-list YAML serialisation that matches the parser in
    `project_topics._parse_topics_frontmatter`."""
    if not topics:
        return "[]"
    return "[" + ", ".join(topics) + "]"


def ensure_project_stubs(
    groups: dict[str, list[tuple[Path, dict[str, Any], str]]],
    meta_dir: Path,
) -> list[Path]:
    """Auto-seed ``wiki/projects/<slug>.md`` for any discovered project
    that doesn't already have one (`issues-commands.md` I-12).

    Without this, real projects render a bare hero — no description, no
    topic chips, no homepage — because those fields come from a hand-
    authored file that never gets created on sync. Seeding pre-populates
    `topics:` from session tags/tools and `description:` from the most-
    recent session's summary or slug, so every real project lights up the
    moment its first session lands (closes #425). Existing hand-authored
    files are never overwritten — only the absence of a file triggers a
    write, so the user's edits always win.

    Returns the list of stub paths actually written (empty if all project
    metadata files already existed).
    """
    meta_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for slug in sorted(groups):
        target = meta_dir / f"{slug}.md"
        if target.exists():
            continue
        sessions = groups[slug]
        topics = _derive_stub_topics(sessions)
        description = _derive_stub_description(sessions)
        # Extract the real course title from the most recent session
        # frontmatter instead of falling back to the slug (numeric ID).
        course_title = slug
        for _path, meta, _body in sessions:
            candidate = meta.get("course_title") or meta.get("title") or ""
            if str(candidate).strip():
                course_title = str(candidate).strip()
                break
        # Escape embedded double-quotes in description so the YAML stays
        # valid — slugs/summaries from real sessions occasionally contain
        # quotes (`"why didn't this work"`).
        description_safe = description.replace("\\", "\\\\").replace('"', '\\"')
        title_safe = course_title.replace("\\", "\\\\").replace('"', '\\"')
        # #py-l8 (#606): drop f-prefix on lines that have no
        # placeholders so ruff's F541 doesn't flag the file. Mixed
        # f-/plain in a concatenation chain is fine.
        stub = (
            "---\n"
            f'title: "{title_safe}"\n'
            "type: entity\n"
            "entity_type: project\n"
            f"project: {slug}\n"
            f"topics: {_format_topics_yaml(topics)}\n"
            f'description: "{description_safe}"\n'
            'homepage: ""\n'
            "---\n\n"
            f"# {title_safe}\n\n"
            "*Auto-generated project stub. `topics` and `description` are "
            "pre-filled from session metadata — edit any field above and "
            "the build will pick it up. Fill in `homepage` to add a link "
            "chip to the project hero.*\n"
        )
        target.write_text(stub, encoding="utf-8")
        written.append(target)
    return written


# ─── markdown normaliser + renderer ───────────────────────────────────────

_H1_LINE_RE = re.compile(r"^#\s+.*\n", re.MULTILINE)


def strip_leading_h1(body: str) -> str:
    m = _H1_LINE_RE.search(body)
    if m and m.start() < 200:
        body = body[: m.start()] + body[m.end() :]
        body = body.lstrip("\n")
    return body


def normalize_markdown(body: str) -> str:
    """Fix common markdown glitches from the converter:
    1. Insert blank line before lists that follow a bold header.
    2. Outdent fenced code blocks that are 2-space-indented under a list item.
    """
    body = re.sub(
        r"(\*\*(?:Tools used|Tool results):\*\*)\n(?!\n)", r"\1\n\n", body,
    )
    lines = body.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip() == "```" and line.startswith("  "):
            if out and out[-1].strip():
                out.append("")
            out.append("```")
            i += 1
            while i < len(lines) and lines[i].strip() != "```":
                bl = lines[i]
                if bl.startswith("  "):
                    bl = bl[2:]
                out.append(bl)
                i += 1
            if i < len(lines):
                out.append("```")
                i += 1
                if i < len(lines) and lines[i].strip():
                    out.append("")
        else:
            out.append(line)
            i += 1
    return "\n".join(out)


# v0.5 (#74): Session content frequently mentions HTML-ish strings in prose —
# e.g. an assistant describing how a hidden `<textarea class="md-source">` works.
# The default Python markdown library passes raw HTML tags through unchanged,
# which means a session that mentions `<textarea>` outside of backticks leaks
# an unclosed textarea into the DOM, swallowing every following element
# (including the <script> tag that boots highlight.js). The v0.5 hljs swap
# made this pre-existing bug catastrophic — before, Pygments rendered code
# server-side so the broken tail didn't visibly matter; now, a single
# unescaped tag breaks the whole page's syntax highlighting.
#
# The preprocessor below escapes anything that *looks* like an HTML tag start
# (`<tagname` or `</tagname`) outside of inline backticks. Fenced code blocks
# are already extracted into placeholders by `fenced_code` (priority 25) before
# this runs (priority 22). Priority 22 also ensures we run *before*
# `html_block` (priority 20) so raw HTML blocks never get a chance to be
# preserved as-is. Bare `<` / `<space>` (e.g. `x < 10`) are left alone —
# markdown's own escaper handles those. HTML comments (`<!-- ... -->`) are
# preserved because the regex only matches `<[letter]`, not `<!`, and
# build.py emits an `<!-- llmwiki:metadata -->` comment that AI agents parse.
_TAG_START_RE = re.compile(r"<(/?[A-Za-z][A-Za-z0-9:_-]*)")
# #sec-13 (#557): also neutralise raw `<![CDATA[` blocks in prose. CDATA
# isn't allowed in HTML but some browsers / parsers treat it as a
# start-of-foreign-content marker; surfaces in MathML / SVG islands or
# in legacy XHTML rendering paths. Escape the leading `<` so the
# surrounding markdown processor doesn't pass it through as-is.
_CDATA_START_RE = re.compile(r"<!\[CDATA\[")
_INLINE_CODE_RE = re.compile(r"`[^`]*`")


class _EscapeRawHtmlPreprocessor(Preprocessor):
    """Escape HTML tag-start patterns outside code spans so raw `<textarea>`
    etc. in session prose can never leak into the DOM as live elements.
    See the comment above `md_to_html` for the full rationale."""

    def run(self, lines: list[str]) -> list[str]:
        out: list[str] = []
        for line in lines:
            parts: list[tuple[str, str]] = []
            last = 0
            for m in _INLINE_CODE_RE.finditer(line):
                parts.append(("text", line[last : m.start()]))
                parts.append(("code", m.group(0)))
                last = m.end()
            parts.append(("text", line[last:]))
            rebuilt: list[str] = []
            for kind, part in parts:
                if kind == "text":
                    # #sec-13: neutralise CDATA markers BEFORE the tag-
                    # start sub so we don't accidentally double-escape.
                    part = _CDATA_START_RE.sub(r"&lt;![CDATA[", part)
                    rebuilt.append(_TAG_START_RE.sub(r"&lt;\1", part))
                else:
                    rebuilt.append(part)
            out.append("".join(rebuilt))
        return out


# #283: in-memory content-hash cache for md_to_html. Same markdown body
# always produces the same HTML, and build steps call md_to_html on the
# same boilerplate (e.g. `## Connections`) across hundreds of pages.
# blake2b(digest_size=8) keyed + bounded by a size cap so repeated
# builds in the same Python process (tests, watch mode, bulk exports)
# don't re-parse.
#
# #417: switched from SHA-256 hex (allocates 64-byte string per call)
# to blake2b(digest_size=8) returning bytes. ~3× faster + 8× less
# allocation per cache key on a 5000-page corpus. The 8-byte (64-bit)
# digest gives a birthday-collision threshold around 4×10^9 entries —
# the 4096-entry cap stays many orders of magnitude below that.
_MD_CACHE: dict[bytes, str] = {}
_PLAIN_CACHE: dict[bytes, str] = {}
_MD_CACHE_MAX = 4096  # entries; ~20 MB ceiling at ~5 KB avg
_md_cache_hits = 0
_md_cache_misses = 0
_plain_cache_hits = 0
_plain_cache_misses = 0


def _content_key(body: str) -> bytes:
    """Compute the cache key for a markdown body (#417).

    blake2b is significantly faster than SHA-256 for short strings,
    and the 8-byte digest is enough headroom for the 4096-entry cap.
    Bytes (not hex) avoids the encode-back-to-string allocation.
    """
    import hashlib as _hl
    return _hl.blake2b(body.encode("utf-8"), digest_size=8).digest()


def md_to_html_cache_stats() -> dict[str, int]:
    """Return ``{hits, misses, size}`` for observability (#283)."""
    return {
        "hits": _md_cache_hits,
        "misses": _md_cache_misses,
        "size": len(_MD_CACHE),
        "plain_hits": _plain_cache_hits,
        "plain_misses": _plain_cache_misses,
        "plain_size": len(_PLAIN_CACHE),
    }


def md_to_html_cache_clear() -> None:
    """Clear the md_to_html + md_to_plain caches (used in tests)."""
    global _md_cache_hits, _md_cache_misses
    global _plain_cache_hits, _plain_cache_misses
    _MD_CACHE.clear()
    _PLAIN_CACHE.clear()
    _md_cache_hits = 0
    _md_cache_misses = 0
    _plain_cache_hits = 0
    _plain_cache_misses = 0


def _evict_first(cache: dict) -> None:
    """FIFO-evict the oldest cache entry."""
    try:
        first_key = next(iter(cache))
        del cache[first_key]
    except StopIteration:
        pass


def md_to_html(body: str) -> str:
    global _md_cache_hits, _md_cache_misses
    key = _content_key(body)
    cached = _MD_CACHE.get(key)
    if cached is not None:
        _md_cache_hits += 1
        return cached
    _md_cache_misses += 1
    result = _md_to_html_uncached(body)
    if len(_MD_CACHE) >= _MD_CACHE_MAX:
        _evict_first(_MD_CACHE)
    _MD_CACHE[key] = result
    return result


def _md_to_html_uncached(body: str) -> str:
    body = normalize_markdown(body)
    # v0.5: highlight.js replaces server-side Pygments/codehilite. The
    # fenced_code extension emits `<pre><code class="language-xxx">` and
    # highlight.js (loaded via CDN in page_head) picks it up client-side.
    # Benefits: lighter builds, no optional dep, consistent look across pages,
    # and auto-detection for untagged blocks.
    extensions = ["fenced_code", "tables", "toc", "sane_lists"]
    ext_configs: dict[str, dict[str, Any]] = {
        # #646: drop `permalink: True`. The Python-Markdown TOC
        # extension's permalink emits a `<a class="headerlink">¶</a>`
        # next to every heading; the site CSS doesn't style
        # `.headerlink` (only `.deep-link` is styled), so axe-core
        # flags every one as a `link-in-text-block` violation
        # (links that aren't visually distinguishable). The JS-
        # driven `.deep-link` icon next to each heading (rendered by
        # render/js.py) is the canonical deep-link affordance — it
        # has CSS + hover state + aria-hidden treatment. Two emitters
        # for the same job; the markdown one is the older one. Anchor
        # targets (`<h2 id="...">`) still ship via toc — links to
        # `#section-name` keep working.
        "toc": {"toc_depth": "2-3"},
    }
    md = markdown.Markdown(extensions=extensions, extension_configs=ext_configs)
    # v0.5 (#74): escape raw HTML tags in prose so session content mentioning
    # `<textarea>` etc. can't break the page. Runs after fenced_code (25) and
    # before html_block (20), so fenced code is preserved verbatim (through
    # placeholders), inline code via backticks is preserved by this
    # preprocessor's own backtick-skipping, and everything else is safe.
    md.preprocessors.register(
        _EscapeRawHtmlPreprocessor(md), "escape_raw_html_tags", 22
    )
    return md.convert(body)


def md_to_plain_text(body: str) -> str:
    """Strip markdown to plain text for the search index.

    #417: memoized on the same content key as md_to_html. The build
    pipeline calls md_to_html and md_to_plain_text on the same body
    repeatedly (per-page render + search-index extract + RSS summary
    + .txt sibling). Sharing the key makes the second + third + …
    calls free.
    """
    global _plain_cache_hits, _plain_cache_misses
    key = _content_key(body)
    cached = _PLAIN_CACHE.get(key)
    if cached is not None:
        _plain_cache_hits += 1
        return cached
    _plain_cache_misses += 1
    result = _md_to_plain_text_uncached(body)
    if len(_PLAIN_CACHE) >= _MD_CACHE_MAX:
        _evict_first(_PLAIN_CACHE)
    _PLAIN_CACHE[key] = result
    return result


def _md_to_plain_text_uncached(body: str) -> str:
    body = normalize_markdown(strip_leading_h1(body))
    # Remove code blocks (they're noisy in search)
    body = re.sub(r"```.*?```", " ", body, flags=re.DOTALL)
    # Inline code
    body = re.sub(r"`([^`]*)`", r"\1", body)
    # Links: [text](url) → text
    body = re.sub(r"\[([^\]]*)\]\([^\)]*\)", r"\1", body)
    # Wikilinks: [[name]] → name
    body = re.sub(r"\[\[([^\]]*)\]\]", r"\1", body)
    # Headings: strip leading #
    body = re.sub(r"^#+\s*", "", body, flags=re.MULTILINE)
    # Bold/italic marks
    body = re.sub(r"\*\*([^*]*)\*\*", r"\1", body)
    body = re.sub(r"\*([^*]*)\*", r"\1", body)
    # HTML comments
    body = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL)
    # Collapse whitespace
    body = re.sub(r"\s+", " ", body).strip()
    return body


# ─── helpers for frontmatter consumers ─────────────────────────────────────

def get_tools_list(meta: dict[str, Any]) -> list[str]:
    tools = meta.get("tools_used", [])
    if isinstance(tools, str):
        return [t.strip() for t in tools.strip("[]").split(",") if t.strip()]
    return list(tools) if tools else []


def short_started(meta: dict[str, Any]) -> str:
    s = str(meta.get("started", ""))
    return s[:16].replace("T", " ")


# ─── freshness (content staleness) ────────────────────────────────────────
# Cached once per build so every page sees the same "now" and the same
# thresholds. Populated lazily by render_freshness().
_FRESHNESS_CONFIG: Optional[tuple[int, int]] = None
_BUILD_NOW: Optional[datetime] = None


def render_freshness(meta: dict[str, Any]) -> str:
    """Render a freshness badge for a page's frontmatter using cached config.

    Thresholds come from ``config.json`` (freshness.green_days /
    yellow_days) or the module defaults. Build-time "now" is cached the
    first call so the whole site renders with one consistent clock.
    """
    global _FRESHNESS_CONFIG, _BUILD_NOW
    if _FRESHNESS_CONFIG is None:
        _FRESHNESS_CONFIG = load_freshness_config()
    if _BUILD_NOW is None:
        _BUILD_NOW = datetime.now(timezone.utc).replace(tzinfo=None)
    green, yellow = _FRESHNESS_CONFIG
    return freshness_badge(meta, now=_BUILD_NOW, green_days=green, yellow_days=yellow)


# ─── html template helpers ─────────────────────────────────────────────────

# v0.5: highlight.js for client-side syntax highlighting. Two themes so the
# switcher can swap between light/dark without a network round-trip. Pinned
# to a major version for stability, served from jsdelivr.
HLJS_VERSION = "11.9.0"
HLJS_LIGHT_CSS = (
    f"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@{HLJS_VERSION}"
    "/build/styles/github.min.css"
)
HLJS_DARK_CSS = (
    f"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@{HLJS_VERSION}"
    "/build/styles/github-dark.min.css"
)
HLJS_SCRIPT = (
    f"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@{HLJS_VERSION}"
    "/build/highlight.min.js"
)
KATEX_VERSION = "0.16.11"
KATEX_CSS = (
    f"https://cdn.jsdelivr.net/npm/katex@{KATEX_VERSION}/dist/katex.min.css"
)
KATEX_SCRIPT = (
    f"https://cdn.jsdelivr.net/npm/katex@{KATEX_VERSION}/dist/katex.min.js"
)
KATEX_AUTORENDER_SCRIPT = (
    f"https://cdn.jsdelivr.net/npm/katex@{KATEX_VERSION}/dist/contrib/auto-render.min.js"
)
FONT_AWESOME_CSS = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css"


def _hljs_head_tags() -> str:
    """Return the `<link>` tags for highlight.js themes. The dark theme is
    loaded with ``disabled`` and the light theme is the default — the runtime
    swaps the ``disabled`` flag when the theme toggles, so code blocks stay in
    sync with the rest of the page."""
    return (
        f'  <link id="hljs-light" rel="stylesheet" href="{HLJS_LIGHT_CSS}">\n'
        f'  <link id="hljs-dark" rel="stylesheet" href="{HLJS_DARK_CSS}" disabled>\n'
    )


def _katex_head_tags() -> str:
    """Return the KaTeX stylesheet tags for client-side math rendering."""
    return (
        f'  <link rel="stylesheet" href="{KATEX_CSS}">\n'
        "  <style>\n"
        "    .katex-display { overflow-x: auto; overflow-y: hidden; padding: 0.2rem 0; }\n"
        "    .katex-display > .katex { max-width: 100%; }\n"
        "  </style>\n"
    )


_PRE_PAINT_THEME_SCRIPT = """  <script>
    /* #458: read localStorage.llmwiki-theme BEFORE first paint so users
       never see a flash of the wrong theme when navigating between pages.
       Falls back to prefers-color-scheme, then dark. Mirrors the same
       pre-paint pattern graph.html already uses (#477). */
    (function () {
      try {
        var t = localStorage.getItem('llmwiki-theme');
        if (t !== 'dark' && t !== 'light') {
          t = (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
        }
        document.documentElement.setAttribute('data-theme', t);
      } catch (e) {
        document.documentElement.setAttribute('data-theme', 'dark');
      }
    })();
  </script>
"""


def page_head(title: str, description: str, css_prefix: str = "", lang: str = "en") -> str:
    # #ui-m13 (#576): lang argument lets callers override the default
    # `<html lang="en">` for translated docs (`docs/i18n/<locale>/`).
    # See also page_head_article() which has the same parameter.
    favicon_links = _favicon_link_tags()
    return f"""<!DOCTYPE html>
<html lang="{html.escape(lang)}" dir="auto">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(description)}">
{_PRE_PAINT_THEME_SCRIPT}  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <!-- #ui-m14 (#577): async-load Google Fonts via media="print" + onload swap so it doesn't render-block first paint. <noscript> fallback for JS-disabled users. -->
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=LXGW+WenKai+TC&family=Noto+Sans+TC:wght@100..900&display=swap" rel="stylesheet" media="print" onload="this.media='all'">
  <noscript><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=LXGW+WenKai+TC&family=Noto+Sans+TC:wght@100..900&display=swap" rel="stylesheet"></noscript>
{_hljs_head_tags()}{_katex_head_tags()}  <link rel="stylesheet" href="{FONT_AWESOME_CSS}">
{favicon_links}  <link rel="stylesheet" href="{css_prefix}style.css">
</head>
<body>
<a href="#main-content" class="skip-link">跳到正文</a>
<div class="progress-bar" id="progress-bar"></div>
"""


def page_head_article(
    title: str,
    description: str,
    css_prefix: str = "",
    canonical: str = "",
    date: str = "",
    metadata_comment: str = "",
    lang: str = "en",
) -> str:
    """v0.4: Extended page head for session (Article) pages with schema.org
    microdata, canonical link, and an AI-readable metadata HTML comment.

    #ui-m13 (#576): `lang` arg lets translated docs override the
    default `en`. `dir="auto"` lets the browser infer RTL/LTR per
    paragraph for sessions whose body contains Arabic / Hebrew
    transliterations or quotes."""
    canonical_tag = ""
    if canonical:
        canonical_tag = f'  <link rel="canonical" href="{html.escape(canonical)}">\n'
    og_tags = f"""  <meta property="og:type" content="article">
  <meta property="og:title" content="{html.escape(title)}">
  <meta property="og:description" content="{html.escape(description)}">
"""
    if date:
        og_tags += f'  <meta property="article:published_time" content="{html.escape(date)}">\n'
    favicon_links = _favicon_link_tags()
    return f"""<!DOCTYPE html>
<html lang="{html.escape(lang)}" dir="auto">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <title>{html.escape(title)}</title>
  <meta name="description" content="{html.escape(description)}">
{_PRE_PAINT_THEME_SCRIPT}{canonical_tag}{og_tags}  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <!-- #ui-m14 (#577): async-load Google Fonts via media="print" + onload swap so it doesn't render-block first paint. <noscript> fallback for JS-disabled users. -->
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=LXGW+WenKai+TC&family=Noto+Sans+TC:wght@100..900&display=swap" rel="stylesheet" media="print" onload="this.media='all'">
  <noscript><link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=LXGW+WenKai+TC&family=Noto+Sans+TC:wght@100..900&display=swap" rel="stylesheet"></noscript>
{_hljs_head_tags()}{_katex_head_tags()}  <link rel="stylesheet" href="{FONT_AWESOME_CSS}">
{favicon_links}  <link rel="stylesheet" href="{css_prefix}style.css">
</head>
<body>
{metadata_comment}<a href="#main-content" class="skip-link">跳到正文</a>
<div class="progress-bar" id="progress-bar"></div>
"""


def _build_metadata_comment(
    meta: dict[str, Any],
    slug: str,
    project_slug: str,
    reading_min: int,
    html_stem: str = "",
) -> str:
    """An HTML comment at the top of every session page that AI agents can
    parse without needing to fetch the separate .json sibling."""
    fields = [
        f"slug: {slug}",
        f"project: {project_slug}",
    ]
    for key in ("date", "started", "ended", "model", "gitBranch", "permissionMode", "user_messages", "tool_calls"):
        val = meta.get(key)
        if val is not None:
            fields.append(f"{key}: {val}")
    tools = get_tools_list(meta)
    if tools:
        fields.append(f"tools_used: [{', '.join(tools)}]")
    fields.append(f"reading_min: {reading_min}")
    sibling_stem = html_stem or slug
    fields.append(f"txt_sibling: {sibling_stem}.txt")
    fields.append(f"json_sibling: {sibling_stem}.json")
    body = "\n".join(fields)
    return f"<!-- llmwiki:metadata\n{body}\n-->\n"


def _ui_site_name() -> str:
    try:
        workspace = REPO_ROOT / "workspace.json"
        if workspace.is_file():
            data = json.loads(workspace.read_text(encoding="utf-8"))
            site_name = str(data.get("site_name") or "").strip()
            if site_name:
                return site_name
    except Exception:
        pass
    return "LLM Wiki"


def _ui_text(key: str) -> str:
    mapping = {
        "projects": "课程",
        "sessions": "课次",
        "session": "课次",
        "project_en": "课程",
        "session_en": "课次",
        "home": "首页",
        "graph": "图谱",
        "search": "搜索",
        "theme": "主题",
        "footer_hint": "课程知识库 · 首页 · 按 ? 查看快捷键",
        "open_nav": "打开导航菜单",
        "open_palette": "打开命令面板",
        "toggle_dark": "切换深色模式",
        "switch_language": "切换界面语言",
        "language_menu": "语言选择",
        "github_repo": "打开 GitHub 仓库",
        "breadcrumbs": "导航路径",
        "main_navigation": "主导航",
        "mobile_navigation": "移动导航",
        "command_palette": "命令面板",
        "search_pages": "搜索页面",
        "search_placeholder": "搜索… 或输入：type:lesson project:look-tongji-notes date:>2026-03 sort:date",
        "palette_nav": "上下移动",
        "palette_open": "打开",
        "palette_close": "关闭",
        "keyboard_shortcuts": "键盘快捷键",
        "open_command_palette": "打开命令面板",
        "focus_search": "聚焦搜索",
        "go_home": "前往首页",
        "go_projects": "前往课程列表",
        "go_sessions": "前往课次列表",
        "next_prev_row": "上一行 / 下一行（表格）",
        "show_help": "显示帮助",
        "close_dialogs": "关闭弹窗",
        "structured_queries": "结构化查询",
        "structured_queries_hint": "可以把 key:value 筛选和自由文本一起使用：",
        "only_session_pages": "仅显示课次页面",
        "filter_project_name": "按课程名筛选（包含匹配）",
        "filter_model_name": "按模型名筛选（包含匹配）",
        "sessions_after_date": "筛选此日期之后的课次",
        "sessions_before_date": "筛选此日期之前的课次",
        "pages_with_tags": "筛选提到该标签/主题的页面",
        "sort_by_date": "按日期排序（最新优先）",
        "example": "示例",
        "close": "关闭",
        "copy_markdown": "复制 Markdown",
        "copy_session_markdown": "复制课次 Markdown 内容",
        "download_md": "下载 .md",
        "back_to_course": "返回课程",
        "plain_text_export": "纯文本导出",
        "json_export": "结构化 JSON 导出",
        "overview": "概览",
        "all_courses": "全部课程",
        "all_lessons": "全部课次",
        "all_lessons_newest": "全部课程课次，按最新优先",
        "course_knowledge_base": "课程知识库",
        "activity_last_365_days": "活跃度 · 最近 365 天",
        "activity_last_365_days_project": "活跃度 · 最近 365 天 · {name}",
        "recent_activity": "最近活动 · 最近 {count} 次操作",
        "lessons_count": "课次（{count}）",
        "course": "课程",
        "from": "从",
        "to": "到",
        "lesson": "课次",
        "lesson_search_placeholder": "输入课次标题中的部分内容…",
        "clear": "清除",
        "agent": "代理",
        "date": "日期",
        "duration": "时长",
        "lesson_total": "{count} 节",
        "course_total": "{count} 门课程",
        "page_not_found": "页面未找到",
        "page_not_found_desc": "你访问的页面不存在，链接可能已失效、页面已被移走，或网址中有拼写错误。",
        "try_these": "可以试试这些入口：",
        "home_overview": "首页 — 总览与最近活动",
        "projects_overview": "课程 — 所有课程页面",
        "sessions_overview": "课次 — 所有课次，可排序和筛选",
        "open_palette_hint": "或者按 ⌘K / Ctrl+K 打开命令面板继续搜索。",
    }
    return mapping.get(key, key)


def _load_timeline_items(path: Path | None) -> list[tuple[int, str, str]]:
    if path is None or not path.is_file():
        return []
    rows: list[tuple[int, str, str]] = []
    pattern = re.compile(r"(?P<start>\d{1,3}:\d{2}(?::\d{2})?)\s*[-–—~～]\s*(?P<end>\d{1,3}:\d{2}(?::\d{2})?)\s*[:：]\s*(?P<text>.+)")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line.strip())
        if not match:
            continue
        raw = match.group("start")
        parts = [int(p) for p in raw.split(":")]
        if len(parts) == 2:
            sec = parts[0] * 60 + parts[1]
        else:
            sec = parts[0] * 3600 + parts[1] * 60 + parts[2]
        rows.append((sec, raw, match.group("text").strip()))
    return rows


def _session_media_block(meta: dict[str, Any]) -> str:
    video_url = str(meta.get("look_tongji_video_url") or "").strip()
    timeline_rel = str(meta.get("look_tongji_timeline") or "").strip()
    subtitle_rel = str(meta.get("look_tongji_subtitle") or "").strip()
    timeline_items = _load_timeline_items((REPO_ROOT / timeline_rel) if timeline_rel else None)
    subtitle_src = ""
    if subtitle_rel:
        subtitle_src = "../../" + subtitle_rel
    if not video_url and not timeline_items:
        return ""
    timeline_html = "".join(
        f'<button class="tongji-timeline-item" type="button" data-seek="{sec}">'
        f'<span class="tongji-time">{html.escape(label)}</span>'
        f'<span class="tongji-text">{html.escape(text)}</span>'
        f'</button>'
        for sec, label, text in timeline_items
    ) or '<p class="muted">暂无时间轴条目。</p>'
    player = (
        f'<div class="tongji-player" data-artplayer data-video-src="{html.escape(video_url)}" '
        f'data-subtitle-src="{html.escape(subtitle_src)}"></div>'
        if video_url else '<div class="tongji-player tongji-player-empty"><p class="muted">暂无课程视频链接。</p></div>'
    )
    return f"""<section class="tongji-media-shell">
  <details class="tongji-media-details">
    <summary><span class="tongji-summary-label">课程视频</span><span class="tongji-summary-caret" aria-hidden="true"><svg class="tongji-caret-down" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" /></svg><svg class="tongji-caret-up" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m4.5 15.75 7.5-7.5 7.5 7.5" /></svg></span></summary>
    <div class="tongji-media-grid">
      <div class="tongji-player-wrap">{player}</div>
      <aside class="tongji-timeline-panel">
        <h2>时间轴</h2>
        <div class="tongji-timeline-list">{timeline_html}</div>
      </aside>
    </div>
  </details>
</section>"""


def nav_bar(active: str, link_prefix: str = "") -> str:
    def link(href: str, label: str, key: str) -> str:
        cls = ' class="active"' if key == active else ""
        return f'<a href="{link_prefix}{href}"{cls}>{label}</a>'

    # #460: hamburger pattern for tablet/mobile (≤1023px). The desktop
    # nav-links row is hidden below 1024 (CSS rule), so without this
    # button the navigation entries would be unreachable on mobile.
    # The drawer below mirrors the same links vertically. JS in
    # render/js.py wires aria-expanded, ESC-to-close, and focus return.
    drawer_link = lambda href, label, key: (
        f'  <a href="{link_prefix}{href}" class="nav-drawer-link'
        + (' active' if key == active else '') + '">'
        + label + '</a>'
    )
    # Post-review: dropped `role="menu"` + `aria-labelledby` — children
    # are plain <a>, not role="menuitem", so screen readers were being
    # told "press arrow keys" which did nothing. The drawer is a
    # disclosure nav, not an ARIA menu. The hamburger's aria-controls
    # already provides the trigger→drawer association; no role needed
    # on the container.
    nav_drawer_html = f"""<div id="nav-drawer" class="nav-drawer" hidden aria-label="{_ui_text('main_navigation')}">
{drawer_link("index.html", _ui_text("home"), "home")}
{drawer_link("projects/index.html", _ui_text("projects"), "projects")}
{drawer_link("sessions/index.html", _ui_text("sessions"), "sessions")}
{drawer_link("graph.html", _ui_text("graph"), "graph")}
</div>"""
    brand_logo = _nav_brand_logo_html()
    return f"""<header class="nav">
  <div class="nav-inner">
    <a href="{link_prefix}index.html" class="nav-brand">
      {brand_logo}
    </a>
    <button type="button" class="nav-hamburger" id="nav-hamburger"
            aria-expanded="false" aria-controls="nav-drawer"
            aria-label="{_ui_text('open_nav')}">
      <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg>
    </button>
    <nav class="nav-links">
      {link("index.html", _ui_text("home"), "home")}
      {link("projects/index.html", _ui_text("projects"), "projects")}
      {link("sessions/index.html", _ui_text("sessions"), "sessions")}
      {link("graph.html", _ui_text("graph"), "graph")}
      <button class="nav-search-btn" id="open-palette"
              aria-label="{_ui_text('open_palette')}"
              aria-haspopup="dialog" aria-expanded="false" aria-controls="palette">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
        <span>{_ui_text("search")}</span>
        <kbd>⌘K</kbd>
      </button>
      <button class="theme-toggle" id="theme-toggle"
              aria-label="{_ui_text('toggle_dark')}" aria-pressed="false">
        <svg aria-hidden="true" class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
        <svg aria-hidden="true" class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>
      </button>
      <a class="nav-icon-link github-link" href="https://github.com/WALKERKILLER/Look-Tongji-Notes" target="_blank" rel="noopener noreferrer" aria-label="{_ui_text('github_repo')}" title="GitHub">
        <i class="fa-brands fa-github" aria-hidden="true"></i>
      </a>
      <div class="lang-switcher">
        <button class="lang-toggle" id="lang-toggle" type="button" aria-label="{_ui_text('switch_language')}" aria-haspopup="menu" aria-expanded="false" aria-controls="lang-menu">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="m10.5 21 5.25-11.25L21 21m-9-3h7.5M3 5.621a48.474 48.474 0 0 1 6-.371m0 0c1.12 0 2.233.038 3.334.114M9 5.25V3m3.334 2.364C11.176 10.658 7.69 15.08 3 17.502m9.334-12.138c.896.061 1.785.147 2.666.257m-4.589 8.495a18.023 18.023 0 0 1-3.827-5.802" />
          </svg>
        </button>
        <div class="lang-menu" id="lang-menu" role="menu" aria-label="{_ui_text('language_menu')}" hidden>
          <button class="lang-menu-item" type="button" data-lang="zh-Hans" role="menuitemradio">简体中文</button>
          <button class="lang-menu-item" type="button" data-lang="zh-Hant" role="menuitemradio">繁體中文</button>
          <button class="lang-menu-item" type="button" data-lang="en" role="menuitemradio">English</button>
        </div>
      </div>
    </nav>
  </div>
  {nav_drawer_html}
</header>
"""


def breadcrumbs_bar(crumbs: list[tuple[str, str]], link_prefix: str = "") -> str:
    if not crumbs:
        return ""
    parts = []
    for i, (label, href) in enumerate(crumbs):
        if href:
            parts.append(f'<a href="{link_prefix}{html.escape(href)}">{html.escape(label)}</a>')
        else:
            parts.append(f'<span aria-current="page">{html.escape(label)}</span>')
    sep = ' <span class="crumb-sep">›</span> '
    return f'<nav class="breadcrumbs" aria-label="{_ui_text("breadcrumbs")}">{sep.join(parts)}</nav>'


def hero(title: str, subtitle: str, size: str = "", subtitle_is_html: bool = False) -> str:
    cls = f"hero {size}".strip()
    sub = subtitle if subtitle_is_html else html.escape(subtitle)
    figure_html = ""
    heading_html = f"<h1>{html.escape(title)}</h1>"
    if "hero-home" in cls:
        figure_html = _home_hero_figure_html()
        site_title = title
        suffix = "的课程知识库"
        if site_title.endswith(suffix):
            user_name = site_title[: -len(suffix)]
            heading_html = (
                '<h1 class="hero-site-title">'
                f'<span class="hero-site-owner">{html.escape(user_name)}<span class="hero-site-glow" aria-hidden="true"></span></span>'
                f'<span class="hero-site-suffix">{html.escape(suffix)}</span>'
                '</h1>'
            )
    return f"""<main id="main-content">
<section class="{cls}">
  <div class="container hero-shell">
    <div class="hero-copy">
      {heading_html}
      <p class="hero-sub">{sub}</p>
    </div>
    {figure_html}
  </div>
</section>
"""


def page_foot(js_prefix: str = "") -> str:
    return f"""<footer class="footer">
  <div class="container">
    <p class="muted">{_ui_text("footer_hint")}</p>
  </div>
</footer>
<nav class="mobile-bottom-nav" aria-label="{_ui_text('mobile_navigation')}">
  <a href="{js_prefix}index.html" class="mbn-link" data-page="home">
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
    <span>{_ui_text("home")}</span>
  </a>
  <a href="{js_prefix}projects/index.html" class="mbn-link" data-page="projects">
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    <span>{_ui_text("projects")}</span>
  </a>
  <a href="{js_prefix}sessions/index.html" class="mbn-link" data-page="sessions">
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
    <span>{_ui_text("sessions")}</span>
  </a>
  <button type="button" class="mbn-link" id="mbn-search" aria-label="{_ui_text('search')}">
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
    <span>{_ui_text("search")}</span>
  </button>
  <button type="button" class="mbn-link" id="mbn-theme" aria-label="{_ui_text('theme')}" aria-pressed="false">
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
    <span>{_ui_text("theme")}</span>
  </button>
</nav>
<div id="palette" class="palette">
  <div class="palette-backdrop" id="palette-backdrop"></div>
  <div class="palette-modal" role="dialog" aria-modal="true" aria-label="{_ui_text('command_palette')}">
    <div class="palette-header">
      <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
      <input type="text" id="palette-input" aria-label="{_ui_text('search_pages')}" placeholder="{_ui_text('search_placeholder')}" autocomplete="off" spellcheck="false">
      <kbd>ESC</kbd>
    </div>
    <ul class="palette-results" id="palette-results"></ul>
    <div class="palette-footer muted">
      <span><kbd>↑↓</kbd> {_ui_text("palette_nav")}</span>
      <span><kbd>↵</kbd> {_ui_text("palette_open")}</span>
      <span><kbd>ESC</kbd> {_ui_text("palette_close")}</span>
    </div>
  </div>
</div>
<div id="help-dialog" class="help-dialog">
  <div class="palette-backdrop" id="help-backdrop"></div>
  <div class="help-modal">
    <h2>{_ui_text("keyboard_shortcuts")}</h2>
    <table>
      <tr><td><kbd>⌘K</kbd> / <kbd>Ctrl+K</kbd></td><td>{_ui_text("open_command_palette")}</td></tr>
      <tr><td><kbd>/</kbd></td><td>{_ui_text("focus_search")}</td></tr>
      <tr><td><kbd>g h</kbd></td><td>{_ui_text("go_home")}</td></tr>
      <tr><td><kbd>g p</kbd></td><td>{_ui_text("go_projects")}</td></tr>
      <tr><td><kbd>g s</kbd></td><td>{_ui_text("go_sessions")}</td></tr>
      <tr><td><kbd>j</kbd> / <kbd>k</kbd></td><td>{_ui_text("next_prev_row")}</td></tr>
      <tr><td><kbd>?</kbd></td><td>{_ui_text("show_help")}</td></tr>
      <tr><td><kbd>Esc</kbd></td><td>{_ui_text("close_dialogs")}</td></tr>
    </table>
    <h3>{_ui_text("structured_queries")}</h3>
    <p class="muted help-dialog-hint">{_ui_text("structured_queries_hint")}</p>
    <table>
      <tr><td><code>type:lesson</code></td><td>{_ui_text("only_session_pages")}</td></tr>
      <tr><td><code>project:look-tongji-notes</code></td><td>{_ui_text("filter_project_name")}</td></tr>
      <tr><td><code>model:claude</code></td><td>{_ui_text("filter_model_name")}</td></tr>
      <tr><td><code>date:&gt;2026-03-01</code></td><td>{_ui_text("sessions_after_date")}</td></tr>
      <tr><td><code>date:&lt;2026-04-01</code></td><td>{_ui_text("sessions_before_date")}</td></tr>
      <tr><td><code>tags:电工学</code></td><td>{_ui_text("pages_with_tags")}</td></tr>
      <tr><td><code>sort:date</code></td><td>{_ui_text("sort_by_date")}</td></tr>
    </table>
    <p class="muted help-dialog-example">{_ui_text("example")}：<code>type:lesson project:look-tongji-notes date:&gt;2026-04 sort:date</code></p>
    <button class="btn" id="help-close">{_ui_text("close")}</button>
  </div>
</div>
<script src="{js_prefix}search-index.json" type="application/json" id="search-index-hint"></script>
<script>window.LLMWIKI_INDEX_URL = "{js_prefix}search-index.json";</script>
<script src="{HLJS_SCRIPT}" defer></script>
<script src="{KATEX_SCRIPT}" defer></script>
<script src="{KATEX_AUTORENDER_SCRIPT}" defer></script>
<script>
  // v0.5: Run highlight.js once the CDN script lands. Defer keeps it out of
  // the critical path; the DOMContentLoaded fallback covers the case where
  // hljs arrives before/after DOM ready depending on cache state.
  function __llmwikiHljsInit() {{
    if (window.hljs) {{ window.hljs.highlightAll(); }}
    else {{ window.addEventListener('load', function() {{ if (window.hljs) window.hljs.highlightAll(); }}); }}
  }}
  if (document.readyState === 'loading') {{
    document.addEventListener('DOMContentLoaded', __llmwikiHljsInit);
  }} else {{
    __llmwikiHljsInit();
  }}

  function __llmwikiRenderMath() {{
    if (!window.renderMathInElement) {{
      window.addEventListener('load', function() {{
        if (!window.renderMathInElement) return;
        window.renderMathInElement(document.body, {{
          delimiters: [
            {{ left: '$$', right: '$$', display: true }},
            {{ left: '$', right: '$', display: false }}
          ],
          throwOnError: false,
          strict: 'ignore'
        }});
      }});
      return;
    }}
    window.renderMathInElement(document.body, {{
      delimiters: [
        {{ left: '$$', right: '$$', display: true }},
        {{ left: '$', right: '$', display: false }}
      ],
      throwOnError: false,
      strict: 'ignore'
    }});
  }}
  if (document.readyState === 'loading') {{
    document.addEventListener('DOMContentLoaded', __llmwikiRenderMath);
  }} else {{
    __llmwikiRenderMath();
  }}
</script>
<script src="https://cdn.jsdelivr.net/npm/artplayer/dist/artplayer.js"></script>
<script src="{js_prefix}script.js"></script>
</body>
</html>
"""


# ─── page renderers ────────────────────────────────────────────────────────

_HOME_HERO_SVG_CACHE: str | None = None
_NAV_BRAND_LOGO_CACHE: str | None = None
_WEB_ICON_DATA_URI_CACHE: str | None = None


def _load_home_hero_svg() -> str:
    global _HOME_HERO_SVG_CACHE
    if _HOME_HERO_SVG_CACHE is not None:
        return _HOME_HERO_SVG_CACHE
    for parent in Path(__file__).resolve().parents:
        candidate = parent / "stacked-paper.svg"
        if not candidate.exists():
            continue
        try:
            svg = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        svg = re.sub(r"^\s*<\?xml[^>]*\?>\s*", "", svg, count=1)
        _HOME_HERO_SVG_CACHE = svg
        return svg
    _HOME_HERO_SVG_CACHE = ""
    return ""


def _load_nav_brand_logo_svg() -> str:
    global _NAV_BRAND_LOGO_CACHE
    if _NAV_BRAND_LOGO_CACHE is not None:
        return _NAV_BRAND_LOGO_CACHE
    candidates = [
        REPO_ROOT / "images" / "logo.svg",
        REPO_ROOT.parent / "images" / "logo.svg",
        REPO_ROOT / "skills" / "look-tongji-notes" / "images" / "logo.svg",
        REPO_ROOT.parent / "skills" / "look-tongji-notes" / "images" / "logo.svg",
    ]
    for candidate in candidates:
        if not candidate.exists():
            continue
        try:
            svg = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        svg = re.sub(r"^\s*<\?xml[^>]*\?>\s*", "", svg, count=1)
        svg = re.sub(r"\s(width|height)=\"[^\"]*\"", "", svg)
        _NAV_BRAND_LOGO_CACHE = svg
        return svg
    _NAV_BRAND_LOGO_CACHE = ""
    return ""


def _nav_brand_logo_html() -> str:
    svg = _load_nav_brand_logo_svg()
    if not svg:
        return '<span class="nav-brand-fallback" aria-hidden="true">LTN</span>'
    return f'<span class="nav-brand-logo" aria-hidden="true">{svg}</span>'


def _load_web_icon_svg() -> str:
    candidates = [
        REPO_ROOT / "images" / "web.svg",
        REPO_ROOT.parent / "images" / "web.svg",
        REPO_ROOT.parent.parent.parent / "web.svg",
        REPO_ROOT.parent.parent / "web.svg",
        REPO_ROOT.parent / "web.svg",
        REPO_ROOT / "web.svg",
    ]
    for candidate in candidates:
        if not candidate.exists():
            continue
        try:
            svg = candidate.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        return re.sub(r"^\s*<\?xml[^>]*\?>\s*", "", svg, count=1)
    return ""


def _copy_site_images(out_dir: Path) -> int:
    candidates = [REPO_ROOT / "images", REPO_ROOT.parent / "images"]
    for source in candidates:
        if not source.exists() or not any(source.iterdir()):
            continue
        site_images = out_dir / "images"
        if site_images.exists():
            shutil.rmtree(site_images)
        shutil.copytree(source, site_images)
        return sum(1 for p in site_images.rglob("*") if p.is_file())
    return 0


def _prepare_favicon_svg(svg: str) -> str:
    match = re.search(r"<svg\b[^>]*>(.*)</svg>\s*$", svg, flags=re.DOTALL | re.IGNORECASE)
    inner = match.group(1).strip() if match else svg.strip()
    # `web.svg` 的主体是横向铺开的图形，原始 1254x1254 画布留白较多。
    # favicon 只在这里裁紧视口，避免标签页图标主体过小；不改原文件本体。
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="110 180 1034 1034" '
        'width="256" height="256" preserveAspectRatio="xMidYMid meet">'
        f"{inner}</svg>"
    )


def _favicon_link_tags() -> str:
    global _WEB_ICON_DATA_URI_CACHE
    if _WEB_ICON_DATA_URI_CACHE is None:
        svg = _load_web_icon_svg()
        if svg:
            svg = _prepare_favicon_svg(svg)
        _WEB_ICON_DATA_URI_CACHE = (
            "data:image/svg+xml;charset=utf-8," + urllib.parse.quote(svg)
            if svg
            else ""
        )
    if not _WEB_ICON_DATA_URI_CACHE:
        return ""
    href = html.escape(_WEB_ICON_DATA_URI_CACHE)
    return (
        f'  <link rel="icon" type="image/svg+xml" href="{href}">\n'
        f'  <link rel="shortcut icon" href="{href}">\n'
        f'  <link rel="apple-touch-icon" href="{href}">\n'
    )


def _home_hero_figure_html() -> str:
    svg = _load_home_hero_svg()
    if not svg:
        return ""
    if "viewBox=" not in svg:
        svg = svg.replace(
            "<svg ",
            '<svg viewBox="51 41 410 431" preserveAspectRatio="xMidYMid meet" ',
            1,
        )
    svg = re.sub(r'\s(width|height)="[^"]*"', "", svg, count=2)
    return f'<div class="hero-figure" aria-hidden="true">{svg}</div>'

def _pluralize(n: int, singular: str, plural: str | None = None) -> str:
    """Return ``"1 session"`` for n=1, ``"3 sessions"`` for n=3.

    Closes #387 U7. The hero subtitle and any other count-bearing
    user-facing string should never read as ``"1 sessions"``."""
    if plural is None:
        plural = singular + "s"
    return f"{n} {singular if n == 1 else plural}"


def calc_reading_time(body: str, wpm: int = 225) -> int:
    """Estimate reading time in minutes from a markdown body."""
    words = len(re.findall(r"\w+", body))
    return max(1, round(words / wpm))


def _format_duration_label(seconds: Any) -> str:
    try:
        total = max(0, int(seconds or 0))
    except Exception:
        total = 0
    minutes, sec = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{sec:02d}"
    return f"{minutes}:{sec:02d}"


def _is_tongji_lesson(meta: dict[str, Any]) -> bool:
    return bool(
        meta.get("look_tongji_video_url")
        or meta.get("look_tongji_subtitle")
        or meta.get("session_title")
    )


def _normalize_session_title(meta: dict[str, Any], title: str) -> str:
    if not _is_tongji_lesson(meta):
        return title
    if title.startswith("Session: "):
        return "Lesson: " + title[9:]
    if title.startswith("Lesson: "):
        return title
    session_title = str(meta.get("session_title") or "").strip()
    if session_title and title == session_title:
        return f"Lesson: {session_title}"
    return title


def _strip_session_like_prefix(title: str) -> str:
    for prefix in ("Session: ", "Lesson: "):
        if title.startswith(prefix):
            return title[len(prefix):]
    return title


def render_session(
    path: Path,
    meta: dict[str, Any],
    body: str,
    out_dir: Path,
    project_slug: str,
) -> Path:
    slug = meta.get("slug", path.stem)
    date = meta.get("date", "")
    fallback_label = "Lesson" if _is_tongji_lesson(meta) else "Session"
    title_raw = _normalize_session_title(meta, str(meta.get("title", f"{fallback_label}: {slug}")))
    proj_profile = load_project_profile(PROJECTS_META_DIR, project_slug)
    project_label = str((proj_profile or {}).get("title") or meta.get("course_title") or project_slug)

    body = strip_leading_h1(body)
    body_html = md_to_html(body)
    # #270: session transcripts often reference files the user had open
    # during the session (tasks.md, CLAUDE.md, convert.py, etc). Route
    # the ones that look like repo source code or root files to GitHub
    # so the links don't dead-end after ingest.
    from llmwiki.docs_pages import (
        rewrite_md_links_to_html,
        rewrite_source_code_links_to_github,
        strip_dead_session_refs,
    )
    body_html = rewrite_source_code_links_to_github(body_html)
    # #284: now that README.md and CONTRIBUTING.md compile to
    # site/README.html / site/CONTRIBUTING.html, session bodies that
    # reference those files should route to the compiled pages.
    # Generic .md → .html pass runs AFTER the GitHub rewrite so
    # source-code and repo-root-only refs (CLAUDE.md, AGENTS.md) still
    # go to GitHub.
    body_html = rewrite_md_links_to_html(body_html)
    # #336: for remaining session-local refs (tasks.md, user_profile.md,
    # wiki/sources/<proj>/... wikilinks), drop the anchor but keep the
    # text — they point at files unique to the user's project and don't
    # compile to anywhere on the site.
    body_html = strip_dead_session_refs(body_html)
    raw_md_for_copy = html.escape(body)
    reading_min = calc_reading_time(body)

    bits: list[str] = []
    if meta.get("project"):
        bits.append(
            f'<a href="../../projects/{html.escape(str(meta["project"]))}.html">{html.escape(project_label)}</a>'
        )
    # Agent badge — shows Claude / Codex / Copilot / Cursor / Gemini
    bits.append(render_agent_badge(meta))
    if meta.get("gitBranch"):
        bits.append(f'branch <code>{html.escape(str(meta["gitBranch"]))}</code>')
    if meta.get("model"):
        bits.append(f'<code>{html.escape(str(meta["model"]))}</code>')
    if meta.get("started"):
        bits.append(f'<span class="muted">{html.escape(short_started(meta))}</span>')
    if meta.get("user_messages"):
        bits.append(f'{html.escape(str(meta["user_messages"]))} 条消息')
    if meta.get("tool_calls"):
        bits.append(f'{html.escape(str(meta["tool_calls"]))} 次工具调用')
    bits.append(f'<span class="muted">{reading_min} 分钟阅读</span>')
    bits.append(render_freshness(meta))
    meta_strip = " · ".join(bits) if bits else ""

    tools_list = get_tools_list(meta)
    tools_preview = ""
    if tools_list:
        preview = ", ".join(tools_list[:6])
        if len(tools_list) > 6:
            preview += f", +{len(tools_list) - 6} more"
        tools_preview = f'<div class="meta-tools muted">工具：{html.escape(preview)}</div>'

    # v0.8 (#65): horizontal bar chart of tool calls in this session.
    # Uses the `tool_counts` JSON dict from frontmatter (#63). Empty
    # sessions (no recorded calls) render nothing.
    tool_chart_svg = render_session_tool_chart(meta)
    tool_chart_block = ""
    if tool_chart_svg:
        tool_chart_block = (
            '<div class="tool-chart-card">'
            '<div class="tool-chart-label muted">Tool calls</div>'
            f'{tool_chart_svg}'
            '</div>'
        )

    # v0.8 (#66): session token-usage card. Input / cache_creation /
    # cache_read / output plus a cache-hit-ratio tier badge. Sessions
    # missing token_totals (older converter output) render nothing.
    token_card_block = render_session_token_card(meta)

    # IMPORTANT: The HTML file is named `<path.stem>.html` (e.g. date-slug),
    # NOT `<slug>.html`. The siblings + canonical must use path.stem.
    html_stem = path.stem
    raw_md_path = f"../../sources/{project_slug}/{path.name}"
    actions_html = f"""<div class="session-actions">
  <button class="btn btn-primary" type="button" aria-label="{_ui_text('copy_session_markdown')}" title="{_ui_text('copy_markdown')}" onclick="copyMarkdown(this)">{_ui_text('copy_markdown')}</button>
  <a class="btn" href="../../projects/{html.escape(project_slug)}.html">← {_ui_text('back_to_course')}</a>
  <a class="btn" href="{html.escape(raw_md_path)}" download>{_ui_text('download_md')}</a>
  <a class="btn" href="{html.escape(html_stem + '.txt')}" title="{_ui_text('plain_text_export')}">.txt</a>
  <a class="btn" href="{html.escape(html_stem + '.json')}" title="{_ui_text('json_export')}">.json</a>
  <textarea class="md-source" hidden>{raw_md_for_copy}</textarea>
</div>"""

    crumbs = [
        (_ui_text("home"), "index.html"),
        (_ui_text("project_en"), "projects/index.html"),
        (project_label, f"projects/{project_slug}.html"),
        (str(slug), ""),
    ]
    breadcrumbs = breadcrumbs_bar(crumbs, link_prefix="../../")

    # v0.4: machine-readable metadata appendix (HTML comment that AI agents
    # scraping HTML can parse without fetching the .json sibling).
    metadata_comment = _build_metadata_comment(meta, slug, project_slug, reading_min, html_stem=html_stem)

    # v0.4: page_head with schema.org article microdata + canonical link.
    # Canonical is relative to the current page (same dir) so the link checker
    # resolves it correctly whether served from a subdomain root or any path.
    page = (
        page_head_article(
            title=f"{title_raw} — {_ui_site_name()}",
            description=f"Course lesson from {meta.get('course_title', meta.get('project', ''))} on {date}",
            css_prefix="../../",
            canonical=f"{html_stem}.html",
            date=str(meta.get("started") or date),
            metadata_comment=metadata_comment,
        )
        + nav_bar("sessions", link_prefix="../../")
        + hero(str(title_raw), meta_strip, size="hero-sm", subtitle_is_html=True)
        # #471: human-readable description rendered as a subtitle below
        # the hero, before the meta-strip. Only emit if frontmatter
        # carries the field; older sessions skip this block cleanly.
        + (
            f'<div class="container session-description"><p>{html.escape(str(meta["description"]))}</p></div>'
            if meta.get("description") else ""
        )
        + f'<section class="section">\n  <div class="container">\n{breadcrumbs}\n{tools_preview}\n{actions_html}\n{_session_media_block(meta)}\n{tool_chart_block}\n{token_card_block}\n    <article class="content" itemscope itemtype="https://schema.org/Article">\n'
        + f'<meta itemprop="headline" content="{html.escape(str(title_raw))}">\n'
        + f'<meta itemprop="datePublished" content="{html.escape(str(meta.get("started") or date))}">\n'
        + f'<meta itemprop="inLanguage" content="en">\n'
        + body_html
        + '\n    </article>\n  </div>\n</section>\n</main>\n'
        + page_foot(js_prefix="../../")
    )

    out_path = out_dir / "sessions" / project_slug / f"{path.stem}.html"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page, encoding="utf-8")
    return out_path


def render_project_page(
    project_slug: str,
    sessions: list[tuple[Path, dict[str, Any], str]],
    out_dir: Path,
) -> Path:
    main_sessions = [s for s in sessions if not _is_subagent(s[1], s[0])]

    def card(p: Path, meta: dict[str, Any]) -> str:
        slug = meta.get("slug", p.stem)
        title = meta.get("title", slug)
        # Strip "Session: project/" prefix for cleaner display
        title = _strip_session_like_prefix(str(title))
        date = meta.get("date", "")
        model = meta.get("model", "")
        href = f"../sessions/{project_slug}/{p.stem}.html"
        badge = render_freshness(meta)
        return f"""  <a class="card" href="{href}">
    <div class="card-title">{html.escape(str(title))}</div>
    <div class="card-meta">{html.escape(str(date))} · {html.escape(str(model))}</div>
    <div class="card-badge">{badge}</div>
  </a>"""

    cards_main = "\n".join(card(p, m) for p, m, _ in main_sessions)

    proj_profile = load_project_profile(PROJECTS_META_DIR, project_slug)
    if proj_profile and proj_profile.get("title"):
        project_label = str(proj_profile["title"])
    else:
        project_label = project_slug
        for _path, meta, _body in sessions:
            candidate = meta.get("course_title") or meta.get("title") or ""
            if str(candidate).strip():
                project_label = str(candidate).strip()
                break

    crumbs = breadcrumbs_bar(
        [(_ui_text("home"), "index.html"), (_ui_text("project_en"), "projects/index.html"), (project_label, "")],
        link_prefix="../",
    )

    # v0.8 (#64, #72): per-project 365-day heatmap — same window as the
    # aggregate on the home page, but filtered to just this project's
    # sessions. Sparse projects (only a handful of sessions) still render
    # the full grid with the rest as level-0 cells, so the shape matches.
    proj_entries = [m for _, m, _ in sessions]
    proj_counts = collect_session_counts(proj_entries, project_slug=project_slug)
    proj_heatmap = render_heatmap(proj_counts, title_prefix=f"{project_label}活跃度")
    heatmap_block = f"""<section class="section heatmap-section">
  <div class="container">
    <div class="activity-heatmap">
      <div class="heatmap-label muted">{_ui_text("activity_last_365_days_project").format(name=html.escape(project_label))}</div>
      {proj_heatmap}
    </div>
  </div>
</section>"""

    # v0.8 (#65): aggregate tool-call bar chart across all sessions in
    # this project. Projects with no recorded tool calls render nothing.
    proj_tool_chart = render_project_tool_chart(proj_entries, project_label)
    tool_chart_block = ""
    if proj_tool_chart:
        tool_chart_block = f"""<section class="section tool-chart-section">
  <div class="container">
    <div class="tool-chart-card">
      <div class="tool-chart-label muted">Tool calls · {html.escape(project_label)} aggregate</div>
      {proj_tool_chart}
    </div>
  </div>
</section>"""

    # v0.8 (#66): project token timeline card (log-scale area chart of
    # total tokens per session date + aggregate cache hit ratio in the
    # header). Empty for projects without any token data.
    proj_token_card_html = render_project_token_card(proj_entries, project_label)
    token_timeline_block = ""
    if proj_token_card_html:
        token_timeline_block = f"""<section class="section token-timeline-section">
  <div class="container">
    {proj_token_card_html}
  </div>
</section>"""

    # Project topics strip — renders below the hero, above the heatmap.
    # Explicit profile via wiki/projects/<slug>.md wins over the
    # session-tag fallback. Projects with no topics render an empty
    # strip (no chip row at all).
    proj_topics = get_project_topics(PROJECTS_META_DIR, project_slug, proj_entries)
    topics_html = render_topic_chips(
        proj_topics, max_visible=12, classname="project-topics project-hero-topics"
    )
    description_html = ""
    if proj_profile and proj_profile.get("description"):
        description_html = (
            f'<p class="project-description muted">'
            f'{html.escape(proj_profile["description"])}</p>'
        )
    homepage_html = ""
    if proj_profile and proj_profile.get("homepage"):
        hp = proj_profile["homepage"]
        homepage_html = (
            f'<a class="project-homepage" href="{html.escape(hp)}" '
            f'rel="noopener">{html.escape(hp)} ↗</a>'
        )
    topics_strip = ""
    if topics_html or description_html or homepage_html:
        topics_strip = (
            '<section class="section project-topics-section">\n'
            '  <div class="container">\n'
            f'    {description_html}\n'
            f'    {topics_html}\n'
            f'    {homepage_html}\n'
            '  </div>\n'
            '</section>\n'
        )

    body = f"""{topics_strip}
{heatmap_block}
{tool_chart_block}
{token_timeline_block}
<section class="section">
  <div class="container">
    {crumbs}
    <h2>{_ui_text("lessons_count").format(count=len(main_sessions))}</h2>
    <div class="card-grid">
{cards_main}
    </div>
  </div>
</section>
</main>
"""

    page = (
        page_head(
            f"{project_label} — {_ui_site_name()}",
            f"{project_label} 的 {len(main_sessions)} 节课次",
            css_prefix="../",
        )
        + nav_bar("projects", link_prefix="../")
        + hero(
            project_label,
            _ui_text("lesson_total").format(count=len(main_sessions)),
        )
        + body
        + page_foot(js_prefix="../")
    )

    out_path = out_dir / "projects" / f"{project_slug}.html"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page, encoding="utf-8")
    return out_path


def render_projects_index(
    groups: dict[str, list[tuple[Path, dict[str, Any], str]]],
    out_dir: Path,
) -> Path:
    cards = []
    for project, sessions in sorted(groups.items(), key=lambda x: -len(x[1])):
        proj_profile = load_project_profile(PROJECTS_META_DIR, project)
        if proj_profile and proj_profile.get("title"):
            project_label = str(proj_profile["title"])
        else:
            project_label = project
            for _path, meta, _body in sessions:
                candidate = meta.get("course_title") or meta.get("title") or ""
                if str(candidate).strip():
                    project_label = str(candidate).strip()
                    break
        main_count = sum(1 for p, m, _ in sessions if not _is_subagent(m, p))
        # Freshness reflects the newest session in the project.
        newest_meta = max(
            (m for _, m, _ in sessions),
            key=lambda m: str(m.get("ended") or m.get("started") or m.get("date") or ""),
            default={},
        )
        badge = render_freshness(newest_meta)
        cards.append(
            f"""  <a class="card" href="{html.escape(project)}.html">
    <div class="card-title">{html.escape(project_label)}</div>
    <div class="card-meta" data-lesson-count="{main_count}">{_ui_text("lesson_total").format(count=main_count)}</div>
    <div class="card-badge">{badge}</div>
  </a>"""
        )

    crumbs = breadcrumbs_bar(
        [(_ui_text("home"), "index.html"), (_ui_text("project_en"), "")], link_prefix="../"
    )

    body = f"""<section class="section">
  <div class="container">
    {crumbs}
    <div class="card-grid">
{chr(10).join(cards)}
    </div>
  </div>
</section>
</main>
"""

    page = (
        page_head(f"{_ui_text('projects')} — {_ui_site_name()}", _ui_text("all_courses"), css_prefix="../")
        + nav_bar("projects", link_prefix="../")
        + hero(_ui_text("projects"), _ui_text("course_total").format(count=len(groups)))
        + body
        + page_foot(js_prefix="../")
    )

    out_path = out_dir / "projects" / "index.html"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page, encoding="utf-8")
    return out_path


def render_sessions_index(
    sources: list[tuple[Path, dict[str, Any], str]],
    groups: dict[str, list[tuple[Path, dict[str, Any], str]]],
    out_dir: Path,
) -> Path:
    rows = []

    def key(t: tuple[Path, dict[str, Any], str]) -> str:
        return str(t[1].get("started", "")) or str(t[0].name)

    for p, meta, _ in sorted(sources, key=key, reverse=True):
        project = meta.get("project", p.parent.name)
        proj_profile = load_project_profile(PROJECTS_META_DIR, str(project))
        if proj_profile and proj_profile.get("title"):
            project_label = str(proj_profile["title"])
        else:
            project_label = str(meta.get("course_title") or meta.get("title") or project)
        slug = meta.get("slug", p.stem)
        title = meta.get("title", slug)
        # Strip "Session: " prefix for cleaner display
        title = _strip_session_like_prefix(str(title))
        # #452: titles auto-generated from session frontmatter follow the
        # pattern "<slug> — <date>" but the table already has a dedicated
        # Date column, so the trailing date is redundant. Strip it so the
        # Session cell shows just the slug (or whatever custom title the
        # user gave) and the Date column carries the date alone.
        date = meta.get("date", "")
        if date and title.endswith(f" — {date}"):
            title = title[: -(len(date) + 3)]
        # Truncate long titles for table display
        display_title = title[:70] + "..." if len(title) > 70 else title
        # #471: human-readable description from the first user turn —
        # if frontmatter carries one, render it as a small muted line
        # below the slug. Falls back to no second line for older
        # sessions without the field.
        description = str(meta.get("description") or "").strip()
        desc_line = (
            f'<div class="session-cell-desc muted">{html.escape(description)}</div>'
            if description else ""
        )
        duration_label = _format_duration_label(meta.get("duration_seconds"))
        href = f"{project}/{p.stem}.html"
        rows.append(
            f"""        <tr data-project="{html.escape(str(project))}" data-date="{html.escape(str(date))}" data-slug="{html.escape(str(slug))}">
          <td><a href="{html.escape(str(href))}">{html.escape(str(display_title))}</a>{desc_line}</td>
          <td>{render_agent_badge(meta, max_visible=3)}</td>
          <td><a href="../projects/{html.escape(str(project))}.html">{html.escape(project_label)}</a></td>
          <td>{html.escape(str(date))}</td>
          <td>{html.escape(duration_label)}</td>
        </tr>"""
        )

    project_options = "\n".join(
        f'        <option value="{html.escape(project)}">{html.escape(str((load_project_profile(PROJECTS_META_DIR, project) or {}).get("title") or project))}</option>'
        for project in sorted(groups.keys())
    )

    crumbs = breadcrumbs_bar(
        [(_ui_text("home"), "index.html"), (_ui_text("session_en"), "")], link_prefix="../"
    )

    body = f"""<section class="section">
  <div class="container">
    {crumbs}
    <div class="filter-bar">
      <label>{_ui_text("course")}
        <select id="filter-project">
          <option value="">{_ui_text("all_courses")}</option>
{project_options}
        </select>
      </label>
      <label>{_ui_text("from")}
        <input type="date" id="filter-date-from">
      </label>
      <label>{_ui_text("to")}
        <input type="date" id="filter-date-to">
      </label>
      <label>{_ui_text("lesson")}
        <input type="text" id="filter-text" placeholder="{_ui_text('lesson_search_placeholder')}">
      </label>
      <button class="btn" id="filter-clear">{_ui_text("clear")}</button>
      <span class="filter-count muted" id="filter-count"></span>
    </div>
    <div class="table-wrap">
    <table class="sessions-table">
      <colgroup>
        <col style="width: 38%">
        <col style="width: 8%">
        <col style="width: 22%">
        <col style="width: 12%">
        <col style="width: 20%">
      </colgroup>
      <thead>
        <tr><th>{_ui_text("lesson")}</th><th>{_ui_text("agent")}</th><th>{_ui_text("course")}</th><th>{_ui_text("date")}</th><th>{_ui_text("duration")}</th></tr>
      </thead>
      <tbody id="sessions-tbody">
{chr(10).join(rows)}
      </tbody>
    </table>
    </div>
  </div>
</section>
</main>
"""

    page = (
        page_head(f"{_ui_text('sessions')} — {_ui_site_name()}", _ui_text("all_lessons_newest"), css_prefix="../")
        + nav_bar("sessions", link_prefix="../")
        + hero(_ui_text("all_lessons"), _ui_text("lesson_total").format(count=len(sources)))
        + body
        + page_foot(js_prefix="../")
    )

    out_path = out_dir / "sessions" / "index.html"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page, encoding="utf-8")
    return out_path


def render_index(
    groups: dict[str, list[tuple[Path, dict[str, Any], str]]],
    all_sources: list[tuple[Path, dict[str, Any], str]],
    out_dir: Path,
    synthesis: Optional[str] = None,
) -> Path:
    total = len(all_sources)
    mains = sum(1 for p, m, _ in all_sources if not _is_subagent(m, p))
    subs = total - mains

    synth_block = ""
    if synthesis:
        synth_block = f"""<section class="section">
  <div class="container">
    <div class="synthesis">
      <h2>{_ui_text("overview")}</h2>
      {md_to_html(synthesis)}
    </div>
  </div>
</section>"""

    # v0.8 (#64, #72): aggregate 365-day GitHub-style heatmap. Counts all
    # main sessions across all projects. Rendered as a pure-SVG block just
    # above the projects grid so the landing page gives a glanceable
    # "last year of activity" view.
    heatmap_entries = [m for _, m, _ in all_sources]
    heatmap_counts = collect_session_counts(heatmap_entries)
    heatmap_svg = render_heatmap(heatmap_counts, title_prefix="活跃度")
    heatmap_block = f"""<section class="section heatmap-section">
  <div class="container">
    <div class="activity-heatmap">
      <div class="heatmap-label muted">{_ui_text("activity_last_365_days")}</div>
      {heatmap_svg}
    </div>
  </div>
</section>"""

    # v0.8 (#66): site-wide token summary stats — four cards showing
    # total tokens processed, average per session, best cache hit project,
    # heaviest project. Empty if no session has token_totals data.
    metas_by_project: dict[str, list[dict[str, Any]]] = {}
    for project, sessions in groups.items():
        metas_by_project[project] = [m for _, m, _ in sessions]
    token_stats_block = render_site_token_stats(metas_by_project, link_prefix="")

    # Recently updated — show last 10 entries from wiki/log.md.
    log_events = _recent_log_events(
        REPO_ROOT / "wiki" / "log.md", limit=10
    )
    recent_block_inner = render_recent_activity(log_events)
    recent_block = (
        f'<section class="section recently-updated-section">\n'
        f'  <div class="container">\n'
        f'    {recent_block_inner}\n'
        f'  </div>\n'
        f'</section>\n'
    ) if recent_block_inner else ""

    cards = []
    for project, sessions in sorted(groups.items(), key=lambda x: -len(x[1])):
        main_count = sum(1 for p, m, _ in sessions if not _is_subagent(m, p))
        # Project topics — explicit profile in wiki/projects/<slug>.md
        # takes precedence, falls back to aggregated session tags with
        # noise filtered out. Rendered as chips below the card meta.
        proj_metas = [m for _, m, _ in sessions]
        topics = get_project_topics(PROJECTS_META_DIR, project, proj_metas)
        topics_html = render_topic_chips(topics, max_visible=4,
                                         classname="project-topics card-topics")
        # #455: render the activity date range under the meta line so
        # users can spot fresh vs stale projects without clicking. Pull
        # `date:` from frontmatter (already YYYY-MM-DD strings); ignore
        # missing/blank values; format as `2026-03-12 → 2026-04-01` for
        # multi-day, just `2026-04-01` if first == last.
        dates = sorted(
            {str(m.get("date", "")) for _, m, _ in sessions if m.get("date")}
        )
        if dates:
            if dates[0] == dates[-1]:
                date_range_html = (
                    f'<div class="card-date-range">{html.escape(dates[0])}</div>'
                )
            else:
                date_range_html = (
                    f'<div class="card-date-range">'
                    f'{html.escape(dates[0])} → {html.escape(dates[-1])}'
                    f'</div>'
                )
        else:
            date_range_html = ""
        proj_profile = load_project_profile(PROJECTS_META_DIR, project)
        if proj_profile and proj_profile.get("title"):
            project_label = str(proj_profile["title"])
        else:
            # Fallback: extract course_title from session frontmatter
            # before showing the raw slug (which is often a numeric ID).
            project_label = project
            for _path, meta, _body in sessions:
                candidate = meta.get("course_title") or meta.get("title") or ""
                if str(candidate).strip():
                    project_label = str(candidate).strip()
                    break
        cards.append(
            f"""  <a class="card card-project" href="projects/{html.escape(project)}.html">
    <div class="card-title">{html.escape(project_label)}</div>
    <div class="card-meta" data-lesson-count="{main_count}">{_ui_text("lesson_total").format(count=main_count)}</div>
    {date_range_html}
    {topics_html}
  </a>"""
        )

    body = f"""{heatmap_block}
{token_stats_block}
{recent_block}
<section class="section">
  <div class="container">
    <h2>{_ui_text("projects")}</h2>
    <div class="card-grid">
{chr(10).join(cards)}
    </div>
  </div>
</section>
</main>
"""

    page = (
        page_head(_ui_site_name(), _ui_text("course_knowledge_base"), css_prefix="")
        + nav_bar("home", link_prefix="")
        + hero(
            _ui_site_name(),
            f"{_ui_text('lesson_total').format(count=mains)} · {_ui_text('course_total').format(count=len(groups))}",
            size="hero-home",
        )
        + synth_block
        + body
        + page_foot(js_prefix="")
    )

    out_path = out_dir / "index.html"
    out_path.write_text(page, encoding="utf-8")
    return out_path


def _render_root_md_page(
    src_name: str,
    out_name: str,
    title: str,
    subtitle: str,
    meta_description: str,
    out_dir: Path,
    *,
    active_nav: str = "docs",
) -> Optional[Path]:
    """Compile a repo-root ``.md`` file to a standalone site page (#284).

    Used for ``README.md`` and ``CONTRIBUTING.md`` so visitors don't get
    bounced out to GitHub for content we're already shipping as HTML.
    """
    src = REPO_ROOT / src_name
    if not src.is_file():
        return None
    raw = src.read_text(encoding="utf-8")
    body_md = raw
    lines = raw.splitlines()
    if lines and lines[0].lstrip().startswith("# "):
        body_md = "\n".join(lines[1:]).lstrip("\n")
    content_html = md_to_html(body_md)
    # #270: route embedded source-code + repo-root links to GitHub, then
    # the generic .md→.html pass for anything remaining.  README has
    # plenty of such links.
    from llmwiki.docs_pages import (
        rewrite_md_links_to_html,
        rewrite_source_code_links_to_github,
    )
    content_html = rewrite_source_code_links_to_github(content_html)
    content_html = rewrite_md_links_to_html(content_html)

    body = f"""<section class="section docs-body">
  <div class="container narrow">
    <article class="article docs-article">
      {content_html}
    </article>
  </div>
</section>
</main>
"""
    page = (
        page_head(
            f"{title} — LLM Wiki",
            meta_description,
            css_prefix="",
        )
        + nav_bar(active_nav, link_prefix="")
        + hero(title, subtitle)
        + body
        + page_foot(js_prefix="")
    )
    out_path = out_dir / out_name
    out_path.write_text(page, encoding="utf-8")
    return out_path


def render_404(out_dir: Path) -> Path:
    """Emit ``site/404.html`` with the standard site chrome and a "Page not
    found" panel. Closes #387 U8 — without this, ``llmwiki serve`` falls
    back to the stdlib ``http.server`` default 404 (an unstyled error string
    with no nav). The page itself is not linked from the index, but
    ``serve.py`` injects it as the body of every 404 response.
    """
    head = page_head(
        title=f"{_ui_text('page_not_found')} · llmwiki",
        description=_ui_text("page_not_found_desc"),
    )
    nav = nav_bar(active="")
    foot = page_foot()
    body = f"""<main id="main-content">
<section class="hero">
  <div class="container">
    <h1>{_ui_text("page_not_found")}</h1>
    <p class="hero-sub">{_ui_text("page_not_found_desc")}</p>
  </div>
</section>
<section class="section">
  <div class="container">
    <p>{_ui_text("try_these")}</p>
    <ul class="not-found-links">
      <li><a href="index.html">{_ui_text("home")}</a> — {_ui_text("home_overview")}</li>
      <li><a href="projects/index.html">{_ui_text("projects")}</a> — {_ui_text("projects_overview")}</li>
      <li><a href="sessions/index.html">{_ui_text("sessions")}</a> — {_ui_text("sessions_overview")}</li>
    </ul>
    <p class="muted">{_ui_text("open_palette_hint")}</p>
  </div>
</section>
</main>
"""
    page = head + nav + body + foot
    out_path = out_dir / "404.html"
    out_path.write_text(page, encoding="utf-8")
    return out_path


def render_readme_page(out_dir: Path) -> Optional[Path]:
    """Compile ``README.md`` to ``site/README.html`` (#284)."""
    return _render_root_md_page(
        "README.md", "README.html",
        title="README",
        subtitle="The public README of llmwiki, rendered from `README.md`.",
        meta_description="llmwiki — Karpathy-style LLM wiki from your Claude Code, Codex CLI, Cursor, and Obsidian sessions.",
        out_dir=out_dir,
    )


def render_contributing_page(out_dir: Path) -> Optional[Path]:
    """Compile ``CONTRIBUTING.md`` to ``site/CONTRIBUTING.html`` (#284)."""
    return _render_root_md_page(
        "CONTRIBUTING.md", "CONTRIBUTING.html",
        title="Contributing",
        subtitle="The 8 rules + review bar for contributing to llmwiki.",
        meta_description="Contribution rules, PR checklist, and review bar for llmwiki.",
        out_dir=out_dir,
    )


# ─── changelog page ────────────────────────────────────────────────────────

def render_changelog(out_dir: Path) -> Optional[Path]:
    """Render ``CHANGELOG.md`` (repo root) to ``site/changelog.html``.

    Returns None if CHANGELOG.md is missing. Shown as its own top-level page
    so visitors can see what's new / what shipped without clicking through to
    GitHub. Keep-a-changelog headings become an in-page TOC via the existing
    `toc` markdown extension.
    """
    src = REPO_ROOT / "CHANGELOG.md"
    if not src.exists():
        return None
    raw = src.read_text(encoding="utf-8")

    # Pull the top H1 ("Changelog") and use it as the hero title; render
    # everything else as the body. Strip the leading H1 line to avoid a
    # duplicate title.
    body_md = raw
    lines = raw.splitlines()
    if lines and lines[0].lstrip().startswith("# "):
        body_md = "\n".join(lines[1:]).lstrip("\n")

    content_html = md_to_html(body_md)

    body = f"""<section class="section changelog-body">
  <div class="container narrow">
    <article class="article">
      {content_html}
    </article>
  </div>
</section>
</main>
"""

    page = (
        page_head(
            "Changelog — LLM Wiki",
            "Release notes for llmwiki — features, fixes, and version history.",
            css_prefix="",
        )
        + nav_bar("changelog", link_prefix="")
        + hero(
            "Changelog",
            "Every release, every fix. Keep-a-changelog format, semver.",
        )
        + body
        + page_foot(js_prefix="")
    )

    out_path = out_dir / "changelog.html"
    out_path.write_text(page, encoding="utf-8")
    return out_path


# ─── v0.7 (#55) models section ─────────────────────────────────────────────

def render_models_section(out_dir: Path) -> tuple[Optional[Path], int]:
    """Discover `wiki/entities/*.md` pages with `entity_kind: ai-model`,
    render one detail page per model + a sortable `/models/index.html`.

    Returns `(index_path_or_None, model_count)`. If there's no
    `wiki/entities/` directory OR no model pages there, we still write
    an empty-state index so the nav link doesn't 404.
    """
    # Post-review: imports lazily so this function actually works the
    # next time someone wires it from the CLI. Previously these names
    # were referenced but never imported — function body was reachable
    # but would crash with NameError on first call.
    from llmwiki.models_page import (  # noqa: F401
        discover_model_entities_with_meta,
        render_models_index,
        render_model_info_card,
    )
    entities_dir = REPO_ROOT / "wiki" / "entities"
    entries_with_meta = discover_model_entities_with_meta(entities_dir)
    # Backwards-compatible list without meta for render_models_index.
    entries = [
        (path, profile, warnings, body)
        for path, _meta, profile, warnings, body in entries_with_meta
    ]
    models_out = out_dir / "models"
    models_out.mkdir(parents=True, exist_ok=True)

    # Index page — always write it so the nav link resolves.
    index_body = render_models_index(entries)
    index_page = (
        page_head(
            "Models — LLM Wiki",
            "Directory of AI-model entities tracked by the wiki with pricing, "
            "context windows, and benchmark scores.",
            css_prefix="../",
        )
        + nav_bar("models", link_prefix="../")
        + hero("Models", f"{len(entries)} model entities tracked")
        + index_body
        + "</main>\n"
        + page_foot(js_prefix="../")
    )
    index_path = models_out / "index.html"
    index_path.write_text(index_page, encoding="utf-8")

    # Per-model detail page — info card + body markdown rendered normally.
    for path, meta, profile, warnings, body in entries_with_meta:
        slug = path.stem
        title = profile.get("title", slug)
        info_card = render_model_info_card(profile)

        # v0.7 (#56): changelog timeline + pricing sparkline below the
        # info card. The sparkline only shows if there are ≥2 dated
        # input-price changes in the changelog.
        changelog_entries, changelog_warnings = parse_changelog(meta)
        warnings = list(warnings) + changelog_warnings
        timeline_html = render_changelog_timeline(changelog_entries)
        timeline_block = ""
        if timeline_html:
            price_pts = extract_price_points(
                changelog_entries, field_suffix="pricing.input_per_1m"
            )
            sparkline = render_price_sparkline(price_pts)
            sparkline_block = (
                f'<div class="timeline-sparkline">'
                f'<span class="muted">Input pricing trend</span> {sparkline}'
                f'</div>'
                if sparkline else ""
            )
            timeline_block = (
                '<div class="timeline-card">'
                '<div class="timeline-card-title">Changelog</div>'
                + sparkline_block
                + timeline_html
                + '</div>'
            )

        body_html = md_to_html(body)
        warnings_html = ""
        if warnings:
            items = "".join(f"<li>{html.escape(w)}</li>" for w in warnings)
            warnings_html = (
                '<details class="model-warnings"><summary>Schema warnings '
                f'({len(warnings)})</summary><ul>{items}</ul></details>'
            )
        page = (
            page_head(
                f"{title} — LLM Wiki",
                f"AI-model entity: {title}",
                css_prefix="../",
            )
            + nav_bar("models", link_prefix="../")
            + hero(title, profile.get("provider", ""))
            + f'<section class="section">\n  <div class="container narrow">\n'
            + info_card
            + timeline_block
            + warnings_html
            + f'    <article class="article content">\n      {body_html}\n    </article>\n'
            + '  </div>\n</section>\n</main>\n'
            + page_foot(js_prefix="../")
        )
        (models_out / f"{slug}.html").write_text(page, encoding="utf-8")

    return index_path, len(entries)


# ─── v0.7 (#58) auto-generated vs-comparison pages ────────────────────────

def render_vs_section(
    out_dir: Path,
    max_pairs: int = 500,
    min_shared_fields: int = 3,
) -> tuple[Optional[Path], int]:
    """Generate `/vs/<slug_a>-vs-<slug_b>.html` for every pair of
    comparable model entities + an index at `/vs/index.html`.

    Honors user overrides under `wiki/vs/<slug>.md` — a hand-written
    comparison replaces the auto-gen for that URL. Returns
    `(index_path, pair_count)`. Always writes the index so the nav
    link resolves even when no entities exist.
    """
    # Post-review: lazy imports so this function actually works the
    # next time someone wires it. Previously these names were referenced
    # but never imported — first call would have crashed with NameError.
    from llmwiki.models_page import discover_model_entities  # noqa: F401
    from llmwiki.compare import (  # noqa: F401
        discover_user_overrides,
        generate_pairs,
        pair_slug,
        render_comparison_body,
        render_comparisons_index,
    )
    entities_dir = REPO_ROOT / "wiki" / "entities"
    overrides_dir = REPO_ROOT / "wiki" / "vs"
    entries = discover_model_entities(entities_dir)
    # Strip down to (path, profile) for compare.generate_pairs
    pair_entries = [(p, profile) for p, profile, _w, _b in entries]
    pairs = generate_pairs(
        pair_entries,
        min_shared_fields=min_shared_fields,
        max_pairs=max_pairs,
    )

    vs_out = out_dir / "vs"
    vs_out.mkdir(parents=True, exist_ok=True)

    # Index
    index_body = render_comparisons_index(pairs)
    index_page = (
        page_head(
            "Model comparisons — LLM Wiki",
            "Auto-generated side-by-side comparisons of AI-model entities.",
            css_prefix="../",
        )
        + nav_bar("vs", link_prefix="../")
        + hero("Model comparisons", f"{len(pairs)} auto-generated pairs")
        + index_body
        + "</main>\n"
        + page_foot(js_prefix="../")
    )
    index_path = vs_out / "index.html"
    index_path.write_text(index_page, encoding="utf-8")

    # User overrides replace the auto-gen for matching slugs
    overrides = discover_user_overrides(overrides_dir)

    for pair in pairs:
        slug = pair_slug(pair)
        if slug in overrides:
            # User override — render the raw body through md_to_html
            body_html = md_to_html(overrides[slug])
            article_body = (
                '<section class="section"><div class="container narrow">'
                f'<article class="article content">{body_html}</article>'
                '</div></section>'
            )
        else:
            # Auto-gen — three structured sections
            comparison_body = render_comparison_body(pair)
            article_body = (
                '<section class="section"><div class="container narrow">'
                f'{comparison_body}'
                '</div></section>'
            )

        title = f"{pair['title_a']} vs {pair['title_b']}"
        page = (
            page_head(
                f"{title} — LLM Wiki",
                f"Side-by-side comparison of {title}.",
                css_prefix="../",
            )
            + nav_bar("vs", link_prefix="../")
            + hero(title, f"{pair['score']} shared structured fields")
            + article_body
            + "</main>\n"
            + page_foot(js_prefix="../")
        )
        (vs_out / f"{slug}.html").write_text(page, encoding="utf-8")

    return index_path, len(pairs)


# ─── search index ──────────────────────────────────────────────────────────

def build_search_index(
    sources: list[tuple[Path, dict[str, Any], str]],
    groups: dict[str, list[tuple[Path, dict[str, Any], str]]],
    out_dir: Path,
    *,
    search_mode: str = "auto",
) -> Path:
    """Build a chunked search index for lazy loading (#47).

    Writes:
      search-index.json          — meta entries (projects + pages) + _chunks manifest
                                  + _mode + _tree_eligible_ratio (#53)
      search-chunks/<project>.json — session entries per project, each
                                    carrying heading_max_depth + count_by_depth

    `search_mode` accepts ``auto`` (default, heuristic), ``tree``, or
    ``flat`` — matches the `llmwiki build --search-mode` flag.
    """
    from llmwiki.search_tree import (
        annotate_entry_headings,
        decide_search_mode,
        search_index_footer_badge,
    )
    # ── session entries grouped by project ──
    from llmwiki.search_facets import enrich_entry
    chunks: dict[str, list[dict[str, Any]]] = {}
    for p, meta, body in sources:
        project = str(meta.get("project") or p.parent.name)
        slug = str(meta.get("slug", p.stem))
        plain = md_to_plain_text(body)[:1200]
        entry = {
            "id": f"session:{project}/{p.stem}",
            "url": f"sessions/{project}/{p.stem}.html",
            "title": slug,
            "type": "session",
            "project": project,
            "date": str(meta.get("date", "")),
            "model": str(meta.get("model", "")),
            "body": plain,
        }
        # v1.0 (#161): enrich with facet fields.
        enrich_entry(entry, meta)
        # v1.2 (#53): inject heading depth so the client can tree-walk.
        annotate_entry_headings(entry, body)
        chunks.setdefault(project, []).append(entry)

    # ── write per-project chunks ──
    chunks_dir = out_dir / "search-chunks"
    chunks_dir.mkdir(exist_ok=True)
    chunk_manifest: list[str] = []
    total_chunk_bytes = 0
    for project_slug, entries in sorted(chunks.items()):
        chunk_path = chunks_dir / f"{project_slug}.json"
        data = json.dumps(entries, ensure_ascii=False)
        chunk_path.write_text(data, encoding="utf-8")
        chunk_manifest.append(f"search-chunks/{project_slug}.json")
        total_chunk_bytes += len(data.encode("utf-8"))

    # ── meta index: projects + static pages + chunk manifest ──
    meta_entries: list[dict[str, Any]] = []

    for project, sessions in groups.items():
        meta_entries.append(
            {
                "id": f"project:{project}",
                "url": f"projects/{project}.html",
                "title": project,
                "type": "project",
                "project": project,
                "date": "",
                "model": "",
                "body": f"{len(sessions)} sessions",
            }
        )

    meta_entries.append(
        {"id": "home", "url": "index.html", "title": _ui_text("home"), "type": "page",
         "project": "", "date": "", "model": "", "body": "overview index"}
    )
    meta_entries.append(
        {"id": "projects-index", "url": "projects/index.html", "title": _ui_text("projects"),
         "type": "page", "project": "", "date": "", "model": "", "body": "all projects"}
    )
    meta_entries.append(
        {"id": "sessions-index", "url": "sessions/index.html", "title": "All sessions",
         "type": "page", "project": "", "date": "", "model": "", "body": "sortable sessions table"}
    )

    # #277: index every docs/ page + every slash command so the palette
    # becomes a universal quick-find (not just sessions + projects).
    from llmwiki.docs_pages import iter_docs_pages, _first_paragraph
    docs_dir = REPO_ROOT / "docs"
    if docs_dir.is_dir():
        for page in iter_docs_pages(docs_dir):
            meta_entries.append({
                "id": f"docs:{page.rel}",
                "url": f"docs/{page.rel.replace('.md', '.html')}",
                "title": page.title,
                "type": "docs",
                "project": "",
                "date": "",
                "model": "",
                "body": _first_paragraph(page.body)[:300],
            })

    # Slash commands — read the first non-empty line of each .md as
    # the description so the palette shows what each /wiki-* does.
    slash_dir = REPO_ROOT / ".claude" / "commands"
    if slash_dir.is_dir():
        for p in sorted(slash_dir.glob("*.md")):
            try:
                text = p.read_text(encoding="utf-8")
            except OSError:
                continue
            first_para = next(
                (ln.strip() for ln in text.splitlines() if ln.strip()),
                "",
            )
            meta_entries.append({
                "id": f"slash:{p.stem}",
                # Slashes aren't URLs — the palette shows a non-clickable
                # entry with the command to type inside Claude Code.
                "url": "",
                "title": f"/{p.stem}",
                "type": "slash",
                "project": "",
                "date": "",
                "model": "",
                "body": first_para[:300],
            })

    # v1.0 (#161): aggregate facet counts across all session chunks so the
    # client can render filter checkboxes without scanning the full index.
    from llmwiki.search_facets import aggregate_facets
    all_entries: list[dict[str, Any]] = []
    for chunk_entries in chunks.values():
        all_entries.extend(chunk_entries)
    facets = aggregate_facets(all_entries)

    # v1.2 (#53): decide tree vs flat across *all* entries, surface
    # the ratio so the client can show it in the palette footer.
    mode, tree_ratio = decide_search_mode(all_entries, override=search_mode)
    mode_badge = search_index_footer_badge(mode, tree_ratio)

    index_obj = {
        "entries": meta_entries,
        "_chunks": chunk_manifest,
        "_facets": facets,
        "_mode": mode,
        "_tree_eligible_ratio": round(tree_ratio, 4),
        "_mode_badge": mode_badge,
    }
    out_path = out_dir / "search-index.json"
    out_path.write_text(json.dumps(index_obj, ensure_ascii=False), encoding="utf-8")

    meta_kb = len(json.dumps(index_obj).encode("utf-8")) // 1024
    chunks_kb = total_chunk_bytes // 1024
    print(
        f"  wrote search-index.json ({meta_kb} KB meta) + "
        f"{len(chunk_manifest)} chunks ({chunks_kb} KB total) · {mode_badge}"
    )

    return out_path


# ─── css + js constants ────────────────────────────────────────────────────

# ─── css + js ────────────────────────────────────────────────────────────
# CSS + JS constants live in llmwiki/render/ since v1.1 (#217). Re-export
# here for backwards compatibility — any external caller still doing
# `from llmwiki.build import CSS` keeps working.
from llmwiki.render.css import CSS  # noqa: F401 (re-exported)
from llmwiki.render.js import JS  # noqa: F401 (re-exported)



# ─── claude synthesis (optional) ───────────────────────────────────────────

# #421: shell metacharacters that have no business in a path-to-an-
# executable. We refuse paths containing any of these rather than
# trying to escape them — the CLI argv is never shell-interpreted
# (we use list-form subprocess.run), but the same path may end up in
# user-facing logs, scripts, or future code paths that *do* interpolate.
# Reject loudly to keep hygiene tight.
# #sec-6 (#550): extended to reject NUL + control chars + unprintable
# bytes. The original list caught the obvious shell-special characters;
# control chars (0x00–0x1F minus tab) get rejected too because they
# survive the rejection of `\n` and `\r` only by accident, and can
# break log parsers / shell prompts in subtle ways.
_PATH_SHELL_METACHARS = re.compile(r"[;&|`$<>\n\r\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def _resolve_claude_path(claude_path: Optional[str]) -> Optional[Path]:
    """Resolve and validate the ``--claude`` path (#421).

    Returns ``None`` when:
      - The path is empty or contains shell metacharacters (rejected loudly).
      - ``shutil.which`` can't find the binary on PATH (when no path passed).
      - The resolved path doesn't exist on disk.

    Returns a ``Path`` when the binary is found and looks safe. Callers
    should treat ``None`` as "skip synthesis" — the synth step is best-
    effort and never fatal.
    """
    if claude_path:
        # Reject explicit paths containing shell metacharacters even
        # though argv is list-form — this keeps the path safe to log.
        if _PATH_SHELL_METACHARS.search(claude_path):
            print(
                f"  warning: refusing claude path with shell metacharacters: "
                f"{claude_path!r}",
                file=sys.stderr,
            )
            return None
        candidate = Path(claude_path)
    else:
        # No explicit path: use shutil.which so PATH-based lookups
        # (homebrew, asdf, npm-global, Windows %PATH%) all just work.
        import shutil as _shutil
        found = _shutil.which("claude")
        if not found:
            return None
        candidate = Path(found)
    if not candidate.exists():
        print(f"  warning: claude CLI not found at {candidate}", file=sys.stderr)
        return None
    return candidate


# #486: validate slug shape before it lands in the synthesize_overview
# prompt. Anything that doesn't match this is replaced by `_invalid_`.
# - Length cap 80 chars (real slugs are far shorter)
# - Charset: alphanumerics + `.`, `_`, `-` (no whitespace, no shell
#   metachars, no NUL bytes, no unicode-confusable categories)
_SAFE_SLUG_RE = re.compile(r"^[A-Za-z0-9._-]{1,80}$")

# #486: cap the total prompt size sent to the claude CLI. 32 KB is well
# inside any LLM's context, well inside macOS's ~256 KB argv limit, and
# small enough that a malicious large slug list can't push the prompt
# past the OS argv limit. (We also pass via stdin below so this is
# defence-in-depth.)
_MAX_OVERVIEW_PROMPT_BYTES = 32_000


def _validate_overview_slug(s: Any) -> str:
    """Return ``s`` if it's a safe slug, ``"_invalid_"`` otherwise.

    #486: a malicious .jsonl could land arbitrary content in the
    `slug` field of a session's frontmatter. That string then ends
    up inside the prompt sent to the claude CLI for overview
    synthesis. Without validation, an attacker-controlled slug could:
    - inject prompt text ("ignore previous instructions, …")
    - contain `\\x00` and crash subprocess.run with a ValueError
    - balloon argv past the OS limit (~256 KB on macOS)
    Replace anything sketchy with the literal `_invalid_` so the
    prompt stays well-formed and the synthesis output stays
    trustworthy.
    """
    if not isinstance(s, str):
        return "_invalid_"
    if not _SAFE_SLUG_RE.match(s):
        return "_invalid_"
    return s


def synthesize_overview(
    groups: dict[str, list[tuple[Path, dict[str, Any], str]]],
    claude_path: str,
) -> Optional[str]:
    resolved = _resolve_claude_path(claude_path)
    if resolved is None:
        return None
    claude_path = str(resolved)

    lines: list[str] = [
        "You are writing a short (200-300 word) overview for a personal knowledge-base",
        "landing page. Below is a JSON summary of the user's Claude Code session history",
        "across multiple projects. Write 2-3 paragraphs of prose in markdown that:",
        "  1. Names the main projects and what each is about (infer from session slugs and tool usage)",
        "  2. Highlights the busiest project(s) and the overall scale of the work",
        "  3. Is written in third person, referring to the user as 'the developer'",
        "Do NOT use bullet points. Just 2-3 short paragraphs of prose.",
        "",
        "Data:",
        "",
    ]
    brief: dict[str, Any] = {}
    for project, sessions in sorted(groups.items()):
        brief[project] = {
            "session_count": len(sessions),
            "main_sessions": sum(1 for p, m, _ in sessions if not _is_subagent(m, p)),
            "dates": sorted({str(m.get("date", "")) for _, m, _ in sessions if m.get("date")}),
            "models": sorted({str(m.get("model", "")) for _, m, _ in sessions if m.get("model")}),
            # #486: every slug filtered through the safe-slug regex so
            # malicious .jsonl content can't prompt-inject or crash
            # subprocess.run via embedded NUL bytes.
            "slugs": [_validate_overview_slug(m.get("slug", p.stem)) for p, m, _ in sessions[:8]],
        }
    prompt = "\n".join(lines) + json.dumps(brief, indent=2)

    # #486: cap total prompt size so a malicious large slug list can't
    # push the prompt past the OS argv limit. Truncation is fine here —
    # the LLM gets the head of the JSON and produces a partial overview;
    # better than a build that silently fails.
    if len(prompt.encode("utf-8")) > _MAX_OVERVIEW_PROMPT_BYTES:
        prompt = prompt.encode("utf-8")[:_MAX_OVERVIEW_PROMPT_BYTES].decode(
            "utf-8", errors="ignore"
        )

    print("  calling claude CLI for overview synthesis…")
    try:
        # #486: pass the prompt via stdin (`-p -`) instead of argv so we
        # dodge the OS argv-length limit entirely. The byte cap above is
        # defence-in-depth — argv-length DoS path closed regardless.
        result = subprocess.run(
            [claude_path, "-p", "-", "--model", "claude-haiku-4-5-20251001"],
            input=prompt,
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        print("  warning: claude CLI timed out after 120s", file=sys.stderr)
        return None
    # #py-m4 (#590): narrow `except Exception` to the families we
    # actually expect from a subprocess call. Catching MemoryError or
    # ImportError silently here would mask real failures.
    except (OSError, subprocess.SubprocessError) as e:
        print(f"  warning: claude CLI failed: {e}", file=sys.stderr)
        return None
    if result.returncode != 0:
        print(f"  warning: claude CLI exited {result.returncode}", file=sys.stderr)
        return None
    return result.stdout.strip() or None


# ─── main ──────────────────────────────────────────────────────────────────

def build_site(
    out_dir: Path = DEFAULT_OUT_DIR,
    synthesize: bool = False,
    claude_path: str = "",
    search_mode: str = "auto",
    seed_project_stubs: bool = False,
) -> int:
    if not RAW_SESSIONS.exists():
        print(
            f"error: {RAW_SESSIONS} does not exist. Run `llmwiki init` + `llmwiki sync` first.",
            file=sys.stderr,
        )
        return 2

    print(f"==> scanning {RAW_SESSIONS}")
    sources = discover_sources(RAW_SESSIONS)
    if not sources:
        print("  no sources found.", file=sys.stderr)
        return 2
    print(f"  found {len(sources)} source markdowns")
    groups = group_by_project(sources)
    print(f"  grouped into {len(groups)} projects")

    # #414: stub-seeding used to be unconditional. `build` is documented
    # as read-only on `wiki/`, but seeding wrote to `wiki/projects/` —
    # CI users running `llmwiki build` on a curated checkout discovered
    # surprise commits in their working tree. Now opt-in: callers that
    # have already accepted mutation (sync, the new `--seed-project-stubs`
    # flag) request seeding explicitly; the default `build` is pure.
    if seed_project_stubs:
        stubs_written = ensure_project_stubs(groups, PROJECTS_META_DIR)
        if stubs_written:
            print(f"  seeded {len(stubs_written)} new wiki/projects/ stubs")

    # Reset output dir (clear contents only — the HTTP server may be cwd'd here)
    # #py-m12 (#598): drop ignore_errors=True. A failure to remove a
    # site/ subtree means we'll write a corrupted partial site on top
    # of stale files; users have hit this when one CI runner left a
    # read-only directory behind. Surface OSError instead so the build
    # halts with a clear message.
    if out_dir.exists():
        rmtree_errors: list[str] = []

        def _on_rmtree_error(func, path, exc_info):
            err = exc_info[1] if isinstance(exc_info, tuple) else exc_info
            rmtree_errors.append(f"{path}: {err}")

        for child in out_dir.iterdir():
            if child.is_dir():
                # Python 3.12+ uses onexc; pre-3.12 uses onerror. Use
                # onerror for back-compat with the 3.9 floor.
                shutil.rmtree(child, onerror=_on_rmtree_error)
            else:
                try:
                    child.unlink()
                except OSError as e:
                    rmtree_errors.append(f"{child}: {e}")
        if rmtree_errors:
            raise OSError(
                "could not reset site dir " + str(out_dir) + ":\n  "
                + "\n  ".join(rmtree_errors)
            )
    else:
        out_dir.mkdir(parents=True)

    # CSS + JS
    (out_dir / "style.css").write_text(CSS, encoding="utf-8")
    (out_dir / "script.js").write_text(JS, encoding="utf-8")
    print("  wrote style.css, script.js")

    # Copy raw markdown files for "Download .md" links
    sources_out = out_dir / "sources"
    if sources_out.exists():
        shutil.rmtree(sources_out)
    shutil.copytree(RAW_SESSIONS, sources_out)
    print(f"  copied raw .md sources to sources/")

    # Copy raw non-session assets (e.g. Tongji subtitle/timeline files)
    # into site/raw so session pages can fetch them with stable relative URLs.
    raw_public_out = out_dir / "raw"
    if raw_public_out.exists():
        shutil.rmtree(raw_public_out)
    raw_public_out.mkdir(parents=True, exist_ok=True)
    raw_public_count = 0
    for child in RAW_DIR.iterdir():
        if child.name == "sessions":
            continue
        target = raw_public_out / child.name
        if child.is_dir():
            shutil.copytree(child, target)
            raw_public_count += sum(1 for p in target.rglob("*") if p.is_file())
        elif child.is_file():
            shutil.copy2(child, target)
            raw_public_count += 1
    if raw_public_count:
        print(f"  copied {raw_public_count} raw support files to raw/")

    image_count = _copy_site_images(out_dir)
    if image_count:
        print(f"  copied {image_count} site images to images/")

    # v0.7 (#96): copy downloaded image assets into site/assets/
    raw_assets = RAW_DIR / "assets"
    if raw_assets.exists() and any(raw_assets.iterdir()):
        site_assets = out_dir / "assets"
        if site_assets.exists():
            shutil.rmtree(site_assets)
        shutil.copytree(raw_assets, site_assets)
        asset_count = sum(1 for _ in site_assets.iterdir() if _.is_file())
        print(f"  copied {asset_count} image assets to assets/")

    # Synthesis
    synthesis = None
    if synthesize:
        synthesis = synthesize_overview(groups, claude_path)
        if synthesis:
            print(f"  synthesis: {len(synthesis)} chars")

    # Render pages — single pass over `sources` (#py-m8 / #594).
    # Sibling writes (.txt + .json) happen inside the same iteration so
    # we don't re-walk `sources` later. The exporter import is hoisted
    # ABOVE the loop with try/except: a missing module degrades to "no
    # siblings on any session" (the import-fail case is truly fatal —
    # no sense retrying it per-source).
    #
    # #v1378-review (architect + python-reviewer): per-source write
    # failures are now isolated. The previous version set a single
    # `siblings_failed` flag on the first OSError/ValueError/
    # RuntimeError and silently dropped sibling writes for EVERY
    # subsequent session in the loop — a single bad body on session 3
    # of 500 produced 497 silently missing siblings. Now each source's
    # sibling write is wrapped individually and collects errors into
    # a list; the build proceeds and we print a summary at the end.
    sibling_writers_loaded = True
    sibling_import_error: Optional[BaseException] = None
    try:
        from llmwiki.exporters import write_page_json, write_page_txt
    except (ImportError, OSError, ValueError, RuntimeError) as e:
        sibling_writers_loaded = False
        sibling_import_error = e

    n_sessions = 0
    n_siblings = 0
    sibling_failures: list[tuple[str, BaseException]] = []
    _wikilink_re = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]")
    for path, meta, body in sources:
        project = str(meta.get("project") or path.parent.name)
        render_session(path, meta, body, out_dir, project)
        n_sessions += 1

        if not sibling_writers_loaded:
            continue
        # render_session writes site/sessions/<project>/<stem>.html;
        # mirror its path here so the siblings land alongside it.
        html_path = out_dir / "sessions" / project / f"{path.stem}.html"
        if not html_path.exists():
            continue
        try:
            body_stripped = strip_leading_h1(body)
            wikilinks_out = _wikilink_re.findall(body_stripped)
            write_page_txt(html_path, body_stripped)
            n_siblings += 1
            meta_copy = dict(meta)
            meta_copy.setdefault("slug", str(meta.get("slug", path.stem)))
            meta_copy.setdefault("project", project)
            write_page_json(html_path, meta_copy, body_stripped, wikilinks_out)
            n_siblings += 1
        except (OSError, ValueError, RuntimeError) as e:
            # Isolate to this source — the next iteration still attempts
            # both writes. n_siblings increments only after each
            # successful write so the count never over-reports.
            sibling_failures.append((str(html_path), e))

    # Print warnings BEFORE the success line so a CI log scanner sees
    # them in the right order (architect-review feedback).
    if not sibling_writers_loaded:
        print(
            f"  warning: per-page siblings disabled (exporter import failed): "
            f"{sibling_import_error}",
            file=sys.stderr,
        )
    if sibling_failures:
        first_path, first_err = sibling_failures[0]
        print(
            f"  warning: per-page sibling write failed on "
            f"{len(sibling_failures)} of {n_sessions} sessions; "
            f"first failure: {first_path}: {first_err}",
            file=sys.stderr,
        )
    print(f"  wrote {n_sessions} session pages")
    if sibling_writers_loaded:
        print(f"  wrote {n_siblings} per-page siblings (.txt + .json)")

    for project, sessions in groups.items():
        render_project_page(project, sessions, out_dir)
    print(f"  wrote {len(groups)} project pages")

    render_projects_index(groups, out_dir)
    render_sessions_index(sources, groups, out_dir)
    render_index(groups, sources, out_dir, synthesis=synthesis)
    cl_path = render_changelog(out_dir)
    # #387 U8: branded 404 page that serve.py returns as the body of any
    # 404 response, instead of the stdlib http.server default.
    not_found_path = render_404(out_dir)
    # #284: compile README + CONTRIBUTING as standalone site pages so
    # they don't bounce visitors out to GitHub for content we're already
    # shipping as HTML.
    readme_path = render_readme_page(out_dir)
    contributing_path = render_contributing_page(out_dir)
    print(
        "  wrote index.html, projects/index.html, sessions/index.html, 404.html"
        + (", changelog.html" if cl_path else "")
    )

    # Search index (chunked — #47) + tree/flat auto-routing (#53)
    idx_path = build_search_index(sources, groups, out_dir, search_mode=search_mode)

    # v0.4: AI-consumable exports (llms.txt, llms-full.txt, graph.jsonld,
    # sitemap.xml, rss.xml, robots.txt, ai-readme.md)
    # #py-m4 (#590): narrow the catch so MemoryError, ImportError,
    # and KeyboardInterrupt aren't silently swallowed into a warning
    # line. ImportError in particular hides a broken module — the
    # build should crash loud, not log "warning: AI exports failed:
    # No module named ..." and ship a half-built site.
    try:
        from llmwiki.exporters import export_all
        ai_paths = export_all(out_dir, groups, sources)
        print(f"  wrote {len(ai_paths)} AI-consumable exports: {', '.join(sorted(ai_paths.keys()))}")
    except (OSError, ValueError, RuntimeError) as e:
        print(f"  warning: AI exports failed: {e}", file=sys.stderr)

    # v1.1 (#118): copy the interactive knowledge graph into the site
    # so the "Graph" nav link works without a separate `llmwiki graph` step.
    try:
        from llmwiki.graph import copy_to_site as copy_graph_to_site
        graph_path = copy_graph_to_site(out_dir)
        if graph_path:
            print(f"  wrote {graph_path.relative_to(out_dir.parent)} (interactive graph viewer)")
    except (OSError, ValueError, RuntimeError) as e:
        print(f"  warning: graph viewer copy failed: {e}", file=sys.stderr)

    # v1.2 (#265): compile the editorial docs (tutorials + hub) under
    # site/docs/. Only pages with `docs_shell: true` in frontmatter
    # are included — reference docs that stay GitHub-rendered aren't
    # touched.
    try:
        from llmwiki.docs_pages import compile_docs_site
        docs_dir = REPO_ROOT / "docs"

        # nav_builder gets called per-page with the right link_prefix so
        # the nav bar's hrefs resolve from whatever depth the page sits at.
        def _docs_nav(link_prefix: str) -> str:
            return nav_bar(active="docs", link_prefix=link_prefix)

        docs_written = compile_docs_site(
            docs_dir,
            out_dir,
            md_to_html=md_to_html,
            page_head=page_head,
            nav_builder=_docs_nav,
        )
        if docs_written:
            print(
                f"  wrote site/docs/ ({len(docs_written)} editorial pages: "
                "hub + tutorials + style guide)"
            )
    # #py-m4: same narrow-catch pattern as above.
    except (OSError, ValueError, RuntimeError) as e:
        print(f"  warning: docs compile failed: {e}", file=sys.stderr)

    # v0.4 per-page sibling .txt and .json — collapsed into the
    # render_session loop above (#py-m8 / #594). The duplicate walk and
    # html_path.exists() guard are gone; siblings now write inside the
    # same iteration that produced the HTML.

    # v0.4: Build manifest with SHA-256 hashes
    try:
        from llmwiki.manifest import write_manifest
        manifest_path = write_manifest(out_dir)
        print(f"  wrote {manifest_path.relative_to(out_dir.parent) if manifest_path.is_relative_to(out_dir.parent) else manifest_path.name}")
    except (OSError, ValueError, RuntimeError) as e:
        print(f"  warning: manifest failed: {e}", file=sys.stderr)

    total_files = sum(1 for _ in out_dir.rglob("*.html"))
    total_bytes = sum(p.stat().st_size for p in out_dir.rglob("*") if p.is_file())
    print(
        f"==> build complete: {total_files} HTML files, {total_bytes / 1024:.0f} KB total"
    )
    print(f"    output: {out_dir}")
    return 0


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    p.add_argument("--synthesize", action="store_true")
    p.add_argument("--claude", type=str, default="")
    p.add_argument("--seed-project-stubs", action="store_true", help="Auto-seed missing wiki/projects/*.md stubs")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    return build_site(
        out_dir=args.out,
        synthesize=args.synthesize,
        claude_path=args.claude,
        seed_project_stubs=args.seed_project_stubs,
    )


if __name__ == "__main__":
    sys.exit(main())

# ─── agent icon detection ────────────────────────────────────────────────

_FALLBACK_AGENT_ICON_SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" '
    'stroke-width="2.75" stroke="currentColor" aria-hidden="true">'
    '<path stroke-linecap="round" stroke-linejoin="round" '
    'd="m6.75 7.5 3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0 0 21 18V6a2.25 2.25 0 0 0-2.25-2.25H5.25A2.25 2.25 0 0 0 3 6v12a2.25 2.25 0 0 0 2.25 2.25Z" />'
    "</svg>"
)


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
        "obsidian": "obsidian",
    }
    return mapping.get(raw, raw)


def _agent_meta(agent: str) -> dict[str, str]:
    normalized = _normalize_agent_name(agent)
    icon_url = "https://unpkg.com/@lobehub/icons-static-svg@latest/icons/{name}.svg"
    png_url = "https://unpkg.com/@lobehub/icons-static-png@latest/light/{name}.png"
    mapping = {
        "codex": {
            "label": "Codex",
            "class": "agent-codex",
            "image": icon_url.format(name="codex-color"),
        },
        "claude": {
            "label": "Claude",
            "class": "agent-claude",
            "image": icon_url.format(name="claude-color"),
        },
        "copilot": {
            "label": "Copilot",
            "class": "agent-copilot",
            "image": icon_url.format(name="githubcopilot"),
        },
        "cursor": {
            "label": "Cursor",
            "class": "agent-cursor",
            "image": png_url.format(name="cursor"),
        },
        "gemini-cli": {
            "label": "Gemini CLI",
            "class": "agent-gemini",
            "image": icon_url.format(name="gemini-color"),
        },
        "openclaw": {
            "label": "OpenClaw",
            "class": "agent-openclaw",
            "image": icon_url.format(name="openclaw-color"),
        },
        "opencode": {
            "label": "OpenCode",
            "class": "agent-opencode",
            "image": icon_url.format(name="opencode"),
        },
        "hermes-agent": {
            "label": "Hermes Agent",
            "class": "agent-hermes",
            "image": icon_url.format(name="nousresearch"),
        },
        "obsidian": {
            "label": "Obsidian",
            "class": "agent-obsidian",
            "image": "",
        },
    }
    meta = mapping.get(normalized)
    if meta:
        return meta
    label = " ".join(part.capitalize() for part in re.split(r"[-_]+", normalized or "agent") if part) or "Agent"
    return {"label": label, "class": "agent-unknown", "image": ""}


def _agent_sequence_from_meta(meta: dict[str, Any]) -> list[str]:
    raw_agents = meta.get("agents")
    if isinstance(raw_agents, list):
        items = raw_agents
    elif isinstance(raw_agents, str) and raw_agents.strip():
        items = [part.strip() for part in raw_agents.split(",")]
    else:
        items = []
    primary = _normalize_agent_name(str(meta.get("agent") or ""))
    if primary:
        items = [primary, *items]
    seen: set[str] = set()
    normalized: list[str] = []
    for item in items:
        agent = _normalize_agent_name(str(item or ""))
        if agent and agent not in seen:
            seen.add(agent)
            normalized.append(agent)
    if normalized:
        return normalized

    model = str(meta.get("model", "")).lower()
    source = str(meta.get("source_file", "")).lower()
    tags = meta.get("tags", [])
    tag_str = " ".join(str(t).lower() for t in tags) if isinstance(tags, list) else str(tags).lower()
    fallbacks = (
        ("claude", ("claude" in model or "claude" in source or ".claude" in source or "claude" in tag_str)),
        ("codex", ("gpt" in model or "o1" in model or "o3" in model or "o4" in model or "codex" in source or ".codex" in source or "codex" in tag_str)),
        ("gemini-cli", ("gemini" in model or "gemini" in source)),
        ("copilot", ("copilot" in model or "copilot" in source or "copilot" in tag_str)),
        ("cursor", ("cursor" in source)),
    )
    for agent, matched in fallbacks:
        if matched:
            return [agent]
    return ["unknown"]


def render_agent_badge(meta: dict, *, max_visible: int | None = None) -> str:
    agents = _agent_sequence_from_meta(meta)
    visible_agents = agents[:max_visible] if max_visible and max_visible > 0 else agents
    hidden_count = max(0, len(agents) - len(visible_agents))
    items: list[str] = []
    labels: list[str] = []
    for index, agent in enumerate(visible_agents):
        spec = _agent_meta(agent)
        labels.append(spec["label"])
        icon_inner = (
            f'<img src="{html.escape(spec["image"])}" alt="" loading="lazy" decoding="async">'
            if spec["image"]
            else _FALLBACK_AGENT_ICON_SVG
        )
        items.append(
            f'<span class="agent-badge {html.escape(spec["class"])}" '
            f'title="{html.escape(spec["label"])}" aria-hidden="true" '
            f'style="z-index:{len(visible_agents) - index};">{icon_inner}</span>'
        )
    label = ", ".join(labels) if labels else "Agent"
    overflow = ""
    if hidden_count:
        label = f"{label}, +{hidden_count} more"
        overflow = (
            f'<span class="agent-badge-overflow" aria-hidden="true" '
            f'title="+{hidden_count}">+{hidden_count}</span>'
        )
    return (
        f'<span class="agent-badge-stack" aria-label="{html.escape(label)}" '
        f'title="{html.escape(label)}">'
        + "".join(items)
        + overflow
        + f'<span class="sr-only">{html.escape(label)}</span>'
        + "</span>"
    )
