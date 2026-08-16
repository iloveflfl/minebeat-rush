"""Unbend the long parts into straight strips, and record the curve they came from.

A part that is drawn curved cannot be mapped onto a simulated strand as-is: the
strand is a line, and the artwork would have to be sheared onto it. So each long
part is resampled along its own centre line into a straight vertical strip - the
same pixels, laid out along a line instead of along a curve - and the curve it
came from is written out beside it.

The rig then uses that curve as the strand's rest shape. At rest the strip bends
back into exactly the arc the artist drew, so nothing has been lost; and when
the strand moves, the artwork bends with it instead of swinging rigidly.

This is what a Live2D artist does by hand when they redraw a part in a neutral
pose. Here the neutral pose is derived from the drawing rather than authored.
"""

import json
import os
import numpy as np
from PIL import Image

PARTS = r"S:\GameDev\MineBeatRush\assets\character\parts"
OUT = r"S:\GameDev\MineBeatRush\assets\character\strips"

# part -> is the part's root the *top* row of its image?
#
# An ear grows upward out of the head, so its root is the bottom row and its tip
# is the top. A scarf end hangs from the collar, so its root is the top row. Get
# this backwards and the part is simulated from the wrong end: the tip is welded
# in place and the root swings, which renders the ear upside down and hangs the
# scarf by its fringe.
ROOT_AT_TOP = {
    "ear_l": False,
    "ear_r": False,
    "scarf_end_l": True,
    "scarf_end_r": True,
}


def smooth(v: np.ndarray, k: int = 21) -> np.ndarray:
    if len(v) < k:
        return v
    pad = np.pad(v, (k // 2, k // 2), mode="edge")
    ker = np.ones(k) / k
    return np.convolve(pad, ker, mode="valid")[:len(v)]


def straighten(name: str, origin: tuple) -> dict:
    im = Image.open(os.path.join(PARTS, name + ".png")).convert("RGBA")
    a = np.array(im)
    h, w = a.shape[:2]
    alpha = a[:, :, 3] > 8

    rows = []
    for y in range(h):
        xs = np.nonzero(alpha[y])[0]
        if len(xs) == 0:
            rows.append(None)
            continue
        rows.append((float(xs.min()), float(xs.max())))

    valid = [i for i, r in enumerate(rows) if r is not None]
    if not valid:
        raise RuntimeError(name + " is empty")
    y0, y1 = valid[0], valid[-1]

    lo = np.array([rows[y][0] if rows[y] else np.nan for y in range(y0, y1 + 1)])
    hi = np.array([rows[y][1] if rows[y] else np.nan for y in range(y0, y1 + 1)])
    # A blank row inside the part (a gap in the fringe, say) must not break the
    # centre line, so gaps are bridged before smoothing.
    idx = np.arange(len(lo))
    for arr in (lo, hi):
        m = np.isnan(arr)
        if m.any():
            arr[m] = np.interp(idx[m], idx[~m], arr[~m])
    cx = smooth((lo + hi) * 0.5)
    half = smooth((hi - lo) * 0.5)

    out_w = int(np.ceil(half.max() * 2.0)) + 2
    out_h = y1 - y0 + 1
    strip = np.zeros((out_h, out_w, 4), np.uint8)
    # Sample each row of the original at the same y, shifted so the centre line
    # lands in the middle of the strip. Rows, not perpendicular slices: these
    # parts run within about 30 degrees of vertical, where the difference is a
    # few per cent of width and invisible, and rows keep the resampling exact.
    for i in range(out_h):
        src_y = y0 + i
        shift = out_w * 0.5 - cx[i]
        xs_out = np.arange(out_w)
        xs_src = xs_out - shift
        x0i = np.floor(xs_src).astype(int)
        frac = (xs_src - x0i)[:, None]
        ok = (x0i >= 0) & (x0i < w - 1)
        px = np.zeros((out_w, 4), np.float32)
        px[ok] = (a[src_y, x0i[ok]].astype(np.float32) * (1.0 - frac[ok])
                  + a[src_y, x0i[ok] + 1].astype(np.float32) * frac[ok])
        strip[i] = px.astype(np.uint8)

    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(strip).save(os.path.join(OUT, name + ".png"))

    # The centre line in panel coordinates, root first. These parts all hang
    # from their top, so the path is written top-down.
    path = [[float(origin[0] + cx[i]), float(origin[1] + y0 + i)]
            for i in range(out_h)]
    print(f"  {name:14s} {w}x{h} -> {out_w}x{out_h}   "
          f"half-width {half.min():.1f}..{half.max():.1f}")
    return {"strip": [out_w, out_h], "path": path,
            "half_max": float(half.max())}


def main() -> None:
    boxes = json.load(open(os.path.join(PARTS, "parts.json")))["boxes"]
    out = {}
    print("straightening:")
    for name in ROOT_AT_TOP:
        b = boxes[name]
        out[name] = straighten(name, (b[0], b[1]))
    # Thinned to a handful of nodes: the rig simulates a chain, not a spline,
    # and 250 points would be both slower and stiffer than the real thing.
    for name, d in out.items():
        p = d["path"]
        n = 9 if name.startswith("scarf") else 7
        step = (len(p) - 1) / float(n - 1)
        nodes = [p[int(round(i * step))] for i in range(n)]
        # Always written root first, so the rig never has to know which way
        # round a given part was drawn.
        if not ROOT_AT_TOP[name]:
            nodes.reverse()
        d["nodes"] = nodes
        d["root_at_top"] = ROOT_AT_TOP[name]
        del d["path"]
    with open(os.path.join(OUT, "strips.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("wrote strips.json")


if __name__ == "__main__":
    main()
