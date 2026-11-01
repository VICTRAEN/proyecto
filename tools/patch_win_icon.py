#!/usr/bin/env python3
"""Pone icon.ico en la plantilla de exportacion de Windows (Godot no puede hacerlo en Linux sin
rcedit/wine). Uso: patch_win_icon.py <plantilla.exe> <icon.ico> <salida.exe>   (requiere: pip install lief)
Luego se apunta custom_template/release del preset Windows a la salida y se exporta."""
import struct, sys, lief
src, icon, out = sys.argv[1:4]
ico = open(icon, 'rb').read()
ent = {}
for i in range(struct.unpack('<H', ico[4:6])[0]):
    w, h, cc, res, pl, bc, size, off = struct.unpack('<BBBBHHII', ico[6 + 16 * i:22 + 16 * i])
    ent[w or 256] = ico[off:off + size]
sizes = {1: 16, 2: 32, 3: 48, 4: 64, 5: 128, 6: 256}
b = lief.PE.parse(src)
root = b.resources
for n in [c for c in root.childs if c.id == 3][0].childs:
    for lang in n.childs:
        lang.content = ent[sizes[n.id]]
for n in [c for c in root.childs if c.id == 14][0].childs:
    for lang in n.childs:
        old = bytes(lang.content)
        new = old[:6]
        for i in range(struct.unpack('<H', old[4:6])[0]):
            w, h, cc, res, pl, bc, size, iid = struct.unpack('<BBBBHHIH', old[6 + 14 * i:20 + 14 * i])
            new += struct.pack('<BBBBHHIH', w, h, 0, 0, 1, 32, len(ent[sizes[iid]]), iid)
        lang.content = new
cfg = lief.PE.Builder.config_t(); cfg.resources = True
bld = lief.PE.Builder(b, cfg); bld.build(); bld.write(out)
