"""Cut the sheet into panels and lift them off the paper.

Nothing is redrawn here. The pixels that come out are the pixels the artist put
in; all this does is decide where one panel ends and the next begins, and turn
the cream paper into transparency so the drawing can be composited.
"""

import os
import cv2
import numpy as np
from PIL import Image

SRC = r"S:\GameDev\MineBeatRush\assets\sprites\_concept_sheet.png"
OUT = r"S:\GameDev\MineBeatRush\assets\character\raw"

# Measured off the sheet by analyse_sheet.py, not guessed.
TURN_Y = (40, 640)
FACE_Y = (675, 1000)
# The turnaround's four panels. Panels 3 and 4 share a column band because their
# scarves touch, so the split between them is placed in the gap between the two
# figures rather than taken from the profile.
TURN_X = [(18, 380), (400, 752), (756, 1076), (1080, 1420)]
FACE_X = [(60, 350), (405, 730), (740, 1055), (1105, 1400)]

NAMES_TURN = ["front_sit", "front_stand", "side", "back"]
NAMES_FACE = ["happy", "surprised", "determined", "worried"]


def cutout(a: np.ndarray, paper: np.ndarray) -> np.ndarray:
    """Paper to transparency, found by connectivity rather than by colour.

    Colour distance is the obvious way to do this and it is wrong for this
    drawing, because the drawing contains colours as light as the paper: the
    white highlights inside the ears, the pale chest, the muzzle. Thresholding
    on distance made every one of them partly transparent, and the character
    rendered with the background showing through its lightest parts.

    The paper has one property those highlights do not: it touches the border
    and they do not. Flooding inward from the edge separates them exactly.
    """
    h, w = a.shape[:2]
    near = (np.abs(a[:, :, :3].astype(np.int16) - paper.astype(np.int16))
            .sum(axis=2) < 30).astype(np.uint8)
    ff = np.zeros((h + 2, w + 2), np.uint8)
    ff[1:-1, 1:-1] = 1 - near          # non-paper is a wall the flood cannot cross
    bg = np.zeros((h, w), np.uint8)
    filled = (1 - near).copy()
    mask = np.zeros((h + 2, w + 2), np.uint8)
    mask[1:-1, 1:-1] = filled
    seed_img = np.zeros((h, w), np.uint8)
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if near[seed[1], seed[0]]:
            cv2.floodFill(seed_img, mask, seed, 255)
    bg = seed_img

    # Coverage at the boundary, opacity everywhere else.
    #
    # The flood decides *which* pixels are drawing; it cannot say how much of an
    # antialiased edge pixel is ink. Treating the whole flooded interior as
    # fully opaque keeps the paper mixed into that one-pixel rim, and the sprite
    # wears a pale outline over any darker background. So the boundary band gets
    # its alpha from how far the pixel is from the paper colour, which is what
    # its coverage actually was, and un-matting below removes the rest.
    d = np.abs(a[:, :, :3].astype(np.float32) - paper).sum(axis=2)
    inside = (255 - bg).astype(np.uint8)
    dist = cv2.distanceTransform(inside, cv2.DIST_L2, 3)
    coverage = np.clip((d - 6.0) / 48.0, 0.0, 1.0)
    alpha = np.where(bg > 0, 0.0, np.where(dist <= 2.0, coverage, 1.0))

    # Un-matting. An edge pixel is not the drawing's colour: it is the drawing
    # blended with the paper, C = a*F + (1-a)*paper. Kept as-is it carries cream
    # into every semi-transparent pixel, and the sprite wears a pale halo the
    # moment it is composited over anything darker than the page. Solving back
    # for F removes the paper instead of hiding it.
    a3 = alpha[:, :, None]
    safe = np.maximum(a3, 0.06)
    fg = (a[:, :, :3].astype(np.float32) - (1.0 - a3) * paper) / safe
    out = a.copy()
    out[:, :, :3] = np.clip(fg, 0, 255).astype(np.uint8)
    out[:, :, 3] = (alpha * 255).astype(np.uint8)
    return out


def trim(a: np.ndarray) -> tuple:
    ys, xs = np.nonzero(a[:, :, 3] > 8)
    if len(ys) == 0:
        return a, (0, 0)
    y0, y1 = ys.min(), ys.max() + 1
    x0, x1 = xs.min(), xs.max() + 1
    return a[y0:y1, x0:x1], (int(x0), int(y0))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(SRC).convert("RGBA")
    a = np.array(im)
    paper = np.array([253.2, 243.8, 234.0], dtype=np.float32)
    cut = cutout(a, paper)

    for name, (x0, x1) in zip(NAMES_TURN, TURN_X):
        sub = cut[TURN_Y[0]:TURN_Y[1], x0:x1]
        sub, off = trim(sub)
        Image.fromarray(sub).save(os.path.join(OUT, f"panel_{name}.png"))
        print(f"panel_{name}.png  {sub.shape[1]} x {sub.shape[0]}  "
              f"(sheet origin {x0 + off[0]},{TURN_Y[0] + off[1]})")

    for name, (x0, x1) in zip(NAMES_FACE, FACE_X):
        sub = cut[FACE_Y[0]:FACE_Y[1], x0:x1]
        sub, off = trim(sub)
        Image.fromarray(sub).save(os.path.join(OUT, f"face_{name}.png"))
        print(f"face_{name}.png  {sub.shape[1]} x {sub.shape[0]}  "
              f"(sheet origin {x0 + off[0]},{FACE_Y[0] + off[1]})")


if __name__ == "__main__":
    main()
