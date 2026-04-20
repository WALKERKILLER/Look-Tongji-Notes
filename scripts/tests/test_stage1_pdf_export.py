#!/usr/bin/env python3
"""Stage-1 functional smoke test for slide PDF export.

This script validates:
1) PDF generation works for scan modes: none/doc/bw.
2) --scan-mode is ignored when --to-pdf is disabled (option resolver behavior).

Run:
  py -3.11 scripts/tests/test_stage1_pdf_export.py
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from tongji_backend.slide_pdf import build_slide_pdf, resolve_pdf_options  # noqa: E402


def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def main() -> int:
    src = ROOT / "images" / "example_link.png"
    if not src.exists():
        raise FileNotFoundError(f"Missing fixture image: {src}")

    temp = ROOT / ".tmp_stage1_pdf_test"
    if temp.exists():
        shutil.rmtree(temp)
    temp.mkdir(parents=True)

    try:
        # Build a tiny 2-page slide set.
        img1 = temp / "0001_t00-00-01_s000001.png"
        img2 = temp / "0002_t00-00-02_s000002.png"
        data = src.read_bytes()
        img1.write_bytes(data)
        img2.write_bytes(data)

        sizes: dict[str, int] = {}
        for mode in ("none", "doc", "bw"):
            out_pdf = temp / f"slides_{mode}.pdf"
            pages, out = build_slide_pdf(
                image_paths=[img1, img2],
                pdf_path=out_pdf,
                scan_mode=mode,
            )
            _assert(pages == 2, f"{mode}: expected 2 pages, got {pages}")
            _assert(out.exists(), f"{mode}: output PDF missing")
            size = out.stat().st_size
            _assert(size > 0, f"{mode}: output PDF is empty")
            sizes[mode] = size

        # Validate "scan-mode ignored without --to-pdf".
        p1 = resolve_pdf_options(to_pdf=False, scan_mode="doc", tag="Test")
        p2 = resolve_pdf_options(to_pdf=False, scan_mode="bw", tag="Test")
        p3 = resolve_pdf_options(to_pdf=True, scan_mode="doc", tag="Test")
        _assert(p1 == (False, "none"), f"unexpected resolver output: {p1}")
        _assert(p2 == (False, "none"), f"unexpected resolver output: {p2}")
        _assert(p3 == (True, "doc"), f"unexpected resolver output: {p3}")

        print("[PASS] stage1_pdf_export")
        print(f"[PASS] pdf_sizes_bytes: {sizes}")
        return 0
    finally:
        if temp.exists():
            shutil.rmtree(temp)


if __name__ == "__main__":
    raise SystemExit(main())
