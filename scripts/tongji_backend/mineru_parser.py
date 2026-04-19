"""MinerU parsing helpers.

This module is intentionally independent from auth/CLI orchestration. It only
accepts a local PDF path and produces structured parsing artifacts.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class MineruOptions:
    enabled: bool
    pages_raw: str
    start_page_1: int | None
    end_page_1: int | None
    start_page_0: int | None
    end_page_0: int | None
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
    src = (source or "modelscope").strip().lower()
    if src not in {"modelscope", "hf"}:
        src = "modelscope"

    language = (lang or "ch").strip().lower() or "ch"
    backend_name = (backend or "pipeline").strip().lower() or "pipeline"
    method_name = (method or "ocr").strip().lower() or "ocr"

    if not enabled:
        return MineruOptions(
            enabled=False,
            pages_raw="",
            start_page_1=None,
            end_page_1=None,
            start_page_0=None,
            end_page_0=None,
            source=src,
            lang=language,
            backend=backend_name,
            method=method_name,
        )

    start_1, end_1 = parse_mineru_pages(pages)
    start_0 = (start_1 - 1) if start_1 is not None else None
    end_0 = (end_1 - 1) if end_1 is not None else None
    return MineruOptions(
        enabled=True,
        pages_raw=(pages or "").strip(),
        start_page_1=start_1,
        end_page_1=end_1,
        start_page_0=start_0,
        end_page_0=end_0,
        source=src,
        lang=language,
        backend=backend_name,
        method=method_name,
    )


def build_mineru_command(
    *,
    pdf_path: Path,
    output_dir: Path,
    options: MineruOptions,
    python_executable: str | None = None,
) -> list[str]:
    py = python_executable or sys.executable
    cmd: list[str] = [
        py,
        "-m",
        "mineru.cli.client",
        "-p",
        str(pdf_path),
        "-o",
        str(output_dir),
        "-b",
        options.backend,
        "-m",
        options.method,
        "-l",
        options.lang,
    ]
    if options.start_page_0 is not None:
        cmd.extend(["-s", str(options.start_page_0)])
    if options.end_page_0 is not None:
        cmd.extend(["-e", str(options.end_page_0)])
    return cmd


def _tail(text: str, max_lines: int = 20) -> str:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) <= max_lines:
        return "\n".join(lines)
    return "\n".join(lines[-max_lines:])


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

    output_dir.mkdir(parents=True, exist_ok=True)
    cmd = build_mineru_command(pdf_path=pdf_path, output_dir=output_dir, options=options)
    env = os.environ.copy()
    env["MINERU_MODEL_SOURCE"] = options.source

    try:
        completed = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
        )
    except Exception as exc:
        result["error"] = f"Failed to run MinerU: {type(exc).__name__}: {exc}"
        return result

    if completed.returncode != 0:
        stderr_tail = _tail(completed.stderr or "")
        stdout_tail = _tail(completed.stdout or "")
        merged = "\n".join(x for x in [stderr_tail, stdout_tail] if x)
        result["error"] = f"MinerU exit code {completed.returncode}" + (f"\n{merged}" if merged else "")
        return result

    doc_root = output_dir / pdf_path.stem / options.method
    if not doc_root.exists():
        result["error"] = f"MinerU finished but output folder not found: {doc_root}"
        return result

    md_path = doc_root / f"{pdf_path.stem}.md"
    json_v1 = doc_root / f"{pdf_path.stem}_content_list.json"
    json_v2 = doc_root / f"{pdf_path.stem}_content_list_v2.json"
    layout_pdf = doc_root / f"{pdf_path.stem}_layout.pdf"
    span_pdf = doc_root / f"{pdf_path.stem}_span.pdf"
    images_dir = doc_root / "images"

    result["md"] = str(md_path) if md_path.exists() else ""
    result["content_list_json"] = str(json_v1) if json_v1.exists() else ""
    result["content_list_v2_json"] = str(json_v2) if json_v2.exists() else ""
    result["layout_pdf"] = str(layout_pdf) if layout_pdf.exists() else ""
    result["span_pdf"] = str(span_pdf) if span_pdf.exists() else ""
    result["images_dir"] = str(images_dir) if images_dir.exists() else ""

    if not result["md"]:
        result["error"] = "MinerU completed but markdown output is missing."
        return result

    result["ok"] = True
    return result
