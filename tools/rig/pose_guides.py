"""Draw OpenPose skeletons for the poses the game actually asks for.

The game has a fixed, small set of states, and each one wants a distinct, strong
silhouette rather than a shade of the last one. Those poses are authored here as
joint positions and rendered in the format ControlNet expects, so the pose is
something decided deliberately rather than whatever a prompt happens to produce.

Format is OpenPose COCO-18, with the limb ordering and colours the ControlNet
preprocessors emit - the model was trained on those exact colours and treats
them as channel identities, so this is not a palette choice.
"""

import json
import math
import os
import numpy as np
from PIL import Image, ImageDraw

OUT = r"S:\GameDev\MineBeatRush\tools\rig\poses"
W = H = 1024

# 0 nose 1 neck 2 Rsho 3 Relb 4 Rwri 5 Lsho 6 Lelb 7 Lwri
# 8 Rhip 9 Rkne 10 Rank 11 Lhip 12 Lkne 13 Lank 14 Reye 15 Leye 16 Rear 17 Lear
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9),
         (9, 10), (1, 11), (11, 12), (12, 13), (1, 0), (0, 14), (14, 16),
         (0, 15), (15, 17)]
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0),
          (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85),
          (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
          (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255),
          (255, 0, 170), (255, 0, 85)]


def skeleton(neck, head_up, sho_w, arm, hip_w, leg, lean=0.0):
    """Build 18 joints from a few readable parameters.

    `arm` and `leg` are per-side (elbow, wrist) and (knee, ankle) offsets from
    the shoulder and hip, in pixels, so a pose is written as what the limbs do
    rather than as eighteen absolute coordinates nobody can check.
    """
    def rot(p, a):
        c, s = math.cos(a), math.sin(a)
        return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)

    a = math.radians(lean)
    nx, ny = neck
    j = {}
    j[1] = (nx, ny)
    d = rot((0, -head_up), a)
    j[0] = (nx + d[0], ny + d[1])
    for eye, ear, sx in ((14, 16, 1), (15, 17, -1)):
        e = rot((sx * 16, -head_up - 12), a)
        j[eye] = (nx + e[0], ny + e[1])
        f = rot((sx * 34, -head_up - 6), a)
        j[ear] = (nx + f[0], ny + f[1])
    for sho, elb, wri, sx in ((2, 3, 4, 1), (5, 6, 7, -1)):
        s0 = rot((sx * sho_w, 12), a)
        j[sho] = (nx + s0[0], ny + s0[1])
        e0 = rot((sx * (sho_w + arm[sx][0][0]), 12 + arm[sx][0][1]), a)
        j[elb] = (nx + e0[0], ny + e0[1])
        w0 = rot((sx * (sho_w + arm[sx][1][0]), 12 + arm[sx][1][1]), a)
        j[wri] = (nx + w0[0], ny + w0[1])
    for hip, kne, ank, sx in ((8, 9, 10, 1), (11, 12, 13, -1)):
        h0 = rot((sx * hip_w, leg["hip"]), a)
        j[hip] = (nx + h0[0], ny + h0[1])
        k0 = rot((sx * (hip_w + leg[sx][0][0]), leg["hip"] + leg[sx][0][1]), a)
        j[kne] = (nx + k0[0], ny + k0[1])
        a0 = rot((sx * (hip_w + leg[sx][1][0]), leg["hip"] + leg[sx][1][1]), a)
        j[ank] = (nx + a0[0], ny + a0[1])
    return [j[i] for i in range(18)]


def render(joints) -> Image.Image:
    im = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    for i, (a, b) in enumerate(LIMBS):
        p, q = joints[a], joints[b]
        # OpenPose draws limbs as tapered ellipses, and the ControlNet models
        # were trained on that look rather than on plain lines.
        cx, cy = (p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5
        length = math.hypot(q[0] - p[0], q[1] - p[1])
        ang = math.degrees(math.atan2(q[1] - p[1], q[0] - p[0]))
        blob = Image.new("RGBA", (max(2, int(length)), 16), (0, 0, 0, 0))
        ImageDraw.Draw(blob).ellipse([0, 0, max(1, int(length)) - 1, 15],
                                     fill=COLORS[i] + (170,))
        blob = blob.rotate(-ang, expand=True, resample=Image.BICUBIC)
        im.paste(blob, (int(cx - blob.width / 2), int(cy - blob.height / 2)),
                 blob)
    for i, p in enumerate(joints):
        d.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], fill=COLORS[i])
    return im


def arms(r_elb, r_wri, l_elb, l_wri):
    return {1: (r_elb, r_wri), -1: (l_elb, l_wri)}


def legs(hip, r_kne, r_ank, l_kne, l_ank):
    return {"hip": hip, 1: (r_kne, r_ank), -1: (l_kne, l_ank)}


# Each pose is what a game animator would draw as the extreme of that action.
POSES = {
    # Standing alert, weight even, reading the board.
    "idle": dict(neck=(512, 430), head_up=120, sho_w=54, hip_w=42, lean=0,
                 arm=arms((26, 66), (34, 118), (26, 66), (34, 118)),
                 leg=legs(190, (16, 120), (12, 240), (16, 120), (12, 240))),
    # Charge live: coiled, low, about to go.
    "armed": dict(neck=(512, 500), head_up=115, sho_w=54, hip_w=44, lean=-6,
                  arm=arms((34, 40), (58, 78), (34, 40), (58, 78)),
                  leg=legs(150, (54, 90), (10, 190), (54, 90), (10, 190))),
    # Takeoff: everything extended, arms driven back and down.
    "launch": dict(neck=(512, 420), head_up=126, sho_w=52, hip_w=38, lean=-4,
                   arm=arms((-16, 84), (-40, 140), (-16, 84), (-40, 140)),
                   leg=legs(196, (6, 140), (2, 280), (6, 140), (2, 280))),
    # Apex, take one: airborne cheer, one arm punched up.
    "apex_a": dict(neck=(512, 470), head_up=122, sho_w=54, hip_w=42, lean=-8,
                   arm=arms((44, -30), (72, -104), (30, 70), (44, 126)),
                   leg=legs(180, (60, 96), (34, 196), (14, 116), (6, 226))),
    # Apex, take two: tucked and proud, both arms up, back arched.
    "apex_b": dict(neck=(512, 470), head_up=124, sho_w=56, hip_w=44, lean=4,
                   arm=arms((52, -22), (86, -88), (52, -22), (86, -88)),
                   leg=legs(176, (66, 90), (30, 168), (66, 90), (30, 168))),
    # Apex, take three: cocky back-lean, one leg kicked out.
    "apex_c": dict(neck=(512, 470), head_up=120, sho_w=54, hip_w=42, lean=16,
                   arm=arms((16, 78), (10, 134), (56, 10), (92, -34)),
                   leg=legs(182, (80, 74), (128, 136), (10, 124), (2, 240))),
    # Falling: arms up in the airstream, legs trailing.
    "fall": dict(neck=(512, 440), head_up=118, sho_w=54, hip_w=42, lean=10,
                 arm=arms((50, -18), (78, -80), (46, -12), (74, -74)),
                 leg=legs(186, (22, 128), (46, 252), (10, 132), (26, 258))),
    # Landing: deep squash, knees wide, arms out to catch the weight.
    "land": dict(neck=(512, 546), head_up=112, sho_w=58, hip_w=50, lean=0,
                 arm=arms((62, 34), (104, 58), (62, 34), (104, 58)),
                 leg=legs(120, (78, 66), (48, 150), (78, 66), (48, 150))),
    # Scarf glide: arms wide, body tipped, legs loose.
    "glide": dict(neck=(512, 450), head_up=118, sho_w=56, hip_w=42, lean=-14,
                  arm=arms((92, -6), (150, 6), (92, -6), (150, 6)),
                  leg=legs(184, (34, 118), (56, 236), (18, 126), (34, 250))),
    # Victory: both arms up, hopping.
    "cheer": dict(neck=(512, 460), head_up=124, sho_w=54, hip_w=42, lean=0,
                  arm=arms((40, -34), (62, -112), (40, -34), (62, -112)),
                  leg=legs(180, (44, 104), (24, 208), (44, 104), (24, 208))),
    # Sideways dash, leaning hard into the move.
    "dash": dict(neck=(512, 452), head_up=118, sho_w=54, hip_w=42, lean=-24,
                 arm=arms((-10, 72), (-34, 122), (54, 44), (86, 84)),
                 leg=legs(184, (48, 112), (86, 226), (2, 126), (-24, 244))),
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    index = {}
    for name, cfg in POSES.items():
        j = skeleton(**cfg)
        render(j).save(os.path.join(OUT, name + ".png"))
        index[name] = [[round(p[0], 1), round(p[1], 1)] for p in j]
        print(f"  {name}")
    with open(os.path.join(OUT, "poses.json"), "w") as f:
        json.dump(index, f, indent=1)
    # A contact sheet, because eleven poses are only worth anything if they read
    # as eleven different silhouettes and that is judged by looking at them
    # together rather than one at a time.
    cols = 4
    rows = (len(POSES) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 256, rows * 256), (12, 12, 16))
    for i, name in enumerate(POSES):
        im = Image.open(os.path.join(OUT, name + ".png")).resize((256, 256))
        sheet.paste(im, ((i % cols) * 256, (i // cols) * 256))
        ImageDraw.Draw(sheet).text(((i % cols) * 256 + 6, (i // cols) * 256 + 6),
                                   name, fill=(255, 255, 255))
    sheet.save(os.path.join(OUT, "_contact.png"))
    print("wrote poses and _contact.png")


if __name__ == "__main__":
    main()
