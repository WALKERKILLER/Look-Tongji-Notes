#!/usr/bin/env python3
"""Stage-2 smoke tests for MinerU OpenAPI integration helpers.

Validates:
1) page range parser (1-based user input) and validation.
2) option resolver stores OpenAPI metadata.
3) output writer behavior via run_mineru_parse with a fake OpenAPI client.

Run:
  py -3.11 scripts/tests/test_stage2_mineru_parser.py
"""

from __future__ import annotations

import sys
import types
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

    # 2) Option resolver
    opts = mp.resolve_mineru_options(
        enabled=True,
        pages="17-24",
        source="openapi",
        lang="ch",
        backend="openapi",
        method="flash",
    )
    _assert(opts.pages_raw == "17-24", "page range should be preserved for OpenAPI")
    _assert(opts.source == "openapi", "source should be openapi")
    _assert(opts.method == "flash", "method should be flash")

    # 3) run_mineru_parse with fake OpenAPI client
    temp_pdf = ROOT / ".tmp_stage2_dummy.pdf"
    temp_pdf.write_bytes(b"%PDF-1.4\n%fake\n")
    fake_root = ROOT / ".tmp_stage2_mineru_openapi_fake"

    class _FakeExtractResult:
        markdown = "# hello from openapi\n"

    class _FakeMinerU:
        calls: list[dict[str, object]] = []

        def __init__(self) -> None:
            pass

        def flash_extract(self, source: str, **kwargs: object) -> _FakeExtractResult:
            self.calls.append({"source": source, **kwargs})
            return _FakeExtractResult()

        def close(self) -> None:
            pass

    fake_module = types.ModuleType("mineru")
    fake_module.MinerU = _FakeMinerU
    old_mineru = sys.modules.get("mineru")
    sys.modules["mineru"] = fake_module
    try:
        parsed = mp.run_mineru_parse(pdf_path=temp_pdf, output_dir=fake_root, options=opts)
    finally:
        if old_mineru is None:
            sys.modules.pop("mineru", None)
        else:
            sys.modules["mineru"] = old_mineru

    _assert(parsed.get("ok") is True, f"Expected ok parse result, got: {parsed}")
    md_path = fake_root / f"{temp_pdf.stem}.md"
    _assert(str(md_path) == parsed.get("md"), "Markdown path mismatch")
    _assert(md_path.read_text(encoding="utf-8") == "# hello from openapi\n", "Markdown content mismatch")

    # Cleanup
    for path in [temp_pdf]:
        if path.exists():
            path.unlink()
    for folder in [fake_root]:
        if folder.exists():
            import shutil

            shutil.rmtree(folder)

    print("[PASS] stage2_mineru_parser")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
