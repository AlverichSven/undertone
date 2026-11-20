#!/usr/bin/env python3
"""Render the Undertone app icon (org edition) and build an .icns.

Dark, minimal squircle with a soft gradient waveform. Own design, not a copy of any product logo.
Usage: python3 scripts/org_make_icon.py <out_dir>   -> <out_dir>/Undertone.png, Undertone.icns
"""
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4096  # supersampled canvas, downscaled to 1024
OUT = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def squircle_mask(size, inset, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (inset, inset, size - inset, size - inset), radius=radius, fill=255
    )
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(g)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(top, bottom, y / (size - 1)))
    return g


def horizontal_gradient(size, stops):
    g = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(g)
    for x in range(size):
        t = x / (size - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                d.line([(x, 0), (x, size)], fill=lerp(c0, c1, (t - p0) / (p1 - p0)))
                break
    return g


def main(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    inset = int(S * 0.098)  # macOS icon grid: ~824/1024 body
    radius = int(S * 0.185)
    mask = squircle_mask(S, inset, radius)

    # Body: deep night blue to near black, with a faint top highlight.
    body = vertical_gradient(S, (28, 30, 52, 255), (8, 8, 14, 255))
    glow_top = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow_top).ellipse((S * 0.15, -S * 0.55, S * 0.85, S * 0.35), fill=70)
    glow_top = glow_top.filter(ImageFilter.GaussianBlur(S * 0.06))
    body = Image.composite(Image.new("RGBA", (S, S), (120, 130, 255, 255)), body, glow_top)

    # Waveform: symmetric rounded bars, envelope tapering to the edges.
    bars = Image.new("L", (S, S), 0)
    bd = ImageDraw.Draw(bars)
    n = 11
    area_w = S * 0.56
    bar_w = area_w / (n * 1.75)
    gap = (area_w - n * bar_w) / (n - 1)
    x0 = (S - area_w) / 2
    cy = S / 2
    heights = [0.10, 0.20, 0.34, 0.24, 0.46, 0.62, 0.46, 0.30, 0.38, 0.20, 0.10]
    for i, h in enumerate(heights):
        x = x0 + i * (bar_w + gap)
        half = S * h / 2
        bd.rounded_rectangle((x, cy - half, x + bar_w, cy + half), radius=bar_w / 2, fill=255)

    color = horizontal_gradient(
        S, [(0.0, (110, 92, 255, 255)), (0.5, (64, 170, 255, 255)), (1.0, (40, 225, 210, 255))]
    )

    # Soft glow under the bars.
    glow = bars.filter(ImageFilter.GaussianBlur(S * 0.03))
    glow = glow.point(lambda v: int(v * 0.65))
    canvas = body.copy()
    canvas = Image.composite(color, canvas, glow)
    canvas = Image.composite(color, canvas, bars)

    # Thin inner rim for depth.
    rim = ImageChops.subtract(mask, squircle_mask(S, inset + int(S * 0.006), radius))
    canvas = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 40)), canvas, rim)

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(canvas, (0, 0), mask)

    # Drop shadow like system icons.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sm = mask.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda v: int(v * 0.35))
    shadow.paste(Image.new("RGBA", (S, S), (0, 0, 0, 255)), (0, int(S * 0.01)), sm)
    final = Image.alpha_composite(shadow, icon).resize((OUT, OUT), Image.LANCZOS)

    png = out_dir / "Undertone.png"
    final.save(png)

    iconset = out_dir / "Undertone.iconset"
    iconset.mkdir(exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        final.resize((base, base), Image.LANCZOS).save(iconset / f"icon_{base}x{base}.png")
        final.resize((base * 2, base * 2), Image.LANCZOS).save(iconset / f"icon_{base}x{base}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out_dir / "Undertone.icns")], check=True)
    print(out_dir / "Undertone.icns")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "org"))
