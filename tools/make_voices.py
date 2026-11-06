#!/usr/bin/env python3
# Bakes every line of the game into a radio-sounding clip in audio/voices/. The game only ever plays these files.
# Needs: pip install piper-tts numpy scipy, and Piper's Russian voices (ru_RU-*-medium.onnx with .json) in one folder.
#   python3 tools/make_voices.py /path/to/voices [--phonemes]
# Voices: denis and dmitri are CC0. ruslan is CC BY-NC-SA and irina has no stated licence: replace them before selling the game.
import json, sys, wave
from pathlib import Path
import numpy as np
from scipy import signal
from piper import PiperVoice
from piper.config import SynthesisConfig

ROOT = Path(__file__).resolve().parent.parent
OUT_RATE = 11025

# model, semitones, tempo (above 1 is faster), drive, band, hiss dB, then the odd one out
CAST = {
    "ded":      dict(m="dmitri", st=-1.0, tempo=0.80, drive=2.0, band=(340, 2600), hiss=-30, shake=0.22),
    "kuz":      dict(m="ruslan", st=-1.5, tempo=0.90, drive=2.0, band=(300, 2900), hiss=-34),
    "zina":     dict(m="irina",  st=-2.0, tempo=1.05, drive=3.5, band=(380, 3100), hiss=-31),
    "pelmen":   dict(m="denis",  st=3.0,  tempo=1.15, drive=2.0, band=(420, 3200), hiss=-32, shake=0.10),
    "shnyr":    dict(m="ruslan", st=4.0,  tempo=1.25, drive=2.5, band=(500, 3300), hiss=-30),
    "siply":    dict(m="dmitri", st=0.5,  tempo=0.95, drive=2.0, band=(450, 3400), hiss=-27, hoarse=0.75),
    "valera":   dict(m="denis",  st=-1.0, tempo=1.00, drive=3.0, band=(320, 2800), hiss=-33),
    "mazut":    dict(m="ruslan", st=-5.0, tempo=0.90, drive=4.0, band=(240, 2500), hiss=-30),
    "babai":    dict(m="dmitri", st=-6.0, tempo=0.82, drive=4.5, band=(220, 2300), hiss=-30, growl=0.45),
    "svarshik": dict(m="denis",  st=-3.0, tempo=0.95, drive=3.5, band=(280, 2700), hiss=-28, crackle=3.0),
    "karb":     dict(m="denis",  st=5.0,  tempo=1.30, drive=3.5, band=(520, 3400), hiss=-29),
    "ryzhiy":   dict(m="dmitri", st=3.0,  tempo=1.15, drive=2.5, band=(460, 3300), hiss=-32),
    "hrom":     dict(m="ruslan", st=1.0,  tempo=1.00, drive=1.5, band=(300, 3500), hiss=-40),
    "gvozd":    dict(m="dmitri", st=-2.5, tempo=1.05, drive=2.5, band=(320, 2700), hiss=-33),
    "cop1":     dict(m="denis",  st=-2.0, tempo=1.00, drive=3.0, band=(420, 2500), hiss=-26, beep=(1000, 1320)),
    "cop2":     dict(m="ruslan", st=-3.0, tempo=1.05, drive=3.0, band=(440, 2400), hiss=-26, beep=(880, 1175)),
    "cop3":     dict(m="dmitri", st=-1.0, tempo=0.95, drive=3.0, band=(400, 2600), hiss=-26, beep=(1175, 880)),
}

# where the speech engine gets the stress wrong
STRESS = {"моя будет": "моя\u0301 будет", "Тормоза": "Тормоза\u0301", "остановитесь": "останови\u0301тесь"}

def fix_stress(text):
    for a, b in STRESS.items():
        text = text.replace(a, b)
    return text

def lines():
    out = {}
    for rid, c in json.load(open(ROOT / "data/rivals.json", encoding="utf8")).items():
        out[rid] = c["say"]
    for c in json.load(open(ROOT / "data/sound.json", encoding="utf8"))["cops"]:
        out[c["id"]] = c["say"]
    return out

def speak(pv, text, tempo):
    chunks = []
    cfg = SynthesisConfig(length_scale=1.0 / tempo, noise_scale=0.7, noise_w_scale=0.9)
    for ch in pv.synthesize(text, syn_config=cfg):
        chunks.append(ch.audio_float_array)
    return np.concatenate(chunks), pv.config.sample_rate

def trim(x, rate):
    e = np.convolve(np.abs(x), np.ones(256) / 256, "same")
    on = np.where(e > e.max() * 0.03)[0]
    return x[max(0, on[0] - 200):min(len(x), on[-1] + int(rate * 0.04))]

def band(x, lo, hi, rate, order=4):
    return signal.sosfilt(signal.butter(order, [lo, hi], "bandpass", fs=rate, output="sos"), x)

def radio(x, rate, c, rng):
    # a different pitch by playing it faster or slower: the throat changes size with it, which is the point
    ratio = 2.0 ** (c["st"] / 12.0)
    n = int(len(x) / ratio)
    x = signal.resample(x, n)
    t = np.arange(len(x)) / rate
    if c.get("hoarse"):
        # breath instead of a voice: the same envelope put on noise
        env = np.sqrt(signal.sosfilt(signal.butter(2, 90, "low", fs=rate, output="sos"), x * x).clip(0))
        breath = band(rng.standard_normal(len(x)), 500, 3800, rate) * env
        breath *= np.sqrt((x**2).mean()) / (np.sqrt((breath**2).mean()) + 1e-9)
        x = x * (1 - c["hoarse"]) + breath * c["hoarse"]
    if c.get("shake"):
        x = x * (1.0 + c["shake"] * np.sin(2 * np.pi * 5.4 * t))
    if c.get("growl"):
        x = x * (1.0 - c["growl"] + c["growl"] * (0.5 + 0.5 * signal.square(2 * np.pi * 38 * t)))
    lo, hi = c["band"]
    x = band(x, lo, hi, rate)
    x = x / (np.abs(x).max() + 1e-9)
    d = c["drive"]
    x = np.tanh(x * d) / np.tanh(d)
    x = band(x, lo * 0.8, min(hi * 1.15, rate * 0.45), rate)
    x = x / (np.sqrt((x**2).mean()) + 1e-9) * 0.16
    # short drop-outs, as if the signal slips
    gain = np.ones(len(x))
    for _ in range(rng.integers(0, 3)):
        a = rng.integers(0, max(1, len(x) - 2000))
        w = rng.integers(rate // 40, rate // 16)
        gain[a:a + w] *= rng.uniform(0.35, 0.7)
    gain = signal.sosfiltfilt(signal.butter(1, 300, "low", fs=rate, output="sos"), gain)
    x = x * gain
    # press-to-talk: a click and a little air before, the squelch tail after
    pre, post = int(rate * 0.09), int(rate * 0.16)
    y = np.zeros(pre + len(x) + post)
    y[pre:pre + len(x)] = x
    hiss = band(rng.standard_normal(len(y)), 400, 4200, rate) * 0.16 * 10 ** (c["hiss"] / 20) * 3.0
    hiss *= 1.0 + 0.3 * np.sin(2 * np.pi * rng.uniform(0.7, 1.6) * np.arange(len(y)) / rate + rng.uniform(0, 6))
    y += hiss
    crack = c.get("crackle", 1.0)
    for _ in range(int(rng.poisson(crack * len(y) / rate * 1.2))):
        a = rng.integers(0, len(y) - 200)
        w = rng.integers(20, 150)
        y[a:a + w] += rng.uniform(0.05, 0.14) * rng.standard_normal(w) * np.hanning(w)
    y[:pre] += band(rng.standard_normal(pre), 700, 3800, rate) * 0.09 * np.exp(-np.arange(pre) / (pre * 0.35))
    y[:60] += 0.22 * rng.standard_normal(60) * np.hanning(60)
    tail = band(rng.standard_normal(post), 500, 4200, rate) * 0.26 * np.exp(-np.arange(post) / (post * 0.28))
    y[-post:] += tail
    if c.get("beep"):
        # the police radio's two-tone pip
        f1, f2 = c["beep"]
        w = int(rate * 0.055)
        t2 = np.arange(w) / rate
        pip = np.concatenate([np.sin(2 * np.pi * f1 * t2), np.sin(2 * np.pi * f2 * t2)]) * np.hanning(2 * w) * 0.16
        y = np.concatenate([pip, y])
    return y

def save(path, y, rate):
    y = signal.resample_poly(y, OUT_RATE, rate)
    peak = np.abs(y).max()
    if peak > 0.89:
        y = y / peak * 0.89
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(OUT_RATE)
        w.writeframes((y * 32767).astype(np.int16).tobytes())
    return len(y) / OUT_RATE

def main():
    mdir = sys.argv[1]
    only_ph = "--phonemes" in sys.argv
    out = ROOT / "audio/voices"
    out.mkdir(parents=True, exist_ok=True)
    pv = {}
    total = 0.0
    for who, say in lines().items():
        c = CAST[who]
        if c["m"] not in pv:
            pv[c["m"]] = PiperVoice.load(f"{mdir}/ru_RU-{c['m']}-medium.onnx")
        v = pv[c["m"]]
        for i, text in enumerate(say):
            if only_ph:
                print(who, i, text, "|", " ".join("".join(p) for p in v.phonemize(fix_stress(text))))
                continue
            rng = np.random.default_rng(abs(hash_text(who + str(i))) % (2**32))
            # asked tempo is what comes out after the pitch change
            ratio = 2.0 ** (c["st"] / 12.0)
            x, rate = speak(v, fix_stress(text), c["tempo"] / ratio)
            x = trim(x, rate)
            total += save(out / f"{who}_{i}.wav", radio(x, rate, c, rng), rate)
    if not only_ph:
        print(f"seconds of speech: {total:.0f}")

def hash_text(s):
    h = 5381
    for ch in s.encode("utf8"):
        h = (h * 33 + ch) & 0xFFFFFFFF
    return h

if __name__ == "__main__":
    main()
