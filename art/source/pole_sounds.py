"""
Makes the show jump pole sounds in sounds/: a wooden pole knocked off its cups, clattering onto
the ground and bouncing. Synthesised here (modal synthesis: a struck wooden bar rings at a few
inharmonic modes that die away fast, plus a short noisy thump), so every sample is ours.

Run from the repository root: python3 art/source/pole_sounds.py
Needs ffmpeg on the path for the .ogg files.

Part of Realistic Equestrian by Jasta007.
"""

import os
import subprocess
import wave

import numpy as np

OUT = "sounds"
RATE = 44100
# A free bar's bending modes, as multiples of its lowest one.
BAR_MODES = [1.0, 2.756, 5.404, 8.933]


def hit(length, pitch, strength, rng, damping=1.0):
    """One strike on a hollow-ish wooden pole: ringing modes and a noisy thump."""
    t = np.arange(int(length * RATE)) / RATE
    out = np.zeros_like(t)
    for i, ratio in enumerate(BAR_MODES):
        f = pitch * ratio * (1 + rng.uniform(-0.015, 0.015))
        decay = (9 + 7 * i) * damping
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-decay * t) / (1 + 0.8 * i)
    noise = rng.standard_normal(len(t))
    # low-passed noise for the woody thump: a running mean
    kernel = np.ones(12) / 12
    thump = np.convolve(noise, kernel, mode="same") * np.exp(-55 * t) * 2.2
    click = noise * np.exp(-400 * t) * 0.35
    return (out + thump + click) * strength


def place(buffer, sound, at):
    start = int(at * RATE)
    end = min(len(buffer), start + len(sound))
    buffer[start:end] += sound[:end - start]


def knock_down(seed, pitch):
    """Knocked off the cups: a tock as the horse hits it, the clonk of one end landing, the other
    end, a couple of bounces and a short roll."""
    rng = np.random.default_rng(seed)
    total = np.zeros(int(1.6 * RATE))
    place(total, hit(0.5, pitch * 1.15, 0.7, rng, damping=1.4), 0.0)          # the hit
    landA = 0.30 + rng.uniform(-0.03, 0.03)
    place(total, hit(0.7, pitch, 1.0, rng), landA)                              # first end lands
    place(total, hit(0.7, pitch * 0.97, 0.85, rng), landA + 0.11 + rng.uniform(0, 0.04))
    gap, level, at = 0.16, 0.45, landA + 0.2
    for _ in range(3):                                                          # bounces
        at += gap
        place(total, hit(0.4, pitch * rng.uniform(0.95, 1.05), level, rng, damping=1.3), at)
        gap *= 0.62
        level *= 0.55
    # a short roll on the ground: soft, quick ticks fading out
    roll = at + 0.05
    for k in range(10):
        place(total, hit(0.08, pitch * 1.3, 0.06 * (1 - k / 10), rng, damping=3), roll + k * 0.035)
    return total


def save(samples, path):
    peak = np.max(np.abs(samples)) or 1.0
    data = (samples / peak * 0.85 * 32767).astype(np.int16)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, (seed, pitch) in enumerate([(11, 210.0), (23, 185.0), (37, 240.0)]):
        wav = os.path.join(OUT, f"poleKnock{i + 1}.wav")
        save(knock_down(seed, pitch), wav)
        ogg = wav[:-4] + ".ogg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
        os.remove(wav)
        print(ogg)


if __name__ == "__main__":
    main()
