#!/usr/bin/env python3
"""Crop launcher icons from Anoop's official Do My Chore JPEG.

Does not redraw or re-encode app/assets/branding/do_my_chore_logo.jpg —
that file is the official pixels (copy the upload over it).

AppIcon: square crop of the left capsule (rounded end + mustard + dots).
The full pill+wordmark lockup is a hairline at 20–60pt; splash / LaunchImage
keep the full square JPEG.

Usage (from repo root):
  python3 scripts/gen_brand_icons.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "app"
LOGO = APP / "assets" / "branding" / "do_my_chore_logo.jpg"


def cream_of(im: Image.Image) -> tuple[int, int, int]:
    rgb = im.convert("RGB")
    w, h = rgb.size
    corners = [rgb.getpixel(p) for p in ((4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5))]
    return tuple(sum(c[i] for c in corners) // 4 for i in range(3))  # type: ignore[return-value]


def content_mask(im: Image.Image, bg: tuple[int, int, int], tol: int = 22) -> Image.Image:
    ref = Image.new("RGB", im.size, bg)
    diff = ImageChops.difference(im.convert("RGB"), ref)
    return diff.point(lambda p: 255 if p > tol else 0)


def mustard_row_span(im: Image.Image) -> tuple[int, int]:
    """Rows that contain mustard fill — the capsule, never the wordmark."""
    rgb = im.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    hits = []
    for y in range(h):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if r > 180 and g > 120 and b < 90 and r > g > b:
                hits.append(y)
                break
    if not hits:
        raise RuntimeError("official logo has no mustard capsule")
    return hits[0], hits[-1]


def capsule_left(im: Image.Image, y0: int, y1: int, cream: tuple[int, int, int]) -> int:
    mask = content_mask(im, cream).crop((0, y0, im.width, y1 + 1))
    box = mask.getbbox()
    if box is None:
        raise RuntimeError("capsule band empty")
    return box[0]


def square_left_capsule(full: Image.Image, cream: tuple[int, int, int]) -> Image.Image:
    y0, y1 = mustard_row_span(full)
    x0 = capsule_left(full, y0, y1, cream)
    # Mustard-only strip — wordmark sits below this band.
    strip = full.convert("RGB").crop((0, y0, full.width, y1 + 1))
    cap_h = y1 - y0 + 1
    side = int(cap_h * 2.15)
    pad_y = (side - cap_h) // 2
    left = max(0, x0 - int(cap_h * 0.18))
    canvas = Image.new("RGB", (side, side), cream)
    canvas.paste(strip, (-left, pad_y))
    return canvas


def resize_square(im: Image.Image, size: int) -> Image.Image:
    return im.resize((size, size), Image.Resampling.LANCZOS)


def write_png(path: Path, im: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG", optimize=True)


def main() -> int:
    if not LOGO.is_file():
        raise SystemExit(f"missing official lockup: {LOGO}")
    full = Image.open(LOGO)
    cream = cream_of(full)
    icon_src = square_left_capsule(full, cream)
    write_png(APP / "assets" / "branding" / "do_my_chore_app_icon.png", resize_square(icon_src, 1024))

    ios_icon_sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    ios_dir = APP / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in ios_icon_sizes.items():
        write_png(ios_dir / name, resize_square(icon_src, size))

    launch_dir = APP / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    rgb = full.convert("RGB")
    for name, size in (
        ("LaunchImage.png", 400),
        ("LaunchImage@2x.png", 800),
        ("LaunchImage@3x.png", 1200),
    ):
        write_png(launch_dir / name, resize_square(rgb, size))

    android = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    res = APP / "android" / "app" / "src" / "main" / "res"
    for folder, size in android.items():
        write_png(res / folder / "ic_launcher.png", resize_square(icon_src, size))
    write_png(res / "drawable" / "launch_logo.png", resize_square(rgb, 720))

    macos_dir = APP / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    if macos_dir.is_dir():
        for size in (16, 32, 64, 128, 256, 512, 1024):
            write_png(macos_dir / f"app_icon_{size}.png", resize_square(icon_src, size))

    web = APP / "web"
    if (web / "favicon.png").exists():
        write_png(web / "favicon.png", resize_square(icon_src, 32))
        write_png(web / "icons" / "Icon-192.png", resize_square(icon_src, 192))
        write_png(web / "icons" / "Icon-512.png", resize_square(icon_src, 512))
        write_png(web / "icons" / "Icon-maskable-192.png", resize_square(icon_src, 192))
        write_png(web / "icons" / "Icon-maskable-512.png", resize_square(icon_src, 512))

    # ponytail: lockup bytes unchanged; icon is square.
    icon = Image.open(APP / "assets" / "branding" / "do_my_chore_app_icon.png")
    assert icon.size == (1024, 1024), icon.size
    print(f"icons from {LOGO.relative_to(ROOT)} ({LOGO.stat().st_size} bytes, {full.size[0]}x{full.size[1]})")
    print("wrote app icon 1024 + iOS/Android/macos/web launcher set")
    return 0


if __name__ == "__main__":
    sys.exit(main())
