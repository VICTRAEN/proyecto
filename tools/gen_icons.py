#!/usr/bin/env python3
"""
Genera los ICONOS SEMI-3D de la interfaz (res://art/ui/icons/<nombre>.png).

Cada icono se construye con formas "hinchadas": a partir de la silueta se calcula
un mapa de alturas suave, de ahi una normal, y se ilumina con una luz arriba a la
izquierda (difusa + reflejo especular + borde oscuro + sombra proyectada + brillo).
Asi todos comparten volumen, reflejos y sombra sin dibujar nada a mano.

Son iconos PROVISIONALES generados por codigo, de calidad de produccion. Para
sustituir uno por arte propio basta con meter un PNG con el mismo nombre en
res://art/ui/icons/ (ver README.md de esa carpeta).

Uso:
    python3 tools/gen_icons.py            # todos
    python3 tools/gen_icons.py coin gem   # solo esos
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

S = 1024          # lienzo de trabajo (se reduce a OUT_SIZE)
OUT_SIZE = 256
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "ui", "icons")
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "fonts", "Rajdhani-Bold.ttf")

YY, XX = np.mgrid[0:S, 0:S].astype(np.float32)
LIGHT = np.array([-0.45, -0.60, 0.66], np.float32)
LIGHT /= np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0, 0, 1], np.float32)
HALF /= np.linalg.norm(HALF)


def C(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# ------------------------------------------------------------------ mascaras

def _canvas():
    return Image.new("L", (S, S), 0)


def _arr(img):
    return np.asarray(img, np.float32) / 255.0


def poly(points, closed=True):
    im = _canvas()
    ImageDraw.Draw(im).polygon([(x * S, y * S) for x, y in points], fill=255)
    return _arr(im)


def circle(cx, cy, r):
    im = _canvas()
    ImageDraw.Draw(im).ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=255)
    return _arr(im)


def ellipse(cx, cy, rx, ry):
    im = _canvas()
    ImageDraw.Draw(im).ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S], fill=255)
    return _arr(im)


def rrect(x0, y0, x1, y1, r):
    im = _canvas()
    ImageDraw.Draw(im).rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=255)
    return _arr(im)


def line(points, width):
    im = _canvas()
    d = ImageDraw.Draw(im)
    pts = [(x * S, y * S) for x, y in points]
    d.line(pts, fill=255, width=int(width * S), joint="curve")
    for p in (pts[0], pts[-1]):
        r = width * S / 2
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    return _arr(im)


def rotated(mask_fn, angle, cx, cy):
    """Genera una mascara y la gira alrededor de (cx, cy) (coordenadas 0..1)."""
    m = Image.fromarray((mask_fn() * 255).astype(np.uint8), "L")
    m = m.rotate(angle, center=(cx * S, cy * S), resample=Image.BICUBIC)
    return _arr(m)


def text_mask(txt, cx, cy, size):
    im = _canvas()
    f = ImageFont.truetype(FONT, int(size * S))
    d = ImageDraw.Draw(im)
    bb = d.textbbox((0, 0), txt, font=f)
    d.text((cx * S - (bb[0] + bb[2]) / 2, cy * S - (bb[1] + bb[3]) / 2), txt, font=f, fill=255)
    return _arr(im)


def star_pts(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ------------------------------------------------------------------- lienzo

class Icon:
    """Lienzo RGBA de float con capas. Por defecto cuadrado SxS; el logo usa otro tamano."""

    def __init__(self, width=S, height=S):
        self.w, self.h = width, height
        self.rgb = np.zeros((height, width, 3), np.float32)
        self.a = np.zeros((height, width), np.float32)
        self.YY, self.XX = np.mgrid[0:height, 0:width].astype(np.float32)

    def _solid(self, color):
        return np.zeros((self.h, self.w, 3), np.float32) + color

    def over(self, rgb, alpha):
        alpha = np.clip(alpha, 0, 1)
        out_a = alpha + self.a * (1 - alpha)
        safe = np.maximum(out_a, 1e-5)[..., None]
        self.rgb = (rgb * alpha[..., None] + self.rgb * (self.a * (1 - alpha))[..., None]) / safe
        self.a = out_a

    def shadow(self, mask, dx=0.012, dy=0.030, blur=16, k=0.50):
        sh = gaussian_filter(np.roll(np.roll(mask, int(dy * S), 0), int(dx * S), 1), blur)
        self.over(self._solid(C("#07031a")), sh * k)

    def glow(self, mask, color, blur=40, k=0.7):
        g = gaussian_filter(mask, blur)
        self.over(self._solid(color), np.clip(g * k * 2.2, 0, 1))

    def puffy(self, mask, top, bottom, sigma=14.0, bump=1.0, spec=0.55, rim=0.45, ambient=0.50,
              outline=None, gloss=0.0, bbox=None):
        """Pinta la silueta con volumen. top/bottom: degradado vertical de la base."""
        if mask.max() <= 0:
            return
        h = gaussian_filter(mask, sigma)
        gy, gx = np.gradient(h)
        k = sigma * 2.2 * bump
        nx, ny, nz = -gx * k, -gy * k, np.ones_like(h)
        n = np.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / n, ny / n, nz / n
        diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
        sp = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0, 1) ** 36 * spec
        ys, xs = np.where(mask > 0.5)
        y0, y1 = ys.min(), ys.max()
        t = np.clip((self.YY - y0) / max(1, (y1 - y0)), 0, 1)[..., None]
        base = top[None, None, :] * (1 - t) + bottom[None, None, :] * t
        edge = np.clip(h / max(h.max() * 0.55, 1e-4), 0, 1)[..., None]
        col = base * (ambient + 0.78 * diff[..., None]) * (1 - rim * (1 - edge) ** 1.5)
        col = col + sp[..., None] * np.array([1, 1, 1], np.float32)
        if gloss > 0:
            gl = np.clip(1 - (self.YY - y0) / max(1, (y1 - y0)) * 2.1, 0, 1) ** 1.6 * gloss
            col = col + (gl * mask)[..., None] * 0.55
        self.over(np.clip(col, 0, 1), mask)

    def flat(self, mask, color, alpha=1.0):
        self.over(self._solid(color), mask * alpha)

    def sparkle(self, cx, cy, size, color=None, k=1.0):
        color = C("#ffffff") if color is None else color
        dx, dy = self.XX - cx * S, self.YY - cy * S
        s = size * S
        hh = np.exp(-np.abs(dy) / (s * 0.045)) * np.exp(-np.abs(dx) / (s * 0.9))
        vv = np.exp(-np.abs(dx) / (s * 0.045)) * np.exp(-np.abs(dy) / (s * 0.9))
        core = np.exp(-(dx * dx + dy * dy) / (s * 0.12) ** 2)
        m = np.clip(hh + vv + core, 0, 1) * k
        self.over(self._solid(color), m)

    def save(self, name, out_size=None, directory=None):
        im = np.dstack([np.clip(self.rgb, 0, 1), np.clip(self.a, 0, 1)])
        pil = Image.fromarray((im * 255 + 0.5).astype(np.uint8), "RGBA")
        if out_size is None:
            out_size = (OUT_SIZE, OUT_SIZE)
        pil = pil.resize(out_size, Image.LANCZOS)
        folder = directory or OUT
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, name + ".png")
        pil.save(path, optimize=True)
        print("  %-12s %5.1f KB" % (name, os.path.getsize(path) / 1024))


# ---------------------------------------------------------------- paletas

GOLD = (C("#ffe9a0"), C("#d08a18"))
GOLD_DK = (C("#c98a1c"), C("#6e3f06"))
SILVER = (C("#f2f0ff"), C("#8a86b8"))
VIOLET = (C("#c8a6ff"), C("#4a2a96"))
MAGENTA = (C("#ff9ad8"), C("#a01e78"))
CYAN = (C("#a8f6ff"), C("#1a86b8"))
GREEN = (C("#b0ffd0"), C("#1a9a64"))
RED = (C("#ff9a9a"), C("#a01e3a"))
DARK = (C("#4a3a7a"), C("#150c36"))
PARCH = (C("#fff2d0"), C("#c89a58"))
BLUE = (C("#9ab8ff"), C("#2a3ea8"))


# ------------------------------------------------------------------ iconos

def icon_coin():
    i = Icon()
    m = circle(0.5, 0.5, 0.40)
    i.glow(m, C("#ffb83a"), 34, 0.35)
    i.shadow(m)
    # canto de la moneda (grosor): disco desplazado hacia abajo, mas oscuro
    edge = circle(0.5, 0.545, 0.40)
    i.puffy(edge, *GOLD_DK, sigma=12)
    i.puffy(m, *GOLD, sigma=20, spec=0.75, gloss=0.35)
    ring = circle(0.5, 0.5, 0.315) - circle(0.5, 0.5, 0.285)
    i.puffy(np.clip(ring, 0, 1), *GOLD_DK, sigma=6, bump=0.8)
    inner = circle(0.5, 0.5, 0.285)
    i.puffy(inner, C("#ffd25a"), C("#e8a020"), sigma=14, spec=0.35)
    st = poly(star_pts(0.5, 0.515, 0.20, 0.085))
    i.puffy(st, C("#fff6c8"), C("#e09a1a"), sigma=7, spec=0.8, rim=0.3)
    i.sparkle(0.30, 0.28, 0.12, k=0.9)
    return i


def facet(i, pts, color, k):
    m = poly(pts)
    i.flat(m, np.clip(color * k, 0, 1))
    return m


def icon_gem():
    i = Icon()
    # diamante: mesa arriba, corona, pabellon
    outline = poly([(0.22, 0.34), (0.34, 0.18), (0.66, 0.18), (0.78, 0.34), (0.5, 0.86)])
    i.glow(outline, C("#4fd8ff"), 38, 0.55)
    i.shadow(outline)
    base = CYAN
    i.puffy(outline, *base, sigma=10, spec=0.2, rim=0.2)
    cy = C("#7ae8ff")
    facet(i, [(0.34, 0.18), (0.66, 0.18), (0.58, 0.34), (0.42, 0.34)], C("#d8fbff"), 1.0)   # mesa
    facet(i, [(0.22, 0.34), (0.34, 0.18), (0.42, 0.34)], C("#7ae0ff"), 1.0)
    facet(i, [(0.78, 0.34), (0.66, 0.18), (0.58, 0.34)], C("#38b0e8"), 1.0)
    facet(i, [(0.22, 0.34), (0.42, 0.34), (0.5, 0.86)], C("#44c4f0"), 0.95)
    facet(i, [(0.42, 0.34), (0.58, 0.34), (0.5, 0.86)], C("#8ff0ff"), 1.0)
    facet(i, [(0.58, 0.34), (0.78, 0.34), (0.5, 0.86)], C("#1e84c0"), 0.95)
    # aristas
    for pts in ([(0.22, 0.34), (0.78, 0.34)], [(0.34, 0.18), (0.42, 0.34), (0.5, 0.86)], [(0.66, 0.18), (0.58, 0.34), (0.5, 0.86)],
                [(0.22, 0.34), (0.34, 0.18), (0.66, 0.18), (0.78, 0.34), (0.5, 0.86), (0.22, 0.34)]):
        i.flat(line(pts, 0.008), C("#eaffff"), 0.75)
    i.sparkle(0.36, 0.27, 0.16, k=1.0)
    i.sparkle(0.70, 0.52, 0.07, k=0.8)
    return i


def icon_crystal():
    """Cristal magenta alto (invocar)."""
    i = Icon()
    body = poly([(0.5, 0.08), (0.70, 0.36), (0.64, 0.84), (0.5, 0.94), (0.36, 0.84), (0.30, 0.36)])
    i.glow(body, C("#ff4fc8"), 46, 0.7)
    i.shadow(body)
    i.puffy(body, *MAGENTA, sigma=10, spec=0.25, rim=0.25)
    facet(i, [(0.5, 0.08), (0.30, 0.36), (0.5, 0.40)], C("#ffc2ee"), 1.0)
    facet(i, [(0.5, 0.08), (0.5, 0.40), (0.70, 0.36)], C("#ff6ac8"), 1.0)
    facet(i, [(0.30, 0.36), (0.36, 0.84), (0.5, 0.40)], C("#e04aae"), 1.0)
    facet(i, [(0.5, 0.40), (0.36, 0.84), (0.5, 0.94), (0.64, 0.84)], C("#9a2a8e"), 1.0)
    facet(i, [(0.5, 0.40), (0.64, 0.84), (0.70, 0.36)], C("#c43aa4"), 1.0)
    for pts in ([(0.5, 0.08), (0.5, 0.94)], [(0.30, 0.36), (0.70, 0.36)], [(0.5, 0.08), (0.30, 0.36), (0.36, 0.84), (0.5, 0.94), (0.64, 0.84), (0.70, 0.36), (0.5, 0.08)]):
        i.flat(line(pts, 0.008), C("#ffe8fa"), 0.7)
    i.sparkle(0.42, 0.26, 0.18, k=1.0)
    i.sparkle(0.80, 0.22, 0.09, C("#ffe2a0"), 0.9)
    i.sparkle(0.22, 0.66, 0.08, C("#9ee8ff"), 0.8)
    return i


def icon_team():
    i = Icon()
    shield = poly([(0.5, 0.06), (0.86, 0.18), (0.86, 0.50), (0.74, 0.74), (0.5, 0.94), (0.26, 0.74), (0.14, 0.50), (0.14, 0.18)])
    i.glow(shield, C("#6a8aff"), 36, 0.4)
    i.shadow(shield)
    i.puffy(shield, *BLUE, sigma=22, spec=0.5, gloss=0.3)
    inner = poly([(0.5, 0.15), (0.78, 0.25), (0.78, 0.49), (0.69, 0.68), (0.5, 0.83), (0.31, 0.68), (0.22, 0.49), (0.22, 0.25)])
    i.puffy(inner, C("#26357a"), C("#0e1442"), sigma=10, bump=0.6, rim=0.2)
    # tres figuras: una central y dos a los lados
    for (cx, cy, s, col) in [(0.37, 0.50, 0.75, SILVER), (0.63, 0.50, 0.75, SILVER), (0.5, 0.47, 1.0, GOLD)]:
        head = circle(cx, cy - 0.06 * s, 0.062 * s)
        bust = poly([(cx - 0.12 * s, cy + 0.20 * s), (cx - 0.10 * s, cy + 0.06 * s), (cx - 0.04 * s, cy + 0.01 * s), (cx + 0.04 * s, cy + 0.01 * s), (cx + 0.10 * s, cy + 0.06 * s), (cx + 0.12 * s, cy + 0.20 * s)])
        i.puffy(np.clip(head + bust, 0, 1), *col, sigma=7, spec=0.5, rim=0.3)
    i.sparkle(0.30, 0.24, 0.12, k=0.8)
    return i


def icon_collection():
    i = Icon()
    cards = [(-20, -0.10, 0.03, VIOLET), (0, 0.0, 0.0, MAGENTA), (20, 0.10, 0.03, CYAN)]
    shadow_union = np.zeros((S, S), np.float32)
    masks = []
    for ang, dx, dy, col in cards:
        m = rotated(lambda: rrect(0.30 + dx, 0.16 + dy, 0.70 + dx, 0.84 + dy, 0.05), ang, 0.5, 0.95)
        masks.append((m, col))
        shadow_union = np.maximum(shadow_union, m)
    i.glow(shadow_union, C("#b05cff"), 36, 0.35)
    i.shadow(shadow_union)
    for (m, col), (ang, dx, dy, _) in zip(masks, cards):
        i.puffy(m, *GOLD, sigma=8, spec=0.5, rim=0.3)
        inner = rotated(lambda dx=dx, dy=dy: rrect(0.325 + dx, 0.19 + dy, 0.675 + dx, 0.81 + dy, 0.035), ang, 0.5, 0.95)
        i.puffy(inner, *col, sigma=10, bump=0.5, spec=0.35, rim=0.15, gloss=0.3)
    # emblema en la carta frontal
    st = rotated(lambda: poly(star_pts(0.5, 0.46, 0.13, 0.055)), 0, 0.5, 0.95)
    i.puffy(st, C("#fff6c8"), C("#e09a1a"), sigma=6, spec=0.8, rim=0.3)
    i.sparkle(0.40, 0.28, 0.10, k=0.8)
    return i


def icon_missions():
    i = Icon()
    sheet = rrect(0.20, 0.10, 0.80, 0.92, 0.06)
    i.glow(sheet, C("#ffd27a"), 30, 0.25)
    i.shadow(sheet)
    i.puffy(sheet, *PARCH, sigma=12, spec=0.25, rim=0.3)
    clip = rrect(0.36, 0.05, 0.64, 0.19, 0.04)
    i.puffy(clip, *GOLD, sigma=7, spec=0.6)
    for k, y in enumerate([0.32, 0.50, 0.68]):
        box = rrect(0.28, y - 0.045, 0.36, y + 0.045, 0.015)
        i.puffy(box, *DARK, sigma=4, bump=0.4, rim=0.1)
        if k < 2:
            i.puffy(line([(0.285, y), (0.31, y + 0.04), (0.36, y - 0.07)], 0.032), *GREEN, sigma=4, spec=0.7)
        i.puffy(rrect(0.42, y - 0.016, 0.72 - 0.08 * k, y + 0.016, 0.01), *DARK, sigma=3, bump=0.4, rim=0.1)
    seal = circle(0.70, 0.82, 0.10)
    i.puffy(seal, *RED, sigma=8, spec=0.7)
    i.puffy(poly(star_pts(0.70, 0.82, 0.062, 0.028)), *GOLD, sigma=3, spec=0.8)
    return i


def icon_history():
    i = Icon()
    left = poly([(0.08, 0.28), (0.48, 0.36), (0.48, 0.88), (0.08, 0.80)])
    right = poly([(0.92, 0.28), (0.52, 0.36), (0.52, 0.88), (0.92, 0.80)])
    cover = poly([(0.05, 0.30), (0.50, 0.40), (0.95, 0.30), (0.95, 0.86), (0.50, 0.96), (0.05, 0.86)])
    i.glow(cover, C("#8a6aff"), 36, 0.35)
    i.shadow(cover)
    i.puffy(cover, *VIOLET, sigma=14, spec=0.4)
    i.puffy(left, *PARCH, sigma=10, spec=0.15, rim=0.3)
    i.puffy(right, *PARCH, sigma=10, spec=0.15, rim=0.3)
    # lineas de texto y un mapa
    for y in (0.46, 0.55, 0.64):
        i.flat(line([(0.14, y), (0.42, y + 0.05)], 0.012), C("#9a6a30"), 0.8)
    i.flat(line([(0.58, 0.46), (0.86, 0.41)], 0.012), C("#9a6a30"), 0.8)
    i.puffy(circle(0.72, 0.62, 0.075), *RED, sigma=6, spec=0.8)
    i.flat(line([(0.58, 0.74), (0.66, 0.68), (0.74, 0.75), (0.86, 0.66)], 0.012), C("#9a6a30"), 0.8)
    # estrella-marcador
    i.puffy(poly(star_pts(0.5, 0.22, 0.12, 0.05)), *GOLD, sigma=6, spec=0.8)
    i.sparkle(0.5, 0.18, 0.14, k=0.9)
    return i


def icon_events():
    i = Icon()
    # lazo (dos colas) + medalla con estrella
    tails = poly([(0.30, 0.60), (0.44, 0.60), (0.50, 0.92), (0.38, 0.84), (0.26, 0.92)])
    tails2 = poly([(0.56, 0.60), (0.70, 0.60), (0.74, 0.92), (0.62, 0.84), (0.50, 0.92)])
    medal = circle(0.5, 0.40, 0.31)
    i.glow(medal, C("#ff5ac8"), 40, 0.5)
    i.shadow(np.clip(medal + tails + tails2, 0, 1))
    i.puffy(tails, *RED, sigma=8)
    i.puffy(tails2, *MAGENTA, sigma=8)
    i.puffy(medal, *GOLD, sigma=20, spec=0.7, gloss=0.3)
    ring = circle(0.5, 0.40, 0.255) - circle(0.5, 0.40, 0.235)
    i.puffy(np.clip(ring, 0, 1), *GOLD_DK, sigma=4, bump=0.6)
    i.puffy(circle(0.5, 0.40, 0.235), C("#7a2a98"), C("#2a0c52"), sigma=14, spec=0.25, rim=0.2, gloss=0.35)
    i.puffy(poly(star_pts(0.5, 0.41, 0.17, 0.072)), C("#fff6c8"), C("#f0a828"), sigma=7, spec=0.8)
    i.sparkle(0.36, 0.26, 0.11, k=0.9)
    return i


def icon_tower():
    i = Icon()
    shaft = poly([(0.40, 0.16), (0.60, 0.16), (0.66, 0.88), (0.34, 0.88)])
    mid = poly([(0.30, 0.44), (0.70, 0.44), (0.74, 0.58), (0.26, 0.58)])
    top = poly([(0.34, 0.16), (0.66, 0.16), (0.60, 0.26), (0.40, 0.26)])
    spire = poly([(0.49, 0.02), (0.51, 0.02), (0.54, 0.16), (0.46, 0.16)])
    base = poly([(0.18, 0.88), (0.82, 0.88), (0.90, 0.96), (0.10, 0.96)])
    allm = np.clip(shaft + mid + top + spire + base, 0, 1)
    i.glow(allm, C("#b78cff"), 40, 0.4)
    i.shadow(allm)
    i.puffy(base, *DARK, sigma=8)
    i.puffy(shaft, C("#8a7ad8"), C("#2a1a78"), sigma=16, spec=0.4)
    i.puffy(mid, *VIOLET, sigma=9, spec=0.5)
    i.puffy(top, *SILVER, sigma=8, spec=0.6)
    i.puffy(spire, *GOLD, sigma=4, spec=0.8)
    for y in (0.34, 0.66, 0.76):
        i.flat(poly([(0.44, y), (0.56, y), (0.56, y + 0.05), (0.44, y + 0.05)]), C("#ffe9a0"), 0.95)
    i.flat(rrect(0.45, 0.50, 0.55, 0.54, 0.01), C("#6df3ff"), 0.9)
    i.sparkle(0.5, 0.03, 0.16, C("#fff0c0"), 1.0)
    return i


def icon_evolution():
    i = Icon()
    hexa = poly([(0.5 + 0.43 * math.cos(math.radians(a)), 0.5 + 0.43 * math.sin(math.radians(a))) for a in range(30, 390, 60)])
    i.glow(hexa, C("#3ae0a0"), 44, 0.55)
    i.shadow(hexa)
    i.puffy(hexa, *GOLD, sigma=18, spec=0.6, gloss=0.25)
    inner = poly([(0.5 + 0.36 * math.cos(math.radians(a)), 0.5 + 0.36 * math.sin(math.radians(a))) for a in range(30, 390, 60)])
    i.puffy(inner, C("#0f6a4a"), C("#052a20"), sigma=14, spec=0.2, rim=0.2, gloss=0.3)
    for k, y in enumerate([0.64, 0.48, 0.32]):
        ch = poly([(0.25, y + 0.07), (0.5, y - 0.12), (0.75, y + 0.07), (0.75, y + 0.17), (0.5, y - 0.02), (0.25, y + 0.17)])
        i.puffy(ch, *GREEN, sigma=7, spec=0.8, rim=0.3, ambient=0.55 + k * 0.08)
    i.sparkle(0.5, 0.22, 0.14, k=0.9)
    return i


def icon_inventory():
    i = Icon()
    # cofre del tesoro
    box = rrect(0.12, 0.44, 0.88, 0.88, 0.05)
    lid = np.clip(poly([(0.12, 0.46), (0.12, 0.34), (0.22, 0.20), (0.78, 0.20), (0.88, 0.34), (0.88, 0.46)]) + circle(0.5, 0.34, 0.0001), 0, 1)
    allm = np.clip(box + lid, 0, 1)
    i.glow(allm, C("#ffb83a"), 40, 0.45)
    i.shadow(allm)
    i.puffy(box, C("#a05a2a"), C("#4a220c"), sigma=16, spec=0.3)
    i.puffy(lid, C("#c2733a"), C("#6a3414"), sigma=14, spec=0.45)
    # bandas doradas
    for x0, x1 in [(0.20, 0.28), (0.72, 0.80)]:
        i.puffy(rrect(x0, 0.20, x1, 0.88, 0.01), *GOLD, sigma=5, spec=0.7)
    i.puffy(rrect(0.12, 0.43, 0.88, 0.49, 0.01), *GOLD, sigma=5, spec=0.7)
    # cerradura
    i.puffy(rrect(0.43, 0.40, 0.57, 0.62, 0.03), *GOLD, sigma=6, spec=0.8)
    i.puffy(circle(0.5, 0.50, 0.025), *DARK, sigma=3, bump=0.3)
    i.puffy(rrect(0.487, 0.50, 0.513, 0.57, 0.008), *DARK, sigma=2, bump=0.3)
    i.sparkle(0.30, 0.26, 0.12, k=0.8)
    return i


def icon_mutations():
    i = Icon()
    flask = poly([(0.40, 0.08), (0.60, 0.08), (0.60, 0.34), (0.82, 0.78), (0.78, 0.90), (0.22, 0.90), (0.18, 0.78), (0.40, 0.34)])
    i.glow(flask, C("#2ae0a0"), 44, 0.6)
    i.shadow(flask)
    i.puffy(flask, C("#e0fff4"), C("#7ac8b0"), sigma=14, spec=0.7, ambient=0.75, rim=0.2)
    liquid = poly([(0.32, 0.56), (0.68, 0.56), (0.80, 0.78), (0.77, 0.87), (0.23, 0.87), (0.20, 0.78)])
    i.puffy(liquid, *GREEN, sigma=12, spec=0.6, rim=0.2, ambient=0.6)
    i.puffy(rrect(0.36, 0.04, 0.64, 0.12, 0.02), *GOLD, sigma=5, spec=0.8)
    for (bx, by, br) in [(0.42, 0.66, 0.035), (0.55, 0.62, 0.025), (0.50, 0.74, 0.045), (0.62, 0.76, 0.03)]:
        i.puffy(circle(bx, by, br), C("#f0fff8"), C("#7affd0"), sigma=4, spec=0.9, rim=0.2)
    i.sparkle(0.36, 0.46, 0.10, k=0.9)
    return i


def icon_shop():
    i = Icon()
    bag = poly([(0.22, 0.30), (0.78, 0.30), (0.88, 0.92), (0.12, 0.92)])
    handle = line([(0.36, 0.34), (0.36, 0.18), (0.40, 0.10), (0.60, 0.10), (0.64, 0.18), (0.64, 0.34)], 0.045)
    allm = np.clip(bag + handle, 0, 1)
    i.glow(allm, C("#ffb83a"), 40, 0.45)
    i.shadow(allm)
    i.puffy(handle, *SILVER, sigma=5, spec=0.8)
    i.puffy(bag, C("#c44a9a"), C("#6a1a58"), sigma=18, spec=0.5, gloss=0.3)
    i.puffy(rrect(0.22, 0.30, 0.78, 0.38, 0.015), *GOLD, sigma=6, spec=0.7)
    # moneda en la bolsa
    i.puffy(circle(0.5, 0.64, 0.16), *GOLD, sigma=12, spec=0.8)
    i.puffy(circle(0.5, 0.64, 0.115), C("#ffd25a"), C("#e8a020"), sigma=8, spec=0.3)
    i.puffy(poly(star_pts(0.5, 0.655, 0.075, 0.032)), C("#fff6c8"), C("#e09a1a"), sigma=4, spec=0.8)
    i.sparkle(0.30, 0.46, 0.10, k=0.7)
    return i


def icon_settings():
    i = Icon()
    n = 8
    gear = circle(0.5, 0.5, 0.30)
    for k in range(n):
        a = 360 / n * k
        tooth = rotated(lambda: rrect(0.43, 0.10, 0.57, 0.30, 0.025), a, 0.5, 0.5)
        gear = np.clip(gear + tooth, 0, 1)
    hole = circle(0.5, 0.5, 0.115)
    i.glow(gear, C("#8a7aff"), 34, 0.4)
    i.shadow(gear)
    i.puffy(np.clip(gear - hole, 0, 1), *SILVER, sigma=14, spec=0.8, gloss=0.3)
    ring = circle(0.5, 0.5, 0.215) - circle(0.5, 0.5, 0.19)
    i.puffy(np.clip(ring, 0, 1), *DARK, sigma=4, bump=0.7, rim=0.2)
    i.puffy(circle(0.5, 0.5, 0.115), C("#1a1040"), C("#0a0624"), sigma=5, bump=-0.5, rim=0.0)
    i.sparkle(0.34, 0.30, 0.10, k=0.8)
    return i


def icon_play():
    """Espadas cruzadas (combate / jugar)."""
    i = Icon()
    blades = []
    for ang in (35, -35):
        blade = rotated(lambda: poly([(0.46, 0.05), (0.54, 0.05), (0.57, 0.64), (0.43, 0.64)]), ang, 0.5, 0.55)
        guard = rotated(lambda: rrect(0.32, 0.64, 0.68, 0.71, 0.025), ang, 0.5, 0.55)
        hilt = rotated(lambda: rrect(0.465, 0.71, 0.535, 0.86, 0.02), ang, 0.5, 0.55)
        pommel = rotated(lambda: circle(0.5, 0.89, 0.035), ang, 0.5, 0.55)
        blades.append((blade, guard, hilt, pommel))
    allm = np.zeros((S, S), np.float32)
    for parts in blades:
        for m in parts:
            allm = np.maximum(allm, m)
    i.glow(allm, C("#ffb83a"), 40, 0.45)
    i.shadow(allm)
    for blade, guard, hilt, pommel in blades:
        i.puffy(blade, *SILVER, sigma=7, spec=0.9, rim=0.3)
        i.puffy(guard, *GOLD, sigma=5, spec=0.8)
        i.puffy(hilt, *RED, sigma=5)
        i.puffy(pommel, *GOLD, sigma=4, spec=0.9)
    i.sparkle(0.5, 0.36, 0.14, k=0.9)
    return i


def icon_lock():
    i = Icon()
    shackle = line([(0.34, 0.46), (0.34, 0.30), (0.40, 0.16), (0.60, 0.16), (0.66, 0.30), (0.66, 0.46)], 0.07)
    body = rrect(0.22, 0.44, 0.78, 0.90, 0.07)
    i.shadow(np.clip(body + shackle, 0, 1))
    i.puffy(shackle, *SILVER, sigma=6, spec=0.9)
    i.puffy(body, *GOLD_DK, sigma=16, spec=0.5, gloss=0.2)
    i.puffy(circle(0.5, 0.62, 0.065), *DARK, sigma=4, bump=0.4)
    i.puffy(rrect(0.475, 0.62, 0.525, 0.78, 0.015), *DARK, sigma=3, bump=0.4)
    return i


def icon_check():
    i = Icon()
    disc = circle(0.5, 0.5, 0.42)
    i.glow(disc, C("#3aff9a"), 34, 0.5)
    i.shadow(disc)
    i.puffy(disc, *GREEN, sigma=20, spec=0.7, gloss=0.35)
    i.puffy(line([(0.28, 0.52), (0.44, 0.68), (0.74, 0.34)], 0.085), C("#ffffff"), C("#d8ffe8"), sigma=6, spec=0.5, rim=0.1)
    return i


def icon_mai_token():
    """Ficha dorada de casino de Mai (icono de OBJETO)."""
    i = Icon()
    disc = circle(0.5, 0.5, 0.42)
    i.glow(disc, C("#ffb83a"), 38, 0.5)
    i.shadow(disc)
    i.puffy(circle(0.5, 0.545, 0.42), *GOLD_DK, sigma=10)
    i.puffy(disc, *GOLD, sigma=22, spec=0.7, gloss=0.3)
    # muescas alrededor
    notches = np.zeros((S, S), np.float32)
    for k in range(12):
        a = 30 * k
        notches = np.maximum(notches, rotated(lambda: rrect(0.455, 0.085, 0.545, 0.175, 0.015), a, 0.5, 0.5))
    i.puffy(notches, C("#3a1a6a"), C("#1a0a3a"), sigma=4, bump=0.5, rim=0.1)
    ring = circle(0.5, 0.5, 0.30) - circle(0.5, 0.5, 0.285)
    i.puffy(np.clip(ring, 0, 1), *GOLD_DK, sigma=4, bump=0.7)
    i.puffy(circle(0.5, 0.5, 0.285), C("#ff4fa8"), C("#8a1060"), sigma=14, spec=0.35, rim=0.2, gloss=0.35)
    i.puffy(text_mask("M", 0.5, 0.50, 0.36), C("#fff6c8"), C("#f0a828"), sigma=5, spec=0.8, rim=0.3)
    i.sparkle(0.30, 0.26, 0.12, k=0.9)
    return i


def icon_rabbit():
    """Uniforme de conejita (icono de OBJETO): orejas, diadema y lazo."""
    i = Icon()
    # cada oreja se dibuja con su propio centro y se inclina sobre su base
    ear1 = rotated(lambda: ellipse(0.35, 0.30, 0.095, 0.27), -12, 0.35, 0.58)
    ear2 = rotated(lambda: ellipse(0.65, 0.30, 0.095, 0.27), 12, 0.65, 0.58)
    in1 = rotated(lambda: ellipse(0.35, 0.31, 0.050, 0.21), -12, 0.35, 0.58)
    in2 = rotated(lambda: ellipse(0.65, 0.31, 0.050, 0.21), 12, 0.65, 0.58)
    band = line([(0.22, 0.60), (0.5, 0.67), (0.78, 0.60)], 0.05)
    allm = np.clip(ear1 + ear2 + band, 0, 1)
    i.glow(allm, C("#ff7ad0"), 40, 0.45)
    i.shadow(allm)
    for e in (ear1, ear2):
        i.puffy(e, C("#4a4a68"), C("#14141f"), sigma=14, spec=0.6)
    for e in (in1, in2):
        i.puffy(e, C("#ffc0e0"), C("#e0508c"), sigma=8, spec=0.5, rim=0.2)
    i.puffy(band, *SILVER, sigma=5, spec=0.9)
    # lazo
    l1 = poly([(0.5, 0.80), (0.27, 0.69), (0.27, 0.91)])
    l2 = poly([(0.5, 0.80), (0.73, 0.69), (0.73, 0.91)])
    i.puffy(l1, *MAGENTA, sigma=8)
    i.puffy(l2, *MAGENTA, sigma=8)
    i.puffy(circle(0.5, 0.80, 0.055), *RED, sigma=6, spec=0.8)
    i.sparkle(0.30, 0.18, 0.10, k=0.8)
    return i


ICONS = {
    "coin": icon_coin, "gem": icon_gem, "crystal": icon_crystal,
    "team": icon_team, "collection": icon_collection, "summon": icon_crystal,
    "missions": icon_missions, "history": icon_history, "events": icon_events,
    "tower": icon_tower, "evolution": icon_evolution, "inventory": icon_inventory,
    "mutations": icon_mutations, "shop": icon_shop, "settings": icon_settings,
    "play": icon_play, "lock": icon_lock, "check": icon_check,
    "mai_token": icon_mai_token, "rabbit_costume": icon_rabbit,
}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(ICONS.keys())
    for name in wanted:
        if name not in ICONS:
            print("desconocido:", name)
            continue
        ICONS[name]().save(name)
