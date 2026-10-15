#!/usr/bin/env python3
"""Genera el audio PROPIO y provisional del juego por sintesis (numpy -> WAV).

Todo lo que sale de aqui lo crea este script desde cero (ondas, ruido, envolventes):
no hay muestras de terceros, asi que no hay problema de licencia. Son sonidos de
relleno para que el juego suene; se sustituyen metiendo un archivo con el mismo
nombre (ver audio/README.md). Uso:  python3 tools/gen_audio.py
"""
import os, wave
import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(7)


def t(d): return np.linspace(0, d, int(SR * d), endpoint=False)
def env(n, a=0.005, r=0.08, curve=2.0):
    e = np.ones(n); na = min(n, max(1, int(SR * a))); nr = min(n, max(1, int(SR * r)))
    e[:na] = np.linspace(0, 1, na); e[-nr:] = np.minimum(e[-nr:], np.linspace(1, 0, nr) ** curve)
    return e
def sine(f, d): return np.sin(2 * np.pi * f * t(d))
def square(f, d, duty=0.5): return np.where((f * t(d)) % 1.0 < duty, 1.0, -1.0) * 0.6
def tri(f, d): return 2 * np.abs(2 * ((f * t(d)) % 1.0) - 1) - 1
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def sweep(f0, f1, d, wave_fn=np.sin):
    x = t(d); f = np.linspace(f0, f1, len(x)); ph = 2 * np.pi * np.cumsum(f) / SR
    return wave_fn(ph)
def tone(f, d, wv=sine, a=0.005, r=0.08): return wv(f, d) * env(int(SR * d), a, r)
def lowpass(x, k): return np.convolve(x, np.ones(k) / k, mode="same")
def cat(*xs): return np.concatenate(xs)
def mix(*xs):
    n = max(len(x) for x in xs); o = np.zeros(n)
    for x in xs: o[:len(x)] += x
    return o
def pad(x, d): return np.pad(x, (0, max(0, int(SR * d) - len(x))))
def note(m): return 440.0 * 2 ** ((m - 69) / 12)


def save(path, x, gain=0.8, rms_db=-12.0):
    """Normaliza por RMS (sonoridad pareja entre sonidos) con limitador suave tanh
    para que ningun pico pase de 'gain'."""
    x = np.asarray(x, dtype=np.float64)
    rms = np.sqrt(np.mean(x ** 2)) or 1.0
    x = x / rms * (10 ** (rms_db / 20))
    x = np.tanh(x * 1.2) / np.tanh(1.2)
    x = x * min(1.0, gain / (np.max(np.abs(x)) or 1.0))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def arp(ms, d=0.09, wv=square, r=0.06): return cat(*[tone(note(m), d, wv, 0.004, r) for m in ms])


SFX = {
 "ui/click": lambda: tone(1300, 0.05, sine, 0.002, 0.04) + 0.4 * tone(2600, 0.05, sine, 0.002, 0.03),
 "ui/select": lambda: cat(tone(880, 0.05, square, 0.002, 0.03), tone(1175, 0.07, square, 0.002, 0.05)),
 "ui/back": lambda: cat(tone(700, 0.05, square, 0.002, 0.03), tone(480, 0.08, square, 0.002, 0.06)),
 "ui/open": lambda: sweep(400, 1200, 0.16) * env(int(SR * 0.16), 0.01, 0.1),
 "ui/close": lambda: sweep(1200, 400, 0.14) * env(int(SR * 0.14), 0.005, 0.1),
 "ui/equip": lambda: cat(noise(0.025) * 0.5 * env(int(SR * 0.025), 0.001, 0.02), arp([67, 74], 0.07, square)),
 "ui/remove": lambda: cat(noise(0.025) * 0.4 * env(int(SR * 0.025), 0.001, 0.02), arp([74, 62], 0.07, square)),
 "ui/claim": lambda: arp([76, 79, 83, 88], 0.08, square, 0.07),
 "ui/tab": lambda: tone(1800, 0.03, sine, 0.001, 0.025),
 "ui/buy": lambda: cat(tone(note(88), 0.07, square, 0.002, 0.05), tone(note(95), 0.28, sine, 0.002, 0.25) + 0.3 * tone(note(107), 0.28, sine, 0.002, 0.25)),
 "combat/attack": lambda: mix(lowpass(noise(0.14), 6) * env(int(SR * 0.14), 0.002, 0.12), tone(110, 0.14, sine, 0.002, 0.12) * 0.9),
 "combat/special": lambda: mix(sweep(300, 1800, 0.45) * env(int(SR * 0.45), 0.02, 0.2) * 0.7, lowpass(noise(0.45), 3) * env(int(SR * 0.45), 0.1, 0.2) * 0.4),
 "combat/critical": lambda: mix(tone(80, 0.25, sine, 0.002, 0.2), lowpass(noise(0.2), 3) * env(int(SR * 0.2), 0.001, 0.18), tone(1800, 0.3, sine, 0.002, 0.28) * 0.4, tone(2400, 0.3, sine, 0.002, 0.28) * 0.3),
 "combat/heal": lambda: arp([72, 76, 79, 84, 88], 0.09, sine, 0.1),
 "combat/victory": lambda: cat(arp([67, 67, 67], 0.12, square, 0.04), arp([72], 0.3, square, 0.2) * 1.0, arp([71, 74, 79], 0.14, square, 0.05), mix(tone(note(79), 0.7, square, 0.01, 0.5), tone(note(84), 0.7, square, 0.01, 0.5), tone(note(88), 0.7, square, 0.01, 0.5))),
 "combat/defeat": lambda: cat(arp([69, 66, 62], 0.22, tri, 0.15), tone(note(57), 0.8, tri, 0.02, 0.7)),
 "progression/summon": lambda: mix(sweep(200, 2200, 1.0) * env(int(SR * 1.0), 0.3, 0.15) * 0.5, lowpass(noise(1.0), 4) * env(int(SR * 1.0), 0.5, 0.1) * 0.25, pad(arp([91, 95, 98, 103, 107], 0.1, sine, 0.15), 1.0) * 0.5),
 "progression/evolution": lambda: cat(mix(sweep(100, 900, 1.4) * env(int(SR * 1.4), 0.8, 0.05) * 0.7, lowpass(noise(1.4), 8) * env(int(SR * 1.4), 1.0, 0.02) * 0.3), mix(*[tone(note(m), 1.1, square, 0.01, 0.9) for m in (60, 67, 72, 76)]), mix(*[tone(note(m), 1.2, sine, 0.01, 1.0) for m in (72, 79, 84, 88)])),
 "progression/level_up": lambda: arp([72, 76, 79, 84, 79, 84, 88], 0.07, square, 0.05),
 "progression/mutation": lambda: mix(sweep(300, 500, 0.9) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t(0.9))) * env(int(SR * 0.9), 0.1, 0.4), tone(note(87), 0.9, sine, 0.2, 0.5) * 0.3, lowpass(noise(0.9), 10) * env(int(SR * 0.9), 0.3, 0.3) * 0.2),
}


def song(name, bpm, root, prog, melody, bass_wv=tri, lead_wv=square, bars=8, drums=True):
    """Bucle de 'bars' compases en 4/4. prog: grados de acordes por compas (semitonos
    desde root). melody: lista de 16 notas (semitonos o None) por compas, repetida."""
    beat = 60.0 / bpm; step = beat / 4; n16 = bars * 16
    out = np.zeros(int(SR * step * n16) + SR)
    def put(x, pos):
        i = int(SR * pos * step); out[i:i + len(x)] += x[:len(out) - i]
    for bar in range(bars):
        ch = prog[bar % len(prog)]
        for s in range(16):
            pos = bar * 16 + s
            if s % 4 == 0:
                put(tone(note(root - 12 + ch[0]), step * 3.5, bass_wv, 0.004, 0.1) * 0.7, pos)
            if s % 2 == 0:
                put(tone(note(root + 12 + ch[(s // 2) % len(ch)]), step * 1.6, lead_wv, 0.003, 0.08) * 0.14, pos)
            m = melody[(bar * 16 + s) % len(melody)]
            if m is not None:
                put(tone(note(root + 12 + m), step * 1.8, lead_wv, 0.004, 0.1) * 0.32, pos)
            if drums:
                if s % 8 == 0: put(tone(70, 0.12, sine, 0.001, 0.1) * 0.8, pos)
                if s % 8 == 4: put(lowpass(noise(0.1), 3) * env(int(SR * 0.1), 0.001, 0.08) * 0.5, pos)
                if s % 2 == 1: put(noise(0.03) * env(int(SR * 0.03), 0.001, 0.025) * 0.12, pos)
    return out[:int(SR * step * n16)]


MAJ = (0, 4, 7, 12); MIN = (0, 3, 7, 12)
MUSIC = {
 "music/menu": lambda: song("menu", 96, 60, [(0, 4, 7, 12), (9, 12, 16, 21), (5, 9, 12, 17), (7, 11, 14, 19)],
     [0, None, 4, None, 7, None, 4, None, 9, None, 7, None, 4, None, 2, None], tri, square, 8, False),
 "music/battle": lambda: song("battle", 148, 57, [(0, 3, 7, 12), (0, 3, 7, 12), (-4, 0, 3, 8), (-2, 2, 5, 10)],
     [0, 0, 7, 0, 3, 0, 7, 10, 12, 0, 10, 0, 7, 0, 3, 5], square, square, 8, True),
 "music/history": lambda: song("history", 84, 62, [(0, 4, 7, 12), (-3, 0, 4, 9), (-5, -1, 2, 7), (-7, -3, 0, 5)],
     [7, None, None, 4, 5, None, None, 2, 4, None, 7, None, 12, None, None, None], tri, tri, 8, False),
 "music/events": lambda: song("events", 120, 64, [(0, 4, 7, 12), (5, 9, 12, 17), (7, 11, 14, 19), (0, 4, 7, 12)],
     [0, 4, 7, 12, 7, 4, 0, None, 5, 9, 12, 17, 12, 9, 5, None], square, square, 8, True),
 "music/results": lambda: song("results", 100, 67, [(0, 4, 7, 12), (5, 9, 12, 17), (7, 11, 14, 19), (0, 4, 7, 12)],
     [12, None, 16, None, 19, None, 24, None, 19, None, 16, None, 12, None, None, None], tri, square, 4, False),
}

if __name__ == "__main__":
    for name, fn in {**SFX, **MUSIC}.items():
        p = os.path.normpath(os.path.join(ROOT, name + ".wav"))
        x = fn()
        if name.startswith("music"):
            # Las ondas cuadradas son duras: un filtro suave quita lo mas estridente y
            # un fundido de 4 ms en los extremos evita el clic al cerrar el bucle.
            x = lowpass(x, 4)
            f = int(SR * 0.004)
            x[:f] *= np.linspace(0, 1, f); x[-f:] *= np.linspace(1, 0, f)
        save(p, x, 0.7 if name.startswith("music") else 0.85)
        print("OK", os.path.relpath(p, ROOT), os.path.getsize(p) // 1024, "KB")
