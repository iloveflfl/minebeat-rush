"""Pose the character as flat blocked-in shapes, in its own colours.

This is the posing tool, and it exists because of what the first generation test
showed: identity survives beautifully but the pose does not move at all. An
OpenPose skeleton describes a human, and this character is a feral chibi fennec
with folded forepaws - the model looks at the stick figure, finds nothing it
recognises, and draws the animal standing exactly as the reference had it.

What does control the composition is a picture of the composition. So each pose
is blocked in here with the character's real proportions and real palette:
ears half its height, a head a third of it, a slim body, a scarf with two long
ends, a thin tail. The result is too crude to ship and is not meant to be - it
goes to the generator as both the structure to follow and the colours to keep,
and the generator returns the drawing.

This is the same division of labour Dead Cells used: a rig decides the pose, and
something else renders the frame. The rig here is a hundred lines of PIL.
"""

import json
import math
import os
from PIL import Image, ImageDraw

OUT = r"S:\GameDev\MineBeatRush\tools\rig\blockout"
S = 1024

FUR = (245, 218, 170)
BELLY = (255, 246, 232)
EAR_IN = (249, 196, 178)
INK = (40, 30, 25)
SCARF = (214, 62, 44)
SCARF_TRIM = (243, 160, 140)
TAIL_TIP = (140, 92, 56)
EYE = (66, 40, 26)
NOSE = (229, 150, 140)


def rot(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


class Pen:
    def __init__(self, img):
        self.d = ImageDraw.Draw(img)

    def capsule(self, p0, p1, r0, r1, fill, outline=6):
        """A tapered limb, drawn as a polygon so the outline is even."""
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L = math.hypot(dx, dy) or 1.0
        ux, uy = dx / L, dy / L
        nx, ny = -uy, ux
        pts = []
        for k in range(13):
            a = math.pi * 0.5 - math.pi * k / 12
            pts.append((p0[0] + nx * math.cos(a) * r0 - ux * math.sin(a) * r0,
                        p0[1] + ny * math.cos(a) * r0 - uy * math.sin(a) * r0))
        for k in range(13):
            a = -math.pi * 0.5 + math.pi * k / 12
            pts.append((p1[0] + nx * math.cos(a) * r1 + ux * math.sin(a) * r1,
                        p1[1] + ny * math.cos(a) * r1 + uy * math.sin(a) * r1))
        self.d.polygon(pts, fill=fill, outline=INK, width=outline)

    def blade(self, root, ang, length, width, curve, fill, inner=None):
        """An ear: long, wide at the base, curving to a point."""
        left, right = [], []
        for k in range(15):
            t = k / 14.0
            a = math.radians(ang + curve * t * t)
            p = (root[0] + math.cos(a) * length * t,
                 root[1] + math.sin(a) * length * t)
            w = width * (0.55 + 0.45 * math.sin(math.pi * (0.18 + 0.7 * t))) \
                * (1.0 - 0.55 * t * t)
            n = rot((0, 1), a)
            left.append((p[0] + n[0] * w, p[1] + n[1] * w))
            right.append((p[0] - n[0] * w, p[1] - n[1] * w))
        self.d.polygon(left + right[::-1], fill=fill, outline=INK, width=6)
        if inner:
            li, ri = [], []
            for k in range(15):
                t = k / 14.0
                a = math.radians(ang + curve * t * t)
                p = (root[0] + math.cos(a) * length * (0.10 + 0.82 * t),
                     root[1] + math.sin(a) * length * (0.10 + 0.82 * t))
                w = width * 0.55 * (0.55 + 0.45 * math.sin(
                    math.pi * (0.18 + 0.7 * t))) * (1.0 - 0.55 * t * t)
                n = rot((0, 1), a)
                li.append((p[0] + n[0] * w, p[1] + n[1] * w))
                ri.append((p[0] - n[0] * w, p[1] - n[1] * w))
            self.d.polygon(li + ri[::-1], fill=inner)

    def ribbon(self, root, ang, length, width, curve, fill, banded=False):
        """A scarf end, or the tail."""
        left, right, spine = [], [], []
        for k in range(17):
            t = k / 16.0
            a = math.radians(ang + curve * t)
            p = (root[0] + math.cos(a) * length * t,
                 root[1] + math.sin(a) * length * t)
            spine.append(p)
            n = rot((0, 1), a)
            left.append((p[0] + n[0] * width, p[1] + n[1] * width))
            right.append((p[0] - n[0] * width, p[1] - n[1] * width))
        self.d.polygon(left + right[::-1], fill=fill, outline=INK, width=6)
        if banded:
            for frac in (0.74, 0.84):
                i = int(frac * 16)
                a = math.radians(ang + curve * frac)
                n = rot((0, 1), a)
                p = spine[i]
                self.d.line([(p[0] + n[0] * width, p[1] + n[1] * width),
                             (p[0] - n[0] * width, p[1] - n[1] * width)],
                            fill=SCARF_TRIM, width=14)
            tip = spine[-1]
            a = math.radians(ang + curve)
            u = (math.cos(a), math.sin(a))
            n = rot((0, 1), a)
            for f in range(4):
                o = (f - 1.5) * width * 0.55
                b = (tip[0] + n[0] * o, tip[1] + n[1] * o)
                self.d.line([b, (b[0] + u[0] * width * 1.1,
                                 b[1] + u[1] * width * 1.1)],
                            fill=fill, width=10)


def draw(pose: dict) -> Image.Image:
    im = Image.new("RGB", (S, S), (255, 255, 255))
    p = Pen(im)
    bx, by = pose["body"][0], pose["body"][1]
    ba = math.radians(pose["body"][2])
    sq = pose["body"][3]

    def on_body(off):
        r = rot(off, ba)
        return (bx + r[0], by + r[1] * sq)

    hip = on_body((0, 90))
    neck = on_body((0, -95))
    head = (neck[0] + pose["head"][0], neck[1] + pose["head"][1])

    # back to front
    for side, (ang, curve) in zip((-1, 1), pose["ears"]):
        p.blade((head[0] + side * 42, head[1] - 40), ang, 330, 62, curve,
                FUR, EAR_IN)
    p.ribbon(hip, pose["tail"][0], 250, 20, pose["tail"][1], FUR)
    tipang = math.radians(pose["tail"][0] + pose["tail"][1])
    tp = (hip[0] + math.cos(tipang) * 250, hip[1] + math.sin(tipang) * 250)
    p.capsule(tp, (tp[0] + math.cos(tipang) * 70,
                   tp[1] + math.sin(tipang) * 70), 26, 12, TAIL_TIP)
    for (ang, curve) in pose["scarf"]:
        p.ribbon((neck[0], neck[1] + 26), ang, 330, 30, curve, SCARF,
                 banded=True)

    # body
    p.capsule(on_body((0, -70)), on_body((0, 78)), 74, 62, FUR)
    p.d.ellipse([bx - 44, by - 30 * sq, bx + 44, by + 84 * sq], fill=BELLY)
    for side, (ang, bend) in zip((-1, 1), pose["legs"]):
        h = on_body((side * 40, 74))
        k = (h[0] + math.cos(math.radians(ang)) * 90,
             h[1] + math.sin(math.radians(ang)) * 90)
        f = (k[0] + math.cos(math.radians(ang + bend)) * 90,
             k[1] + math.sin(math.radians(ang + bend)) * 90)
        p.capsule(h, k, 30, 24, FUR)
        p.capsule(k, f, 24, 20, FUR)
        p.d.ellipse([f[0] - 26, f[1] - 16, f[0] + 26, f[1] + 16], fill=BELLY,
                    outline=INK, width=5)
    for side, (ang, ln) in zip((-1, 1), pose["arms"]):
        sh = on_body((side * 52, -46))
        e = (sh[0] + math.cos(math.radians(ang)) * ln,
             sh[1] + math.sin(math.radians(ang)) * ln)
        p.capsule(sh, e, 26, 22, FUR)
        p.d.ellipse([e[0] - 24, e[1] - 22, e[0] + 24, e[1] + 22], fill=BELLY,
                    outline=INK, width=5)

    # head last, over the ear roots
    p.d.ellipse([head[0] - 108, head[1] - 96, head[0] + 108, head[1] + 104],
                fill=FUR, outline=INK, width=7)
    p.d.ellipse([head[0] - 52, head[1] + 6, head[0] + 52, head[1] + 62],
                fill=BELLY)
    for sx in (-1, 1):
        p.d.ellipse([head[0] + sx * 46 - 24, head[1] - 32,
                     head[0] + sx * 46 + 24, head[1] + 20], fill=EYE)
    p.d.ellipse([head[0] - 13, head[1] + 14, head[0] + 13, head[1] + 34],
                fill=NOSE)
    # collar
    p.d.ellipse([neck[0] - 76, neck[1] + 2, neck[0] + 76, neck[1] + 56],
                fill=SCARF, outline=INK, width=7)
    return im


POSES = {
    "idle":    dict(body=(512, 560, 0, 1.00), head=(0, -40),
                    ears=((-104, 14), (-76, -14)), arms=((96, 74), (84, 74)),
                    legs=((96, -6), (84, 6)), tail=(30, 46),
                    scarf=((116, 26), (64, -26))),
    "armed":   dict(body=(512, 620, 0, 0.82), head=(0, -26),
                    ears=((-98, 26), (-82, -26)), arms=((112, 66), (68, 66)),
                    legs=((122, -46), (58, 46)), tail=(24, 60),
                    scarf=((118, 22), (62, -22))),
    "launch":  dict(body=(512, 520, 0, 1.22), head=(0, -54),
                    ears=((-118, 36), (-62, -36)), arms=((122, 84), (58, 84)),
                    legs=((94, -2), (86, 2)), tail=(52, 40),
                    scarf=((132, 40), (48, -40))),
    "apex_a":  dict(body=(512, 540, -10, 0.94), head=(-8, -44),
                    ears=((-128, -26), (-52, 30)), arms=((-96, 96), (54, 78)),
                    legs=((72, 44), (104, -30)), tail=(8, 66),
                    scarf=((150, 34), (28, -22))),
    "apex_b":  dict(body=(512, 540, 6, 0.90), head=(6, -48),
                    ears=((-112, 22), (-68, -22)), arms=((-104, 92), (-76, 92)),
                    legs=((66, 52), (114, -52)), tail=(-16, 76),
                    scarf=((140, 46), (40, -46))),
    "apex_c":  dict(body=(512, 540, 18, 0.96), head=(14, -40),
                    ears=((-96, 34), (-58, -8)), arms=((110, 70), (-70, 88)),
                    legs=((44, 26), (108, -20)), tail=(-4, 70),
                    scarf=((128, 52), (52, -14))),
    "fall":    dict(body=(512, 540, 12, 1.06), head=(10, -44),
                    ears=((-136, -30), (-46, 34)), arms=((-108, 88), (-64, 88)),
                    legs=((84, 16), (96, -16)), tail=(-30, 54),
                    scarf=((-118, -30), (-62, 30))),
    "land":    dict(body=(512, 660, 0, 0.62), head=(0, -14),
                    ears=((-70, 46), (-110, -46)), arms=((140, 78), (40, 78)),
                    legs=((136, -62), (44, 62)), tail=(18, 62),
                    scarf=((104, 16), (76, -16))),
    "glide":   dict(body=(512, 540, -16, 0.92), head=(-12, -40),
                    ears=((-142, -34), (-40, 38)), arms=((176, 96), (6, 96)),
                    legs=((88, 24), (98, -22)), tail=(-24, 62),
                    scarf=((-160, -22), (-20, 22))),
    "cheer":   dict(body=(512, 540, 0, 1.06), head=(0, -48),
                    ears=((-110, 20), (-70, -20)), arms=((-102, 94), (-78, 94)),
                    legs=((80, 34), (100, -34)), tail=(6, 66),
                    scarf=((136, 40), (44, -40))),
    "dash":    dict(body=(512, 560, -26, 0.98), head=(-20, -36),
                    ears=((-150, -30), (-58, 20)), arms=((150, 80), (-14, 70)),
                    legs=((66, 40), (112, -34)), tail=(-40, 50),
                    scarf=((166, -18), (10, 26))),
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, pose in POSES.items():
        draw(pose).save(os.path.join(OUT, name + ".png"))
    cols = 4
    rows = (len(POSES) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 256, rows * 256), (255, 255, 255))
    for i, name in enumerate(POSES):
        sheet.paste(Image.open(os.path.join(OUT, name + ".png"))
                    .resize((256, 256)), ((i % cols) * 256, (i // cols) * 256))
        ImageDraw.Draw(sheet).text(((i % cols) * 256 + 6, (i // cols) * 256 + 6),
                                   name, fill=(0, 0, 0))
    sheet.save(os.path.join(OUT, "_contact.png"))
    print(f"wrote {len(POSES)} blockouts and _contact.png")


if __name__ == "__main__":
    main()
