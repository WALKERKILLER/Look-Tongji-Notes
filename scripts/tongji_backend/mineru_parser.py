"""MinerU OpenAPI parsing helpers.

This module is intentionally independent from auth/CLI orchestration. It only
accepts a local PDF path and saves the Markdown returned by MinerU OpenAPI.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class MineruOptions:
    enabled: bool
    pages_raw: str
    source: str
    lang: str
    backend: str
    method: str


def parse_mineru_pages(pages: str) -> tuple[int | None, int | None]:
    raw = (pages or "").strip()
    if not raw:
        return None, None

    match = re.fullmatch(r"(\d+)\s*-\s*(\d+)", raw)
    if not match:
        raise ValueError("Invalid --mineru-pages. Expected format: N-M (for example: 17-24).")

    start_1 = int(match.group(1))
    end_1 = int(match.group(2))
    if start_1 < 1:
        raise ValueError("Invalid --mineru-pages. Start page must be >= 1.")
    if end_1 < start_1:
        raise ValueError("Invalid --mineru-pages. End page must be >= start page.")
    return start_1, end_1


def resolve_mineru_options(
    *,
    enabled: bool,
    pages: str,
    source: str,
    lang: str,
    backend: str,
    method: str,
) -> MineruOptions:
    # Kept for CLI compatibility. OpenAPI flash does not use local model source.
    src = (source or "openapi").strip().lower()
    language = (lang or "ch").strip().lower() or "ch"
    backend_name = (backend or "openapi").strip().lower() or "openapi"
    method_name = (method or "flash").strip().lower() or "flash"

    if enabled:
        parse_mineru_pages(pages)

    return MineruOptions(
        enabled=bool(enabled),
        pages_raw=(pages or "").strip() if enabled else "",
        source=src,
        lang=language,
        backend=backend_name,
        method=method_name,
    )


def run_mineru_parse(
    *,
    pdf_path: Path,
    output_dir: Path,
    options: MineruOptions,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "enabled": options.enabled,
        "ok": False,
        "pages": options.pages_raw,
        "source": options.source,
        "lang": options.lang,
        "backend": options.backend,
        "method": options.method,
        "output_dir": str(output_dir),
        "md": "",
        "content_list_json": "",
        "content_list_v2_json": "",
        "layout_pdf": "",
        "span_pdf": "",
        "images_dir": "",
        "error": "",
    }

    if not options.enabled:
        result["ok"] = True
        return result

    if not pdf_path.exists():
        result["error"] = f"PDF not found: {pdf_path}"
        return result

    try:
        from mineru import MinerU
    except Exception as exc:
        result["error"] = (
            "MinerU OpenAPI SDK is required. Install with: "
            f"pip install mineru-open-sdk ({type(exc).__name__}: {exc})"
        )
        return result

    output_dir.mkdir(parents=True, exist_ok=True)
    md_path = output_dir / f"{pdf_path.stem}.md"

    client = MinerU()
    try:
        extracted = client.flash_extract(
            str(pdf_path),
            language=options.lang,
            page_range=options.pages_raw or None,
            is_ocr=True,
            enable_formula=True,
            enable_table=True,
        )
    except Exception as exc:
        result["error"] = f"MinerU OpenAPI failed: {type(exc).__name__}: {exc}"
        return result
    finally:
        try:
            client.close()
        except Exception:
            pass

    markdown = getattr(extracted, "markdown", None) or ""
    if not markdown.strip():
        state = getattr(extracted, "state", "")
        err_code = getattr(extracted, "err_code", "")
        error = getattr(extracted, "error", "")
        result["error"] = (
            "MinerU OpenAPI completed but markdown output is empty"
            f" (state={state}, err_code={err_code}, error={error})."
        )
        return result

    md_path.write_text(markdown, encoding="utf-8")
    result["md"] = str(md_path)
    result["ok"] = True
    return result
