#!/usr/bin/env python3
"""Timeline formatting utilities for Tongji Look lecture notes.

This script does NOT call any LLM. It only helps the agent:
- sample large SRT files uniformly (for stable timeline generation context),
- normalize/validate timeline outline text into a strict output format,
- convert between SRT timestamps (HH:MM:SS,mmm) and MM:SS.

Keep this file in sync with the top-level `scripts/timeline_tools.py`.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

_SRT_TIME_RE = re.compile(r"(?P<h>\d{1,3}):(?P<m>\d{2}):(?P<s>\d{2}),(?P<ms>\d{3})")
_SRT_RANGE_RE = re.compile(
    r"(?P<start>\d{1,3}:\d{2}:\d{2},\d{3})\s*-->\s*(?P<end>\d{1,3}:\d{2}:\d{2},\d{3})"
)

_TIMELINE_LINE_RE = re.compile(
    r"(?P<start>\d{1,3}:\d{2}(?::\d{2})?)\s*[-–—~～]\s*(?P<end>\d{1,3}:\d{2}(?::\d{2})?)\s*[:：]?\s*(?P<text>.+)"
)


@dataclass(frozen=True)
class TimelineEntry:
    start_sec: int
    end_sec: int
    text: str


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _parse_srt_time_to_ms(time_str: str) -> int:
    match = _SRT_TIME_RE.fullmatch(time_str.strip())
    if not match:
        raise ValueError(f"Invalid SRT time: {time_str}")
    hours = int(match.group("h"))
    minutes = int(match.group("m"))
    seconds = int(match.group("s"))
    millis = int(match.group("ms"))
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis


def _srt_end_ms(srt_content: str) -> int:
    end_ms = 0
    for match in _SRT_RANGE_RE.finditer(srt_content or ""):
        try:
            ms = _parse_srt_time_to_ms(match.group("end"))
        except Exception:
            continue
        end_ms = max(end_ms, ms)
    return end_ms


def _seconds_to_mmss(total_seconds: int) -> str:
    sec = max(0, int(total_seconds))
    minutes = sec // 60
    seconds = sec % 60
    return f"{minutes:02d}:{seconds:02d}"


def _parse_mmss_or_hms_to_seconds(time_str: str) -> int:
    parts = [p.strip() for p in time_str.strip().split(":")]
    if len(parts) == 2:
        mm, ss = parts
        return int(mm) * 60 + int(ss)
    if len(parts) == 3:
        hh, mm, ss = parts
        return int(hh) * 3600 + int(mm) * 60 + int(ss)
    raise ValueError(f"Invalid time format: {time_str}")


def sample_srt_blocks(srt_content: str, max_chars: int) -> str:
    """Uniformly sample SRT blocks across the whole file to fit in max_chars."""
    blocks = re.split(r"(?:\r?\n){2,}", (srt_content or "").strip())
    if not blocks:
        return (srt_content or "").strip()

    total_len = len(srt_content or "")
    if total_len <= max_chars:
        return (srt_content or "").strip()

    total_blocks = len(blocks)
    avg_block_len = max(1.0, total_len / max(1, total_blocks))
    keep_count = max(10, int(max_chars / avg_block_len))

    step = total_blocks / max(1, keep_count)
    indices = [int(i * step) for i in range(keep_count)]
    indices.append(0)
    indices.append(total_blocks - 1)
    indices = sorted(set(i for i in indices if 0 <= i < total_blocks))

    sampled = [blocks[i] for i in indices]
    return "\n\n".join(sampled).strip()


def _parse_timeline_text(timeline_text: str) -> list[TimelineEntry]:
    entries: list[TimelineEntry] = []
    for line_no, raw_line in enumerate((timeline_text or "").splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue
        line = re.sub(r"^\s*[-*•]\s*", "", line)
        line = re.sub(r"^\s*\d+\s*[.)）]\s*", "", line)
        line = re.sub(r"^\s*[（(]?\d+[）)]\s*", "", line)
        match = _TIMELINE_LINE_RE.match(line)
        if not match:
            raise ValueError(f"Invalid timeline line at {line_no}: {raw_line}")
        start_sec = _parse_mmss_or_hms_to_seconds(match.group("start"))
        end_sec = _parse_mmss_or_hms_to_seconds(match.group("end"))
        text = re.sub(r"\s+", " ", match.group("text")).strip()
        entries.append(TimelineEntry(start_sec=start_sec, end_sec=end_sec, text=text))
    return entries


def _normalize_timeline_entries(
    entries: list[TimelineEntry],
    *,
    srt_end_sec: int | None,
    tolerance_sec: int,
) -> list[TimelineEntry]:
    if not entries:
        raise ValueError("Timeline is empty")

    normalized: list[TimelineEntry] = []
    prev_end: int | None = None

    for i, e in enumerate(entries):
        start_sec = int(e.start_sec)
        end_sec = int(e.end_sec)
        text = (e.text or "").strip()

        if i == 0:
            if start_sec != 0:
                if abs(start_sec - 0) <= tolerance_sec:
                    start_sec = 0
                else:
                    raise ValueError(f"Timeline must start at 00:00, got {_seconds_to_mmss(start_sec)}")
        else:
            assert prev_end is not None
            if start_sec != prev_end:
                if abs(start_sec - prev_end) <= tolerance_sec:
                    start_sec = prev_end
                else:
                    raise ValueError(
                        "Timeline segments must be contiguous. "
                        f"Expected start={_seconds_to_mmss(prev_end)}, got {_seconds_to_mmss(start_sec)}"
                    )

        if end_sec <= start_sec:
            if i < len(entries) - 1:
                next_start = int(entries[i + 1].start_sec)
                if next_start > start_sec:
                    end_sec = next_start
                else:
                    raise ValueError(
                        f"Invalid segment end at #{i+1}: end<=start ({_seconds_to_mmss(end_sec)} <= {_seconds_to_mmss(start_sec)})"
                    )
            elif srt_end_sec is not None and srt_end_sec > start_sec:
                end_sec = srt_end_sec
            else:
                raise ValueError(
                    f"Invalid segment end at #{i+1}: end<=start ({_seconds_to_mmss(end_sec)} <= {_seconds_to_mmss(start_sec)})"
                )

        normalized.append(TimelineEntry(start_sec=start_sec, end_sec=end_sec, text=text))
        prev_end = end_sec

    for i in range(len(normalized) - 1):
        cur = normalized[i]
        nxt = normalized[i + 1]
        if cur.end_sec != nxt.start_sec:
            if abs(cur.end_sec - nxt.start_sec) <= tolerance_sec:
                normalized[i] = TimelineEntry(start_sec=cur.start_sec, end_sec=nxt.start_sec, text=cur.text)
            else:
                raise ValueError(
                    "Timeline segments must be contiguous. "
                    f"Expected end={_seconds_to_mmss(nxt.start_sec)}, got {_seconds_to_mmss(cur.end_sec)}"
                )

    if srt_end_sec is not None:
        last = normalized[-1]
        delta = last.end_sec - srt_end_sec
        if abs(delta) <= tolerance_sec:
            normalized[-1] = TimelineEntry(start_sec=last.start_sec, end_sec=srt_end_sec, text=last.text)
        elif abs(delta) <= 10:
            normalized[-1] = TimelineEntry(start_sec=last.start_sec, end_sec=srt_end_sec, text=last.text)
        else:
            raise ValueError(
                "Last segment end must be close to the last subtitle end time. "
                f"timeline_end={_seconds_to_mmss(last.end_sec)} srt_end={_seconds_to_mmss(srt_end_sec)}"
            )

    return normalized


def _render_timeline(entries: list[TimelineEntry]) -> str:
    lines: list[str] = []
    for e in entries:
        start = _seconds_to_mmss(e.start_sec)
        end = _seconds_to_mmss(e.end_sec)
        text = (e.text or "").strip()
        lines.append(f"{start}-{end}：{text}")
    return "\n".join(lines).strip() + "\n"


def cmd_srt_sample(args: argparse.Namespace) -> int:
    srt_path = Path(args.srt).expanduser().resolve()
    out_path = Path(args.out).expanduser().resolve()
    max_chars = max(1000, int(args.max_chars))

    if not srt_path.exists():
        print(f"[ERROR] SRT not found: {srt_path}", file=sys.stderr)
        return 2

    raw = _read_text(srt_path)
    sampled = sample_srt_blocks(raw, max_chars=max_chars)
    _write_text(out_path, sampled.strip() + "\n")

    end_ms = _srt_end_ms(raw)
    end_sec = (end_ms + 999) // 1000
    print(f"[OK] Sample written: {out_path}")
    print(f"[INFO] SRT end: {end_sec}s ({_seconds_to_mmss(end_sec)})")
    return 0


def cmd_timeline_normalize(args: argparse.Namespace) -> int:
    in_path = Path(args.input).expanduser().resolve()
    out_path = Path(args.out).expanduser().resolve() if args.out else in_path
    tolerance_sec = max(0, int(args.tolerance))

    if not in_path.exists():
        print(f"[ERROR] Timeline input not found: {in_path}", file=sys.stderr)
        return 2

    srt_end_sec: int | None = None
    if args.srt:
        srt_path = Path(args.srt).expanduser().resolve()
        if not srt_path.exists():
            print(f"[ERROR] SRT not found: {srt_path}", file=sys.stderr)
            return 2
        srt_raw = _read_text(srt_path)
        end_ms = _srt_end_ms(srt_raw)
        srt_end_sec = (end_ms + 999) // 1000

    raw = _read_text(in_path)
    entries = _parse_timeline_text(raw)
    normalized = _normalize_timeline_entries(entries, srt_end_sec=srt_end_sec, tolerance_sec=tolerance_sec)
    _write_text(out_path, _render_timeline(normalized))
    print(f"[OK] Timeline normalized: {out_path}")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="timeline_tools.py", description="SRT/timeline formatting helpers (no LLM).")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_sample = sub.add_parser("srt-sample", help="Uniformly sample SRT blocks for timeline context.")
    p_sample.add_argument("--srt", required=True, help="Input .srt path")
    p_sample.add_argument("--out", required=True, help="Output path for sampled context (text)")
    p_sample.add_argument("--max-chars", default=15000, help="Max characters for sampled output (default: 15000)")
    p_sample.set_defaults(func=cmd_srt_sample)

    p_norm = sub.add_parser("timeline-normalize", help="Normalize/validate timeline text into strict format.")
    p_norm.add_argument("--input", "--in", dest="input", required=True, help="Timeline text file to normalize")
    p_norm.add_argument("--out", default="", help="Output path (default: rewrite --input in-place)")
    p_norm.add_argument("--srt", default="", help="Optional .srt path for validating/aligning the last end time")
    p_norm.add_argument("--tolerance", default=1, help="Second-level tolerance for snapping/validation (default: 1)")
    p_norm.set_defaults(func=cmd_timeline_normalize)

    return p


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
