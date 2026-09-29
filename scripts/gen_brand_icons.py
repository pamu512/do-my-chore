#!/usr/bin/env python3
"""Render Anoop's Do My Chore mark and the iOS/Android launcher set.

The attached official JPEG was not persisted on this VM; this redraws the
same lockup (cream field, forest-green capsule, mustard fill, five cream
dots, green check, serif wordmark) and writes the JPEG used in-app.

AppIcon uses a square crop of the pill + check only. The wordmark vanishes
at 20–60pt home-screen sizes; the full lockup stays in
app/assets/branding/do_my_chore_logo.jpg.

Usage (from repo root):
  python3 scripts/gen_brand_icons.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "app"
FONT = APP / "assets" / "fonts" / "Fraunces-700.ttf"

CREAM = (253, 249, 242)  # #FDF9F2 — paper field from the official mark
GREEN = (26, 69, 48)  # #1A4530 — forest outline / wordmark / check
MUSTARD = (212, 166, 45)  # #D4A62D — capsule fill

# Official lockup canvas (square, generous cream — matches the attached JPEG).
CANVAS = 2400


def _circle(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill) -> None:
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def _rounded_caps_line(
    overlay: Image.Image,
    pts: list[tuple[float, float]],
    color: tuple[int, int, int],
    width: float,
) -> None:
    """Stroke a polyline with round joins/caps on a transparent overlay."""
    layer = Image.new("RGBA", overlay.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    xy = [(int(round(x)), int(round(y))) for x, y in pts]
    d.line(xy, fill=(*color, 255), width=int(round(width)), joint="curve")
    r = width / 2
    for x, y in xy:
        _circle(d, x, y, r, (*color, 255))
    overlay.alpha_composite(layer)


def render_lockup() -> tuple[Image.Image, Image.Image]:
    """Return (full square lockup RGB, pill+check on cream RGB)."""
    im = Image.new("RGBA", (CANVAS, CANVAS), (*CREAM, 255))
    draw = ImageDraw.Draw(im)

    # Horizontal unit: capsule + connector + check, optically centered.
    unit_w = 1520
    left = (CANVAS - unit_w) / 2
    cy = 1000
    cap_h = 176
    cap_w = 1040
    stroke = 13

    x0, y0 = left, cy - cap_h / 2
    x1, y1 = left + cap_w, cy + cap_h / 2
    radius = cap_h / 2

    # Capsule outline (cream interior), then mustard fill that stops short of
    # the right cap so the green nose stays visible — same as the official art.
    draw.rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=CREAM, outline=GREEN, width=stroke)

    inset = stroke + 2
    fill_right = x1 - radius * 0.62
    draw.rounded_rectangle(
        (x0 + inset, y0 + inset, fill_right, y1 - inset),
        radius=(cap_h - 2 * inset) / 2,
        fill=MUSTARD,
    )

    # Five cream milestone dots, evenly spaced in the mustard.
    inner_left = x0 + radius * 0.92
    inner_right = fill_right - (cap_h - 2 * inset) / 2
    dot_r = 16
    for i in range(5):
        t = (i + 0.5) / 5
        _circle(draw, inner_left + t * (inner_right - inner_left), cy, dot_r, CREAM)

    # Official mark: short green stem off the right cap, then a standalone check.
    stem_end = x1 + 58
    _rounded_caps_line(im, [(x1 - stroke / 2, cy), (stem_end, cy)], GREEN, stroke)
    _rounded_caps_line(
        im,
        [
            (stem_end + 22, cy + 6),
            (stem_end + 78, cy + 68),
            (stem_end + 210, cy - 78),
        ],
        GREEN,
        stroke + 6,
    )

    pill = im.copy()

    font = ImageFont.truetype(str(FONT), 158)
    words = ["Do", "My", "Chore"]
    gap = 46
    widths = []
    for word in words:
        tb = draw.textbbox((0, 0), word, font=font)
        widths.append(tb[2] - tb[0])
    total = sum(widths) + gap * (len(words) - 1)
    x = (CANVAS - total) / 2
    ty_base = cy + cap_h / 2 + 70
    for word, w in zip(words, widths):
        tb = draw.textbbox((0, 0), word, font=font)
        draw.text((x - tb[0], ty_base - tb[1]), word, font=font, fill=GREEN)
        x += w + gap

    rgb = im.convert("RGB")
    return rgb, pill.convert("RGB")


def content_bbox(im: Image.Image, bg: tuple[int, int, int] = CREAM, tol: int = 12):
    ref = Image.new("RGB", im.size, bg)
    diff = ImageChops.difference(im.convert("RGB"), ref)
    # Flatten small AA fringe so getbbox hugs the mark.
    mask = diff.point(lambda p: 255 if p > tol else 0)
    return mask.getbbox()


def square_crop(im: Image.Image, pad_ratio: float = 0.22) -> Image.Image:
    box = content_bbox(im)
    if box is None:
        raise RuntimeError("logo render produced an empty mark")
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    side = int(max(w, h) * (1 + pad_ratio))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    half = side / 2
    crop = (int(cx - half), int(cy - half), int(cx + half), int(cy + half))
    # Paste onto cream so we can crop past the canvas edge safely.
    canvas = Image.new("RGB", (im.width + side, im.height + side), CREAM)
    canvas.paste(im, (side // 2, side // 2))
    ox, oy = side // 2, side // 2
    crop = (crop[0] + ox, crop[1] + oy, crop[2] + ox, crop[3] + oy)
    return canvas.crop(crop)


def resize_square(im: Image.Image, size: int) -> Image.Image:
    return im.resize((size, size), Image.Resampling.LANCZOS)


def write_jpeg(path: Path, im: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "JPEG", quality=95, optimize=True, progressive=True)


def write_png(path: Path, im: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG", optimize=True)


def main() -> int:
    full, pill = render_lockup()
    logo_path = APP / "assets" / "branding" / "do_my_chore_logo.jpg"
    write_jpeg(logo_path, full)

    # AppIcon: tight square through the mustard pill. A full pill+wordmark
    # lockup is a wide strip — at 20–60pt the wordmark and check vanish —
    # so the launcher uses the readable center of the capsule (dots + stroke).
    cap_box = content_bbox(pill)
    if cap_box is None:
        raise RuntimeError("pill render produced an empty mark")
    # Square through the left cap + first dots so the stadium silhouette
    # stays readable; a full-width lockup shrinks to a hairline at 60pt.
    cap_h = cap_box[3] - cap_box[1]
    side = int(cap_h * 2.7)
    cx = cap_box[0] + side * 0.52
    cy0 = (cap_box[1] + cap_box[3]) / 2
    half = side / 2
    padded = Image.new("RGB", (pill.width + side, pill.height + side), CREAM)
    padded.paste(pill, (side // 2, side // 2))
    icon_src = padded.crop(
        (
            int(cx + side / 2 - half),
            int(cy0 + side / 2 - half),
            int(cx + side / 2 + half),
            int(cy0 + side / 2 + half),
        )
    )
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
    # Full lockup, cream field, 1x/2x/3x. Storyboard centers this.
    for name, size in (
        ("LaunchImage.png", 400),
        ("LaunchImage@2x.png", 800),
        ("LaunchImage@3x.png", 1200),
    ):
        write_png(launch_dir / name, resize_square(full, size))

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

    write_png(res / "drawable" / "launch_logo.png", resize_square(full, 720))

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

    # ponytail: one check that the lockup and icon exist and are the right shape.
    assert logo_path.stat().st_size > 8_000, logo_path
    icon = Image.open(APP / "assets" / "branding" / "do_my_chore_app_icon.png")
    assert icon.size == (1024, 1024), icon.size
    print(f"wrote {logo_path.relative_to(ROOT)} ({logo_path.stat().st_size} bytes)")
    print(f"wrote app icon 1024 + iOS/Android/macos/web launcher set")
    return 0


if __name__ == "__main__":
    sys.exit(main())
