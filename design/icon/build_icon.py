#!/usr/bin/env python3
"""Builds the Snap app icon SVGs from the symbol geometry.

Usage: python3 build_icon.py [--palette NAME] [--out-dir DIR]

Writes app-icon.svg (512 px and up) and app-icon-small.svg (16-32 px, uses the small cut).
The icon follows the macOS template: a 1024 canvas with an 824 px continuous-corner body
centred on it and a soft drop shadow.

Also writes AppIcon.icon, the Icon Composer document macOS 26 needs: there the system draws the
tile, mask and lighting itself, and only gets the background fill and the symbol layers.
Without it, macOS 26 shrinks the old-style icon into a grey frame.
"""
import argparse
import json
import math
import pathlib

# Symbol geometry on the 256 grid (same as snap-symbol.svg / snap-symbol-small.svg).
SYMBOL = {
    "block": "M40 56H184V108H159V151H116V176H40Z",
    "cross": "M130 165H170V187H130ZM198 165H238V187H198ZM173 122H195V162H173ZM173 190H195V230H173Z",
    "offset": (-11, -17),
    "bounds": (29, 39, 227, 213),  # x0, y0, x1, y1 after the offset
}
SYMBOL_SMALL = {
    "block": "M36 56H180V94H146V138H102V172H36Z",
    "cross": "M122 158H162V186H122ZM198 158H238V186H198ZM166 114H194V154H166ZM166 190H194V230H166Z",
    "offset": (-9, -15),
    "bounds": (27, 41, 229, 215),
}

# tile gradient top/bottom, selection block, crosshair, rim (keeps the edge visible on
# backgrounds close to the tile colour)
PALETTES = {
    "night": ("#2B2E38", "#15161B", "#FFC531", "#FFFFFF", "rgba(255,255,255,0.14)"),
    "blueprint": ("#4F7BFF", "#2A4FE0", "#FFFFFF", "#FFC531", "rgba(255,255,255,0.18)"),
    "daylight": ("#FFFFFF", "#E6E8EE", "#FF5A4E", "#23252D", "rgba(0,0,0,0.08)"),
}


def squircle_path(x, y, size, n=5.0, steps=720):
    """Superellipse |u|^n + |v|^n = 1, close to Apple's continuous-corner icon shape."""
    half = size / 2
    cx, cy = x + half, y + half
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        px = cx + half * math.copysign(abs(c) ** (2 / n), c)
        py = cy + half * math.copysign(abs(s) ** (2 / n), s)
        points.append(f"{px:.2f} {py:.2f}")
    return "M" + "L".join(points) + "Z"


def icon_svg(symbol, palette, scale):
    tile_top, tile_bottom, block, cross, rim = palette
    x0, y0, x1, y1 = symbol["bounds"]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    # Optical centre: a touch above the geometric centre of the body.
    tx, ty = 512 - cx * scale, 506 - cy * scale
    ox, oy = symbol["offset"]
    body = squircle_path(100, 100, 824)
    inner = squircle_path(102, 102, 820)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <title>Snap</title>
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{tile_top}"/>
      <stop offset="1" stop-color="{tile_bottom}"/>
    </linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.3"/>
    </filter>
  </defs>
  <path d="{body}" fill="url(#tile)" filter="url(#shadow)"/>
  <path d="{inner}" fill="none" stroke="{rim}" stroke-width="4"/>
  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale}) translate({ox} {oy})">
    <path d="{symbol['block']}" fill="{block}"/>
    <path d="{symbol['cross']}" fill="{cross}"/>
  </g>
</svg>
"""


def srgb(hex_colour):
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def layer_svg(path, colour, scale):
    """One symbol layer on the full-bleed 1024 Icon Composer canvas."""
    x0, y0, x1, y1 = SYMBOL["bounds"]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    tx, ty = 512 - cx * scale, 504 - cy * scale
    ox, oy = SYMBOL["offset"]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale}) translate({ox} {oy})">
    <path d="{path}" fill="{colour}"/>
  </g>
</svg>
"""


def write_icon_composer(bundle, palette):
    tile_top, tile_bottom, block, cross, _ = palette
    (bundle / "Assets").mkdir(parents=True, exist_ok=True)
    # Same symbol-to-tile proportion as app-icon.svg (2.3 on an 824 body), on a 1024 body.
    scale = 2.3 * 1024 / 824
    (bundle / "Assets" / "block.svg").write_text(layer_svg(SYMBOL["block"], block, scale))
    (bundle / "Assets" / "crosshair.svg").write_text(layer_svg(SYMBOL["cross"], cross, scale))
    document = {
        "fill": {"linear-gradient": [srgb(tile_top), srgb(tile_bottom)]},
        "groups": [
            {
                "layers": [
                    {"image-name": "crosshair.svg", "name": "crosshair", "glass": False},
                    {"image-name": "block.svg", "name": "block", "glass": False},
                ],
                "shadow": {"kind": "neutral", "opacity": 0.4},
                "translucency": {"enabled": False, "value": 0},
            }
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (bundle / "icon.json").write_text(json.dumps(document, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--palette", choices=sorted(PALETTES), default="night")
    parser.add_argument("--out-dir", default=".")
    parser.add_argument("--icon-composer", default="../../Resources/AppIcon.icon",
                        help="where to write the Icon Composer document (compiled by scripts/bundle.sh)")
    args = parser.parse_args()
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    palette = PALETTES[args.palette]
    (out / "app-icon.svg").write_text(icon_svg(SYMBOL, palette, 2.3))
    (out / "app-icon-small.svg").write_text(icon_svg(SYMBOL_SMALL, palette, 2.6))
    write_icon_composer(pathlib.Path(args.icon_composer), palette)


if __name__ == "__main__":
    main()
