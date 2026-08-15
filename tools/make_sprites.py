"""
Cut the fennec concept sheet into Paper-Mario-style flat sprites.

The sheet is a 4x2 grid: four full-body views on top (front, three-quarter,
side, back) and four expression heads underneath.

Three things happen here that are not just "crop the grid":

1. Background removal is a flood fill from the border, not a colour threshold.
   The character's belly is nearly the same cream as the paper, so a global
   threshold would punch holes straight through it.

2. The trailing scarf is dropped from the body sprites. On the sheet it spans
   about three times the body width, which on a 3-wide Minesweeper deck would
   cover the clue row - and GDD 15.3 puts the numbers above the character in
   reading order. Columns are kept only if they carry ink in the upper part of
   the cell, which is exactly the head/ears/body and not the low trailing ends.
   The scarf still exists in game: it is the simulated ribbon on the neck bone.

3. Head and body are split at the scarf. Paper Mario characters are a stack of
   flat parts, and having the head as its own quad is what lets it lag, tilt and
   swap expression without redrawing the body.

Output: assets/sprites/*.png plus sprites.json (rects and the ground anchor),
and _contact.png for eyeballing the whole cut in one look.

Run:  python tools/make_sprites.py [source.png]
"""

import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "sprites")
os.makedirs(OUT, exist_ok=True)

## The sheet is copied into the project on first run, so the pipeline stops
## depending on whatever is sitting in Downloads.
VENDORED = os.path.join(OUT, "_concept_sheet.png")


def find_source():
    if os.path.exists(VENDORED):
        return VENDORED
    import glob
    candidates = []
    for pattern in ("ChatGPT Image*.png", "*concept*.png", "*fennec*.png"):
        candidates += glob.glob(os.path.join(
            os.path.expanduser("~"), "Downloads", pattern))
    if not candidates:
        return None
    return max(candidates, key=os.path.getmtime)

BODY_NAMES = ["front", "quarter", "side", "back"]
FACE_NAMES = ["happy", "surprised", "determined", "worried"]

# A column is part of the character (rather than trailing scarf) if it has ink
# above this fraction of the cell height.
BODY_TOP_FRACTION = 0.42
BG_TOLERANCE = 26


def load(path):
    img = Image.open(path).convert("RGB")
    return np.asarray(img).astype(np.int16)


def foreground_mask(rgb):
    """True where the artwork is. Flood filled inward from the border."""
    corner = np.median(
        np.concatenate([rgb[0, :], rgb[-1, :], rgb[:, 0], rgb[:, -1]]), axis=0)
    near_bg = np.max(np.abs(rgb - corner), axis=2) < BG_TOLERANCE

    lab, n = ndimage.label(near_bg)
    if n == 0:
        return np.ones(rgb.shape[:2], bool)
    border = np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))
    border = border[border > 0]
    outside = np.isin(lab, border)
    return ~outside


def split_runs(profile, min_gap):
    """Index ranges of consecutive non-empty entries, ignoring short gaps."""
    on = profile > 0
    runs, start = [], None
    gap = 0
    for i, v in enumerate(on):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                runs.append((start, i - gap + 1))
                start = None
    if start is not None:
        runs.append((start, len(on)))
    return runs


def scarf_row(rgb, mask, y0, y1, x0, x1, band):
    """Topmost row where the red scarf appears - the head/body seam.

    `band` limits the search to the fraction of the figure where a neck can
    physically be. Without it the detector latches onto whatever faint warm
    pixel happens to sit highest in the frame and cuts the ears off.
    """
    sub = rgb[y0:y1, x0:x1].astype(np.float32)
    m = mask[y0:y1, x0:x1]
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    mx = sub.max(axis=2)
    mn = sub.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1.0), 0.0)
    # Strongly saturated and clearly red-dominant: the scarf, not the fur and
    # not the much paler pink inside the ears.
    red = m & (sat > 0.42) & (r > 120) & (r > g * 1.45) & (r > b * 1.45)

    n = red.shape[0]
    lo, hi = int(n * band[0]), int(n * band[1])
    per_row = red.sum(axis=1)
    windowed = np.zeros_like(per_row)
    windowed[lo:hi] = per_row[lo:hi]
    if windowed.max() < 8:
        return None
    # Walk up from the widest red row rather than taking the first one. The
    # scarf band is by far the biggest run of red in the figure; the first red
    # row is whatever stray saturated pixel sits highest, which on this sheet is
    # the coral inside the ears - and taking it decapitates the character.
    peak = int(np.argmax(windowed))
    thresh = max(6, windowed[peak] * 0.35)
    row = peak
    while row > lo and windowed[row - 1] >= thresh:
        row -= 1
    return row


def cut(rgb, mask, box, drop_trailing, band):
    """Crop one cell to the character and return (RGBA, seam row within it)."""
    y0, y1, x0, x1 = box
    cell = mask[y0:y1, x0:x1]

    if drop_trailing:
        top_limit = int(cell.shape[0] * BODY_TOP_FRACTION)
        keeps = cell[:top_limit, :].any(axis=0)
        cols = np.nonzero(keeps)[0]
        if cols.size:
            # Widen slightly so the shoulders and the scarf knot survive.
            pad = int(cell.shape[1] * 0.04)
            cx0 = max(0, cols[0] - pad)
            cx1 = min(cell.shape[1], cols[-1] + 1 + pad)
            x0, x1 = x0 + cx0, x0 + cx1
            cell = mask[y0:y1, x0:x1]

    rows = np.nonzero(cell.any(axis=1))[0]
    cols = np.nonzero(cell.any(axis=0))[0]
    y0, y1 = y0 + rows[0], y0 + rows[-1] + 1
    x0, x1 = x0 + cols[0], x0 + cols[-1] + 1

    seam = scarf_row(rgb, mask, y0, y1, x0, x1, band)

    rgba = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    rgba[..., :3] = rgb[y0:y1, x0:x1]
    rgba[..., 3] = mask[y0:y1, x0:x1].astype(np.uint8) * 255
    return rgba, seam


def trim_trailing_scarf(rgba):
    """Crop a body sprite to the animal, cutting the scarf off at the shoulders.

    On the sheet the scarf is posed streaming out to both sides, about three
    times the body's own width. Left in, it would lie across the clue row, and
    GDD 15.3 puts the numbers above the character in reading order. The in-game
    scarf is the simulated ribbon on the neck, so nothing is actually lost.
    """
    # Colour cannot separate them - the scarf carries the same dark outline and
    # the same cream as the fur. Density can: the animal is a tall solid column
    # of ink, the streaming scarf is a thin band passing through. Grow outward
    # from the densest column while the column stays substantial.
    a = rgba[..., 3] > 0
    density = a.sum(axis=0).astype(np.float32)
    if density.max() <= 0:
        return rgba
    peak = int(np.argmax(density))
    floor = density[peak] * 0.33

    x0 = peak
    while x0 > 0 and density[x0 - 1] >= floor:
        x0 -= 1
    x1 = peak
    while x1 < len(density) - 1 and density[x1 + 1] >= floor:
        x1 += 1

    pad = max(4, int(rgba.shape[1] * 0.04))
    x0 = max(0, x0 - pad)
    x1 = min(rgba.shape[1], x1 + 1 + pad)
    out = rgba[:, x0:x1]

    rows = np.nonzero((out[..., 3] > 0).any(axis=1))[0]
    return out[rows[0]:rows[-1] + 1]


def save(name, rgba):
    path = os.path.join(OUT, name + ".png")
    Image.fromarray(rgba, "RGBA").save(path)
    return path


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else find_source()
    if not src or not os.path.exists(src):
        raise SystemExit("concept sheet not found - pass it as an argument")
    print(f"source: {src}")
    if os.path.abspath(src) != os.path.abspath(VENDORED):
        import shutil
        shutil.copyfile(src, VENDORED)
        print(f"vendored -> {VENDORED}")

    rgb = load(src)
    mask = foreground_mask(rgb)
    h, w = mask.shape

    row_runs = split_runs(mask.sum(axis=1), min_gap=int(h * 0.03))
    if len(row_runs) != 2:
        raise SystemExit(f"expected 2 rows of art, found {len(row_runs)}: {row_runs}")

    manifest = {"parts": {}}
    contact = []

    for ri, (ry0, ry1) in enumerate(row_runs):
        band = mask[ry0:ry1]
        col_runs = split_runs(band.sum(axis=0), min_gap=int(w * 0.012))
        if len(col_runs) != 4:
            raise SystemExit(
                f"row {ri}: expected 4 figures, found {len(col_runs)}: {col_runs}")

        names = BODY_NAMES if ri == 0 else FACE_NAMES
        for ci, (cx0, cx1) in enumerate(col_runs):
            rgba, seam = cut(rgb, mask, (ry0, ry1, cx0, cx1), drop_trailing=(ri == 0),
                                    band=(0.28, 0.72) if ri == 0 else (0.55, 1.0))
            name = names[ci]
            hh, ww = rgba.shape[:2]

            if ri == 0:
                if seam is None:
                    seam = int(hh * 0.42)
                head = rgba[:seam + int(hh * 0.03)]
                body = trim_trailing_scarf(rgba[seam - int(hh * 0.02):])
                save(f"body_{name}", body)
                save(f"head_{name}", head)
                manifest["parts"][f"body_{name}"] = {
                    "w": int(body.shape[1]), "h": int(body.shape[0])}
                manifest["parts"][f"head_{name}"] = {
                    "w": int(head.shape[1]), "h": int(head.shape[0]),
                    # Where the head's base sits inside the full figure, as a
                    # fraction of full height - the engine stacks on this.
                    "seam_frac": round(seam / hh, 4),
                    "full_h": int(hh), "full_w": int(ww)}
                contact += [head, body]
            else:
                # Expression heads: trim their collar off at the same seam so
                # they drop straight into the head slot.
                if seam is not None:
                    rgba = rgba[:seam + int(hh * 0.05)]
                save(f"face_{name}", rgba)
                manifest["parts"][f"face_{name}"] = {
                    "w": int(rgba.shape[1]), "h": int(rgba.shape[0])}
                contact.append(rgba)

    with open(os.path.join(OUT, "sprites.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    # Contact sheet, so the whole cut can be checked in one look.
    pad = 12
    cols = 4
    rows = (len(contact) + cols - 1) // cols
    cw = max(a.shape[1] for a in contact) + pad
    ch = max(a.shape[0] for a in contact) + pad
    sheet = Image.new("RGBA", (cw * cols, ch * rows), (40, 44, 52, 255))
    for i, a in enumerate(contact):
        im = Image.fromarray(a, "RGBA")
        x = (i % cols) * cw + (cw - im.width) // 2
        y = (i // cols) * ch + (ch - im.height) // 2
        sheet.alpha_composite(im, (x, y))
    sheet.save(os.path.join(OUT, "_contact.png"))

    for k, v in manifest["parts"].items():
        print(f"  {k:20s} {v['w']:4d} x {v['h']:4d}")
    print(f"contact sheet: {os.path.join(OUT, '_contact.png')}")


if __name__ == "__main__":
    main()

