"""Cut the drawing into rig parts - the real pixels, not a redrawing of them.

The objection that killed every earlier attempt at this was that a cut through a
picture leaves a straight edge and whatever the cut concealed does not exist.
Both halves of that are solvable, and this is how every cutout rig has always
solved them:

  * The edge is hidden by *layer order*, not by care. An ear is cut generously,
    well inside the head, and the head is drawn on top of the join. The cut is
    still there; nothing ever sees it.
  * What the cut concealed is painted in. Where the scarf covers the chest, the
    chest underneath is reconstructed by inpainting before the scarf is lifted
    off, so the body is whole when the scarf swings away from it.

Nothing here invents new artwork. It separates what is drawn, and reconstructs
only what another layer was sitting on top of.
"""

import os
import numpy as np
import cv2
from PIL import Image, ImageDraw

RAW = r"S:\GameDev\MineBeatRush\assets\character\raw"
OUT = r"S:\GameDev\MineBeatRush\assets\character\parts"
DBG = r"S:\GameDev\MineBeatRush\tools\rig"

# Read off a labelled grid of the 346 x 580 panel, not estimated from a preview.
EAR_L = [(72, 6), (44, 58), (31, 120), (35, 172), (52, 222), (76, 262),
         (98, 292), (124, 303), (152, 286), (170, 246), (176, 198),
         (162, 146), (132, 88), (100, 32)]
EAR_R = [(268, 6), (297, 52), (310, 114), (306, 170), (288, 222), (266, 260),
         (246, 290), (222, 300), (198, 282), (186, 242), (188, 194),
         (204, 142), (230, 84), (248, 30)]
HEAD = [(168, 118), (188, 138), (206, 116), (218, 144), (248, 148),
        (278, 176), (300, 214), (302, 252), (288, 284), (262, 304),
        (222, 314), (182, 310), (146, 296), (116, 276), (100, 246),
        (101, 204), (120, 170), (146, 146)]

# The limbs, cut so their roots run well up under the torso.
#
# This is the same trick the ears use, and it is what keeps the reconstruction
# work small: a leg is cut with a generous rounded top that the torso is drawn
# over, so the straight edge of the cut is never on screen and the only place
# genuinely needing to be painted back in is the chest behind the forepaws.
PAW_L = [(158, 336), (176, 326), (196, 332), (208, 350), (210, 372),
         (200, 390), (180, 394), (163, 384), (155, 362)]
PAW_R = [(206, 334), (224, 324), (242, 332), (250, 352), (248, 376),
         (236, 394), (216, 396), (203, 380), (200, 356)]
LEG_L = [(150, 424), (176, 416), (196, 428), (198, 470), (196, 512),
         (194, 548), (188, 566), (166, 570), (152, 560), (148, 520),
         (144, 476)]
LEG_R = [(196, 428), (216, 416), (240, 424), (244, 474), (246, 520),
         (242, 558), (228, 570), (206, 568), (198, 550), (196, 512)]
# The torso, taken to include the hip mass the legs plug into.
TORSO = [(160, 296), (200, 292), (240, 298), (250, 330), (252, 372),
         (248, 412), (244, 452), (234, 486), (206, 496), (176, 490),
         (156, 456), (150, 412), (148, 356), (152, 320)]

SCARF_RED = np.array([216, 60, 36], dtype=np.int16)


def poly_mask(shape, pts) -> np.ndarray:
    m = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return np.array(m)


def save(rgba: np.ndarray, mask: np.ndarray, name: str) -> None:
    out = rgba.copy()
    a = (out[:, :, 3].astype(np.float32) * (mask.astype(np.float32) / 255.0))
    out[:, :, 3] = a.astype(np.uint8)
    ys, xs = np.nonzero(out[:, :, 3] > 6)
    if len(ys) == 0:
        print(f"  !! {name} empty")
        return
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    Image.fromarray(out[y0:y1, x0:x1]).save(os.path.join(OUT, name + ".png"))
    # The origin is what the rig needs: where this piece sat in the whole
    # drawing. Without it the parts reassemble into a pile.
    print(f"  {name:16s} {x1-x0:3d} x {y1-y0:3d}   at ({x0},{y0})")
    return (int(x0), int(y0), int(x1), int(y1))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(os.path.join(RAW, "panel_front_stand.png")).convert("RGBA")
    a = np.array(im)
    h, w = a.shape[:2]
    print(f"panel {w} x {h}")
    figure = a[:, :, 3] > 6

    # --- scarf, by colour ---------------------------------------------------
    # Saturation, not distance. The scarf red and the inner-ear pink are close
    # enough in absolute distance that any threshold loose enough to catch the
    # scarf's shadowed folds also swallowed the inside of both ears. What
    # actually separates them is how far red runs ahead of green: 156 on the
    # scarf, 84 on the ear.
    rgb = a[:, :, :3].astype(np.int16)
    scarf = (figure & (rgb[:, :, 0] > 165)
             & (rgb[:, :, 1] < 130)
             & (rgb[:, :, 0] - rgb[:, :, 1] > 105))
    scarf = cv2.morphologyEx(scarf.astype(np.uint8), cv2.MORPH_CLOSE,
                             np.ones((9, 9), np.uint8))
    scarf = cv2.morphologyEx(scarf, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    scarf = cv2.dilate(scarf, np.ones((3, 3), np.uint8))
    n, lab, stats, _cent = cv2.connectedComponentsWithStats(scarf, 8)
    keep = [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] > 300]
    print(f"scarf: {len(keep)} components kept of {n - 1}")
    scarf_all = np.isin(lab, keep).astype(np.uint8) * 255

    # Claim the scarf's own black outline as part of the scarf.
    #
    # A mask built from colour stops at the red. The stroke drawn around it is
    # not red, so it belonged to no layer at all: subtracted from the body,
    # never added to the scarf, and simply gone. The reassembly check found it
    # immediately as a hollow cyan outline tracing every edge of the scarf.
    # Grabbing dark pixels within a few pixels of the red takes the stroke
    # without eating the fur beside it.
    lum = rgb.mean(axis=2)
    near = cv2.dilate(scarf_all, np.ones((11, 11), np.uint8)) > 0
    outline = (near & figure & (lum < 105)).astype(np.uint8) * 255
    scarf_all = np.maximum(scarf_all, outline)
    scarf_all = cv2.morphologyEx(scarf_all, cv2.MORPH_CLOSE,
                                 np.ones((5, 5), np.uint8))

    ys, xs = np.mgrid[0:h, 0:w]

    # The three pieces are one connected shape, so they are split by where they
    # are rather than by connectivity: the wrap sits in a known box at the
    # throat, and the two ends are whatever hangs outside it.
    in_collar = (xs >= 131) & (xs <= 264) & (ys >= 262) & (ys <= 330)
    collar = np.where(in_collar, scarf_all, 0).astype(np.uint8)
    rest = np.where(in_collar, 0, scarf_all).astype(np.uint8)
    end_l = np.where(xs < 173, rest, 0).astype(np.uint8)
    end_r = np.where(xs >= 173, rest, 0).astype(np.uint8)

    ear_l = poly_mask((h, w), EAR_L)
    ear_r = poly_mask((h, w), EAR_R)
    head = poly_mask((h, w), HEAD)

    # Above the head there is nothing but ears, so everything drawn up there is
    # claimed by one or the other. Trimming to the polygon alone left slivers of
    # the ears' own black outline behind on the body, floating above the
    # shoulders like a pair of horns - and no amount of nudging the polygon
    # fixes that reliably, because the stroke is what strays outside it.
    high = figure & (ys < 250) & (head == 0)
    ear_l = np.maximum(ear_l, np.where(high & (xs < 173), 255, 0)).astype(np.uint8)
    ear_r = np.maximum(ear_r, np.where(high & (xs >= 173), 255, 0)).astype(np.uint8)

    # --- body: everything that is not ear, head or scarf --------------------
    # The ear and head masks are grown a little before being subtracted. Cut on
    # the exact polygon, a rim of the ear's own black outline stayed behind on
    # the body and floated above the shoulders like a pair of horns.
    grow = np.ones((5, 5), np.uint8)
    ear_l_d = cv2.dilate(ear_l, grow)
    ear_r_d = cv2.dilate(ear_r, grow)
    head_d = cv2.dilate(head, grow)

    # Exactly the mask that the scarf pieces are saved with, so the two are
    # complements and the union is the original drawing. Subtracting more than
    # was added is what opened the gap in the first place.
    scarf_d = scarf_all
    body = (figure.astype(np.uint8) * 255)
    body[ear_l_d > 0] = 0
    body[ear_r_d > 0] = 0
    body[head_d > 0] = 0
    body[scarf_d > 0] = 0

    # Reconstruct only what the scarf was actually lying *on*.
    #
    # Most of the scarf hangs past the animal's outline with nothing behind it
    # but paper, and inpainting there does not restore a hidden chest - it
    # invents a grey smear the shape of the scarf. What genuinely needs filling
    # is the neck and upper chest under the wrap, which is a small patch in the
    # middle of the figure.
    # The full height of the torso column, not just the chest. The ends brush
    # past the legs on their way down, and stopping the reconstruction at the
    # waist left a pale notch out of each thigh where they passed.
    # Generous either side of the torso column. The scarf is redrawn in the rig
    # by resampling a straightened strip back onto a curve, which lands within a
    # pixel or two of where it was - not exactly on it. Reconstructing only the
    # width the scarf covers leaves a sliver along its edge that neither layer
    # paints, and the background shows through the chest in a thin bright line.
    hole = ((scarf_d > 0) & (xs > 118) & (xs < 274)).astype(np.uint8)
    hole = cv2.dilate(hole, np.ones((5, 5), np.uint8))
    hole = (hole & figure).astype(np.uint8)

    # Filled with the chest's own fur rather than inpainted.
    #
    # A generic inpainter has the collar's black outline on one side of this
    # patch and shaded fur on the other, and it dutifully averages them into a
    # grey band across the throat. The neck under a scarf is a flat area of one
    # colour, so sampling that colour from the chest just below and filling with
    # it reconstructs it more accurately than any algorithm guessing.
    chest = body[:, :] > 0
    band = chest & (ys > 336) & (ys < 392) & (xs > 168) & (xs < 236)
    fur = np.median(a[:, :, :3][band], axis=0).astype(np.uint8) if band.any() \
        else np.array([240, 200, 150], np.uint8)
    print("neck fill #%02x%02x%02x" % (fur[0], fur[1], fur[2]))
    body_rgba = a.copy()
    body_rgba[:, :, :3] = np.where(hole[:, :, None] > 0, fur, a[:, :, :3])
    # The reconstructed neck has to be opaque, or the scarf swings aside and
    # reveals a hole exactly where the chest should be.
    body_alpha = np.maximum(body, np.where(hole > 0, 255, 0).astype(np.uint8))
    body_alpha[head_d > 0] = 0
    body_alpha[ear_l_d > 0] = 0
    body_alpha[ear_r_d > 0] = 0

    # --- limbs --------------------------------------------------------------
    paw_l = (poly_mask((h, w), PAW_L) > 0) & (body_alpha > 0)
    paw_r = (poly_mask((h, w), PAW_R) > 0) & (body_alpha > 0)
    leg_l = (poly_mask((h, w), LEG_L) > 0) & (body_alpha > 0)
    leg_r = (poly_mask((h, w), LEG_R) > 0) & (body_alpha > 0)
    torso = (poly_mask((h, w), TORSO) > 0) & (body_alpha > 0)

    # The chest the forepaws are folded against has to exist for them to lift
    # away from. It is a flat area of one colour, so it is filled with the
    # colour rather than guessed at by an inpainter.
    paws = (paw_l | paw_r)
    chest_band = (torso & ~paws & (ys > 300) & (ys < 420))
    if chest_band.any():
        chest_fur = np.median(a[:, :, :3][chest_band], axis=0).astype(np.uint8)
    else:
        chest_fur = fur
    torso_rgba = body_rgba.copy()
    behind = cv2.dilate((paws & torso).astype(np.uint8),
                        np.ones((5, 5), np.uint8)) > 0
    torso_rgba[:, :, :3] = np.where(behind[:, :, None], chest_fur,
                                    torso_rgba[:, :, :3])
    # What remains of the body once the named limbs are taken out: the tail.
    tail = body_alpha.copy()
    for m in (paw_l, paw_r, leg_l, leg_r, torso):
        tail[m] = 0

    print("\nparts:")
    boxes = {}
    boxes["ear_l"] = save(a, ear_l, "ear_l")
    boxes["ear_r"] = save(a, ear_r, "ear_r")
    boxes["head"] = save(a, head, "head")
    boxes["tail"] = save(body_rgba, tail, "tail")
    boxes["leg_l"] = save(body_rgba, (leg_l * 255).astype(np.uint8), "leg_l")
    boxes["leg_r"] = save(body_rgba, (leg_r * 255).astype(np.uint8), "leg_r")
    boxes["torso"] = save(torso_rgba, (torso * 255).astype(np.uint8), "torso")
    boxes["paw_l"] = save(body_rgba, (paw_l * 255).astype(np.uint8), "paw_l")
    boxes["paw_r"] = save(body_rgba, (paw_r * 255).astype(np.uint8), "paw_r")
    boxes["scarf_collar"] = save(a, collar, "scarf_collar")
    boxes["scarf_end_l"] = save(a, end_l, "scarf_end_l")
    boxes["scarf_end_r"] = save(a, end_r, "scarf_end_r")

    with open(os.path.join(OUT, "parts.json"), "w") as f:
        import json
        json.dump({"panel": [w, h],
                   "boxes": {k: v for k, v in boxes.items() if v}}, f, indent=1)

    # --- debug composite ----------------------------------------------------
    dbg = np.zeros((h, w, 3), np.uint8)
    dbg[:] = (24, 24, 28)
    for m, col in [(ear_l, (255, 90, 90)), (ear_r, (90, 160, 255)),
                   (head, (255, 220, 90)), (body_alpha, (120, 255, 140)),
                   (scarf_all, (255, 120, 255))]:
        sel = (m > 0) & figure
        dbg[sel] = (dbg[sel] * 0.25 + np.array(col) * 0.75).astype(np.uint8)
    Image.fromarray(dbg).save(os.path.join(DBG, "cut_debug.png"))
    print("\nwrote cut_debug.png")


if __name__ == "__main__":
    main()

