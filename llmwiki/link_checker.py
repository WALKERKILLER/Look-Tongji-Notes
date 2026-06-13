"""Link checker (v0.4).

Walks every HTML file under `site/` and verifies every internal link
(href + src) resolves to a file that actually exists. Reports broken
links with the source page + line number.

External links (http/https) are not checked — the tool stays offline.
Stdlib only.

Usage:

    python3 -m llmwiki check-links
    python3 -m llmwiki check-links --site-dir ./site --fail-on-broken
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from llmwiki import REPO_ROOT

# Only match actual anchor-tag hrefs, not URLs that happen to appear inside
# <code> blocks or tool-result output. We require a <a ... href="..."> shape
# and we cap the URL at 512 chars to avoid runaway matches on pathological
# rendered output.
ANCHOR_HREF_RE = re.compile(r'<a\b[^>]*?\bhref="([^"#?]{1,512})"[^>]*>')
LINK_HREF_RE = re.compile(r'<link\b[^>]*?\bhref="([^"#?]{1,512})"[^>]*>')
SCRIPT_SRC_RE = re.compile(r'<script\b[^>]*?\bsrc="([^"#?]{1,512})"[^>]*>')
STYLE_HREF_RE = re.compile(r'<link\b[^>]*?\bhref="([^"#?]{1,512})"[^>]*rel="stylesheet"')

DEFAULT_SITE_DIR = REPO_ROOT / "site"


def is_external(url: str) -> bool:
    return url.startswith(("http://", "https://", "//", "mailto:", "javascript:"))


def resolve_target(source_file: Path, href: str, site_dir: Path) -> Path:
    """Resolve a relative href from source_file to a Path under site_dir."""
    if href.startswith("/"):
        return (site_dir / href.lstrip("/")).resolve()
    return (source_file.parent / href).resolve()


def check_site(site_dir: Path) -> dict[str, Any]:
    """Return a dict with counts + broken link list."""
    if not site_dir.exists():
        return {"error": f"{site_dir} does not exist", "broken": []}

    total_links = 0
    broken: list[dict[str, Any]] = []
    external_skipped = 0

    for html_file in sorted(site_dir.rglob("*.html")):
        try:
            content = html_file.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        # Combine anchor + link + script src patterns
        matches: list[tuple[re.Match[str], str]] = []
        for m in ANCHOR_HREF_RE.finditer(content):
            matches.append((m, "a"))
        for m in LINK_HREF_RE.finditer(content):
            matches.append((m, "link"))
        for m in SCRIPT_SRC_RE.finditer(content):
            matches.append((m, "script"))

        for match, _tag in matches:
            url = match.group(1).strip()
            # Skip anything with newlines — it's definitely from a truncated
            # code block accidentally rendered as a link
            if not url or "\n" in url or len(url) > 512:
                continue
            total_links += 1
            if is_external(url):
                external_skipped += 1
                continue
            # Skip fragment-only links
            if url.startswith("#"):
                continue
            try:
                target = resolve_target(html_file, url, site_dir)
            except (OSError, ValueError):
                continue
            # Skip anything whose resolved path name is > 250 chars (filesystem limit)
            if len(target.name) > 250:
                continue
            if not target.exists():
                line_num = content[: match.start()].count("\n") + 1
                broken.append(
                    {
                        "source": str(html_file.relative_to(site_dir)),
                        "line": line_num,
                        "href": url,
                        "resolved": str(target.relative_to(site_dir)) if target.is_relative_to(site_dir) else str(target),
                    }
                )

    return {
        "site_dir": str(site_dir),
        "total_links": total_links,
        "external_skipped": external_skipped,
        "internal_checked": total_links - external_skipped,
        "broken_count": len(broken),
        # #336: expose all broken entries (capped list was misleading —
        # hid the reduction when a fix dropped the head but tail
        # reshuffled).  ``broken_count`` has always been exact; now
        # ``broken`` matches it instead of silently truncating at 100.
        "broken": broken,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site-dir", type=Path, default=DEFAULT_SITE_DIR)
    parser.add_argument("--fail-on-broken", action="store_true", help="Exit non-zero if any broken links")
    parser.add_argument("--limit", type=int, default=20, help="Max broken links to print")
    args = parser.parse_args(argv)

    report = check_site(args.site_dir)
    if "error" in report:
        print(f"error: {report['error']}", file=sys.stderr)
        return 2

    print(f"==> link check — {report['site_dir']}")
    print(f"    internal links checked: {report['internal_checked']}")
    print(f"    external links skipped: {report['external_skipped']}")
    print(f"    broken: {report['broken_count']}")

    if report["broken"]:
        print()
        print("  Broken links:")
        for entry in report["broken"][: args.limit]:
            print(f"    {entry['source']}:{entry['line']}  →  {entry['href']}")
        if report["broken_count"] > args.limit:
            print(f"    ... and {report['broken_count'] - args.limit} more")

    if args.fail_on_broken and report["broken_count"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
