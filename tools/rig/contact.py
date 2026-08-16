"""Contact sheet of the generated candidates, for picking by eye.

A generator is not reliable per sample. Which of three candidates is the pose
you asked for, drawn as the character you asked for, is a judgement made by
looking at them side by side - the same way a sprite sheet has always been
approved.
"""

import os
import sys
from PIL import Image, ImageDraw

SRC = sys.argv[1] if len(sys.argv) > 1 else r"S:\GameDev\MineBeatRush\tools\rig\gen"
DST = sys.argv[2] if len(sys.argv) > 2 else os.path.join(SRC, "_contact.png")
CELL = int(sys.argv[3]) if len(sys.argv) > 3 else 230


def main() -> None:
    names = sorted(f for f in os.listdir(SRC)
                   if f.endswith(".png") and not f.startswith("_"))
    if not names:
        raise SystemExit("nothing to contact-sheet in " + SRC)
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * CELL, rows * CELL), (250, 246, 238))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(SRC, n)).convert("RGB").resize((CELL, CELL))
        x, y = (i % cols) * CELL, (i // cols) * CELL
        sheet.paste(im, (x, y))
        d.rectangle([x, y, x + CELL - 1, y + 16], fill=(20, 20, 24))
        d.text((x + 4, y + 3), n[:-4], fill=(255, 255, 255))
    sheet.save(DST)
    print(f"{DST}  {len(names)} images")


if __name__ == "__main__":
    main()
