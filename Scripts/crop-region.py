"""Crop a screen capture to a region given in screen points.

`screencapture` writes backing-store pixels, so the point region is scaled by
the display's backing scale factor. The caller passes that factor because only
the capture script knows which display produced the image.
"""

import sys

from PIL import Image


def main() -> int:
    if len(sys.argv) not in (8, 9):
        print(
            "usage: crop-region.py SOURCE TARGET X Y WIDTH HEIGHT MARGIN [SCALE]",
            file=sys.stderr,
        )
        return 64

    source, target = sys.argv[1], sys.argv[2]
    x, y, width, height, margin = (int(value) for value in sys.argv[3:8])
    scale = float(sys.argv[8]) if len(sys.argv) == 9 else 0

    image = Image.open(source)
    if scale <= 0:
        # Fall back to the ratio between captured pixels and the region's own
        # screen extent, which is correct for a single-display capture.
        scale = 2 if image.width > 2560 else 1

    left = max(0, round((x - margin) * scale))
    top = max(0, round((y - margin) * scale))
    right = min(image.width, round((x + width + margin) * scale))
    bottom = min(image.height, round((y + height + margin) * scale))

    if right <= left or bottom <= top:
        print(f"empty crop region for {source}", file=sys.stderr)
        return 1

    image.crop((left, top, right, bottom)).save(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
