# Artwork provenance

Every file in `branding/` is original work made for this project. Nothing here is
copied, traced, recoloured or derived from Fedora's artwork, from KDE's artwork, or
from any third-party source. That matters for two reasons: Fedora's marks are
reserved (see [licensing.md §7](../docs/licensing.md)), and a wallpaper with an
unclear origin is a liability nobody wants to audit later.

## What is in here

| Path | What it is | Licence |
| --- | --- | --- |
| `logo/openqos-mark.svg` | The mark, for light backgrounds | CC BY-SA 4.0 |
| `logo/openqos-mark-inverse.svg` | The mark, for dark backgrounds | CC BY-SA 4.0 |
| `logo/openqos-logo.svg` | Horizontal lockup, for light backgrounds | CC BY-SA 4.0 |
| `logo/openqos-logo-inverse.svg` | Horizontal lockup, for dark backgrounds | CC BY-SA 4.0 |
| `wallpapers/openqos-default.svg` | The default wallpaper, 3840×2160 | CC BY-SA 4.0 |
| `themes/OpenQOS.colors` | Plasma colour scheme | CC BY-SA 4.0 |
| `plymouth/openqos/openqos.plymouth` | Plymouth boot theme | CC BY-SA 4.0 |
| `tools/render-assets.py` | Renders the raster assets | GPL-3.0-or-later |
| Rendered PNG and JPEG outputs | Derived from the SVGs above | CC BY-SA 4.0 |

The generator is source code and carries the project's code licence; the images it
produces are artwork and carry the artwork licence. The split is deliberate, because
the two are used differently: the images are redistributed as assets, the script is
not.

**The licence choice is proposed, not settled.** [licensing.md §7](../docs/licensing.md)
still lists the artwork licence as an open decision. CC BY-SA 4.0 is what the files
declare today because it is the usual choice for design assets and its share-alike
term keeps a later closed derivative from taking the visual identity private. Full
licence text is not yet bundled; that must happen before any release.

## Authorship

The artwork was created by the OpenQOS project's contributors as work on this
repository. It is geometric construction, not illustration: circles, arcs, straight
strokes and gradients, defined by explicit coordinates. There is no tracing, no
photo manipulation, and no generated-by-model imagery in any of it.

Anyone can therefore check the claim by reading the source. The mark is an arc with
a known centre and radius plus one straight stroke; the wallpaper is two gradients,
three arcs and a vignette; the colour scheme is a table of RGB triples.

## How the raster assets are produced

`branding/tools/render-assets.py` renders every PNG and JPEG from the SVG sources
and is the only thing that writes them. Run it inside the development VM:

```sh
branding/tools/render-assets.py            # rewrite the outputs
branding/tools/render-assets.py --check    # verify the outputs still match
```

It uses GdkPixbuf with librsvg's SVG loader — libraries the desktop already depends
on — so no new build dependency is introduced. Outputs are deterministic: the asset
table is ordered and no timestamp is written, so two runs produce byte-identical
files and a change to the artwork shows up as a reviewable diff.

Two details worth knowing:

* **Cover, not stretch.** The wallpaper is designed at 16:9 and the wallpaper
  package also ships a 9:16 variant. The renderer scales to *cover* the target and
  then centre-crops, so a 16:9 document is never squashed into a portrait frame.
* **The mark appears in three SVG files.** `openqos-mark.svg`,
  `openqos-mark-inverse.svg` and both lockups contain the same arc geometry, drawn
  inline so each file stands alone. **Change them together** — the duplication is a
  deliberate trade of one maintenance burden for the guarantee that no logo file
  breaks when it is copied out of the tree.

## Honest limitations

These are recorded because the alternative is someone discovering them later:

* **The wordmark is not drawn.** "OpenQOS" is set in a generic sans stack
  (`DejaVu Sans`, `Liberation Sans`, `Noto Sans`, `Cantarell`) and split by weight:
  "Open" regular, "QOS" bold. That split is the typographic idea and it survives a
  font substitution, which a hand-kerned wordmark would not — but the letterforms
  are not ours. A release should ship drawn letterforms or a properly licensed face.
* **The boot splash has not been seen.** This development VM has no DRM device, so
  Plymouth falls back to its text renderer and never draws the graphical theme. The
  files, their keys and the module they use are verified; the rendered result is not.
* **The desktop has not been photographed.** `contents/previews/` in the look-and-feel
  contains a scaled crop of the wallpaper, not a screenshot of a running desktop.
  Real screenshots need a virtual GPU; see the roadmap.
* **The name is a working title.** No trademark clearance has been performed on
  "OpenQOS". See [licensing.md](../docs/licensing.md).
