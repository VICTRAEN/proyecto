#!/usr/bin/env python3
"""
Comprobaciones ESTATICAS de Anime Battle. No abre Godot, no ejecuta el juego y
NO MODIFICA NI BORRA NADA del proyecto (solo escribe el informe que se le pide).

    python3 tools/project_check.py check      # valida datos, ids, referencias y arte
    python3 tools/project_check.py report     # escribe art/characters/ASSET_REPORT.md
    python3 tools/project_check.py snapshot   # (re)escribe tools/image_inventory.txt

`check` sale con codigo 1 si hay ERRORES (avisos no cuentan). Incluye la
comprobacion "no se ha perdido ninguna imagen": compara las imagenes actuales con
tools/image_inventory.txt (ruta + sha256). Una imagen que falta o que ha cambiado
es un ERROR.

IMPORTANTE: la resolucion de arte de aqui es una REPRODUCCION de
ui/character_assets.gd hecha en Python para poder revisar el arte sin Godot. Es un
espejo del orden de busqueda, NO una prueba de que el juego funcione. Si se cambia
uno, hay que cambiar el otro.
"""
import glob
import hashlib
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG_EXTS = (".png", ".webp", ".jpg", ".jpeg")
SLOTS = ["front", "back", "icon"]
ID_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
# Links y categorias ya existentes usan guiones (energia-oculta): se aceptan.
ID_RE_LOOSE = re.compile(r"^[a-z0-9]+([_-][a-z0-9]+)*$")
STRICT_ID_DIRS = ("characters", "enemies")
# Convencion recomendada para ids NUEVOS: <nombre>_<serie>_<nnn>  (gojo_jjk_002)
NEW_ID_RE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*_[a-z]{2,4}_\d{3}$")
INVENTORY = os.path.join(ROOT, "tools", "image_inventory.txt")
REPORT = os.path.join(ROOT, "art", "characters", "ASSET_REPORT.md")

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def res(path):
    """res://a/b.png -> ruta real en disco."""
    return os.path.join(ROOT, path[len("res://"):]) if path.startswith("res://") else path


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as exc:  # noqa: BLE001
        err(f"JSON invalido: {os.path.relpath(path, ROOT)} ({exc})")
        return None


def read_rarity_order():
    """Lee VisualIdentity.RARITY_ORDER para usar la MISMA lista que el juego."""
    text = open(os.path.join(ROOT, "ui", "visual_identity.gd"), encoding="utf-8").read()
    m = re.search(r"const RARITY_ORDER\s*:?=\s*\[(.*?)\]", text)
    if not m:
        err("No se encuentra RARITY_ORDER en ui/visual_identity.gd")
        return ["r", "sr", "ssr", "ur", "lr"]
    return [x.strip().strip('"').lower() for x in m.group(1).split(",") if x.strip()]


RARITY_ORDER = read_rarity_order()

# ---------------------------------------------------------------------------
# Espejo de ui/character_assets.gd
# ---------------------------------------------------------------------------
ART_ROOT = "res://art/characters/"
LEGACY_DIR = "res://art/portraits/"


def form_chain(form):
    form = (form or "").lower()
    if not form:
        return []
    if form not in RARITY_ORDER:
        return [form]
    return list(reversed(RARITY_ORDER[: RARITY_ORDER.index(form) + 1]))


def stem_and_ext(path):
    low = path.lower()
    for ext in IMG_EXTS:
        if low.endswith(ext):
            return path[: -len(ext)], ext
    return path, ""


def expand(stem, preferred=""):
    out = []
    if not stem:
        return out
    if preferred:
        out.append(stem + preferred)
    for ext in IMG_EXTS:
        if stem + ext not in out:
            out.append(stem + ext)
    return out


def candidate_entries(cid, form, slot, explicit="", also=()):
    entries = []

    def push(path, layer):
        if all(e[0] != path for e in entries):
            entries.append((path, layer))

    ids = [cid] + [a for a in also if a and a != cid]
    if explicit:
        stem, ext = stem_and_ext(explicit)
        if not any(stem == f"{ART_ROOT}{i}/{slot}" for i in ids):
            if not ext:
                push(explicit, "custom")
            else:
                for p in expand(stem, ext):
                    push(p, "custom")
    for i in ids:
        for f in form_chain(form):
            for p in expand(f"{ART_ROOT}{i}/{f}/{slot}"):
                push(p, f"form:{f}")
    for i in ids:
        for p in expand(f"{ART_ROOT}{i}/{slot}"):
            push(p, "base")
    for i in ids:
        for p in expand(f"{LEGACY_DIR}{i}"):
            push(p, "legacy")
    return entries


def resolve(cid, form, slot, explicit=""):
    for path, layer in candidate_entries(cid, form, slot, explicit):
        if os.path.isfile(res(path)):
            return path, layer
    return "", "none"


# ---------------------------------------------------------------------------
# Carga de datos
# ---------------------------------------------------------------------------
def entity_dir(name):
    """{id: (datos, archivo)} de data/<name>/*.json, con las comprobaciones de id."""
    out = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "data", name, "*.json"))):
        d = load_json(f)
        if not isinstance(d, dict):
            continue
        rel = os.path.relpath(f, ROOT)
        eid = d.get("id")
        if not eid:
            err(f"{rel}: no tiene campo 'id'")
            continue
        if eid != os.path.basename(f)[:-5]:
            err(f"{rel}: el id '{eid}' no coincide con el nombre del archivo")
        if eid in out:
            err(f"{rel}: id duplicado '{eid}'")
        rule = ID_RE if name in STRICT_ID_DIRS else ID_RE_LOOSE
        if not rule.match(eid):
            err(f"{rel}: el id '{eid}' no es valido (solo a-z, 0-9 y _" + ("" if name in STRICT_ID_DIRS else " o -") + ")")
        out[eid] = (d, rel)
    return out


def image_files():
    found = []
    for base, dirs, files in os.walk(ROOT):
        if ".godot" in base.split(os.sep):
            continue
        for fn in files:
            if fn.lower().endswith(IMG_EXTS + (".svg",)):
                found.append(os.path.relpath(os.path.join(base, fn), ROOT).replace(os.sep, "/"))
    return sorted(found)


def sha256(path):
    h = hashlib.sha256()
    with open(os.path.join(ROOT, path), "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Comprobaciones
# ---------------------------------------------------------------------------
def check_all():
    chars = entity_dir("characters")
    enemies = entity_dir("enemies")
    cats = entity_dir("categories")
    links = entity_dir("links")
    items = entity_dir("items")
    stages = entity_dir("stages")
    events = entity_dir("events")
    towers = entity_dir("towers")
    worlds = entity_dir("worlds")
    dialogues = entity_dir("dialogues")
    banners = entity_dir("banners")
    for other in ("missions", "shop"):
        entity_dir(other)

    # JSON sueltos que no son entidades por archivo
    for extra in ("mutations/config.json", "evolution/rules.json", "evolutions/special.json",
                  "leaders/leaders.json", "ids/aliases.json"):
        p = os.path.join(ROOT, "data", extra)
        if os.path.isfile(p):
            load_json(p)
        else:
            warn(f"data/{extra} no existe")

    # --- ids ------------------------------------------------------------
    clash = set(chars) & set(enemies)
    if clash:
        err(f"ids repetidos entre personajes y enemigos: {sorted(clash)}")
    # Enemigos basados en un personaje del roster ("based_on").
    for eid, (e, rel) in enemies.items():
        base = e.get("based_on")
        if base is not None and base not in chars:
            err(f"{rel}: based_on '{base}' no es un personaje")
    non_new = [i for i in chars if not NEW_ID_RE.match(i)]
    print(f"IDs de personaje: {len(chars)} (todos validos). "
          f"{len(non_new)} usan el formato antiguo (nombre corto) y se CONSERVAN; "
          f"los nuevos deberian ser <nombre>_<serie>_<nnn>.")

    aliases = {}
    apath = os.path.join(ROOT, "data", "ids", "aliases.json")
    if os.path.isfile(apath):
        aliases = (load_json(apath) or {}).get("aliases", {})
        for old, new in aliases.items():
            if old in chars:
                err(f"alias '{old}' tapa a un personaje real")
            if new not in chars:
                err(f"alias '{old}' apunta a '{new}', que no existe")
    known_ids = set(chars) | set(aliases)

    # --- referencias ------------------------------------------------------
    def need(kind_set, value, where, kind):
        if value and value not in kind_set:
            err(f"{where}: {kind} '{value}' no existe")

    for cid, (d, rel) in chars.items():
        for c in d.get("categories", []):
            need(cats, c, rel, "categoria")
        for lk in d.get("links", []):
            need(links, lk if isinstance(lk, str) else lk.get("id"), rel, "link")
        ev = d.get("evolution", {}) if isinstance(d.get("evolution"), dict) else {}
        for key in ("evolved_from", "evolves_to"):
            for holder in (d, ev):
                v = holder.get(key)
                if isinstance(v, str):
                    need(chars, v, rel, key)
    for bid, (b, rel) in banners.items():
        for x in b.get("featured", []):
            need(known_ids, x, rel, "personaje destacado")
    for evid, (e, rel) in events.items():
        need(chars, e.get("character_reward", ""), rel, "character_reward")
        for st in e.get("stages", []):
            w = f"{rel}::{st.get('id')}"
            for en in st.get("enemies", []):
                if en not in enemies and en not in chars:
                    err(f"{w}: enemigo '{en}' no existe")
            need(chars, st.get("grant_character", ""), w, "grant_character")
            need(chars, st.get("requires_party_character", ""), w, "requires_party_character")
            if st.get("dialogue"):
                need(dialogues, st["dialogue"], w, "dialogo")
            for dr in st.get("drops", []):
                need(items, dr.get("item"), w, "objeto")
    for sid, (s, rel) in stages.items():
        for en in s.get("enemies", []):
            if en not in enemies and en not in chars:
                err(f"{rel}: enemigo '{en}' no existe")
    for tid, (t, rel) in towers.items():
        for fl in t.get("floors", []):
            for en in fl.get("enemies", []):
                if en not in enemies and en not in chars:
                    err(f"{rel} piso {fl.get('floor')}: enemigo '{en}' no existe")
            if fl.get("first_clear_item"):
                need(items, fl["first_clear_item"], f"{rel} piso {fl.get('floor')}", "objeto")
    for wid, (w, rel) in worlds.items():
        for lv in w.get("levels", []):
            for dname, dd in (lv.get("difficulties") or {}).items():
                for en in dd.get("enemies", []):
                    if en not in enemies and en not in chars:
                        err(f"{rel} {lv.get('id')} {dname}: enemigo '{en}' no existe")
    sp = os.path.join(ROOT, "data", "evolutions", "special.json")
    if os.path.isfile(sp):
        for r in (load_json(sp) or {}).get("routes", []):
            w = f"evolutions/special.json::{r.get('id')}"
            need(chars, r.get("from"), w, "from")
            need(chars, r.get("to"), w, "to")
            if r.get("boss") and r["boss"] not in enemies and r["boss"] not in chars:
                err(f"{w}: boss '{r['boss']}' no existe")
            if r.get("dialogue"):
                need(dialogues, r["dialogue"], w, "dialogo")
            for ic in r.get("item_cost", []):
                need(items, ic.get("item"), w, "objeto")
            if r.get("requires_event"):
                need(events, r["requires_event"], w, "evento")
    for f in glob.glob(os.path.join(ROOT, "data", "shop", "*.json")):
        d = load_json(f) or {}
        cid = d.get("character_id") or (d.get("grant") or {}).get("character")
        if cid:
            need(chars, cid, os.path.relpath(f, ROOT), "character_id")
    lp = os.path.join(ROOT, "data", "leaders", "leaders.json")
    if os.path.isfile(lp):
        lj = load_json(lp) or {}
        leader_ids = {x.get("id") for x in lj.get("leaders", [])}
        if lj.get("default_leader") not in leader_ids:
            err(f"leaders.json: default_leader '{lj.get('default_leader')}' no esta entre los leaders")
        for cid, lead in (lj.get("by_character") or {}).items():
            if lead and lead not in leader_ids:
                err(f"leaders.json: by_character '{cid}' apunta al leader '{lead}', que no existe")
        for cid, lead in ((load_json(lp) or {}).get("by_character") or {}).items():
            if cid not in chars:
                if lead:
                    err(f"leaders.json: by_character '{cid}' no existe y tiene lider asignado ('{lead}')")
                else:
                    warn(f"leaders.json: by_character '{cid}' no es un personaje (entrada vacia, sin efecto)")
    for did, (d, rel) in dialogues.items():
        for ln in d.get("lines", []):
            p = ln.get("portrait")
            if p and p not in chars and p not in enemies:
                err(f"{rel}: portrait '{p}' no existe")

    # --- arte declarado en los JSON --------------------------------------
    for cid, (d, rel) in chars.items():
        for holder, tag in ((d.get("art") or {}, "art"), ((d.get("evolution") or {}).get("art") or {}, "evolution.art")):
            for slot, path in holder.items():
                if not path:
                    continue
                if not path.startswith("res://"):
                    err(f"{rel}: {tag}.{slot} no empieza por res://")
                stem, _ = stem_and_ext(path)
                if stem.startswith(ART_ROOT + cid + "/"):
                    continue
                warn(f"{rel}: {tag}.{slot} apunta a una ruta propia ({path}); manda sobre las formas")
    return chars, enemies, items


def check_audio():
    """Los archivos de audio tienen que llamarse como el catalogo de audio/audio.gd."""
    src = open(os.path.join(ROOT, "audio", "audio.gd"), encoding="utf-8").read()
    block = re.search(r"const CATALOG := \{(.*?)\n\}", src, re.S)
    if not block:
        err("No se encuentra CATALOG en audio/audio.gd")
        return
    catalog = {}
    for m in re.finditer(r'"(\w+)":\s*\[(.*?)\]', block.group(1), re.S):
        catalog[m.group(1)] = re.findall(r'"(\w+)"', m.group(2))
    total = sum(len(v) for v in catalog.values())
    present = 0
    for cat, names in catalog.items():
        folder = os.path.join(ROOT, "audio", cat)
        if not os.path.isdir(folder):
            err(f"falta la carpeta audio/{cat}/")
            continue
        for fn in os.listdir(folder):
            stem, ext = os.path.splitext(fn)
            if ext.lower() in (".ogg", ".wav", ".mp3"):
                if stem not in names:
                    warn(f"audio/{cat}/{fn}: el nombre '{stem}' no esta en el catalogo (no sonara)")
                else:
                    present += 1
    print(f"Audio: {present} de {total} sonidos del catalogo tienen archivo (sin archivo = silencio, sin error)")


def check_images():
    """Ninguna imagen puede faltar ni haber cambiado respecto al inventario."""
    if not os.path.isfile(INVENTORY):
        warn("no hay tools/image_inventory.txt: ejecuta 'snapshot' para crearlo")
        return
    before = {}
    for line in open(INVENTORY, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            digest, path = line.split("  ", 1)
            before[path] = digest
    now = set(image_files())
    missing = sorted(set(before) - now)
    changed = sorted(p for p in before if p in now and sha256(p) != before[p])
    added = sorted(now - set(before))
    print(f"Imagenes: ANTES {len(before)} | AHORA {len(now)} | nuevas {len(added)} | perdidas {len(missing)} | modificadas {len(changed)}")
    for p in missing:
        err(f"IMAGEN PERDIDA: {p}")
    for p in changed:
        err(f"IMAGEN MODIFICADA: {p}")
    for p in added:
        warn(f"imagen nueva desde el inventario: {p}")


def art_matrix(chars):
    """Por personaje y ranura: que archivo usaria el juego (espejo del resolvedor)."""
    rows = []
    for cid, (d, rel) in sorted(chars.items()):
        base_form = (d.get("rarity") or "").lower()
        forms = [base_form]
        if base_form == "ssr":
            forms.append("ur")  # data/evolution/rules.json: SSR -> UR
        art = d.get("art") or {}
        for form in forms:
            row = {"id": cid, "name": d.get("name", ""), "form": form, "slots": {}}
            for slot in SLOTS:
                row["slots"][slot] = resolve(cid, form, slot, art.get(slot, ""))
            rows.append(row)
    return rows


def write_report(chars, enemies, items):
    rows = art_matrix(chars)
    lines = ["# Informe de assets de personajes", "",
             "Generado por `tools/project_check.py report`. Es un ESPEJO en Python del orden de busqueda de",
             "`ui/character_assets.gd` (no una prueba de ejecucion en Godot) y **no modifica ni borra nada**.", "",
             "Orden de busqueda: ruta propia del JSON (solo si no es la base) -> `<id>/<forma>/` de la forma actual y",
             "las inferiores (LR -> UR -> SSR -> SR -> R) -> `<id>/<ranura>.png` (arte base) -> `art/portraits/<id>.png`.", ""]
    with_art = defaultdict(list)
    for r in rows:
        if r["form"] == (chars[r["id"]][0].get("rarity") or "").lower():
            found = [s for s in SLOTS if r["slots"][s][0]]
            with_art[len(found)].append(r["id"])
    total = len(chars)
    lines += ["## Resumen", "",
              f"- Personajes: **{total}**",
              f"- Con las 3 imagenes (front/back/icon): **{len(with_art[3])}**",
              f"- Con 1 o 2 imagenes: **{len(with_art[1]) + len(with_art[2])}**",
              f"- Sin ninguna imagen (se dibuja silueta): **{len(with_art[0])}**", ""]
    lines += ["## Assets encontrados", "", "| id | nombre | forma | front | back | icon |", "|---|---|---|---|---|---|"]
    for r in rows:
        if not any(r["slots"][s][0] for s in SLOTS):
            continue
        cells = []
        for s in SLOTS:
            path, layer = r["slots"][s]
            cells.append(f"`{path[len('res://'):]}` ({layer})" if path else "—")
        lines.append(f"| {r['id']} | {r['name']} | {r['form'].upper()} | " + " | ".join(cells) + " |")
    lines += ["", "## Assets SIN encontrar (el juego dibuja silueta, no da error)", ""]
    empty = sorted(r["id"] for r in rows if not any(r["slots"][s][0] for s in SLOTS) and r["form"] == (chars[r["id"]][0].get("rarity") or "").lower())
    partial = [(r["id"], [s for s in SLOTS if not r["slots"][s][0]]) for r in rows
               if any(r["slots"][s][0] for s in SLOTS) and not all(r["slots"][s][0] for s in SLOTS)]
    lines.append(f"**Sin ninguna imagen ({len(empty)}):** " + ", ".join(empty) if empty else "Ninguno.")
    if partial:
        lines += ["", "**Con ranuras que faltan:**", ""]
        for cid, miss in partial:
            lines.append(f"- {cid}: falta {', '.join(miss)}")
    lines += ["", "## Formas evolucionadas (SSR -> UR)", "",
              "Para un SSR se comprueba tambien que veria al evolucionar a UR:", ""]
    for r in rows:
        if r["form"] == "ur" and (chars[r["id"]][0].get("rarity") or "").lower() == "ssr":
            layers = {s: r["slots"][s][1] for s in SLOTS if r["slots"][s][0]}
            if any(v.startswith("form:") for v in layers.values()):
                lines.append(f"- {r['id']}: ya tiene arte propio de UR ({layers})")
    lines.append("- El resto usa el arte base hasta que existan `<id>/ur/front.png`, `back.png`, `icon.png`.")
    lines += ["", "## Enemigos", "",
              "Los enemigos (`data/enemies/`) usan la misma convencion `art/characters/<id>/`. Ninguno tiene carpeta hoy: " +
              ", ".join(sorted(enemies)) + ". Se dibuja silueta.", "", "## Objetos (`art/items/`)", ""]
    for iid, (d, rel) in sorted(items.items()):
        icon = d.get("icon", "")
        ok = bool(icon) and os.path.isfile(res(icon))
        lines.append(f"- {iid}: `{icon}` -> {'encontrado' if ok else 'NO existe todavia'}")
    lines += ["", "## Carpetas de arte sin personaje", ""]
    orphan = sorted(d for d in os.listdir(os.path.join(ROOT, "art", "characters"))
                    if os.path.isdir(os.path.join(ROOT, "art", "characters", d)) and d not in chars and d not in enemies)
    lines.append(", ".join(orphan) if orphan else "Ninguna.")
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("Informe escrito en", os.path.relpath(REPORT, ROOT))


def snapshot():
    files = image_files()
    with open(INVENTORY, "w", encoding="utf-8") as f:
        f.write("# sha256  ruta   (imagenes del proyecto; check_images falla si falta o cambia alguna)\n")
        for p in files:
            f.write(f"{sha256(p)}  {p}\n")
    print(f"Inventario escrito: {len(files)} imagenes")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    if mode == "snapshot":
        snapshot()
        return 0
    chars, enemies, items = check_all()
    check_images()
    check_audio()
    if mode == "report":
        write_report(chars, enemies, items)
    print(f"\nERRORES: {len(errors)} | AVISOS: {len(warnings)}")
    for e in errors:
        print("  ERROR:", e)
    for w in warnings[:40]:
        print("  aviso:", w)
    if len(warnings) > 40:
        print(f"  ... y {len(warnings) - 40} avisos mas")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
