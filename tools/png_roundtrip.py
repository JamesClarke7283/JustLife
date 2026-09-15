#!/usr/bin/env python3
"""Convert PNG through JPEG and save a slightly transparent PNG.

Install: python3 -m pip install Pillow
Usage: python3 tools/png_roundtrip.py input.png output.png --opacity 0.98

JPEG is lossy and has no transparency: transparent areas are flattened onto
white. The intermediate JPEG is kept in memory. Existing files are protected.
"""

import argparse
from io import BytesIO
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--opacity", type=float, default=0.98,
                        help="Final opacity from 0 to 1 (default: 0.98).")
    parser.add_argument("--quality", type=int, default=95,
                        help="Intermediate JPEG quality from 1 to 95 (default: 95).")
    args = parser.parse_args()
    if not 0 <= args.opacity <= 1:
        parser.error("--opacity must be between 0 and 1")
    if not 1 <= args.quality <= 95:
        parser.error("--quality must be between 1 and 95")
    output = args.output or args.input.with_name(args.input.stem + "_edited.png")
    if output.suffix.lower() != ".png":
        parser.error("output must have a .png extension")
    if output.exists():
        parser.error(f"Output already exists: {output}")

    try:
        from PIL import Image
    except ImportError:
        parser.error("Install Pillow first: python3 -m pip install Pillow")

    try:
        with Image.open(args.input) as source:
            if source.format != "PNG":
                parser.error("input must be a PNG image")
            rgba = source.convert("RGBA")
        background = Image.new("RGBA", rgba.size, "white")
        rgb = Image.alpha_composite(background, rgba).convert("RGB")
        with BytesIO() as jpeg:
            rgb.save(jpeg, format="JPEG", quality=args.quality)
            jpeg.seek(0)
            with Image.open(jpeg) as decoded:
                result = decoded.convert("RGBA")
            result.putalpha(round(255 * args.opacity))
            with output.open("xb") as destination:
                result.save(destination, format="PNG")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"Saved {output} at {args.opacity:.0%} opacity")


if __name__ == "__main__":
    main()
