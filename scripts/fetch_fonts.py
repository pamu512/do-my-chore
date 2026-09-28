#!/usr/bin/env python3
"""Fetch static TTFs for the C-Ledger design system into app/assets/fonts/."""
import os
import re
import urllib.request

OUT = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "fonts")
os.makedirs(OUT, exist_ok=True)

# Legacy UA makes the CSS API serve TTF links instead of woff2 subsets.
UA = ("Mozilla/5.0 (Windows NT 5.1)")
FAMILIES = [
    ("Public Sans", "Public+Sans:wght@400;500;600;700", "PublicSans"),
    ("Fraunces", "Fraunces:opsz,wght@9..144,600;9..144,700", "Fraunces"),
]

fetch = []
for label, query, prefix in FAMILIES:
    css_url = f"https://fonts.googleapis.com/css2?family={query}&display=swap"
    req = urllib.request.Request(css_url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        css = r.read().decode()
    blocks = re.findall(r"@font-face\s*{([^}]+)}", css)
    for block in blocks:
        wm = re.search(r"font-weight:\s*(\d+)", block)
        um = re.search(r"url\((https://fonts\.gstatic\.com/[^)]+\.ttf)\)", block)
        if not (wm and um):
            continue
        weight = wm.group(1)
        name = f"{prefix}-{weight}.ttf"
        fetch.append((name, um.group(1), label))

ok = True
for name, url, label in fetch:
    path = os.path.join(OUT, name)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    with open(path, "wb") as f:
        f.write(data)
    good = len(data) > 20000 and data[:4] in (b"\x00\x01\x00\x00", b"true", b"OTTO")
    ok = ok and good
    print(f"{'OK ' if good else 'BAD'} {name:20s} {len(data):8d} bytes  ({label})")

print("ALL FONTS OK" if ok and fetch else "FONT FETCH FAILED")
