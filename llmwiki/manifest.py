"""Build manifest (v0.4).

Walks every file under site/ after a build and produces `site/manifest.json`
containing:

    {
      "version": "0.4.0",
      "generated_at": "ISO timestamp",
      "total_files": N,
      "total_bytes": M,
      "perf_budget": { ... targets from docs/framework.md ... },
      "files": [
        {"path": "index.html", "size": 12345, "sha256": "16-hex-chars"},
        ...
      ]
    }

Used by:
- CI to detect drift between builds (hash-based diff)
- AI agents to verify they have the latest version
- Performance budget enforcement (total_bytes check)

Stdlib only.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from llmwiki import __version__

# Performance budget targets. Tuned against a 280-session corpus (llm-wiki's
# own dogfood dataset). Any single violation is reported but doesn't fail
# the build unless CI passes --fail-on-violations to the link checker.
PERF_BUDGET = {
    "cold_build_seconds": 30,
    "incremental_build_seconds": 2,
    "total_site_bytes": 150 * 1024 * 1024,  # 150 MB (generous for AI exports)
    "per_page_bytes": 3 * 1024 * 1024,      # 3 MB (accommodates huge subagent sessions)
    "css_js_bytes": 200 * 1024,             # 200 KB combined
    "llms_full_bytes": 10 * 1024 * 1024,    # 10 MB
}


def sha256_hex(path: Path, chunk_size: int = 65536) -> str:
    """Compute sha256 of a file, return first 16 hex chars."""
    h = hashlib.sha256()
    try:
        with path.open("rb") as f:
            while True:
                data = f.read(chunk_size)
                if not data:
                    break
                h.update(data)
    except OSError:
        return ""
    return h.hexdigest()[:16]


def build_manifest(site_dir: Path) -> dict[str, Any]:
    """Walk site_dir and produce the manifest dict."""
    if not site_dir.exists():
        return {"error": f"{site_dir} does not exist"}

    files: list[dict[str, Any]] = []
    total_bytes = 0
    largest_page = 0

    for p in sorted(site_dir.rglob("*")):
        if not p.is_file():
            continue
        if p.name == "manifest.json":
            continue
        try:
            size = p.stat().st_size
        except OSError:
            continue
        rel = p.relative_to(site_dir)
        files.append(
            {
                "path": str(rel),
                "size": size,
                "sha256": sha256_hex(p),
            }
        )
        total_bytes += size
        if p.suffix == ".html" and size > largest_page:
            largest_page = size

    css_js_bytes = sum(f["size"] for f in files if f["path"].endswith((".css", ".js")))

    budget_violations: list[str] = []
    if total_bytes > PERF_BUDGET["total_site_bytes"]:
        budget_violations.append(
            f"total_site_bytes: {total_bytes / 1024 / 1024:.1f} MB > {PERF_BUDGET['total_site_bytes'] / 1024 / 1024:.1f} MB"
        )
    if largest_page > PERF_BUDGET["per_page_bytes"]:
        budget_violations.append(
            f"per_page_bytes: {largest_page / 1024:.0f} KB > {PERF_BUDGET['per_page_bytes'] / 1024:.0f} KB"
        )
    if css_js_bytes > PERF_BUDGET["css_js_bytes"]:
        budget_violations.append(
            f"css_js_bytes: {css_js_bytes / 1024:.0f} KB > {PERF_BUDGET['css_js_bytes'] / 1024:.0f} KB"
        )
    llms_full = site_dir / "llms-full.txt"
    if llms_full.exists() and llms_full.stat().st_size > PERF_BUDGET["llms_full_bytes"]:
        budget_violations.append(
            f"llms_full_bytes: {llms_full.stat().st_size / 1024 / 1024:.1f} MB > {PERF_BUDGET['llms_full_bytes'] / 1024 / 1024:.1f} MB"
        )

    return {
        "version": __version__,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_files": len(files),
        "total_bytes": total_bytes,
        "largest_page_bytes": largest_page,
        "css_js_bytes": css_js_bytes,
        "perf_budget": PERF_BUDGET,
        "budget_violations": budget_violations,
        "files": files,
    }


def write_manifest(site_dir: Path) -> Path:
    manifest = build_manifest(site_dir)
    out_path = site_dir / "manifest.json"
    out_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return out_path
