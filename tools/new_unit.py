#!/usr/bin/env python3
"""Crea una UNIDAD nueva: su JSON de datos y sus carpetas de arte.

    python3 tools/new_unit.py gojo 002 "Satoru Gojo (joven)" --rarity SSR --type INT
    python3 tools/new_unit.py goku 003 "Goku SSJ3" --rarity UR --type STR --forms ssr ur lr

Crea:
    data/characters/gojo_002.json          (plantilla valida: edita stats, skills y links)
    art/characters/gojo/gojo_002/ssr/      (y ur/, lr/ si las pides con --forms)
        _pon_tus_imagenes_aqui.txt         (front.png, back.png, icon.png)

El ID (gojo_002) es interno y unico. El NOMBRE VISIBLE es el que pasas entre comillas:
nunca se usa el id para mostrar nada. NO borra ni modifica nada existente: si el id ya
existe aborta.
"""
import argparse, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("family", help="familia de arte, p. ej. gojo")
    ap.add_argument("number", help="numero de unidad, p. ej. 002")
    ap.add_argument("name", help="nombre visible, p. ej. 'Satoru Gojo (joven)'")
    ap.add_argument("--rarity", default="SSR", choices=["R", "SR", "SSR", "UR", "LR"])
    ap.add_argument("--type", default="STR", choices=["STR", "AGI", "INT", "TEQ", "PHY"])
    ap.add_argument("--forms", nargs="*", default=None, help="carpetas de forma (por defecto: la rareza base)")
    ap.add_argument("--gacha", default="true", choices=["true", "false"], help="false = no sale en banners")
    a = ap.parse_args()

    uid = "%s_%s" % (a.family.lower(), a.number)
    data_path = os.path.join(ROOT, "data", "characters", uid + ".json")
    if os.path.exists(data_path):
        sys.exit("ABORTO: ya existe %s. No se sobrescribe nada." % data_path)
    with open(os.path.join(ROOT, "tools", "templates", "character_template.json"), encoding="utf-8") as f:
        data = json.load(f)
    data["id"] = uid
    data["name"] = a.name
    data["art_family"] = a.family.lower()
    data["rarity"] = a.rarity
    data["type"] = a.type
    if a.gacha == "false":
        data["gacha"] = False
    data["art"] = {}
    for sk in data["skills"]:
        sk["id"] = sk["id"].replace("UID", uid)
    data["passive"]["id"] = data["passive"]["id"].replace("UID", uid)
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent="\t")

    forms = a.forms if a.forms else [a.rarity.lower()]
    for form in forms:
        d = os.path.join(ROOT, "art", "characters", a.family.lower(), uid, form.lower())
        os.makedirs(d, exist_ok=True)
        note = os.path.join(d, "_pon_tus_imagenes_aqui.txt")
        if not os.path.exists(note):
            with open(note, "w", encoding="utf-8") as f:
                f.write("Deja aqui front.png, back.png e icon.png de %s (%s).\n" % (a.name, form.upper()))
    print("Creado %s (%s)." % (uid, a.name))
    print("  datos: data/characters/%s.json  <- revisa stats, skills, categories y links" % uid)
    print("  arte : art/characters/%s/%s/<forma>/{front,back,icon}.png" % (a.family.lower(), uid))


if __name__ == "__main__":
    main()
