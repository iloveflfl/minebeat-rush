"""
MineBeat Rush - procedural audio generator.

GDD 17: 3-2-1-GO must be carried by music + structural sound, never by a note-lane UI.
GDD 26: audio is the master clock, so the music has to be one continuous take whose
        bar downbeats land exactly on the GO beats of the tempo map.

Produces:
  assets/audio/music_<stem>.wav   (4 stems, same length, played in sync,
                                   mixed at runtime by AudioDirector per Act)
  assets/audio/sfx_*.wav          (short one-shots triggered by the game)

Run:  python tools/gen_audio.py
"""

import json
import os
import shutil
import subprocess
import wave

import numpy as np
from scipy.signal import lfilter

SR = 22050

## The music stems, in the order AudioDirector expects them.
STEMS = ["drums", "bass", "lead", "atmos", "drive"]

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "assets", "data", "stage1_tempo.json")
OUT = os.path.join(ROOT, "assets", "audio")
os.makedirs(OUT, exist_ok=True)

with open(DATA, encoding="utf-8") as f:
    CFG = json.load(f)

SEGS = CFG["segments"]
_SEG_T = [0.0]
for i in range(1, len(SEGS)):
    db = SEGS[i]["beat"] - SEGS[i - 1]["beat"]
    _SEG_T.append(_SEG_T[-1] + db * 60.0 / SEGS[i - 1]["bpm"])


def _seg_index(beat):
    idx = 0
    for k, s in enumerate(SEGS):
        if s["beat"] <= beat:
            idx = k
    return idx


def t_at(beat):
    i = _seg_index(beat)
    return _SEG_T[i] + (beat - SEGS[i]["beat"]) * 60.0 / SEGS[i]["bpm"]


def bpm_at(beat):
    return SEGS[_seg_index(beat)]["bpm"]


TOTAL_BEATS = CFG["total_beats"]
DURATION = t_at(TOTAL_BEATS) + 6.0
N = int(DURATION * SR)

print(f"tempo map -> {DURATION:.1f}s ({TOTAL_BEATS} beats), {N} samples @ {SR}Hz")


# ----------------------------------------------------------------------------
# synthesis helpers
# ----------------------------------------------------------------------------

def env_ad(n, attack, decay, curve=2.0):
    """Attack/decay envelope, length n samples."""
    a = max(1, int(attack * SR))
    e = np.ones(n, dtype=np.float64)
    a = min(a, n)
    e[:a] = np.linspace(0.0, 1.0, a)
    d = np.arange(n) / SR
    e *= np.exp(-d / max(1e-4, decay)) ** curve
    return e


def osc(freq, n, kind="sine", phase=0.0):
    t = np.arange(n) / SR
    ph = 2.0 * np.pi * freq * t + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2.0 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":
        return 2.0 * ((freq * t + phase / (2 * np.pi)) % 1.0) - 1.0
    if kind == "square":
        return np.sign(np.sin(ph))
    raise ValueError(kind)


def noise(n, rng):
    return rng.standard_normal(n)


def lowpass(x, cutoff):
    """One-pole lowpass."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    return lfilter([1.0 - a], [1.0, -a], x)


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def place(buf, t0, sig, gain=1.0):
    i0 = int(t0 * SR)
    if i0 >= buf.size:
        return
    if i0 < 0:
        sig = sig[-i0:]
        i0 = 0
    i1 = min(buf.size, i0 + sig.size)
    buf[i0:i1] += sig[: i1 - i0] * gain


def save(name, buf, peak=0.86):
    m = float(np.max(np.abs(buf)))
    if m > 1e-9:
        buf = buf / m * peak
    pcm = np.clip(buf, -1.0, 1.0)
    data = (pcm * 32767.0).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"  {name:26s} {os.path.getsize(path) / 1024 / 1024:6.2f} MB")


# ----------------------------------------------------------------------------
# instruments
# ----------------------------------------------------------------------------

def kick(dur=0.40, f0=150.0, f1=44.0, click=0.5, rng=None):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / 0.045)
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * env_ad(n, 0.001, 0.16, 1.0)
    out = body
    if click > 0.0 and rng is not None:
        cl = highpass(noise(n, rng), 2500.0) * env_ad(n, 0.0005, 0.008, 1.0)
        out = out + cl * click
    return out * 1.0


def snare(dur=0.30, rng=None):
    n = int(dur * SR)
    body = osc(190.0, n, "tri") * env_ad(n, 0.001, 0.055, 1.0) * 0.5
    nz = highpass(noise(n, rng), 1200.0) * env_ad(n, 0.001, 0.075, 1.0)
    return body + nz * 0.8


def hat(dur=0.09, bright=6500.0, rng=None):
    n = int(dur * SR)
    return highpass(noise(n, rng), bright) * env_ad(n, 0.0004, 0.022, 1.4) * 0.5


def frame_drum(dur=0.55, f=86.0, rng=None):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2.0 * np.pi * (f + 30.0 * np.exp(-t / 0.03)) * t
    return (np.sin(ph) + 0.4 * np.sin(2.3 * ph)) * env_ad(n, 0.001, 0.13, 1.0)


def pluck(freq, dur, kind="saw", cutoff=2600.0, decay=0.22, rng=None):
    n = int(dur * SR)
    raw = 0.6 * osc(freq, n, kind) + 0.4 * osc(freq * 1.005, n, kind)
    raw = lowpass(raw, cutoff)
    return raw * env_ad(n, 0.004, decay, 1.0)


def bass_note(freq, dur):
    n = int(dur * SR)
    raw = osc(freq, n, "saw") * 0.55 + osc(freq * 0.5, n, "sine") * 0.7
    raw = lowpass(raw, 420.0)
    return raw * env_ad(n, 0.008, dur * 0.55, 1.0)


def riser(dur, f_lo=300.0, f_hi=4200.0, rng=None):
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / max(1e-6, dur)
    nz = noise(n, rng)
    # cheap sweep: crossfade between two filtered copies
    lo = lowpass(nz, f_lo)
    hi = highpass(nz, f_hi * 0.35)
    sig = lo * (1.0 - u) + hi * u
    return sig * (u ** 2.2)


# ----------------------------------------------------------------------------
# note tables - D phrygian dominant (desert colour)
# ----------------------------------------------------------------------------

def hz(semi):
    return 440.0 * (2.0 ** ((semi - 9) / 12.0))


D3, D4 = hz(-10), hz(2)
SCALE = [0, 1, 4, 5, 7, 8, 10, 12]          # phrygian dominant degrees
PROG = [0, -4, -5, -2]                      # per 4-bar block, semitone offsets from D


# ----------------------------------------------------------------------------
# build stems
# ----------------------------------------------------------------------------

rng = np.random.default_rng(20260815)

drums = np.zeros(N)
bass = np.zeros(N)
lead = np.zeros(N)
atmos = np.zeros(N)
drive = np.zeros(N)

bars = TOTAL_BEATS // 4
kick_times = []

for bar in range(bars):
    b0 = bar * 4
    tb = t_at(b0)
    beat_len = 60.0 / bpm_at(b0)
    chord = PROG[(bar // 4) % len(PROG)]

    # --- drums: four on the floor. Every beat gets a kick, the bar downbeat
    #     (which is always a GO) gets the loudest one. Offbeat open hats and a
    #     clap on 2 and 4 are the rest of the techno skeleton.
    for k in range(4):
        accent = 1.0 if k == 0 else 0.72
        place(drums, t_at(b0 + k), kick(rng=rng), accent)
        kick_times.append(t_at(b0 + k))
    for k in (1.0, 3.0):
        place(drums, t_at(b0 + k), snare(dur=0.24, rng=rng), 0.50)
    for k in range(8):
        bb = b0 + k * 0.5
        if k % 2 == 1:
            place(drums, t_at(bb), hat(dur=0.16, bright=5200.0, rng=rng), 0.34)
        else:
            place(drums, t_at(bb), hat(dur=0.05, bright=9000.0, rng=rng), 0.14)
    # Every fourth bar, a snare roll winds into the next GO.
    if bar % 4 == 3:
        for k in range(8):
            place(drums, t_at(b0 + 3.0 + k * 0.125),
                  snare(dur=0.12, rng=rng), 0.16 + 0.05 * k)

    # --- bass: root on the downbeat, octave push on the "1" count ------------
    root = D3 * (2.0 ** (chord / 12.0))
    place(bass, tb, bass_note(root, beat_len * 2.1), 0.9)
    place(bass, t_at(b0 + 2), bass_note(root, beat_len * 0.9), 0.65)
    place(bass, t_at(b0 + 3), bass_note(root * (2 ** (7 / 12.0)), beat_len * 0.9), 0.55)

    # --- lead: a 16th-note saw arp. This is the line that makes it read as
    #     techno rather than as a folk tune in a hat.
    arp = [0, 2, 4, 6, 4, 2, 4, 7]
    for k in range(16):
        deg = arp[k % len(arp)] + (7 if (bar % 4 == 3 and k >= 8) else 0)
        f = D4 * (2.0 ** ((chord + SCALE[deg % len(SCALE)]
                           + 12 * (deg // len(SCALE))) / 12.0))
        # Filter opens across the bar, the classic rising-tension move.
        cutoff = 900.0 + 3200.0 * (k / 15.0)
        place(lead, t_at(b0 + k * 0.25),
              pluck(f, beat_len * 0.30, kind="saw", cutoff=cutoff, decay=0.09, rng=rng),
              0.30 if k % 2 else 0.44)

    # --- drive: the "stop dragging" stem. 16ths, claps and a fill every 4th
    #     bar. Faded in from Act 2 onward so the stage physically speeds up
    #     without the tempo having to do all the work. -------------------------
    for k in range(16):
        bb = b0 + k * 0.25
        g = 0.26 if k % 4 == 0 else (0.15 if k % 2 == 0 else 0.09)
        place(drive, t_at(bb), hat(dur=0.05, bright=9000.0, rng=rng), g)
    for cb in (1.0, 3.0):
        place(drive, t_at(b0 + cb), snare(dur=0.22, rng=rng), 0.42)
    if bar % 4 == 3:
        for k in range(6):
            place(drive, t_at(b0 + 2.5 + k * 0.25),
                  frame_drum(dur=0.30, f=150.0 - k * 14.0, rng=rng), 0.42)
    if bar % 8 == 0:
        place(drive, tb, kick(dur=0.5, f0=220.0, rng=rng), 0.7)

    # --- atmos: drone + a riser into every GO --------------------------------
    dn = int(beat_len * 4 * SR)
    dt = np.arange(dn) / SR
    drone = (np.sin(2 * np.pi * root * dt) * 0.35
             + np.sin(2 * np.pi * root * 1.5 * dt) * 0.18
             + np.sin(2 * np.pi * root * 2.0 * (1.0 + 0.0008 * np.sin(2 * np.pi * 0.3 * dt)) * dt) * 0.10)
    drone *= 0.5 - 0.5 * np.cos(np.linspace(0, 2 * np.pi, dn))
    place(atmos, tb, drone, 0.55)
    rl = t_at(b0 + 4) - t_at(b0 + 2.5)
    place(atmos, t_at(b0 + 2.5), riser(rl, rng=rng), 0.42)


# ----------------------------------------------------------------------------
# Sidechain. Everything that is not the drums ducks under every kick and swells
# back - the pump that makes four-on-the-floor feel like it is breathing. It is
# also the single strongest way to hear the beat grid, which matters here for
# more than style: the player is being asked to land their last dash on the GO
# (GDD 11.2), so the beat has to be impossible to miss.
# ----------------------------------------------------------------------------

def sidechain(buf, times, depth=0.72, release=0.16):
    gain = np.ones(buf.size)
    idx = np.clip((np.array(times) * SR).astype(int), 0, buf.size - 1)
    env_len = int(release * 4.0 * SR)
    shape = 1.0 - depth * np.exp(-np.arange(env_len) / (release * SR))
    for i in idx:
        end = min(buf.size, i + env_len)
        np.minimum(gain[i:end], shape[: end - i], out=gain[i:end])
    return buf * gain


print("sidechain:")
bass = sidechain(bass, kick_times)
lead = sidechain(lead, kick_times, depth=0.55)
atmos = sidechain(atmos, kick_times, depth=0.60)
drive = sidechain(drive, kick_times, depth=0.35)

print("stems:")
save("music_drums.wav", drums)
save("music_bass.wav", bass)
save("music_lead.wav", lead)
save("music_atmos.wav", atmos)
save("music_drive.wav", drive)


# ----------------------------------------------------------------------------
# one-shot SFX (GDD 16 / 17)
# ----------------------------------------------------------------------------

def sfx_dash():
    n = int(0.13 * SR)
    s = highpass(noise(n, rng), 900.0) * env_ad(n, 0.0008, 0.030, 1.6)
    s += osc(240.0, n, "sine") * env_ad(n, 0.001, 0.020, 1.0) * 0.35
    return s


def sfx_step_stone():
    n = int(0.18 * SR)
    s = lowpass(noise(n, rng), 1800.0) * env_ad(n, 0.001, 0.035, 1.4)
    s += osc(140.0, n, "sine") * env_ad(n, 0.001, 0.03, 1.0) * 0.4
    return s


def sfx_click():
    n = int(0.22 * SR)
    s = highpass(noise(n, rng), 3200.0) * env_ad(n, 0.0003, 0.006, 1.0) * 1.2
    s += osc(1800.0, n, "square") * env_ad(n, 0.0003, 0.010, 1.0) * 0.35
    s += osc(620.0, n, "sine") * env_ad(n, 0.0005, 0.05, 1.0) * 0.25
    return s


def sfx_explosion():
    n = int(2.4 * SR)
    t = np.arange(n) / SR
    f = 30.0 + 190.0 * np.exp(-t / 0.10)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.001, 0.55, 1.0)
    body = lowpass(noise(n, rng), 900.0) * env_ad(n, 0.001, 0.45, 1.0)
    crack = highpass(noise(n, rng), 2600.0) * env_ad(n, 0.0005, 0.05, 1.0)
    tail = lowpass(noise(n, rng), 300.0) * env_ad(n, 0.05, 0.9, 1.0) * 0.5
    return sub * 1.0 + body * 0.9 + crack * 0.7 + tail


def sfx_land():
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = 55.0 + 120.0 * np.exp(-t / 0.03)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.001, 0.14, 1.0)
    grit = lowpass(noise(n, rng), 2200.0) * env_ad(n, 0.001, 0.10, 1.2)
    return thud + grit * 0.55


def sfx_crack(stage):
    """stage 1..3 -> progressively bigger structural failure."""
    dur = [0.55, 0.8, 1.1][stage - 1]
    n = int(dur * SR)
    lo = [70.0, 58.0, 46.0][stage - 1]
    body = osc(lo, n, "sine") * env_ad(n, 0.004, dur * 0.35, 1.0)
    body += osc(lo * 1.48, n, "tri") * env_ad(n, 0.004, dur * 0.22, 1.0) * 0.4
    grit = lowpass(noise(n, rng), 1400.0) * env_ad(n, 0.002, dur * 0.28, 1.3)
    snap = highpass(noise(n, rng), 3000.0) * env_ad(n, 0.001, 0.03 * stage, 1.0)
    return body * 0.9 + grit * (0.35 + 0.2 * stage) + snap * (0.15 * stage)


def sfx_collapse():
    n = int(3.2 * SR)
    rum = lowpass(noise(n, rng), 240.0) * env_ad(n, 0.02, 1.1, 1.0)
    deb = lowpass(noise(n, rng), 3000.0) * env_ad(n, 0.005, 0.6, 1.0) * 0.5
    sub = osc(38.0, n, "sine") * env_ad(n, 0.01, 0.8, 1.0) * 0.8
    return rum * 1.2 + deb + sub


def sfx_wind(rise=True):
    n = int(1.6 * SR)
    u = np.arange(n) / n
    nz = noise(n, rng)
    a = lowpass(nz, 700.0)
    b = highpass(nz, 1500.0)
    if rise:
        sig = a * (1 - u) + b * u
        amp = np.sin(np.pi * u) ** 0.7
    else:
        sig = b * (1 - u) + a * u
        amp = np.sin(np.pi * u) ** 0.9
    return sig * amp * 0.8


def sfx_scarf():
    n = int(1.1 * SR)
    u = np.arange(n) / n
    flap = lowpass(noise(n, rng), 1600.0)
    trem = 0.5 + 0.5 * np.sin(2 * np.pi * 11.0 * u * (1.0 + u))
    return flap * trem * np.sin(np.pi * u) ** 0.6


def sfx_reject():
    n = int(0.16 * SR)
    s = lowpass(noise(n, rng), 700.0) * env_ad(n, 0.001, 0.03, 1.4)
    s += osc(95.0, n, "sine") * env_ad(n, 0.001, 0.05, 1.0) * 0.5
    return s


def sfx_gate():
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    ch = np.zeros(n)
    for k, semi in enumerate([0, 7, 12, 19]):
        f = D3 * (2 ** (semi / 12.0))
        ch += np.sin(2 * np.pi * f * t) * np.exp(-t / (2.0 + 0.4 * k)) * (0.5 ** k + 0.2)
    shim = highpass(noise(n, rng), 4000.0) * env_ad(n, 0.4, 1.6, 1.0) * 0.25
    return ch * 0.4 + shim


def sfx_pop():
    """Cartoon 'POP' - the comedy layer on top of the real explosion."""
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = 900.0 * np.exp(-t / 0.04) + 120.0
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.0008, 0.07, 1.0)
    smack = highpass(noise(n, rng), 2000.0) * env_ad(n, 0.0005, 0.02, 1.0)
    boing = osc(320.0, n, "tri") * env_ad(n, 0.002, 0.13, 1.0) * 0.5
    return body * 1.0 + smack * 0.6 + boing


def sfx_boing():
    """Springy anticipation - the crouch before a launch."""
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 180.0 + 420.0 * (t / 0.35)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.003, 0.09, 1.0)
    return s + osc(90.0, n, "tri") * env_ad(n, 0.002, 0.05, 1.0) * 0.4


def sfx_whoosh():
    n = int(0.5 * SR)
    u = np.arange(n) / n
    nz = noise(n, rng)
    sig = lowpass(nz, 900.0) * (1 - u) + highpass(nz, 2200.0) * u
    return sig * (np.sin(np.pi * u) ** 0.8)


def sfx_sparkle():
    n = int(0.7 * SR)
    out = np.zeros(n)
    for k, f in enumerate([1760.0, 2637.0, 3520.0, 4186.0]):
        seg = osc(f, n, "sine") * env_ad(n, 0.002, 0.10 - k * 0.015, 1.0)
        off = int(k * 0.045 * SR)
        out[off:] += seg[: n - off] * (0.55 - k * 0.08)
    return out


def sfx_reveal():
    n = int(0.35 * SR)
    s = osc(880.0, n, "tri") * env_ad(n, 0.002, 0.06, 1.0) * 0.5
    s += osc(1320.0, n, "sine") * env_ad(n, 0.004, 0.05, 1.0) * 0.3
    s += lowpass(noise(n, rng), 2400.0) * env_ad(n, 0.001, 0.04, 1.4) * 0.4
    return s


print("sfx:")
for nm, sig in [
    ("sfx_dash.wav", sfx_dash()),
    ("sfx_step.wav", sfx_step_stone()),
    ("sfx_click.wav", sfx_click()),
    ("sfx_explosion.wav", sfx_explosion()),
    ("sfx_land.wav", sfx_land()),
    ("sfx_crack1.wav", sfx_crack(1)),
    ("sfx_crack2.wav", sfx_crack(2)),
    ("sfx_crack3.wav", sfx_crack(3)),
    ("sfx_collapse.wav", sfx_collapse()),
    ("sfx_wind_rise.wav", sfx_wind(True)),
    ("sfx_wind_fall.wav", sfx_wind(False)),
    ("sfx_scarf.wav", sfx_scarf()),
    ("sfx_reject.wav", sfx_reject()),
    ("sfx_reveal.wav", sfx_reveal()),
    ("sfx_pop.wav", sfx_pop()),
    ("sfx_boing.wav", sfx_boing()),
    ("sfx_whoosh.wav", sfx_whoosh()),
    ("sfx_sparkle.wav", sfx_sparkle()),
    ("sfx_gate.wav", sfx_gate()),
]:
    save(nm, sig, peak=0.9)


# ----------------------------------------------------------------------------
# web/mobile delivery: the stems are ~8 MB each as WAV, which is fine off a
# local disk and absurd over a phone connection. Vorbis at 22 kHz mono holds up
# perfectly for this material and cuts the music down by roughly 20x.
# ----------------------------------------------------------------------------

def to_ogg(name, quality=3):
    src = os.path.join(OUT, name + ".wav")
    dst = os.path.join(OUT, name + ".ogg")
    if not os.path.exists(src):
        return
    r = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", src,
         "-c:a", "libvorbis", "-q:a", str(quality), dst],
        capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  ! ffmpeg failed for {name}: {r.stderr.strip()[:200]}")
        return
    os.remove(src)
    for stale in (src + ".import",):
        if os.path.exists(stale):
            os.remove(stale)
    print(f"  {name + '.ogg':26s} {os.path.getsize(dst) / 1024 / 1024:6.2f} MB")


if shutil.which("ffmpeg"):
    print("music -> ogg (web delivery):")
    for s in STEMS:
        to_ogg("music_" + s)
else:
    print("ffmpeg not found - music stays as WAV (too large for a web build)")

print("done.")
