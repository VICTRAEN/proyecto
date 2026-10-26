#!/usr/bin/env python3
"""
Genera el LOGOTIPO provisional de Anime Battle (res://art/ui/logo.png): el titulo
en dorado "hinchado" con contorno violeta, gema central, destellos y un trazo de
luz debajo. Reutiliza el motor de volumen de gen_icons.py.

Es un logotipo PROVISIONAL generado por codigo. Para poner el definitivo basta con
sustituir res://art/ui/logo.png por otro PNG (cualquier proporcion).

Uso:  python3 tools/gen_logo.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_icons as G  # noqa: E402

W, H = 1800, 560
FONT = G.FONT


def text_mask(txt, size, spacing=6, cx=None, cy=None):
    font = ImageFont.truetype(FONT, size)
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    widths = [d.textlength(ch, font=font) + spacing for ch in txt]
    total = sum(widths) - spacing
    x = (cx if cx is not None else W / 2) - total / 2
    bb = d.textbbox((0, 0), "H", font=font)
    y = (cy if cy is not None else H / 2) - (bb[1] + bb[3]) / 2
    for ch, w in zip(txt, widths):
        d.text((x, y), ch, font=font, fill=255)
        x += w
    return np.asarray(im, np.float32) / 255.0


def main():
    icon = G.Icon(W, H)
    C = G.C
    # palabra unica "ANIME BATTLE" en una linea, con la gema entre las dos palabras
    m_a = text_mask("ANIME", 250, 10, cx=W * 0.240, cy=H * 0.46)
    m_b = text_mask("BATTLE", 250, 10, cx=W * 0.708, cy=H * 0.46)
    letters = np.clip(m_a + m_b, 0, 1)
    # contorno grueso violeta (se dibuja detras)
    outline = gaussian_filter(letters, 7) > 0.08
    outline = gaussian_filter(outline.astype(np.float32), 2.0)
    icon.glow(letters, C("#ff4fc8"), 40, 0.55)
    icon.glow(letters, C("#ffb83a"), 18, 0.35)
    icon.flat(np.clip(outline, 0, 1), C("#2a0c52"))
    thin = gaussian_filter(letters, 3.5) > 0.12
    icon.flat(gaussian_filter(thin.astype(np.float32), 1.5), C("#120528"))
    icon.puffy(letters, G.GOLD[0], C("#c97a10"), sigma=16, spec=0.9, rim=0.5, gloss=0.35)
    # segunda pasada mas fina para un biselado interior
    icon.puffy(np.clip(letters - gaussian_filter(letters, 12) * 0.0, 0, 1) * (gaussian_filter(letters, 10) > 0.62), C("#fff4c8"), C("#f0a828"), sigma=8, spec=0.5, rim=0.1, ambient=0.75)
    # gema central
    cx, cy = W * 0.4655, H * 0.46
    gem_pts = [(cx, cy - 88), (cx + 46, cy - 14), (cx, cy + 96), (cx - 46, cy - 14)]
    im = Image.new("L", (W, H), 0)
    ImageDraw.Draw(im).polygon(gem_pts, fill=255)
    gem_mask = np.asarray(im, np.float32) / 255.0
    icon.glow(gem_mask, C("#4fd8ff"), 30, 0.8)
    icon.puffy(gem_mask, C("#c8fbff"), C("#1a86b8"), sigma=9, spec=0.8, rim=0.3)
    for pts, k in [([(cx, cy - 88), (cx + 46, cy - 14), (cx, cy - 14)], 1.1), ([(cx, cy - 88), (cx - 46, cy - 14), (cx, cy - 14)], 0.85),
                   ([(cx - 46, cy - 14), (cx, cy + 96), (cx, cy - 14)], 0.65), ([(cx + 46, cy - 14), (cx, cy + 96), (cx, cy - 14)], 0.45)]:
        im = Image.new("L", (W, H), 0)
        ImageDraw.Draw(im).polygon(pts, fill=255)
        icon.flat(np.asarray(im, np.float32) / 255.0, np.clip(C("#7ae8ff") * k, 0, 1), 0.9)
    # trazo de luz inferior con destellos
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    for k in range(60):
        t = k / 59.0
        a = 255 * (1 - abs(t - 0.5) * 2) ** 0.8
        d.line([(W * (0.06 + 0.88 * t), H * 0.86), (W * (0.06 + 0.88 * (t + 1 / 59.0)), H * 0.86)], fill=int(a), width=7)
    sweep = np.asarray(im, np.float32) / 255.0
    icon.glow(sweep, C("#ffb83a"), 12, 0.8)
    icon.flat(sweep, C("#fff2c0"))
    for (sx, sy, sz) in [(0.115, 0.30, 0.06), (0.905, 0.28, 0.07), (0.50, 0.12, 0.08)]:
        # sparkle usa coordenadas normalizadas al tamano del lienzo cuadrado: ajuste
        dx, dy = icon.XX - sx * W, icon.YY - sy * H
        s_ = sz * W * 0.55
        hh = np.exp(-np.abs(dy) / (s_ * 0.045)) * np.exp(-np.abs(dx) / (s_ * 0.9))
        vv = np.exp(-np.abs(dx) / (s_ * 0.045)) * np.exp(-np.abs(dy) / (s_ * 0.9))
        core = np.exp(-(dx * dx + dy * dy) / (s_ * 0.12) ** 2)
        icon.over(icon._solid(C("#ffffff")), np.clip(hh + vv + core, 0, 1))
    icon.save("logo", out_size=(W // 2, H // 2), directory=os.path.join(os.path.dirname(G.OUT)))


if __name__ == "__main__":
    main()
