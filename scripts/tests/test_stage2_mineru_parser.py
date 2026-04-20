#!/usr/bin/env python3
"""Stage-2 smoke tests for MinerU integration helpers.

Validates:
1) page range parser (1-based user input) and validation.
2) command builder emits expected 0-based MinerU page flags.
3) output collector behavior via run_mineru_parse with a fake runner.

Run:
  py -3.11 scripts/tests/test_stage2_mineru_parser.py
"""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import tongji_backend.mineru_parser as mp  # noqa: E402


def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def _expect_raises(fn, msg: str) -> None:
    try:
        fn()
    except Exception:
        return
    raise AssertionError(msg)


def main() -> int:
    # 1) Page range parsing
    s, e = mp.parse_mineru_pages("17-24")
    _assert((s, e) == (17, 24), f"Unexpected parse result: {(s, e)}")
    s2, e2 = mp.parse_mineru_pages(" 1 - 1 ")
    _assert((s2, e2) == (1, 1), f"Unexpected parse result: {(s2, e2)}")
    s3, e3 = mp.parse_mineru_pages("")
    _assert((s3, e3) == (None, None), f"Unexpected empty parse result: {(s3, e3)}")

    _expect_raises(lambda: mp.parse_mineru_pages("24-17"), "Should reject reversed range")
    _expect_raises(lambda: mp.parse_mineru_pages("0-8"), "Should reject page < 1")
    _expect_raises(lambda: mp.parse_mineru_pages("17,24"), "Should reject invalid separator")

    # 2) Option resolver + command builder
    opts = mp.resolve_mineru_options(
        enabled=True,
        pages="17-24",
        source="modelscope",
        lang="ch",
        backend="pipeline",
        method="ocr",
    )
    _assert(opts.start_page_0 == 16 and opts.end_page_0 == 23, "1-based to 0-based conversion failed")

    pdf_path = ROOT / ".tmp_stage2_mineru_parser_test.pdf"
    out_dir = ROOT / ".tmp_stage2_mineru_parser_out"
    cmd = mp.build_mineru_command(pdf_path=pdf_path, output_dir=out_dir, options=opts, python_executable="py")
    cmd_text = " ".join(cmd)
    _assert(" -s 16 " in f" {cmd_text} ", f"Missing -s conversion in cmd: {cmd_text}")
    _assert(" -e 23 " in f" {cmd_text} ", f"Missing -e conversion in cmd: {cmd_text}")

    # 3) run_mineru_parse with fake subprocess runner
    temp_pdf = ROOT / ".tmp_stage2_dummy.pdf"
    temp_pdf.write_bytes(b"%PDF-1.4\n%fake\n")
    fake_root = ROOT / ".tmp_stage2_mineru_fake"
    doc_root = fake_root / temp_pdf.stem / "ocr"
    doc_root.mkdir(parents=True, exist_ok=True)
    (doc_root / f"{temp_pdf.stem}.md").write_text("hello", encoding="utf-8")
    (doc_root / f"{temp_pdf.stem}_content_list.json").write_text("{}", encoding="utf-8")
    (doc_root / f"{temp_pdf.stem}_content_list_v2.json").write_text("{}", encoding="utf-8")
    (doc_root / f"{temp_pdf.stem}_layout.pdf").write_bytes(b"%PDF-1.4\n")
    (doc_root / f"{temp_pdf.stem}_span.pdf").write_bytes(b"%PDF-1.4\n")
    (doc_root / "images").mkdir(parents=True, exist_ok=True)

    class _Completed:
        def __init__(self) -> None:
            self.returncode = 0
            self.stdout = "ok"
            self.stderr = ""

    real_run = mp.subprocess.run
    mp.subprocess.run = lambda *args, **kwargs: _Completed()  # type: ignore[assignment]
    try:
        parsed = mp.run_mineru_parse(pdf_path=temp_pdf, output_dir=fake_root, options=opts)
    finally:
        mp.subprocess.run = real_run  # type: ignore[assignment]

    _assert(parsed.get("ok") is True, f"Expected ok parse result, got: {parsed}")
    _assert(str(doc_root / f"{temp_pdf.stem}.md") == parsed.get("md"), "Markdown path mismatch")

    # Cleanup
    for path in [temp_pdf, pdf_path]:
        if path.exists():
            path.unlink()
    for folder in [fake_root, out_dir]:
        if folder.exists():
            import shutil

            shutil.rmtree(folder)

    print("[PASS] stage2_mineru_parser")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
