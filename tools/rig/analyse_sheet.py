"""Find what is actually on the concept sheet, before cutting anything.

Measuring the panels rather than guessing at coordinates: the sheet is a
turnaround plus an expression row, and every part that gets cut later has to be
located against a panel that was found, not against a number someone typed.
"""

import sys
import numpy as np
from PIL import Image

SRC = r"S:\GameDev\MineBeatRush\assets\sprites\_concept_sheet.png"


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    a = np.array(im)
    h, w = a.shape[:2]
    print(f"sheet {w} x {h}")

    # The paper is a flat cream. Sample the corners rather than assuming it.
    corners = np.array([a[4, 4], a[4, w - 5], a[h - 5, 4], a[h - 5, w - 5]])
    paper = corners[:, :3].mean(axis=0)
    print("paper colour", paper.round(1))

    # Ink-or-fill: anything far enough from the paper to be part of a drawing.
    d = np.abs(a[:, :, :3].astype(np.int16) - paper.astype(np.int16)).sum(axis=2)
    fg = d > 26
    print("foreground coverage %.1f%%" % (100.0 * fg.mean()))

    # Column and row profiles show the gutters between panels directly.
    cols = fg.sum(axis=0)
    rows = fg.sum(axis=1)

    def runs(profile: np.ndarray, thresh: int) -> list:
        out = []
        start = None
        for i, v in enumerate(profile):
            if v > thresh and start is None:
                start = i
            elif v <= thresh and start is not None:
                out.append((start, i - 1))
                start = None
        if start is not None:
            out.append((start, len(profile) - 1))
        return [r for r in out if r[1] - r[0] > 20]

    print("\ncolumn bands (panels left..right):")
    for r in runs(cols, 2):
        print("   x %4d .. %4d   width %4d" % (r[0], r[1], r[1] - r[0] + 1))
    print("\nrow bands (turnaround row, expression row):")
    for r in runs(rows, 2):
        print("   y %4d .. %4d   height %4d" % (r[0], r[1], r[1] - r[0] + 1))

    # The palette actually used, so the cut parts can be matched exactly rather
    # than eyeballed off a screenshot.
    px = a[fg][:, :3].reshape(-1, 3)
    q = (px // 12 * 12).astype(np.uint8)
    uniq, counts = np.unique(q, axis=0, return_counts=True)
    order = np.argsort(-counts)[:14]
    print("\ndominant colours:")
    for i in order:
        c = uniq[i]
        print("   #%02x%02x%02x  %6.2f%%" % (c[0], c[1], c[2],
                                             100.0 * counts[i] / len(q)))


if __name__ == "__main__":
    sys.exit(main())
