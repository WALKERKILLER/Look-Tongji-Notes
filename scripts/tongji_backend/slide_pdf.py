"""Slide-to-PDF export helpers.

This module is intentionally independent from CLI/auth logic, so it can be
reused as a standalone utility in later stages.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any


def resolve_pdf_options(*, to_pdf: bool, scan_mode: str, tag: str) -> tuple[bool, str]:
    mode = (scan_mode or "none").strip().lower()
    if mode not in {"none", "doc", "bw"}:
        mode = "none"
    if not to_pdf and mode != "none":
        print(f"[{tag}] --scan-mode={mode} ignored because --to-pdf is not enabled.")
        mode = "none"
    return bool(to_pdf), mode


def _load_pdf_deps(scan_mode: str) -> tuple[Any, Any | None, Any | None]:
    try:
        from PIL import Image
    except Exception as e:
        raise RuntimeError(
            "PDF export requires Pillow. Install with: pip install Pillow"
        ) from e

    if scan_mode == "none":
        return Image, None, None

    try:
        import cv2
        import numpy as np
    except Exception as e:
        raise RuntimeError(
            f"scan-mode '{scan_mode}' requires OpenCV + NumPy. "
            "Install with: pip install opencv-python-headless numpy"
        ) from e

    return Image, cv2, np


def _order_points(np: Any, pts: Any) -> Any:
    rect = np.zeros((4, 2), dtype="float32")
    sums = pts.sum(axis=1)
    rect[0] = pts[np.argmin(sums)]  # top-left
    rect[2] = pts[np.argmax(sums)]  # bottom-right
    diffs = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diffs)]  # top-right
    rect[3] = pts[np.argmax(diffs)]  # bottom-left
    return rect


def _warp_perspective(cv2: Any, np: Any, image_bgr: Any, pts: Any) -> Any:
    rect = _order_points(np, pts.astype("float32"))
    tl, tr, br, bl = rect

    width_a = np.linalg.norm(br - bl)
    width_b = np.linalg.norm(tr - tl)
    max_width = max(1, int(round(max(width_a, width_b))))

    height_a = np.linalg.norm(tr - br)
    height_b = np.linalg.norm(tl - bl)
    max_height = max(1, int(round(max(height_a, height_b))))

    dst = np.array(
        [
            [0, 0],
            [max_width - 1, 0],
            [max_width - 1, max_height - 1],
            [0, max_height - 1],
        ],
        dtype="float32",
    )
    matrix = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(image_bgr, matrix, (max_width, max_height))


def _detect_document_quad(cv2: Any, image_bgr: Any) -> Any | None:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blur, 50, 180)

    contours_data = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    contours = contours_data[0] if len(contours_data) == 2 else contours_data[1]
    if contours is None:
        return None

    image_area = float(image_bgr.shape[0] * image_bgr.shape[1])
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:12]:
        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        area = cv2.contourArea(approx)
        if len(approx) == 4 and area >= image_area * 0.15:
            return approx.reshape(4, 2)
    return None


def _scan_enhance_image(cv2: Any, np: Any, image_bgr: Any, scan_mode: str) -> Any:
    working = image_bgr
    quad = _detect_document_quad(cv2, working)
    if quad is not None:
        try:
            working = _warp_perspective(cv2, np, working, quad)
        except Exception:
            pass

    gray = cv2.cvtColor(working, cv2.COLOR_BGR2GRAY)
    if scan_mode == "bw":
        bw = cv2.adaptiveThreshold(
            gray,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY,
            35,
            11,
        )
        return cv2.cvtColor(bw, cv2.COLOR_GRAY2BGR)

    normalized = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
    denoised = cv2.bilateralFilter(normalized, 9, 75, 75)
    return cv2.cvtColor(denoised, cv2.COLOR_GRAY2BGR)


def _read_cv2_image(cv2: Any, np: Any, path: Path) -> Any | None:
    try:
        data = np.fromfile(str(path), dtype=np.uint8)
        if data.size > 0:
            image = cv2.imdecode(data, cv2.IMREAD_COLOR)
            if image is not None:
                return image
    except Exception:
        pass
    try:
        return cv2.imread(str(path), cv2.IMREAD_COLOR)
    except Exception:
        return None


def build_slide_pdf(
    *,
    image_paths: list[Path],
    pdf_path: Path,
    scan_mode: str,
) -> tuple[int, Path]:
    if not image_paths:
        raise RuntimeError("No slide images available for PDF export.")

    Image, cv2, np = _load_pdf_deps(scan_mode)

    pages: list[Any] = []
    try:
        for path in image_paths:
            if not path.exists():
                continue
            if scan_mode == "none":
                with Image.open(path) as im:
                    pages.append(im.convert("RGB"))
                continue

            image_bgr = _read_cv2_image(cv2, np, path)
            if image_bgr is None:
                with Image.open(path) as im:
                    pages.append(im.convert("RGB"))
                continue

            enhanced = _scan_enhance_image(cv2, np, image_bgr, scan_mode)
            rgb = cv2.cvtColor(enhanced, cv2.COLOR_BGR2RGB)
            pages.append(Image.fromarray(rgb))

        if not pages:
            raise RuntimeError("No readable slide images found for PDF export.")

        pdf_path.parent.mkdir(parents=True, exist_ok=True)
        first, *rest = pages
        first.save(
            pdf_path,
            format="PDF",
            save_all=True,
            append_images=rest,
            resolution=150.0,
        )
        return len(pages), pdf_path
    finally:
        for page in pages:
            try:
                page.close()
            except Exception:
                pass

