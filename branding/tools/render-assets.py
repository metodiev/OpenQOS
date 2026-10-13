#!/usr/bin/env python3
"""Render OpenQOS raster assets from their SVG sources.

Run inside the Fedora development VM:

    branding/tools/render-assets.py
    branding/tools/render-assets.py --check

Why a generator instead of hand-exported files
----------------------------------------------
The SVGs are the artwork. The PNGs and JPEGs are derived from them, and they have
to be derived *the same way every time*, or the images in a build stop matching
the sources they claim to come from. A committed generator plus committed output
means a reviewer can see both, and a rebuild that differs shows up as a diff.

No new build dependency
-----------------------
The development VM has no rsvg-convert, no ImageMagick and no Pillow, and the
cairo GObject binding exposes no surface type (that needs pycairo). It does have
GdkPixbuf, and librsvg ships a GdkPixbuf loader, so GdkPixbuf renders the SVGs
directly. That is the whole dependency list: a library the desktop already uses.

`cover` rather than `stretch`
-----------------------------
The wallpaper is designed at 16:9, but a wallpaper package also ships a portrait
variant. Rendering a 16:9 document into a 9:16 surface would squash the design,
so each target is rendered the way a wallpaper is displayed: scaled to cover the
target, then centre-cropped. The intermediate size is computed *from the target*,
so it keeps the target's aspect ratio, which means the SVG is never distorted —
only ever scaled uniformly and then cropped.

Determinism
-----------
The asset table is ordered and no timestamp is written into any output, so two
runs produce byte-identical files. `--check` reports whether the committed files
still match what the sources produce.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import gi

    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
except (ImportError, ValueError) as error:  # pragma: no cover - environment check
    print(f"error: cannot load GdkPixbuf: {error}", file=sys.stderr)
    print("       Install: gdk-pixbuf2 librsvg2 python3-gobject", file=sys.stderr)
    raise SystemExit(1) from error


BRANDING_DIR = Path(__file__).resolve().parent.parent

# Backdrop used when an asset is rendered opaque. Matches the darkest stop of the
# wallpaper gradient, so a transparent region can never become a bright seam.
OPAQUE_BACKDROP = 0x0B1219FF


@dataclass(frozen=True)
class Asset:
    """One rendered output, and where it goes."""

    source: str
    output: str
    width: int
    height: int
    format: str = "png"
    alpha: bool = True
    quality: int = 92


# Everything the image needs, plus review copies kept beside the sources.
# Wallpapers are opaque; logos keep their transparency.
ASSETS: tuple[Asset, ...] = (
    # The desktop wallpaper package: /usr/share/wallpapers/OpenQOS
    Asset("wallpapers/openqos-default.svg", "wallpapers/contents/images/3840x2160.png", 3840, 2160, alpha=False),
    Asset("wallpapers/openqos-default.svg", "wallpapers/contents/images/1080x1920.png", 1080, 1920, alpha=False),
    Asset("wallpapers/openqos-default.svg", "wallpapers/contents/screenshot.png", 1024, 576, alpha=False),
    # Look-and-feel previews, installed by the config overlay in config/common.
    Asset(
        "wallpapers/openqos-default.svg",
        "../config/common/usr/share/plasma/look-and-feel/org.openqos.desktop/contents/previews/preview.png",
        512,
        288,
        alpha=False,
    ),
    Asset(
        "wallpapers/openqos-default.svg",
        "../config/common/usr/share/plasma/look-and-feel/org.openqos.desktop/contents/previews/fullscreenpreview.jpg",
        1920,
        1080,
        format="jpeg",
        alpha=False,
    ),
    # The hicolor icon named by LOGO=openqos-logo in os-release. The inverse mark,
    # because OpenQOS ships a dark desktop and the icon is read on dark surfaces.
    # SVG is what icon themes prefer; the PNG sizes exist for tools that still ask
    # for a raster icon and will not follow a scalable one.
    Asset("logo/openqos-mark-inverse.svg", "icons/hicolor/scalable/apps/openqos-logo.svg", 0, 0, format="copy"),
    Asset("logo/openqos-mark-inverse.svg", "icons/hicolor/256x256/apps/openqos-logo.png", 256, 256),
    Asset("logo/openqos-mark-inverse.svg", "icons/hicolor/48x48/apps/openqos-logo.png", 48, 48),
    # Boot splash watermark. Plymouth's own `two-step` module loads this exact
    # filename from the theme's ImageDir, which is why it is not called
    # openqos-logo.png here.
    Asset("logo/openqos-logo-inverse.svg", "plymouth/openqos/watermark.png", 560, 163),
    # Review copies for the README and for eyeballing changes: both the light and
    # the dark variant, so a change to one is visibly a change to a pair.
    Asset("logo/openqos-logo.svg", "logo/dist/openqos-logo.png", 1100, 320),
    Asset("logo/openqos-logo-inverse.svg", "logo/dist/openqos-logo-inverse.png", 1100, 320),
    Asset("logo/openqos-mark.svg", "logo/dist/openqos-mark.png", 512, 512),
    Asset("logo/openqos-mark-inverse.svg", "logo/dist/openqos-mark-inverse.png", 512, 512),
)


def svg_size(path: Path) -> tuple[float, float]:
    """Read the intrinsic size from an SVG's root element."""
    header = path.read_text(encoding="utf-8")[:2048]
    match = re.search(r'<svg\b[^>]*?width="([0-9.]+)"[^>]*?height="([0-9.]+)"', header, re.S)
    if not match:
        raise ValueError(f"{path}: no width/height on the <svg> element")
    return float(match.group(1)), float(match.group(2))


def flatten(pixbuf: GdkPixbuf.Pixbuf) -> GdkPixbuf.Pixbuf:
    """Composite a pixbuf onto an opaque backdrop, dropping the alpha channel."""
    flat = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, pixbuf.get_width(), pixbuf.get_height())
    flat.fill(OPAQUE_BACKDROP)
    pixbuf.composite(
        flat, 0, 0, pixbuf.get_width(), pixbuf.get_height(), 0, 0, 1, 1, GdkPixbuf.InterpType.BILINEAR, 255
    )
    return flat


def render(asset: Asset) -> bytes:
    """Render one asset and write it to its output path."""
    source = BRANDING_DIR / asset.source
    output = BRANDING_DIR / asset.output
    output.parent.mkdir(parents=True, exist_ok=True)

    doc_width, doc_height = svg_size(source)

    # Scale the *target* by the cover factor, so the intermediate keeps the
    # target's aspect ratio and the SVG is scaled uniformly.
    scale = max(asset.width / doc_width, asset.height / doc_height)
    intermediate_width = round(doc_width * scale)
    intermediate_height = round(doc_height * scale)

    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
        str(source), intermediate_width, intermediate_height, False
    )

    if (intermediate_width, intermediate_height) != (asset.width, asset.height):
        pixbuf = pixbuf.new_subpixbuf(
            (intermediate_width - asset.width) // 2,
            (intermediate_height - asset.height) // 2,
            asset.width,
            asset.height,
        )

    if not asset.alpha:
        pixbuf = flatten(pixbuf)

    if asset.format == "png":
        pixbuf.savev(str(output), "png", ["compression"], ["9"])
    elif asset.format in {"jpeg", "jpg"}:
        pixbuf.savev(str(output), "jpeg", ["quality"], [str(asset.quality)])
    else:
        raise ValueError(f"unsupported format: {asset.format}")

    return output.read_bytes()


def copy_asset(asset: Asset) -> bytes:
    """Copy a source file to its output path verbatim."""
    source = BRANDING_DIR / asset.source
    output = BRANDING_DIR / asset.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(source.read_bytes())
    return output.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser(description="Render OpenQOS raster assets from SVG sources.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the committed assets match the sources instead of rewriting them",
    )
    args = parser.parse_args()

    stale: list[str] = []
    for asset in ASSETS:
        path = BRANDING_DIR / asset.output
        produced = copy_asset(asset) if asset.format == "copy" else render(asset)
        digest = hashlib.sha256(produced).hexdigest()

        if args.check:
            actual = path.read_bytes()
            if hashlib.sha256(actual).hexdigest() != digest:
                stale.append(asset.output)
                print(f"STALE  {asset.output}")
            else:
                print(f"ok     {asset.output}  {len(actual):>9} bytes")
        else:
            print(f"render {asset.output}  {len(produced):>9} bytes  sha256:{digest[:16]}")

    if args.check and stale:
        print(f"\n{len(stale)} asset(s) do not match their source; re-run without --check.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
