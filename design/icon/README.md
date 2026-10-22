# Snap icon

<img src="web/icon-512.png" width="160" alt="Snap app icon">

**Idea:** a selection being dragged out, with the screenshot crosshair on the corner you're
dragging. The dark tile is the dimmed screen, the yellow block is the part you selected.

## Files

| File | Use |
| --- | --- |
| `snap-symbol.svg` | Master symbol, one colour. 40 px and up. |
| `snap-symbol-small.svg` | Small-size cut: thicker crosshair, wider gaps. Below 40 px, and the menu bar. |
| `snap-symbol-white.svg` | One colour, for dark backgrounds. |
| `app-icon.svg` | macOS app icon master (1024 canvas, 824 body, macOS template). 64 px and up. |
| `app-icon-small.svg` | App icon built on the small cut. 16 and 32 px. |
| `build_icon.py` | Generates both app icon SVGs and `Resources/AppIcon.icon` from the symbol geometry and a palette. |
| `web/` | `favicon.ico` (16/32/48), `favicon.svg`, `apple-touch-icon.png`, 192 and 512 px icons. |
| `explorations/` | The concept round (`concepts.png`) and colour round (`colors.png`) that led here. |

The app ships two forms of the icon:

- `Resources/AppIcon.icon`: an Icon Composer document (background fill plus the block and
  crosshair layers). `scripts/bundle.sh` compiles it into `Assets.car` with `actool` from Xcode 26.
  macOS 26 uses it; without it, macOS 26 shrinks the icon into a grey frame.
- `Resources/AppIcon.icns`: rendered from the two app icon SVGs, for macOS 14 and 15 (and for
  builds with an older Xcode).

The menu bar glyph is drawn in code from the small cut (`Sources/Snap/MenuBar/MenuBarIcon.swift`);
keep the two in sync.

## Colours

| Name | HEX | RGB | Used for |
| --- | --- | --- | --- |
| Snap Yellow | `#FFC531` | 255 197 49 | The selection block |
| Graphite (top) | `#2B2E38` | 43 46 56 | Tile gradient, top |
| Graphite (bottom) | `#15161B` | 21 22 27 | Tile gradient, bottom |
| White | `#FFFFFF` | 255 255 255 | Crosshair |

Snap Yellow on white has too little contrast for the symbol. On light backgrounds use the
one-colour black symbol, or the full app icon with its tile.

## Rules

- **Clear space:** keep at least one crosshair arm length (40 units on the 256 grid, about 20 % of
  the symbol's width) free around the symbol.
- **Minimum size:** 16 px with the small cut; standard cut from 40 px.
- **Don't** rotate or mirror it: the crosshair belongs on the bottom-right corner, where a drag ends.
- **Don't** recolour the crosshair or the block separately, round the block's corners, or add
  outlines, glows or extra shadows.
- **Don't** close the gap between block and crosshair; it's what keeps the two readable at small sizes.

## Rebuilding

```sh
python3 build_icon.py      # writes app-icon.svg, app-icon-small.svg and ../../Resources/AppIcon.icon
```

To rebuild `AppIcon.icns`, render the iconset with any SVG renderer (the icon was made with the
`logo-design` skill's `render_png.py`, which uses headless Chrome) and run `iconutil`:
`app-icon-small.svg` for the 16 and 32 px slots (including 16@2x), `app-icon.svg` for all others.

```sh
iconutil -c icns AppIcon.iconset -o ../../Resources/AppIcon.icns
```

The design hasn't been through a trademark search.
