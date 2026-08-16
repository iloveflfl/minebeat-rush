"""Draw the character in each game pose, with its identity pinned to the sheet.

The reference is one illustration of a standing character. A game needs it
crouched, launching, tumbling and landing, and no amount of rigging a portrait
produces those - the forepaws are drawn folded and small, and rotating them
about a joint gives a paper doll, not a jump.

So the poses are drawn. What makes that trustworthy rather than a lottery is
that identity is constrained from three directions at once: the checkpoint and
LoRA supply the style, ControlNet supplies the exact skeleton authored in
pose_guides.py, and the reference itself supplies colour and markings through
img2img. The pose is decided by us; only the drawing is generated.

Several candidates per pose, because a generator is not reliable per-sample and
picking from a contact sheet is how this is done in practice.
"""

import argparse
import io
import json
import os
import random
import sys
import time
import urllib.parse
import urllib.request

HOST = "http://127.0.0.1:8188"
POSES = r"S:\GameDev\MineBeatRush\tools\rig\poses"
REF = r"S:\GameDev\MineBeatRush\assets\character\raw\panel_front_stand.png"
OUT = r"S:\GameDev\MineBeatRush\tools\rig\gen"
# Plates from the posing rig - see tools/rig/pose_plates.gd.
PLATES = r"S:\GameDev\captures\plates"

POSITIVE = (
    "masterpiece, best quality, amazing quality, very aesthetic, "
    "no humans, solo, feral, fennec fox, chibi, small animal, "
    "cream fur, pale yellow fur, huge pointed ears, pink inner ear, "
    "white fur tufts, fluffy cheeks, very large round brown eyes, "
    "sparkling eyes, shiny eyes, tiny pink nose, "
    "red knitted scarf, very long scarf, patterned scarf ends, tassels, "
    "thin tail, brown tail tip, "
    "full body, dynamic pose, "
    "simple background, white background, "
    "thick black outline, bold lineart, flat color, cel shading, "
    "storybook illustration, cream background"
)
NEGATIVE = (
    "worst quality, low quality, lowres, jpeg artifacts, blurry, "
    "human, humanoid, anthro, breasts, clothes, shirt, "
    "realistic, photo, 3d, text, watermark, signature, "
    "multiple views, reference sheet, extra limbs, extra tails, "
    "grey background, dark background, muted colors"
)


# What each game state should look like, in the words the model responds to.
#
# This is the pose specification now that a human skeleton has been shown not to
# steer a feral animal. Each entry is written as an extreme - the drawing an
# animator would put at the peak of that action - because a set of poses is only
# worth having if the silhouettes differ.
POSE_WORDS = {
    "idle": "standing on hind legs, alert, ears up, tail down, calm",
    "armed": "crouching low, coiled, braced, ears flattened back, tense",
    "launch": "leaping upward, body stretched tall, forelegs tucked, "
              "hind legs extended, scarf streaming downward, motion lines",
    "apex_a": "mid air, joyful, one foreleg raised high, body twisted, "
              "hind legs tucked, scarf flying, floating",
    "apex_b": "mid air, back arched, both forelegs raised, hind legs tucked "
              "under, scarf billowing upward, triumphant",
    "apex_c": "mid air, leaning back, cocky, one hind leg kicked out, "
              "scarf whipping sideways",
    "fall": "falling, forelegs raised overhead, hind legs trailing below, "
            "scarf streaming upward, surprised",
    "land": "landing, squashed low, hind legs splayed wide, forelegs out for "
            "balance, ears flattened, impact",
    "glide": "gliding, body tilted, forelegs spread wide, scarf spread out "
             "horizontally, floating",
    "cheer": "jumping for joy, both forelegs raised, closed happy eyes, "
             "smiling, scarf flying upward",
    "dash": "running fast, leaning hard into the turn, legs mid stride, "
            "scarf trailing behind, speed lines",
}


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        HOST + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def get(path: str) -> dict:
    with urllib.request.urlopen(HOST + path, timeout=60) as r:
        return json.loads(r.read())


def upload(path: str, name: str) -> str:
    """Multipart upload, written by hand to keep the tool dependency-free."""
    boundary = "----mbr" + str(random.randint(10 ** 8, 9 * 10 ** 8))
    with open(path, "rb") as f:
        data = f.read()
    body = io.BytesIO()
    body.write(f"--{boundary}\r\n".encode())
    body.write(f'Content-Disposition: form-data; name="image"; '
               f'filename="{name}"\r\n'.encode())
    body.write(b"Content-Type: image/png\r\n\r\n")
    body.write(data)
    body.write(f"\r\n--{boundary}\r\n".encode())
    body.write(b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n')
    body.write(f"--{boundary}--\r\n".encode())
    req = urllib.request.Request(
        HOST + "/upload/image", data=body.getvalue(),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())["name"]


def pick(options: list, *want: str) -> str:
    """First option containing all the given fragments - the enums carry version
    numbers and folder separators that change between installs."""
    for o in options:
        low = str(o).lower()
        if all(w.lower() in low for w in want):
            return o
    raise SystemExit(f"none of {options} matches {want}")


def build(models: dict, pose_img: str, ref_img: str, seed: int,
          denoise: float, cn_strength: float, pose_words: str) -> dict:
    g = {}

    def node(cid, cls, inputs):
        g[cid] = {"class_type": cls, "inputs": inputs}

    node("1", "CheckpointLoaderSimple", {"ckpt_name": models["ckpt"]})
    node("2", "LoraLoader", {
        "model": ["1", 0], "clip": ["1", 1],
        "lora_name": models["lora"], "strength_model": 0.75,
        "strength_clip": 0.75})
    node("3", "CLIPTextEncode", {"clip": ["2", 1], "text": POSITIVE + ", " + pose_words})
    node("4", "CLIPTextEncode", {"clip": ["2", 1], "text": NEGATIVE})
    node("6", "LoadImage", {"image": ref_img})
    # ControlNet is deliberately optional, and off by default.
    #
    # The first test pinned an OpenPose skeleton to a feral chibi animal. The
    # model found nothing it recognised in a human stick figure, ignored it for
    # posing, and drew the character standing exactly as the reference had it -
    # the conditioning was not merely useless, it anchored the composition to
    # the input. Prompted poses move; a mismatched skeleton does not.
    if cn_strength > 0.0:
        node("5", "LoadImage", {"image": pose_img})
        node("7", "ControlNetLoader", {"control_net_name": models["cnet"]})
        node("8", "ControlNetApplyAdvanced", {
            "positive": ["3", 0], "negative": ["4", 0],
            "control_net": ["7", 0], "image": ["5", 0],
            "strength": cn_strength, "start_percent": 0.0,
            "end_percent": 0.72})
        pos, neg = ["8", 0], ["8", 1]
    else:
        pos, neg = ["3", 0], ["4", 0]
    # The reference goes in as the starting latent. At this denoise the
    # composition is free to become the new pose while the palette and markings
    # are inherited rather than re-invented.
    node("9", "ImageScale", {
        "image": ["6", 0], "upscale_method": "lanczos",
        "width": 1024, "height": 1024, "crop": "disabled"})
    node("10", "VAEEncode", {"pixels": ["9", 0], "vae": ["1", 2]})
    node("11", "KSampler", {
        "model": ["2", 0], "positive": pos, "negative": neg,
        "latent_image": ["10", 0], "seed": seed, "steps": 30, "cfg": 5.5,
        "sampler_name": "dpmpp_2m_sde", "scheduler": "karras",
        "denoise": denoise})
    node("12", "VAEDecode", {"samples": ["11", 0], "vae": ["1", 2]})
    node("13", "SaveImage", {"images": ["12", 0], "filename_prefix": "mbr_pose"})
    return g


def run(graph: dict) -> list:
    pid = post("/prompt", {"prompt": graph})["prompt_id"]
    while True:
        h = get(f"/history/{pid}")
        if pid in h:
            outs = []
            for _n, o in h[pid]["outputs"].items():
                for img in o.get("images", []):
                    outs.append(img)
            return outs
        time.sleep(2)


def fetch(img: dict) -> bytes:
    q = urllib.parse.urlencode(
        {"filename": img["filename"], "subfolder": img.get("subfolder", ""),
         "type": img.get("type", "output")})
    with urllib.request.urlopen(HOST + "/view?" + q, timeout=120) as r:
        return r.read()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--poses", default="idle")
    ap.add_argument("--count", type=int, default=4)
    ap.add_argument("--denoise", type=float, default=0.82)
    ap.add_argument("--cn", type=float, default=0.0)
    ap.add_argument("--init", default="plate", choices=["plate", "ref"])
    # Scribble, driven by the plate's own outlines. OpenPose is kept only to
    # record that it was tried and does not steer a feral animal.
    ap.add_argument("--cnet", default="scribble",
                    choices=["scribble", "openpose"])
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    cnet_kind = args.cnet
    info = get("/object_info")
    models = {
        "ckpt": pick(info["CheckpointLoaderSimple"]["input"]["required"]
                     ["ckpt_name"][0], "malus"),
        "lora": pick(info["LoraLoader"]["input"]["required"]["lora_name"][0],
                     "foxremi", "ON"),
        "cnet": pick(info["ControlNetLoader"]["input"]["required"]
                     ["control_net_name"][0], cnet_kind),
    }
    print("using:", json.dumps(models, indent=1))

    ref_name = upload(REF, "mbr_ref.png")
    for pose in args.poses.split(","):
        # The starting latent is the posing rig's plate, not the reference.
        #
        # This is the whole mechanism. Started from the reference, every sample
        # came back in the reference's standing pose no matter what the prompt
        # asked for - the composition is carried by the latent, and words do not
        # outvote it. Started from a plate that already holds the pose, the
        # sampler keeps the composition and spends its effort on the drawing.
        init_path = os.path.join(PLATES, pose + ".png")
        if args.init == "ref" or not os.path.exists(init_path):
            init_name = ref_name
        else:
            init_name = upload(init_path, f"mbr_init_{pose}.png")
        pose_name = ""
        if args.cn > 0.0:
            pose_name = upload(os.path.join(POSES, pose + ".png"),
                               f"mbr_pose_{pose}.png")
        for i in range(args.count):
            seed = random.randint(1, 2 ** 31)
            g = build(models, pose_name, init_name, seed, args.denoise,
                      args.cn, POSE_WORDS.get(pose, ""))
            for img in run(g):
                dst = os.path.join(OUT, f"{pose}_{i}.png")
                with open(dst, "wb") as f:
                    f.write(fetch(img))
                print(f"  {pose}_{i}.png  seed {seed}")


if __name__ == "__main__":
    sys.exit(main())
