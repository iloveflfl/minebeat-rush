"""Put the cut parts back where they came from and diff against the original.

The claim the whole approach rests on is that the parts are the artist's pixels,
merely separated. That claim is checkable: stack them in their recorded
positions in the recorded order and the result should be the panel again. If it
is not, the cutter is losing or duplicating something, and no amount of looking
at a 3D render will tell you which.
"""

import json
import os
import numpy as np
from PIL import Image

RAW = r"S:\GameDev\MineBeatRush\assets\character\raw"
PARTS = r"S:\GameDev\MineBeatRush\assets\character\parts"
OUT = r"S:\GameDev\MineBeatRush\tools\rig"

# Back to front, the same order the rig stacks them in.
ORDER = ["ear_l", "ear_r", "body", "scarf_end_l", "scarf_end_r", "head",
         "scarf_collar"]


def main() -> None:
    meta = json.load(open(os.path.join(PARTS, "parts.json")))
    w, h = meta["panel"]
    boxes = meta["boxes"]

    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for name in ORDER:
        p = Image.open(os.path.join(PARTS, name + ".png")).convert("RGBA")
        b = boxes[name]
        canvas.alpha_composite(p, (b[0], b[1]))
    canvas.save(os.path.join(OUT, "reassembled.png"))

    orig = Image.open(os.path.join(RAW, "panel_front_stand.png")).convert("RGBA")
    o = np.array(orig).astype(np.int16)
    c = np.array(canvas).astype(np.int16)

    # Compare only where the original is opaque; the paper is not the subject.
    solid = o[:, :, 3] > 200
    drgb = np.abs(o[:, :, :3] - c[:, :, :3]).sum(axis=2)
    dalpha = np.abs(o[:, :, 3] - c[:, :, 3])
    print(f"opaque pixels compared: {solid.sum()}")
    print(f"  mean RGB difference   {drgb[solid].mean():.2f} / 765")
    print(f"  pixels off by > 40    {(drgb[solid] > 40).sum()} "
          f"({100.0 * (drgb[solid] > 40).mean():.2f}%)")
    print(f"  holes (alpha lost)    {(c[:, :, 3][solid] < 200).sum()}")

    # A visual diff, so whatever is wrong can be located rather than described.
    vis = np.zeros((h, w, 3), np.uint8)
    vis[:, :, 0] = np.clip(drgb, 0, 255)
    vis[:, :, 1] = np.where(solid & (c[:, :, 3] < 200), 255, 0)
    vis[:, :, 2] = np.clip(dalpha, 0, 255)
    Image.fromarray(vis).save(os.path.join(OUT, "reassembly_diff.png"))
    print("wrote reassembled.png and reassembly_diff.png "
          "(red = colour drift, green = hole, blue = alpha drift)")


if __name__ == "__main__":
    main()
