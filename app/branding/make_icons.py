#!/usr/bin/env python3
"""Draws the Look Studio icon and renders it for every platform.

The mark: a scalloped lens (the M3 Expressive "cookie" shape the app uses
for its own illustrations) holding a play mark, underlined by a highlighter
stroke - watching a lecture and marking what matters. Warm paper, spruce
ink and a coral accent keep it away from the usual neon gradients.

Flat layers only (no baked shadows or glows), so the parts can later feed a
layered macOS 26 icon. Run from anywhere; needs resvg and ImageMagick:

    python3 app/branding/make_icons.py
"""

import math
import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)

PAPER_TOP, PAPER_BOTTOM = "#F7F2E8", "#EADFCB"
INK_TOP, INK_BOTTOM = "#175450", "#0B2B2C"
CORAL = "#FF6B3D"


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def superellipse(cx, cy, half, n=5.0, steps=256):
    """Continuous-corner tile, close to Apple's and M3's rounded squares."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + half * math.copysign(abs(c) ** (2 / n), c)
        y = cy + half * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{f(x)},{f(y)}")
    return "M" + " L".join(pts) + " Z"


def cookie(cx, cy, r, lobes=9, depth=0.065, steps=540):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        rr = r * (1 + depth * math.cos(lobes * (t + math.pi / 2)))
        pts.append(f"{f(cx + rr * math.cos(t))},{f(cy + rr * math.sin(t))}")
    return "M" + " L".join(pts) + " Z"


def play(cx, cy, h):
    """A right-pointing triangle, nudged right to sit optically centred."""
    w = h * 0.92
    x0 = cx - w * 0.40
    return [(x0, cy - h / 2), (x0, cy + h / 2), (x0 + w, cy)]


def mark(cx, cy, s, mono=False):
    """The lens, play mark and highlighter, centred near (cx, cy); s = lens radius."""
    lens = cookie(cx, cy - s * 0.06, s)
    tri = play(cx + s * 0.02, cy - s * 0.06, s * 0.74)
    round_r = s * 0.075
    tri_pts = " ".join(f"{f(x)},{f(y)}" for x, y in tri)
    # Highlighter: a pill crossing the lens's lower right edge.
    bw, bh = s * 1.42, s * 0.215
    bx, by = cx - s * 0.30, cy + s * 0.80
    angle = -7
    bar = (f'<rect x="{f(bx)}" y="{f(by - bh / 2)}" width="{f(bw)}" height="{f(bh)}" rx="{f(bh / 2)}" '
           f'transform="rotate({angle} {f(bx + bw / 2)} {f(by)})"')
    if mono:
        # One colour: the play mark is cut out of the lens; the bar keeps a gap.
        gap = s * 0.07
        return (f'<mask id="m"><rect width="100%" height="100%" fill="#fff"/>'
                f'<polygon points="{tri_pts}" fill="#000" stroke="#000" stroke-width="{f(round_r * 2)}" stroke-linejoin="round"/>'
                f'{bar.replace("<rect", "<rect", 1)} fill="#000" stroke="#000" stroke-width="{f(gap * 2)}"/></mask>'
                f'<path d="{lens}" fill="#000" mask="url(#m)"/>'
                f'{bar} fill="#000"/>')
    return (f'<path d="{lens}" fill="url(#ink)"/>'
            f'<polygon points="{tri_pts}" fill="{PAPER_TOP}" stroke="{PAPER_TOP}" stroke-width="{f(round_r * 2)}" stroke-linejoin="round"/>'
            f'{bar} fill="{CORAL}"/>')


def defs(size):
    return (f'<defs>'
            f'<linearGradient id="paper" x1="0" y1="0" x2="0" y2="{size}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{PAPER_TOP}"/><stop offset="1" stop-color="{PAPER_BOTTOM}"/></linearGradient>'
            f'<linearGradient id="ink" x1="{f(size * 0.3)}" y1="{f(size * 0.2)}" x2="{f(size * 0.7)}" y2="{f(size * 0.78)}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{INK_TOP}"/><stop offset="1" stop-color="{INK_BOTTOM}"/></linearGradient>'
            f'</defs>')


def svg(size, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{defs(size)}{body}</svg>\n'


def app_icon(margin):
    """The full icon on a 1024 canvas; margin is the empty border per side."""
    half = 512 - margin
    k = half / 412  # scale relative to the macOS 824 px body
    tile = f'<path d="{superellipse(512, 512, half)}" fill="url(#paper)"/>'
    return svg(1024, tile + mark(512, 500, 262 * k))


def adaptive_foreground():
    # 108 dp canvas at 432 px; the mark stays inside the 66 dp (264 px) safe circle.
    return svg(432, mark(216, 208, 100))


def adaptive_monochrome():
    return svg(432, mark(216, 208, 100, mono=True))


def render(svg_text, png, size, tmp):
    src = os.path.join(tmp, "in.svg")
    with open(src, "w") as fh:
        fh.write(svg_text)
    os.makedirs(os.path.dirname(png), exist_ok=True)
    subprocess.run(["resvg", "-w", str(size), "-h", str(size), src, png], check=True)


def main():
    mac = app_icon(100)    # Apple's 824 px body on 1024
    tight = app_icon(48)   # Windows, Linux, legacy Android
    for name, text in [("icon.svg", tight), ("icon-macos.svg", mac),
                       ("android-foreground.svg", adaptive_foreground()),
                       ("android-monochrome.svg", adaptive_monochrome())]:
        with open(os.path.join(HERE, name), "w") as fh:
            fh.write(text)

    with tempfile.TemporaryDirectory() as tmp:
        # macOS asset catalog
        mac_dir = os.path.join(APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
        for s in (16, 32, 64, 128, 256, 512, 1024):
            render(mac, os.path.join(mac_dir, f"app_icon_{s}.png"), s, tmp)

        # Windows .ico with the sizes the shell asks for
        pngs = []
        for s in (16, 20, 24, 32, 40, 48, 64, 96, 128, 256):
            p = os.path.join(tmp, f"w{s}.png")
            render(tight, p, s, tmp)
            pngs.append(p)
        subprocess.run(["magick", *pngs, os.path.join(APP, "windows/runner/resources/app_icon.ico")], check=True)

        # Linux hicolor theme icons and a 512 px PNG for packages
        for s in (32, 48, 64, 128, 256, 512):
            render(tight, os.path.join(APP, f"linux/icons/hicolor/{s}x{s}/apps/cn.lookstudio.look_studio.png"), s, tmp)
        scalable = os.path.join(APP, "linux/icons/hicolor/scalable/apps/cn.lookstudio.look_studio.svg")
        os.makedirs(os.path.dirname(scalable), exist_ok=True)
        shutil.copyfile(os.path.join(HERE, "icon.svg"), scalable)

        # Android: legacy squircle plus adaptive layers (API 26+, themed 33+)
        res = os.path.join(APP, "android/app/src/main/res")
        for d, s in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
            render(tight, os.path.join(res, f"mipmap-{d}/ic_launcher.png"), s, tmp)
            fg = s * 108 // 48
            render(adaptive_foreground(), os.path.join(res, f"mipmap-{d}/ic_launcher_foreground.png"), fg, tmp)
            render(adaptive_monochrome(), os.path.join(res, f"mipmap-{d}/ic_launcher_monochrome.png"), fg, tmp)

        # For the README and release pages
        render(tight, os.path.join(HERE, "icon-512.png"), 512, tmp)


if __name__ == "__main__":
    main()
