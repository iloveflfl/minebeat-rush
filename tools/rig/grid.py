"""Overlay a coordinate grid so cut boundaries can be read off rather than guessed.

Every earlier attempt at this character failed in the same place: a number was
estimated from a screenshot, looked about right, and was wrong by enough to cut
through something. Reading coordinates off a labelled grid costs one image and
removes that whole class of mistake.
"""

import sys
import numpy as np
from PIL import Image, ImageDraw

SRC = sys.argv[1]
DST = sys.argv[2]
STEP = int(sys.argv[3]) if len(sys.argv) > 3 else 20
SCALE = int(sys.argv[4]) if len(sys.argv) > 4 else 2


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    bg = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    bg.alpha_composite(im)
    bg = bg.resize((w * SCALE, h * SCALE), Image.NEAREST)
    d = ImageDraw.Draw(bg)
    for x in range(0, w, STEP):
        heavy = (x % (STEP * 5)) == 0
        d.line([(x * SCALE, 0), (x * SCALE, h * SCALE)],
               fill=(0, 140, 255, 200) if heavy else (0, 200, 255, 90),
               width=2 if heavy else 1)
        if heavy:
            d.text((x * SCALE + 3, 3), str(x), fill=(0, 80, 200, 255))
    for y in range(0, h, STEP):
        heavy = (y % (STEP * 5)) == 0
        d.line([(0, y * SCALE), (w * SCALE, y * SCALE)],
               fill=(255, 60, 160, 200) if heavy else (255, 120, 200, 90),
               width=2 if heavy else 1)
        if heavy:
            d.text((3, y * SCALE + 3), str(y), fill=(190, 0, 90, 255))
    bg.convert("RGB").save(DST)
    print(f"{DST}  source {w}x{h}  grid {STEP}px  scale {SCALE}x")


if __name__ == "__main__":
    main()
