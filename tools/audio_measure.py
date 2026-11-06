#!/usr/bin/env python3
# Reads a Movie Maker recording of tests/audio_probe and prints what reaches the ear: level, peak, how much sits above 2 kHz.
import subprocess, sys, tempfile, os
import numpy as np
from scipy.io import wavfile

def a_weight(f):
    f2 = f * f
    r = (12194.0**2 * f2**2) / ((f2 + 20.6**2) * np.sqrt((f2 + 107.7**2) * (f2 + 737.9**2)) * (f2 + 12194.0**2))
    return r * 10 ** (2.0 / 20)

def measure(x, rate):
    x = x - x.mean()
    win = np.hanning(len(x))
    sp = np.fft.rfft(x * win) / (win.sum() / 2)
    f = np.fft.rfftfreq(len(x), 1 / rate)
    w = a_weight(np.maximum(f, 1.0))
    p = (np.abs(sp) * w) ** 2 / 2
    total = p.sum() + 1e-20
    centroid = (f * p).sum() / total
    return 10 * np.log10(total), p[f >= 2000].sum() / total, centroid

def main(avi, marks_path):
    tmp = tempfile.mktemp(suffix=".wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", avi, "-vn", tmp], check=True)
    rate, d = wavfile.read(tmp)
    os.remove(tmp)
    d = d.astype(float) / (2**15 if d.dtype == np.int16 else 2**31 if d.dtype == np.int32 else 1)
    x = d.mean(axis=1) if d.ndim > 1 else d
    marks = []
    for line in open(marks_path, encoding="utf8"):
        t, name = line.strip().split(" ", 1)
        marks.append((float(t), name))
    marks.append((len(x) / rate, "end"))
    print(f"{'segment':30}{'dB(A)':>7}{'rms':>7}{'peak':>7}{'>2kHz':>7}{'centre':>8}")
    for (t0, n), (t1, _) in zip(marks, marks[1:]):
        a, b = int((t0 + 0.15) * rate), int((t1 - 0.02) * rate)
        s = x[a:b]
        if len(s) < 256:
            continue
        la, hi, c = measure(s, rate)
        rms = 20 * np.log10(np.sqrt((s**2).mean()) + 1e-9)
        peak = 20 * np.log10(np.abs(x[int(t0 * rate):int(t1 * rate)]).max() + 1e-9)
        print(f"{n:30}{la:7.1f}{rms:7.1f}{peak:7.1f}{hi*100:6.0f}%{c:7.0f}Hz")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
