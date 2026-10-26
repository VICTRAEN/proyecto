#!/usr/bin/env python3
"""
Genera los FONDOS de pantalla de Anime Battle (res://art/backgrounds/<slot>.webp).

Son escenas ilustradas por codigo (cielos, soles, ciudades futuristas al
atardecer, cristales, portales...) con una paleta comun: violeta profundo, azul
medianoche, magenta y dorado. NO son arte final de ningun artista: son fondos
PROVISIONALES de calidad de produccion para que el juego tenga identidad desde el
primer dia. Para sustituir uno basta con meter un PNG con el mismo nombre en
res://art/backgrounds/ (el PNG gana al .webp; ver README.md de esa carpeta).

Uso:
    python3 tools/gen_backgrounds.py            # todos
    python3 tools/gen_backgrounds.py menu tower # solo esos

Requisitos: numpy, scipy, pillow (con WebP). Es determinista: la misma semilla da
la misma imagen.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter, zoom

W, H = 1080, 1920
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "backgrounds")

YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)


def C(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# ---------------------------------------------------------------- primitivas

def vgrad(stops):
    """Degradado vertical. stops = [(y 0..1, color), ...]"""
    ys = np.linspace(0, 1, H)
    xs = [s[0] for s in stops]
    out = np.zeros((H, W, 3), np.float32)
    for c in range(3):
        out[:, :, c] = np.interp(ys, xs, [s[1][c] for s in stops])[:, None]
    return out


def screen(a, b):
    return 1.0 - (1.0 - a) * (1.0 - b)


def blur(img, s):
    if img.ndim == 3:
        return gaussian_filter(img, (s, s, 0))
    return gaussian_filter(img, s)


def noise(cell_y, cell_x=None, octaves=4, seed=0, persist=0.5):
    """Ruido fractal suave 0..1 de tamano HxW."""
    rng = np.random.default_rng(seed)
    cell_x = cell_x or cell_y
    acc = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cy, cx = max(8.0, cell_y / (2 ** o)), max(8.0, cell_x / (2 ** o))
        gh, gw = int(math.ceil(H / cy)) + 3, int(math.ceil(W / cx)) + 3
        small = rng.random((gh, gw)).astype(np.float32)
        up = zoom(small, (H / (gh - 3) * 1.0, W / (gw - 3) * 1.0), order=3)
        up = up[: H + int(cy * 3), : W + int(cx * 3)]
        up = np.pad(up, ((0, max(0, H - up.shape[0])), (0, max(0, W - up.shape[1]))), mode="edge")
        acc += amp * up[:H, :W]
        tot += amp
        amp *= persist
    acc /= tot
    acc = (acc - acc.min()) / (acc.max() - acc.min() + 1e-6)
    return acc


def blob(cx, cy, rx, ry, power=2.0):
    d = np.sqrt(((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2)
    return np.clip(1.0 - d, 0, 1) ** power


def add_glow(img, mask, color, k=1.0):
    return screen(img, mask[..., None] * color[None, None, :] * k)


def to_pil_rgba(arr_rgb, alpha):
    a = np.dstack([np.clip(arr_rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]])
    return Image.fromarray((a * 255).astype(np.uint8), "RGBA")


def composite(base, rgb, alpha):
    return base * (1 - alpha[..., None]) + rgb * alpha[..., None]


# ------------------------------------------------------------------- cielo

def sky(stops):
    return vgrad(stops)


def stars(img, rng, count=420, ymax=0.55, strength=1.0, tint=None):
    layer = np.zeros((H, W), np.float32)
    ys = (rng.random(count) ** 1.6 * ymax * H).astype(int)
    xs = rng.integers(0, W, count)
    br = rng.random(count) ** 2.5
    for x, y, b in zip(xs, ys, br):
        layer[y, x] = max(layer[y, x], b)
    big = layer > 0.55
    glow = blur(layer * big, 2.2) * 6.0
    layer = np.clip(layer * 1.1 + glow, 0, 1)
    fade = np.clip(1.0 - YY / (ymax * H), 0, 1)
    color = tint if tint is not None else C("#f1ecff")
    return screen(img, (layer * fade * strength)[..., None] * color)


def clouds(img, seed, y0, y1, color_lit, color_dark, density=0.55, cell=(220, 700), light_from=None):
    n = noise(cell[0], cell[1], 5, seed, 0.55)
    band = np.clip(1 - np.abs((YY / H - (y0 + y1) / 2) / ((y1 - y0) / 2 + 1e-6)), 0, 1) ** 0.8
    a = np.clip((n - (1 - density)) / density, 0, 1) ** 1.2 * band
    shade = np.clip(1.0 - (YY / H - y0) / (y1 - y0 + 1e-6), 0, 1)
    col = color_dark[None, None, :] * (1 - shade[..., None] * 0.0) + (color_lit - color_dark)[None, None, :] * (shade[..., None] ** 0.7 * 0.0)
    # luz desde abajo (el sol esta en el horizonte): la parte baja de la nube brilla
    lit = np.clip((YY / H - y0) / (y1 - y0 + 1e-6), 0, 1)[..., None]
    col = color_dark[None, None, :] * (1 - lit) + color_lit[None, None, :] * lit
    return composite(img, col, a * 0.85)


def sun(img, cx, cy, r, color_core, color_halo, bands=False):
    halo = blob(cx, cy, r * 5.0, r * 4.2, 2.2)
    img = add_glow(img, halo, color_halo, 0.55)
    halo2 = blob(cx, cy, r * 2.2, r * 2.0, 1.6)
    img = add_glow(img, halo2, color_halo, 0.55)
    d = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
    disc = np.clip((r - d) / 2.5, 0, 1)
    if bands:
        # franjas horizontales que se ensanchan hacia abajo (sol "synthwave")
        t = np.clip((YY - (cy - r * 0.1)) / (r * 1.1), 0, 1)
        stripe = (np.sin(YY / (10.0 - t * 6.0 + 2.0) * 1.6) > (0.15 - t * 1.4)).astype(np.float32)
        disc = disc * np.where(YY > cy - r * 0.1, stripe, 1.0)
    grad = np.clip((YY - (cy - r)) / (2 * r), 0, 1)[..., None]
    sun_col = color_core[None, None, :] * (1 - grad) + (color_halo * 0.9)[None, None, :] * grad
    return composite(img, sun_col, disc * 0.98)


# ---------------------------------------------------------------- ciudad

def skyline(rng, base_y, hmin, hmax, wmin, wmax, seed_detail=0, spires=0.25, slant=0.3, neon=None, x_pad=40):
    """Devuelve (mascara HxW, lista de edificios (x0,x1,top)) con siluetas de torres
    futuristas: cajas, torres escalonadas, techos inclinados y antenas."""
    ss = 2
    mask = Image.new("L", (W * ss, H * ss), 0)
    d = ImageDraw.Draw(mask)
    rects = []
    x = -x_pad
    while x < W + x_pad:
        w = int(rng.integers(wmin, wmax))
        h = int(hmin + (hmax - hmin) * (rng.random() ** 1.5))
        top = base_y - h
        kind = rng.random()
        pts_list = []
        if kind < slant:
            lean = int(rng.integers(8, max(9, w // 2)))
            if rng.random() < 0.5:
                pts_list.append([(x, base_y + 5), (x, top + lean), (x + w, top), (x + w, base_y + 5)])
            else:
                pts_list.append([(x, base_y + 5), (x, top), (x + w, top + lean), (x + w, base_y + 5)])
        elif kind < slant + 0.3:
            # escalonada
            w2 = int(w * rng.uniform(0.45, 0.7))
            xo = x + (w - w2) // 2
            h2 = int(h * rng.uniform(0.18, 0.4))
            pts_list.append([(x, base_y + 5), (x, top + h2), (x + w, top + h2), (x + w, base_y + 5)])
            pts_list.append([(xo, top + h2 + 2), (xo, top), (xo + w2, top), (xo + w2, top + h2 + 2)])
        else:
            pts_list.append([(x, base_y + 5), (x, top), (x + w, top), (x + w, base_y + 5)])
        for pts in pts_list:
            d.polygon([(px * ss, py * ss) for px, py in pts], fill=255)
        # antena / aguja
        if rng.random() < spires:
            cx = x + w // 2 + int(rng.integers(-w // 4, w // 4 + 1))
            sh = int(rng.integers(30, 120))
            d.polygon([(cx * ss - 2 * ss, top * ss + 2), (cx * ss, (top - sh) * ss), (cx * ss + 2 * ss, top * ss + 2)], fill=255)
        rects.append((x, x + w, top))
        x += w + int(rng.integers(-6, 10))
    mask = mask.resize((W, H), Image.LANCZOS)
    return np.asarray(mask, np.float32) / 255.0, rects


def city_layer(img, rng, base_y, hmin, hmax, wmin, wmax, color_top, color_bottom, haze,
               windows=None, edge_light=None, spires=0.25, slant=0.3):
    mask, rects = skyline(rng, base_y, hmin, hmax, wmin, wmax, spires=spires, slant=slant)
    top_y = base_y - hmax - 120
    t = np.clip((YY - top_y) / (base_y - top_y + 1e-6), 0, 1)[..., None]
    col = color_top[None, None, :] * (1 - t) + color_bottom[None, None, :] * t
    # perspectiva atmosferica: se tinta del cielo (desenfocado, para que el sol no
    # se vea a traves de la silueta)
    ref = blur(img[::4, ::4], 9.0)
    ref = np.repeat(np.repeat(ref, 4, axis=0), 4, axis=1)[:H, :W]
    col = col * (1 - haze) + haze * ref
    img = composite(img, col, mask)
    if edge_light is not None:
        # filo de luz en el borde superior de las siluetas
        up = np.roll(mask, 3, axis=0)
        rim = np.clip(mask - up, 0, 1)
        img = add_glow(img, blur(rim, 1.2), edge_light, 1.4)
    if windows is not None:
        emit = np.zeros((H, W, 3), np.float32)
        wimg = Image.new("RGB", (W, H), (0, 0, 0))
        wd = ImageDraw.Draw(wimg)
        pal = windows["palette"]
        p = windows.get("p", 0.35)
        ww, wh = windows.get("size", (6, 9))
        gx, gy = windows.get("grid", (16, 22))
        for (x0, x1, top) in rects:
            y = top + 14
            while y < base_y - 10:
                xx = x0 + 8
                while xx < x1 - 8 - ww:
                    if rng.random() < p:
                        c = pal[int(rng.integers(0, len(pal)))]
                        k = rng.uniform(0.55, 1.0)
                        wd.rectangle([xx, y, xx + ww, y + wh], fill=tuple(int(v * 255 * k) for v in c))
                    xx += gx
                y += gy
        emit = np.asarray(wimg, np.float32) / 255.0 * mask[..., None]
        bloom = blur(emit, 5.0) * 1.8
        img = screen(img, emit * 0.9)
        img = screen(img, np.clip(bloom, 0, 1) * 0.6)
    return img, mask, rects


def window_grid(img, mask, rng, gx=18, gy=24, size=(6, 9), p=0.25, palette=None, y_min=0, y_max=H, bloom=True):
    """Ventanas iluminadas sobre una silueta cualquiera (rejilla regular con huecos)."""
    palette = palette or NEON + WARM
    emit = np.zeros((H, W, 3), np.float32)
    for y in range(int(y_min), int(y_max), gy):
        for x in range(0, W, gx):
            if rng.random() < p:
                c = palette[int(rng.integers(0, len(palette)))]
                emit[y: y + size[1], x: x + size[0]] = c * rng.uniform(0.5, 1.0)
    emit *= mask[..., None]
    out = screen(img, emit * 0.9)
    if bloom:
        out = screen(out, np.clip(blur(emit, 5.0) * 1.8, 0, 1) * 0.6)
    return out


def reflect_floor(img, horizon_y, strength=0.45, fade=700, tint=None):
    """Suelo brillante: refleja lo que hay sobre el horizonte, desenfocado."""
    out = img.copy()
    h_below = H - horizon_y
    src = img[max(0, horizon_y - h_below): horizon_y][::-1]
    src = blur(src, 6.0)
    n = min(src.shape[0], h_below)
    t = np.clip(1 - np.arange(n) / fade, 0, 1)[:, None, None] ** 1.5 * strength
    base = out[horizon_y: horizon_y + n]
    tinted = src[:n] if tint is None else src[:n] * 0.7 + tint[None, None, :] * 0.3
    out[horizon_y: horizon_y + n] = base * (1 - t) + tinted * t
    return out


def beams(img, rng, origins, color, spread=0.06, length=1100, alpha=0.20, angle_range=(-0.5, 0.5)):
    layer = np.zeros((H, W), np.float32)
    for (ox, oy) in origins:
        ang = -math.pi / 2 + rng.uniform(*angle_range)
        dx, dy = XX - ox, YY - oy
        dist = np.sqrt(dx * dx + dy * dy) + 1e-6
        cosang = (dx * math.cos(ang) + dy * math.sin(ang)) / dist
        w = np.clip((cosang - (1 - spread)) / spread, 0, 1) ** 1.4
        fade = np.clip(1 - dist / length, 0, 1) ** 1.2
        layer += w * fade
    layer = np.clip(layer, 0, 1)
    return add_glow(img, blur(layer, 6.0), color, alpha)


def bokeh(img, rng, count, palette, ymin=0.0, ymax=1.0, rmin=8, rmax=46, alpha=0.18):
    layer = np.zeros((H, W, 3), np.float32)
    for _ in range(count):
        cx = rng.uniform(0, W)
        cy = rng.uniform(ymin * H, ymax * H)
        r = rng.uniform(rmin, rmax)
        c = palette[int(rng.integers(0, len(palette)))]
        d = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
        disc = np.clip((r - d) / 2.0, 0, 1) * 0.55 + np.clip(1 - d / (r * 1.15), 0, 1) * 0.15
        disc *= rng.uniform(0.35, 1.0)
        layer += disc[..., None] * c[None, None, :]
    return screen(img, np.clip(layer, 0, 1) * alpha * 3.0)


def crystal(img, cx, cy, size, color, rng, glow_k=0.8, tilt=0.0, aspect=2.2):
    """Cristal facetado (bipiramide alargada) con brillo y facetas."""
    ss = 3
    S = int(size * 3.2)
    pil = Image.new("RGBA", (S * ss, S * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    c = S * ss // 2
    hw = size * ss * 0.5
    hh = size * ss * 0.5 * aspect
    top = (c, c - hh)
    bot = (c, c + hh)
    l = (c - hw, c - hh * 0.12)
    r = (c + hw, c - hh * 0.12)
    m = (c, c + hh * 0.18)
    base = color
    def mix(k):
        return tuple(int(255 * np.clip(v * k, 0, 1)) for v in base) + (255,)
    d.polygon([top, l, m], fill=mix(1.25))
    d.polygon([top, m, r], fill=mix(0.85))
    d.polygon([l, bot, m], fill=mix(0.55))
    d.polygon([m, bot, r], fill=mix(0.38))
    d.line([top, l, bot, r, top], fill=tuple(int(255 * min(1, v * 1.5 + 0.35)) for v in base) + (255,), width=ss * 2)
    d.line([top, m, bot], fill=(255, 255, 255, 120), width=ss)
    pil = pil.rotate(math.degrees(tilt), resample=Image.BICUBIC)
    pil = pil.resize((S, S), Image.LANCZOS)
    arr = np.asarray(pil, np.float32) / 255.0
    x0, y0 = int(cx - S / 2), int(cy - S / 2)
    out = img.copy()
    # halo
    out = add_glow(out, blob(cx, cy, size * 3.2, size * 3.8, 2.0), base, glow_k * 0.55)
    xs0, ys0 = max(0, x0), max(0, y0)
    xs1, ys1 = min(W, x0 + S), min(H, y0 + S)
    if xs1 > xs0 and ys1 > ys0:
        sub = arr[ys0 - y0: ys1 - y0, xs0 - x0: xs1 - x0]
        a = sub[..., 3]
        out[ys0:ys1, xs0:xs1] = composite(out[ys0:ys1, xs0:xs1], sub[..., :3], a * 0.95)
    return out


def sparkle(img, cx, cy, size, color, k=1.0):
    """Destello de 4 puntas (lens flare sencillo)."""
    dx, dy = XX - cx, YY - cy
    h = np.exp(-np.abs(dy) / (size * 0.05)) * np.exp(-np.abs(dx) / (size * 0.9))
    v = np.exp(-np.abs(dx) / (size * 0.05)) * np.exp(-np.abs(dy) / (size * 0.55))
    core = np.exp(-(dx * dx + dy * dy) / (size * 0.10) ** 2)
    m = np.clip(h + v * 0.8 + core, 0, 1)
    return screen(img, m[..., None] * color[None, None, :] * k)


def vignette(img, strength=0.55, power=2.2):
    d = np.sqrt(((XX - W / 2) / (W * 0.75)) ** 2 + ((YY - H / 2) / (H * 0.68)) ** 2)
    v = np.clip(d, 0, 1.4) ** power
    return img * (1 - np.clip(v, 0, 1)[..., None] * strength)


def finish(img, name, rng, grain=0.012, quality=88):
    img = np.clip(img, 0, 1)
    img = img + (rng.random((H, W, 1)).astype(np.float32) - 0.5) * grain * 2
    img = np.clip(img, 0, 1)
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".webp")
    im.save(path, "WEBP", quality=quality, method=6)
    print("  %-14s %6.0f KB" % (name, os.path.getsize(path) / 1024))
    return im


# ================================================================ ESCENAS

NEON = [C("#6df3ff"), C("#ff5ac8"), C("#ffd166"), C("#b78cff")]
WARM = [C("#ffd9a0"), C("#ffb866"), C("#ff9ad5"), C("#fff1c9")]


def scene_menu(seed=11):
    """MENU: ciudad futurista al atardecer. Sol magenta-dorado tras las torres."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.60)
    img = sky([(0.0, C("#0a0526")), (0.14, C("#241062")), (0.30, C("#6a1f86")),
               (0.41, C("#c4307f")), (0.49, C("#ff7a5c")), (0.57, C("#ffc680")), (0.62, C("#ffe0a0")), (1.0, C("#2a0f4a"))])
    img = stars(img, rng, 520, 0.38, 1.0)
    img = clouds(img, 3, 0.18, 0.54, C("#ff8a7a"), C("#3a1470"), 0.55, (200, 620))
    img = sun(img, W * 0.5, horizon - 130, 250, C("#fff6d0"), C("#ff8a6a"), bands=True)
    img = beams(img, rng, [(W * 0.12, horizon), (W * 0.9, horizon), (W * 0.62, horizon)], C("#ffd2a8"), 0.04, 1000, 0.10, (-0.35, 0.35))
    # tres capas de ciudad, de lejos (clara, brumosa) a cerca (oscura y con ventanas)
    img, _, _ = city_layer(img, rng, horizon + 4, 120, 380, 38, 90, C("#6a2b8c"), C("#a8446e"), 0.62, spires=0.3)
    img, _, _ = city_layer(img, rng, horizon + 14, 160, 520, 44, 110, C("#2d1259"), C("#5a1f6a"), 0.35,
                           windows={"palette": NEON + WARM, "p": 0.22, "size": (5, 8), "grid": (15, 21)},
                           edge_light=C("#ff9ad5"), spires=0.3)
    img, _, _ = city_layer(img, rng, horizon + 36, 90, 300, 60, 140, C("#150a38"), C("#240d44"), 0.08,
                           windows={"palette": WARM + NEON[:2], "p": 0.18, "size": (7, 10), "grid": (20, 26)},
                           edge_light=C("#ffb27a"), spires=0.18)
    # suelo: plaza mojada que refleja el atardecer
    floor = vgrad([(0, C("#1a0b36")), (1, C("#09041a"))])
    ground = (YY > horizon + 36).astype(np.float32)
    img = composite(img, floor, ground)
    img = reflect_floor(img, horizon + 36, 0.55, 720, C("#ff7ab0"))
    img = add_glow(img, blob(W * 0.5, horizon + 40, 520, 120, 1.6), C("#ff9a8a"), 0.45)
    # torres de ENCUADRE a los lados (dejan el centro libre para el personaje)
    for side in (-1, 1):
        base_x = 0 if side < 0 else W
        inward = -side
        m = Image.new("L", (W * 2, H * 2), 0)
        dd = ImageDraw.Draw(m)
        for (off, wd, top) in [(-20, 125, 560), (95, 95, 800)]:
            x0 = base_x + inward * off
            x1 = x0 + inward * wd
            xa, xb = sorted((x0, x1))
            dd.polygon([(xa * 2, H * 2), (xa * 2, (top + 40) * 2), ((xa + (xb - xa) // 2) * 2, top * 2), (xb * 2, (top + 40) * 2), (xb * 2, H * 2)], fill=255)
        mk = np.asarray(m.resize((W, H), Image.LANCZOS), np.float32) / 255.0
        mk *= np.clip(1.0 - (YY - (horizon + 30)) / 380.0, 0.0, 1.0)  # se funden con el suelo
        tcol = vgrad([(0.2, C("#2a1058")), (0.6, C("#150a38")), (1, C("#0a0420"))])
        img = composite(img, tcol, mk)
        edge = np.clip(mk - np.roll(mk, -inward * 4, axis=1), 0, 1)
        img = add_glow(img, blur(edge, 1.6), C("#ff9ad5"), 1.5)
        # tiras de neon verticales
        strip = np.zeros((H, W), np.float32)
        for (off, wd, top) in [(-20, 125, 560), (95, 95, 800)]:
            xx = int(base_x + inward * (off + wd * (0.85 if inward > 0 else 0.15)))
            strip[top + 60: horizon + 40, xx: xx + 3] = 1
        img = window_grid(img, mk, rng, 17, 25, (6, 9), 0.24, NEON + WARM, 540, horizon + 30)
        strip *= mk
        img = add_glow(img, blur(strip, 1.0), C("#6df3ff") if side < 0 else C("#ff5ac8"), 1.1)
        img = add_glow(img, blur(strip, 7.0), C("#6df3ff") if side < 0 else C("#ff5ac8"), 0.9)
    # cristales flotantes
    for (cx, cy, s, col, tl) in [(160, 520, 38, C("#6df3ff"), 0.3), (930, 380, 50, C("#ff5ac8"), -0.25),
                                  (880, 760, 28, C("#ffd166"), 0.35), (120, 880, 24, C("#b78cff"), -0.4)]:
        img = crystal(img, cx, cy, s, col, rng, 0.8, tl)
    img = bokeh(img, rng, 26, NEON + WARM, 0.35, 0.8, 6, 26, 0.10)
    for (sx, sy, ss_, col) in [(160, 520, 70, "#6df3ff"), (930, 380, 90, "#ff9ad5"), (880, 760, 50, "#ffd166")]:
        img = sparkle(img, sx, sy, ss_, C(col), 0.7)
    img = vignette(img, 0.55)
    return finish(img, "menu", rng)


def scene_collection(seed=21):
    """COLECCION: galeria cristalina. Cielo violeta, nebulosas, cristales en profundidad."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#0a0630")), (0.35, C("#2a1170")), (0.7, C("#5a1d86")), (1.0, C("#150a40"))])
    n1 = noise(380, 540, 5, 5)
    n2 = noise(300, 420, 5, 8)
    img = add_glow(img, np.clip(n1 * 1.4 - 0.45, 0, 1), C("#ff4fb8"), 0.55)
    img = add_glow(img, np.clip(n2 * 1.5 - 0.7, 0, 1), C("#4fd8ff"), 0.45)
    img = stars(img, rng, 700, 0.95, 1.0)
    img = beams(img, rng, [(W * 0.2, -40), (W * 0.55, -80), (W * 0.85, -40)], C("#cdb8ff"), 0.05, 1600, 0.17, (math.pi - 0.2, math.pi + 0.2))
    # ciudad lejana, muy brumosa, abajo
    horizon = int(H * 0.86)
    img, _, _ = city_layer(img, rng, horizon, 80, 260, 40, 90, C("#3b1a73"), C("#6a2d8f"), 0.55, spires=0.25)
    img, _, _ = city_layer(img, rng, horizon + 30, 80, 200, 50, 110, C("#1c0e46"), C("#2f1458"), 0.25,
                           windows={"palette": NEON, "p": 0.15, "size": (5, 8), "grid": (16, 22)}, edge_light=C("#b78cff"))
    # cristales a distintas profundidades (los lejanos pequenos y brumosos)
    spots = [(140, 300, 62, "#6df3ff", 0.25), (940, 220, 80, "#ff5ac8", -0.3), (880, 880, 56, "#b78cff", 0.35),
             (90, 1100, 44, "#ffd166", -0.2), (990, 1380, 70, "#6df3ff", 0.4), (200, 1500, 52, "#ff5ac8", 0.2),
             (540, 120, 34, "#ffd166", 0.0), (760, 540, 26, "#6df3ff", -0.3), (320, 760, 22, "#b78cff", 0.3)]
    for (cx, cy, s, col, tl) in spots:
        img = crystal(img, cx, cy, s, C(col), rng, 0.9, tl)
    img = bokeh(img, rng, 34, NEON, 0.0, 1.0, 8, 40, 0.10)
    img = vignette(img, 0.6)
    return finish(img, "collection", rng)


def scene_summon(seed=31):
    """INVOCAR: portal. Circulo magico, rayos y un nucleo de luz."""
    rng = np.random.default_rng(seed)
    cx, cy = W * 0.5, H * 0.46
    img = sky([(0, C("#07031c")), (0.5, C("#190a48")), (1, C("#05020f"))])
    d = np.sqrt(((XX - cx) / 1.0) ** 2 + ((YY - cy) / 1.0) ** 2)
    img = add_glow(img, np.clip(1 - d / 980, 0, 1) ** 1.6, C("#6a2bd6"), 0.9)
    img = add_glow(img, np.clip(1 - d / 520, 0, 1) ** 1.8, C("#ff4fb8"), 0.65)
    img = add_glow(img, np.clip(1 - d / 230, 0, 1) ** 2.0, C("#fff0ff"), 0.9)
    # rayos radiales
    ang = np.arctan2(YY - cy, XX - cx)
    rays = (np.sin(ang * 14 + 0.6) * 0.5 + 0.5) ** 6 * (np.sin(ang * 5 + 1.3) * 0.5 + 0.5) ** 2
    img = add_glow(img, rays * np.clip(1 - d / 1250, 0, 1) ** 1.2, C("#d9b8ff"), 0.55)
    # circulos magicos (anillos finos con marcas)
    ring = np.zeros((H, W), np.float32)
    for r, w in [(760, 4), (700, 2), (610, 3), (470, 2), (340, 3)]:
        ring += np.clip(1 - np.abs(d - r) / w, 0, 1)
    for r, n in [(735, 72), (505, 48), (655, 36)]:
        tick = (np.abs(((ang * n / (2 * math.pi)) % 1.0) - 0.5) < 0.06).astype(np.float32)
        ring += tick * np.clip(1 - np.abs(d - r) / 14, 0, 1)
    # hexagrama
    hexg = np.zeros((H, W), np.float32)
    for k in range(2):
        pts = [(cx + 600 * math.cos(math.radians(a + 90 + 60 * k)), cy + 600 * math.sin(math.radians(a + 90 + 60 * k))) for a in range(0, 360, 120)]
        pil = Image.new("L", (W, H), 0)
        ImageDraw.Draw(pil).line(pts + [pts[0]], fill=255, width=3)
        hexg = np.maximum(hexg, np.asarray(pil, np.float32) / 255.0)
    ring = np.clip(ring + hexg, 0, 1)
    img = add_glow(img, blur(ring, 1.0), C("#f1d4ff"), 0.85)
    img = add_glow(img, blur(ring, 6.0), C("#b05cff"), 1.1)
    # plataforma de invocacion en el suelo
    plat = blob(cx, H * 0.80, 620, 120, 1.4)
    img = add_glow(img, plat, C("#ff5ac8"), 0.5)
    img = stars(img, rng, 380, 0.9, 0.9)
    img = bokeh(img, rng, 40, NEON, 0.0, 1.0, 5, 18, 0.12)
    img = vignette(img, 0.55)
    return finish(img, "summon", rng)


def scene_team(seed=41):
    """EQUIPO: hangar de preparacion. Suelo de rejilla en perspectiva y focos."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.55)
    img = sky([(0, C("#050a22")), (0.3, C("#0c1c4a")), (0.55, C("#1a2f78")), (0.56, C("#0c0a2a")), (1, C("#06041a"))])
    # muro del fondo con paneles hexagonales tenues
    for r in range(-1, 40):
        for c in range(-1, 22):
            hx = c * 60 + (30 if r % 2 else 0)
            hy = r * 52
            if hy > horizon:
                continue
            a = 0.05 + 0.05 * math.sin(r * 0.7 + c * 0.9)
            img[max(0, hy - 1): hy + 2, max(0, hx - 24): hx + 24] += np.array([0.10, 0.20, 0.40], np.float32) * a
    img = add_glow(img, blob(W * 0.5, horizon, 760, 360, 1.8), C("#3b7bff"), 0.65)
    img = add_glow(img, blob(W * 0.5, horizon - 80, 380, 180, 2.0), C("#ff4fb8"), 0.55)
    # focos (conos de luz) desde el techo
    img = beams(img, rng, [(W * 0.18, -30), (W * 0.5, -60), (W * 0.82, -30)], C("#9ec8ff"), 0.05, 1500, 0.22, (math.pi - 0.15, math.pi + 0.15))
    # suelo: rejilla en perspectiva
    floor = vgrad([(0.0, C("#0a0a2a")), (1.0, C("#05030f"))])
    ground = (YY > horizon).astype(np.float32)
    img = composite(img, floor, ground)
    t = np.clip((YY - horizon) / (H - horizon), 1e-4, 1)
    persp = 1.0 / (t + 0.02)
    vlines = np.abs(((XX - W / 2) * persp / 90.0) % 1.0 - 0.5)
    hlines = np.abs((persp * 2.0) % 1.0 - 0.5)
    gridv = np.clip(1 - vlines * 22 / np.maximum(persp, 1.0) * 1.0, 0, 1)
    gridh = np.clip(1 - hlines * 22 / 6.0, 0, 1)
    g = np.maximum(gridv, gridh * 0.8) * (YY > horizon) * np.clip(t * 3, 0, 1) ** 0.7
    img = add_glow(img, blur(g, 0.8), C("#4fd8ff"), 0.50)
    img = add_glow(img, blur(g, 5.0), C("#ff4fb8"), 0.45)
    img = add_glow(img, blob(W * 0.5, horizon + 10, 700, 90, 1.3), C("#7ab8ff"), 0.5)
    # ciudad lejana en la ventana del fondo
    img, _, _ = city_layer(img, rng, horizon, 60, 180, 38, 80, C("#101a4a"), C("#1b2f78"), 0.45,
                           windows={"palette": NEON, "p": 0.2, "size": (4, 6), "grid": (13, 18)}, edge_light=C("#6df3ff"))
    img = bokeh(img, rng, 18, NEON, 0.2, 0.7, 5, 20, 0.08)
    img = vignette(img, 0.6)
    return finish(img, "team", rng)


def scene_stages(seed=51):
    """SELECCION DE BATALLA: calle de la ciudad al atardecer azulado."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.58)
    img = sky([(0, C("#06143a")), (0.3, C("#143a8a")), (0.5, C("#6a4ab0")), (0.58, C("#ff8a8a")), (0.62, C("#ffc890")), (1, C("#10163a"))])
    img = stars(img, rng, 300, 0.3, 0.8)
    img = clouds(img, 9, 0.25, 0.56, C("#ffa8a0"), C("#2a3a8a"), 0.5, (200, 640))
    img = sun(img, W * 0.3, horizon - 30, 150, C("#fff0c8"), C("#ffa08a"))
    img, _, _ = city_layer(img, rng, horizon, 140, 420, 40, 100, C("#3a3a98"), C("#7a5aa8"), 0.55)
    img, _, _ = city_layer(img, rng, horizon + 20, 100, 360, 50, 120, C("#161a58"), C("#2b2a72"), 0.2,
                           windows={"palette": WARM + NEON[:1], "p": 0.2, "size": (5, 8), "grid": (15, 21)}, edge_light=C("#ffb898"))
    floor = vgrad([(0, C("#12163e")), (1, C("#070918"))])
    img = composite(img, floor, (YY > horizon + 20).astype(np.float32))
    img = reflect_floor(img, horizon + 20, 0.5, 600, C("#ff9ab0"))
    img = beams(img, rng, [(W * 0.7, horizon), (W * 0.15, horizon)], C("#ffd2a8"), 0.04, 900, 0.10, (-0.3, 0.3))
    img = bokeh(img, rng, 20, WARM + NEON[:2], 0.3, 0.75, 6, 24, 0.09)
    img = vignette(img, 0.55)
    return finish(img, "stages", rng)


def scene_battle(seed=61, variant="plain"):
    """COMBATE: escenario sobrio (maxima legibilidad): contraste bajo, tonos medios."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.52)
    if variant == "forest":
        img = sky([(0, C("#04161e")), (0.4, C("#0c4a4a")), (0.52, C("#3aa08a")), (1, C("#06201e"))])
        img = stars(img, rng, 250, 0.4, 0.7)
        img = beams(img, rng, [(W * 0.3, -40), (W * 0.7, -40)], C("#9effd8"), 0.05, 1500, 0.16, (math.pi - 0.1, math.pi + 0.1))
        # troncos y copas como siluetas
        for layer_i, (hh, col, hz) in enumerate([(520, C("#0e4a42"), 0.6), (420, C("#06302c"), 0.25), (360, C("#031a18"), 0.05)]):
            m = Image.new("L", (W, H), 0)
            dd = ImageDraw.Draw(m)
            x = -30
            while x < W + 30:
                tw = int(rng.integers(26, 60))
                th = int(hh * rng.uniform(0.6, 1.3))
                dd.rectangle([x, horizon + 30 - th, x + tw, horizon + 40], fill=255)
                rr = int(rng.integers(70, 150))
                dd.ellipse([x + tw // 2 - rr, horizon + 30 - th - rr // 2, x + tw // 2 + rr, horizon + 30 - th + rr], fill=255)
                x += int(rng.integers(70, 170))
            mk = np.asarray(m.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
            img = composite(img, col[None, None, :] * (1 - hz * 0.3) + img * hz * 0.4, mk)
        floor = vgrad([(0, C("#0a3a30")), (1, C("#03100e"))])
        img = composite(img, floor, (YY > horizon + 30).astype(np.float32))
        img = bokeh(img, rng, 40, [C("#9effd8"), C("#6df3ff"), C("#e8ffb0")], 0.2, 0.9, 4, 14, 0.14)
    elif variant == "ruins":
        img = sky([(0, C("#100626")), (0.35, C("#3a1468")), (0.5, C("#a8306a")), (0.56, C("#ff8a70")), (1, C("#1a0c30"))])
        img = stars(img, rng, 300, 0.35, 0.8)
        img = sun(img, W * 0.7, horizon - 40, 130, C("#fff0c8"), C("#ff8a6a"))
        m = Image.new("L", (W * 2, H * 2), 0)
        dd = ImageDraw.Draw(m)
        for i in range(9):
            px = int(rng.integers(0, W))
            pw = int(rng.integers(40, 90))
            ph = int(rng.integers(220, 560))
            top = horizon - ph
            dd.polygon([(px * 2, (horizon + 20) * 2), (px * 2, (top + int(rng.integers(0, 60))) * 2), ((px + pw) * 2, top * 2), ((px + pw) * 2, (horizon + 20) * 2)], fill=255)
        # arco roto
        dd.arc([(W // 2 - 260) * 2, (horizon - 560) * 2, (W // 2 + 260) * 2, (horizon + 80) * 2], 180, 360, fill=255, width=70)
        mk = np.asarray(m.resize((W, H), Image.LANCZOS), np.float32) / 255.0
        img = composite(img, vgrad([(0, C("#3a1a52")), (1, C("#12061f"))]), mk * 0.92)
        img = composite(img, vgrad([(0, C("#1a0a30")), (1, C("#07030f"))]), (YY > horizon + 20).astype(np.float32))
        img = bokeh(img, rng, 30, WARM, 0.25, 0.85, 4, 16, 0.12)
    else:
        img = sky([(0, C("#080a24")), (0.3, C("#1c1f58")), (0.48, C("#6a3a8a")), (0.54, C("#f08a7a")), (0.58, C("#ffc79a")), (1, C("#0c0a24"))])
        img = stars(img, rng, 300, 0.3, 0.8)
        img = clouds(img, 13, 0.2, 0.5, C("#e07a8a"), C("#252468"), 0.5, (180, 560))
        img = sun(img, W * 0.5, horizon - 20, 120, C("#fff0c8"), C("#ff9a7a"))
        img, _, _ = city_layer(img, rng, horizon, 90, 260, 40, 100, C("#44307f"), C("#7a4a98"), 0.6)
        img, _, _ = city_layer(img, rng, horizon + 12, 70, 200, 56, 120, C("#1b1650"), C("#2c1b64"), 0.25,
                               windows={"palette": WARM, "p": 0.14, "size": (5, 8), "grid": (16, 22)}, edge_light=C("#ffb898"))
        img = composite(img, vgrad([(0, C("#171243")), (1, C("#070418"))]), (YY > horizon + 12).astype(np.float32))
        img = reflect_floor(img, horizon + 12, 0.35, 560, C("#ff9ab0"))
    img = vignette(img, 0.45)
    return finish(img, "battle" if variant == "plain" else "battle_" + variant, rng)


def scene_results(seed=71):
    """RESULTADOS: rayos dorados y brillo de victoria sobre violeta."""
    rng = np.random.default_rng(seed)
    cx, cy = W * 0.5, H * 0.34
    img = sky([(0, C("#0c0630")), (0.4, C("#3a1478")), (0.7, C("#7a2a8a")), (1, C("#140a34"))])
    d = np.sqrt((XX - cx) ** 2 + (YY - cy) ** 2)
    ang = np.arctan2(YY - cy, XX - cx)
    rays = (np.sin(ang * 18) * 0.5 + 0.5) ** 3 * (np.sin(ang * 7 + 0.5) * 0.5 + 0.5) ** 1.5
    img = add_glow(img, np.clip(1 - d / 1500, 0, 1) ** 1.1 * rays, C("#ffd986"), 0.95)
    img = add_glow(img, np.clip(1 - d / 700, 0, 1) ** 1.8, C("#ffb04a"), 0.75)
    img = add_glow(img, np.clip(1 - d / 260, 0, 1) ** 2.0, C("#fff6d6"), 0.9)
    img = stars(img, rng, 500, 0.9, 0.8, C("#ffe9b0"))
    horizon = int(H * 0.82)
    img, _, _ = city_layer(img, rng, horizon, 70, 220, 50, 110, C("#2a1260"), C("#4a1f70"), 0.45, spires=0.2)
    img, _, _ = city_layer(img, rng, horizon + 20, 50, 160, 60, 130, C("#150a38"), C("#1c0d44"), 0.15,
                           windows={"palette": WARM, "p": 0.18, "size": (6, 9), "grid": (18, 24)}, edge_light=C("#ffd08a"))
    img = bokeh(img, rng, 60, WARM, 0.0, 0.9, 4, 18, 0.16)
    img = vignette(img, 0.5)
    return finish(img, "results", rng)


def scene_missions(seed=81):
    """MISIONES: sala de control holografica. Rejilla hexagonal y nodos."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#050a1e")), (0.4, C("#0c1a46")), (1, C("#090618"))])
    img = add_glow(img, blob(W * 0.5, H * 0.28, 820, 520, 1.6), C("#2a68d8"), 0.55)
    img = add_glow(img, blob(W * 0.15, H * 0.85, 520, 380, 1.8), C("#b02aa0"), 0.45)
    hexm = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(hexm)
    R = 64
    for r in range(-1, 28):
        for c in range(-1, 12):
            hx = c * R * 1.5 * 1.0
            hy = r * R * 1.732 + (R * 0.866 if c % 2 else 0)
            pts = [(hx + R * 0.94 * math.cos(math.radians(a)), hy + R * 0.94 * math.sin(math.radians(a))) for a in range(0, 360, 60)]
            dd.line(pts + [pts[0]], fill=255, width=2)
    hexa = np.asarray(hexm, np.float32) / 255.0
    fade = np.clip(1 - np.abs(YY / H - 0.35) / 0.55, 0, 1) ** 1.3
    img = add_glow(img, hexa * fade, C("#5a9cff"), 0.38)
    # nodos luminosos
    for _ in range(26):
        cx, cy = rng.uniform(0, W), rng.uniform(0.05 * H, 0.9 * H)
        img = add_glow(img, blob(cx, cy, 36, 36, 2.0), (C("#ff5ac8") if rng.integers(0, 3) == 0 else C("#6df3ff")), 0.8)
    img = beams(img, rng, [(W * 0.3, H + 40), (W * 0.75, H + 40)], C("#7ab8ff"), 0.05, 1500, 0.14, (-0.15, 0.15))
    img = stars(img, rng, 200, 0.5, 0.6)
    img = vignette(img, 0.6)
    return finish(img, "missions", rng)


def scene_events(seed=91):
    """EVENTOS: atardecer de festival. Magenta, luces flotantes y guirnaldas."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.62)
    img = sky([(0, C("#1a0436")), (0.2, C("#5a0f6a")), (0.42, C("#b02a7a")), (0.54, C("#ff6a6a")), (0.60, C("#ffb870")), (1, C("#2a0a3a"))])
    img = stars(img, rng, 260, 0.25, 0.8)
    img = clouds(img, 5, 0.15, 0.5, C("#ff9aa0"), C("#4a1068"), 0.5, (200, 620))
    img = sun(img, W * 0.5, horizon - 30, 250, C("#fff0d0"), C("#ff8a8a"))
    img, _, _ = city_layer(img, rng, horizon, 90, 300, 40, 100, C("#7a2a78"), C("#b04a78"), 0.5)
    img, _, _ = city_layer(img, rng, horizon + 20, 80, 260, 56, 120, C("#2a0e4a"), C("#4a1458"), 0.2,
                           windows={"palette": WARM + [C("#ff5ac8")], "p": 0.3, "size": (6, 8), "grid": (14, 20)}, edge_light=C("#ffc89a"))
    img = composite(img, vgrad([(0, C("#240a3a")), (1, C("#0b0418"))]), (YY > horizon + 20).astype(np.float32))
    img = reflect_floor(img, horizon + 20, 0.5, 600, C("#ff7a9a"))
    # guirnaldas de luces (catenarias) cruzando el cielo
    for y0, sag, phase in [(260, 70, 0.0), (420, 90, 1.3), (610, 70, 2.1)]:
        pts = []
        for x in range(-20, W + 40, 6):
            t = x / W
            pts.append((x, y0 + sag * math.sin(math.pi * t) + 14 * math.sin(phase + t * 9)))
        pil = Image.new("L", (W, H), 0)
        ImageDraw.Draw(pil).line(pts, fill=120, width=2)
        img = composite(img, np.array([0.1, 0.03, 0.15], np.float32), np.asarray(pil, np.float32) / 255.0 * 0.8)
        bulbs = np.zeros((H, W), np.float32)
        for i in range(0, len(pts), 5):
            bx, by = pts[i]
            bulbs += blob(bx, by + 6, 14, 14, 1.6)
        img = add_glow(img, np.clip(bulbs, 0, 1), C("#ffe2a0"), 0.95)
    img = bokeh(img, rng, 44, WARM + [C("#ff5ac8")], 0.1, 0.85, 6, 30, 0.12)
    img = vignette(img, 0.5)
    return finish(img, "events", rng)


def scene_history(seed=101):
    """HISTORIA: atlas de islas flotantes con caminos de luz y constelaciones."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#070730")), (0.35, C("#1a1a6a")), (0.7, C("#4a2a98")), (1, C("#0e0a38"))])
    img = add_glow(img, np.clip(noise(420, 520, 5, 3) * 1.5 - 0.55, 0, 1), C("#7a5aff"), 0.5)
    img = add_glow(img, np.clip(noise(320, 420, 5, 4) * 1.5 - 0.75, 0, 1), C("#ff5ac8"), 0.30)
    img = stars(img, rng, 700, 0.9, 1.0)
    # constelaciones: puntos unidos por lineas tenues
    pts = [(rng.uniform(60, W - 60), rng.uniform(60, H * 0.5)) for _ in range(14)]
    pil = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(pil)
    for i in range(len(pts) - 1):
        if math.dist(pts[i], pts[i + 1]) < 300:
            dd.line([pts[i], pts[i + 1]], fill=130, width=1)
    cons = blur(np.asarray(pil, np.float32) / 255.0, 0.8)
    img = add_glow(img, cons, C("#bcd0ff"), 0.6)
    # islas flotantes
    isl = [(250, 760, 300, 0.7), (800, 560, 240, 0.55), (520, 1180, 360, 0.8), (150, 1500, 220, 0.5), (900, 1480, 260, 0.6)]
    for (ix, iy, iw, a) in isl:
        m = Image.new("L", (W * 2, H * 2), 0)
        dd = ImageDraw.Draw(m)
        top = [(ix - iw // 2, iy), (ix - iw // 3, iy - 26), (ix, iy - 38), (ix + iw // 3, iy - 24), (ix + iw // 2, iy)]
        under = [(ix + iw // 2, iy), (ix + iw // 4, iy + 70), (ix + iw // 8, iy + 140), (ix, iy + int(iw * 0.5)),
                 (ix - iw // 7, iy + 130), (ix - iw // 3, iy + 60), (ix - iw // 2, iy)]
        dd.polygon([(x * 2, y * 2) for x, y in top + under], fill=255)
        mk = np.asarray(m.resize((W, H), Image.LANCZOS), np.float32) / 255.0
        grad = vgrad([(0, C("#6a5ab8")), (1, C("#1a1058"))])
        img = composite(img, grad * (0.55 + 0.4 * a), mk * 0.96)
        edge = np.clip(mk - np.roll(mk, 4, axis=0), 0, 1)
        img = add_glow(img, blur(edge, 1.5), C("#bcd0ff"), 0.9)
        img = crystal(img, ix + iw * 0.1, iy - 56, 26 + iw // 18, (C("#6df3ff") if rng.integers(0, 2) == 0 else C("#ff5ac8")), rng, 0.8, rng.uniform(-0.3, 0.3))
        img = add_glow(img, blob(ix, iy + 60, iw * 0.7, iw * 0.5, 2.0), C("#7a5aff"), 0.25)
    # senderos de luz entre islas
    pil = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(pil)
    order = [(150, 1500), (520, 1180), (250, 760), (800, 560)]
    for a, b in zip(order[:-1], order[1:]):
        for i in range(0, 41):
            t = i / 40
            x = a[0] + (b[0] - a[0]) * t + math.sin(t * 6) * 30
            y = a[1] + (b[1] - a[1]) * t
            r = 3 if i % 2 == 0 else 2
            dd.ellipse([x - r, y - r, x + r, y + r], fill=230)
    img = add_glow(img, blur(np.asarray(pil, np.float32) / 255.0, 3.0), C("#ffe2a0"), 1.6)
    img = bokeh(img, rng, 24, NEON, 0.0, 1.0, 5, 22, 0.08)
    img = vignette(img, 0.6)
    return finish(img, "history", rng)


def scene_map(seed=111):
    """MAPA DE MUNDO: cielo crepuscular con valle luminoso (mas calido que historia)."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.58)
    img = sky([(0, C("#071a3a")), (0.3, C("#1c4a8a")), (0.5, C("#5a7ac0")), (0.58, C("#ffc890")), (1, C("#10204a"))])
    img = stars(img, rng, 350, 0.3, 0.8)
    img = clouds(img, 17, 0.2, 0.55, C("#ffd0a8"), C("#2a4a8a"), 0.5, (180, 600))
    img = sun(img, W * 0.72, horizon - 30, 120, C("#fff3d0"), C("#ffb48a"))
    # tres cordilleras
    for i, (col_top, col_bot, hmax, haze) in enumerate([(C("#4a6aa8"), C("#8a8ac0"), 300, 0.6), (C("#24407a"), C("#3a4a8a"), 340, 0.35), (C("#0f2250"), C("#16285a"), 300, 0.1)]):
        pts = [(-10, H)]
        phase = rng.uniform(0, 6)
        for k in range(0, 21):
            t = k / 20
            y = horizon + 30 * i - hmax * (0.25 + 0.5 * abs(math.sin(t * 5 + phase + i))) * (1 - 0.25 * i)
            pts.append((W * t, y))
        pts.append((W + 10, H))
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(pts, fill=255)
        mk = np.asarray(m.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
        t = np.clip((YY - (horizon - hmax)) / (hmax + 200), 0, 1)[..., None]
        col = col_top[None, None, :] * (1 - t) + col_bot[None, None, :] * t
        col = col * (1 - haze) + haze * img
        img = composite(img, col, mk)
    img = composite(img, vgrad([(0, C("#10254f")), (1, C("#060c20"))]), (YY > horizon + 160).astype(np.float32))
    img = beams(img, rng, [(W * 0.72, horizon)], C("#ffe2b0"), 0.05, 1100, 0.12, (-0.1, 0.1))
    img = bokeh(img, rng, 22, WARM + NEON[:1], 0.4, 0.9, 5, 18, 0.10)
    img = vignette(img, 0.5)
    return finish(img, "map", rng)


def scene_inventory(seed=121):
    """INVENTARIO: camara del tesoro. Arcos, luz dorada y cristales de almacenaje."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#0a0420")), (0.5, C("#240c4a")), (1, C("#12062a"))])
    img = add_glow(img, blob(W * 0.5, H * 0.18, 720, 520, 1.5), C("#ffb04a"), 0.60)
    img = add_glow(img, blob(W * 0.5, H * 0.95, 900, 360, 1.6), C("#ff5ac8"), 0.35)
    # arcos verticales (pilares con arco) en perspectiva
    m = Image.new("L", (W * 2, H * 2), 0)
    dd = ImageDraw.Draw(m)
    for i, (cx, wd, top) in enumerate([(140, 150, 400), (940, 150, 400), (360, 100, 520), (720, 100, 520)]):
        dd.rectangle([(cx - wd // 2) * 2, top * 2, (cx + wd // 2) * 2, H * 2], fill=255)
        dd.pieslice([(cx - wd) * 2, (top - wd) * 2, (cx + wd) * 2, (top + wd) * 2], 180, 360, fill=255)
    mk = np.asarray(m.resize((W, H), Image.LANCZOS), np.float32) / 255.0
    img = composite(img, vgrad([(0, C("#3a1c66")), (1, C("#14082c"))]), mk * 0.9)
    edge = np.clip(mk - np.roll(mk, 3, axis=1), 0, 1) + np.clip(mk - np.roll(mk, -3, axis=1), 0, 1)
    img = add_glow(img, blur(edge, 1.5), C("#ffd27a"), 0.8)
    img = beams(img, rng, [(W * 0.5, -40)], C("#ffe2a0"), 0.09, 1700, 0.20, (math.pi - 0.05, math.pi + 0.05))
    # cristales de almacenaje abajo
    for (cx, cy, s, col, tl) in [(120, 1700, 60, "#ffd166", 0.2), (960, 1680, 72, "#ff5ac8", -0.25), (250, 1820, 40, "#6df3ff", 0.1), (860, 1830, 44, "#b78cff", -0.1)]:
        img = crystal(img, cx, cy, s, C(col), rng, 0.8, tl)
    img = bokeh(img, rng, 40, WARM, 0.0, 1.0, 4, 20, 0.12)
    img = stars(img, rng, 150, 0.4, 0.4, C("#ffe9b0"))
    img = vignette(img, 0.6)
    return finish(img, "inventory", rng)


def scene_mutation(seed=131):
    """MUTACIONES: laboratorio arcano esmeralda con helice de ADN y runas."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#021412")), (0.4, C("#06382f")), (0.75, C("#0b5a46")), (1, C("#03140f"))])
    img = add_glow(img, blob(W * 0.5, H * 0.42, 720, 640, 1.6), C("#1fe0a0"), 0.55)
    img = add_glow(img, blob(W * 0.5, H * 0.42, 300, 330, 2.0), C("#c8fff0"), 0.55)
    # doble helice vertical
    pil = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(pil)
    pa, pb = [], []
    for y in range(-20, H + 20, 4):
        a = y / 150.0
        pa.append((W * 0.5 + 170 * math.sin(a), y))
        pb.append((W * 0.5 - 170 * math.sin(a), y))
    dd.line(pa, fill=255, width=6)
    dd.line(pb, fill=255, width=6)
    for y in range(0, H, 34):
        a = y / 150.0
        x1, x2 = W * 0.5 + 170 * math.sin(a), W * 0.5 - 170 * math.sin(a)
        dd.line([(x1, y), (x2, y)], fill=150, width=2)
        dd.ellipse([x1 - 6, y - 6, x1 + 6, y + 6], fill=255)
        dd.ellipse([x2 - 6, y - 6, x2 + 6, y + 6], fill=255)
    helix = np.asarray(pil, np.float32) / 255.0
    fade = np.clip(1 - np.abs(YY / H - 0.42) / 0.62, 0, 1) ** 1.2
    img = add_glow(img, blur(helix, 1.0) * fade, C("#aaffe0"), 0.8)
    img = add_glow(img, blur(helix, 8.0) * fade, C("#1fe0a0"), 1.2)
    # circulo runico en el suelo
    d = np.sqrt(((XX - W * 0.5) / 1.0) ** 2 + ((YY - H * 0.9) / 0.28) ** 2)
    ring = np.clip(1 - np.abs(d - 520) / 4, 0, 1) + np.clip(1 - np.abs(d - 400) / 3, 0, 1) * 0.8
    img = add_glow(img, blur(ring, 1.5), C("#aaffe0"), 0.9)
    img = add_glow(img, blob(W * 0.5, H * 0.9, 600, 170, 1.6), C("#1fe0a0"), 0.4)
    # esporas
    img = bokeh(img, rng, 70, [C("#aaffe0"), C("#6df3ff"), C("#e8ffa0")], 0.0, 1.0, 3, 16, 0.18)
    img = vignette(img, 0.6)
    return finish(img, "mutation", rng)


def scene_shop(seed=141):
    """TIENDA: calle de mercado al anochecer, farolillos dorados y carteles de neon."""
    rng = np.random.default_rng(seed)
    horizon = int(H * 0.6)
    img = sky([(0, C("#180a2a")), (0.25, C("#4a1a52")), (0.45, C("#b04a4a")), (0.56, C("#ffa050")), (0.61, C("#ffd890")), (1, C("#200c24"))])
    img = stars(img, rng, 200, 0.2, 0.8)
    img = clouds(img, 23, 0.15, 0.5, C("#ffb070"), C("#4a1a52"), 0.45, (180, 560))
    img = sun(img, W * 0.35, horizon - 20, 170, C("#fff0c0"), C("#ffa860"))
    img, _, _ = city_layer(img, rng, horizon, 90, 280, 50, 120, C("#7a3a58"), C("#b0605a"), 0.5)
    img, _, rects = city_layer(img, rng, horizon + 24, 150, 360, 66, 140, C("#2a1034"), C("#44183c"), 0.15,
                            windows={"palette": WARM, "p": 0.36, "size": (7, 9), "grid": (15, 20)}, edge_light=C("#ffc27a"), spires=0.1, slant=0.1)
    # carteles de neon en las fachadas
    neon = np.zeros((H, W, 3), np.float32)
    for (x0, x1, top) in rects:
        if rng.random() < 0.55 and x1 - x0 > 70:
            sy = top + int(rng.integers(40, 160))
            sw = int((x1 - x0) * rng.uniform(0.4, 0.7))
            sx = x0 + 10
            col = [C("#ff5ac8"), C("#6df3ff"), C("#ffd166")][int(rng.integers(0, 3))]
            neon[sy: sy + 12, sx: sx + sw] = col
            neon[sy + 22: sy + 30, sx: sx + int(sw * 0.6)] = col * 0.8
    img = screen(img, neon * 0.9)
    img = screen(img, np.clip(blur(neon, 7.0) * 2.2, 0, 1) * 0.7)
    img = composite(img, vgrad([(0, C("#240e28")), (1, C("#0a0414"))]), (YY > horizon + 24).astype(np.float32))
    img = reflect_floor(img, horizon + 24, 0.5, 600, C("#ff9a6a"))
    # farolillos / guirnaldas
    for y0, sag in [(180, 80), (360, 100)]:
        pts = [(x, y0 + sag * math.sin(math.pi * x / W)) for x in range(-10, W + 20, 6)]
        pil = Image.new("L", (W, H), 0)
        ImageDraw.Draw(pil).line(pts, fill=110, width=2)
        img = composite(img, np.array([0.08, 0.02, 0.1], np.float32), np.asarray(pil, np.float32) / 255.0 * 0.9)
        bulbs = np.zeros((H, W), np.float32)
        for i in range(0, len(pts), 8):
            bulbs += blob(pts[i][0], pts[i][1] + 14, 20, 24, 1.5)
        img = add_glow(img, np.clip(bulbs, 0, 1), C("#ffc870"), 1.0)
    img = bokeh(img, rng, 34, WARM, 0.15, 0.9, 6, 28, 0.12)
    img = vignette(img, 0.5)
    return finish(img, "shop", rng)


def scene_tower(seed=151):
    """TORRE: megatorre atravesando las nubes, haz de luz hacia el cielo."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#05052a")), (0.25, C("#1a1a74")), (0.5, C("#5a2a98")), (0.72, C("#c4407a")), (0.86, C("#ff9a7a")), (1, C("#2a1048"))])
    img = stars(img, rng, 560, 0.5, 1.0)
    cx = W * 0.5
    # haz de luz desde la cima
    top_y = 250
    d = np.abs(XX - cx)
    beam = np.clip(1 - d / (40 + YY * 0.05), 0, 1) ** 2 * np.clip(1 - YY / 1200, 0, 1)
    img = add_glow(img, beam * (YY < top_y + 40), C("#e9d4ff"), 1.0)
    img = add_glow(img, blob(cx, top_y, 260, 260, 2.0), C("#d9b8ff"), 0.9)
    # nubes en capas
    img = clouds(img, 31, 0.36, 0.75, C("#ffb0a0"), C("#42208a"), 0.62, (160, 520))
    # torre central: fuste con anillos y aguja
    m = Image.new("L", (W * 2, H * 2), 0)
    dd = ImageDraw.Draw(m)
    segs = [(0, 70), (240, 70), (300, 96), (700, 130), (1100, 170), (1500, 230), (H, 300)]
    left = [(cx - w / 2, y) for y, w in segs]
    right = [(cx + w / 2, y) for y, w in segs][::-1]
    poly = [(cx - 6, top_y - 190)] + [(cx - 4, top_y - 20)] + left + right + [(cx + 4, top_y - 20)]
    dd.polygon([(x * 2, y * 2 + 0) for x, y in [(cx, top_y - 190)] + [(cx - 10, top_y)] + [(cx - 38, top_y + 10)] + left[1:] + right[:-1] + [(cx + 38, top_y + 10), (cx + 10, top_y)]], fill=255)
    mk = np.asarray(m.resize((W, H), Image.LANCZOS), np.float32) / 255.0
    tcol = vgrad([(0, C("#4a3a8a")), (0.4, C("#241058")), (1, C("#0e0630"))])
    img = composite(img, tcol, mk)
    edge = np.clip(mk - np.roll(mk, 3, axis=1), 0, 1)
    img = add_glow(img, blur(edge, 1.4), C("#ffb0e0"), 1.2)
    # anillos luminosos y ventanas de la torre
    for ry in range(top_y + 60, H, 78):
        wdt = np.interp(ry, [s[0] for s in segs], [s[1] for s in segs])
        band = np.zeros((H, W), np.float32)
        band[ry: ry + 4, int(cx - wdt / 2 + 4): int(cx + wdt / 2 - 4)] = 1
        img = add_glow(img, blur(band, 1.2) * mk, C("#6df3ff") if (ry // 78) % 2 else C("#ff5ac8"), 0.9)
    # ciudad base en brumas
    horizon = int(H * 0.9)
    img, _, _ = city_layer(img, rng, horizon, 100, 360, 50, 120, C("#241058"), C("#14082f"), 0.2,
                           windows={"palette": NEON, "p": 0.18, "size": (6, 9), "grid": (17, 23)}, edge_light=C("#b78cff"))
    img = bokeh(img, rng, 26, NEON, 0.0, 0.8, 4, 20, 0.10)
    img = vignette(img, 0.55)
    return finish(img, "tower", rng)


def scene_evolution(seed=161):
    """EVOLUCION: camara de energia. Columna de luz central y anillos ascendentes."""
    rng = np.random.default_rng(seed)
    cx = W * 0.5
    img = sky([(0, C("#080426")), (0.5, C("#1c0c52")), (1, C("#0a0420"))])
    d = np.abs(XX - cx)
    col = np.clip(1 - d / 190, 0, 1) ** 1.6
    img = add_glow(img, col * np.clip(1 - np.abs(YY / H - 0.45) / 0.65, 0, 1), C("#7ad8ff"), 0.9)
    img = add_glow(img, np.clip(1 - d / 70, 0, 1) ** 2 * np.clip(1 - np.abs(YY / H - 0.45) / 0.65, 0, 1), C("#ffffff"), 0.9)
    img = add_glow(img, blob(cx, H * 0.45, 800, 700, 1.7), C("#7a4aff"), 0.55)
    # anillos elipticos ascendentes
    for i, ry in enumerate(range(260, 1700, 150)):
        dy = (YY - ry) / 48.0
        dx = (XX - cx) / 360.0
        e = np.abs(np.sqrt(dx * dx + dy * dy) - 1)
        ring = np.clip(1 - e / 0.03, 0, 1)
        img = add_glow(img, blur(ring, 1.0), C("#ffd986") if i % 2 else C("#ff7ad0"), 0.65)
    img = add_glow(img, blob(cx, H * 0.88, 520, 110, 1.4), C("#7ad8ff"), 0.65)
    img = stars(img, rng, 300, 1.0, 0.9)
    img = bokeh(img, rng, 70, [C("#ffe2a0"), C("#9ee8ff"), C("#ffb0f0")], 0.0, 1.0, 3, 14, 0.16)
    img = vignette(img, 0.55)
    return finish(img, "evolution", rng)


def scene_settings(seed=171):
    """AJUSTES: limpio. Violeta oscuro, rejilla muy suave y un resplandor superior."""
    rng = np.random.default_rng(seed)
    img = sky([(0, C("#100a34")), (0.5, C("#0b0724")), (1, C("#06041a"))])
    img = add_glow(img, blob(W * 0.5, -60, 900, 700, 1.6), C("#7a4aff"), 0.55)
    img = add_glow(img, blob(W * 0.9, H * 0.95, 600, 420, 1.8), C("#ff4fb8"), 0.22)
    grid = np.zeros((H, W), np.float32)
    grid[::96, :] = 1
    grid[:, ::96] = 1
    fade = np.clip(1 - YY / (H * 0.9), 0, 1) ** 1.4
    img = add_glow(img, blur(grid, 0.7) * fade, C("#8a7aff"), 0.14)
    img = stars(img, rng, 160, 0.5, 0.5)
    img = vignette(img, 0.55)
    return finish(img, "settings", rng)


SCENES = {
    "menu": scene_menu, "collection": scene_collection, "summon": scene_summon, "team": scene_team,
    "stages": scene_stages, "battle": lambda: scene_battle(61, "plain"),
    "battle_forest": lambda: scene_battle(62, "forest"), "battle_ruins": lambda: scene_battle(63, "ruins"),
    "results": scene_results, "missions": scene_missions, "events": scene_events,
    "history": scene_history, "map": scene_map, "inventory": scene_inventory,
    "mutation": scene_mutation, "shop": scene_shop, "tower": scene_tower,
    "evolution": scene_evolution, "settings": scene_settings,
}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SCENES.keys())
    for name in wanted:
        if name not in SCENES:
            print("desconocido:", name)
            continue
        SCENES[name]()
