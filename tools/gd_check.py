#!/usr/bin/env python3
"""
Revision ESTATICA de los scripts y escenas de Godot. No abre Godot ni ejecuta el
juego, y NO MODIFICA nada del proyecto.

    python3 tools/gd_check.py

Busca la clase de fallos que aparece cuando se escribe GDScript sin poder ejecutarlo:

  1. Indentacion con espacios o parentesis/corchetes/llaves sin cerrar.
  2. `preload("res://...")` y recursos de .tscn que apuntan a un archivo que no existe.
  3. `GameState.algo`, `DB.algo`, `GameSettings.algo`, `GameAudio.algo` donde `algo` no
     esta declarado en ese autoload (func, var, const, signal, enum).
  4. `X.algo` donde X es un `const X := preload("...gd")` y `algo` no existe en ese script.
  5. `@onready var v: T = $Ruta/De/Nodos` cuyo nodo no existe en la escena a la que
     esta atado el script.
  6. Nombres de sonido (GameAudio.play / play_music / set_meta("sfx", ...)) que no
     estan en el catalogo de audio/audio.gd.

Es un LINTER casero: no entiende todo GDScript (avisa de lo que ve, no demuestra que
el juego funcione). Sale con codigo 1 si hay errores.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUTOLOADS = {}  # nombre -> ruta del script, leido de project.godot
# Metodos y propiedades incorporados de Object/Node: valen en cualquier autoload.
BUILTIN_MEMBERS = {
    "get", "set", "call", "callv", "connect", "disconnect", "is_connected", "has_method", "has_signal",
    "get_node", "get_node_or_null", "add_child", "remove_child", "queue_free", "get_children", "get_tree",
    "name", "set_meta", "get_meta", "has_meta", "emit_signal", "get_script", "get_parent", "is_inside_tree",
    "get_child", "get_child_count", "find_children", "process_mode", "call_deferred", "set_deferred",
}
problems = []
notes = []


def bad(path, line, msg):
    problems.append(f"{os.path.relpath(path, ROOT)}:{line}: {msg}")


def res(path):
    return os.path.join(ROOT, path[len("res://"):])


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_code(src):
    """Quita comentarios y contenido de strings (deja las comillas) manteniendo los saltos de linea."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c in "\"'":
            q = c
            out.append(q)
            i += 1
            while i < n and src[i] != q:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            out.append(q)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def members_of(script_path):
    """Nombres declarados al nivel del script (func, var, const, signal, enum y sus valores)."""
    src = strip_code(read(script_path))
    names = set()
    for m in re.finditer(r"^\s*(?:static\s+)?(?:func|var|const|signal|class)\s+([A-Za-z_]\w*)", src, re.M):
        names.add(m.group(1))
    for m in re.finditer(r"^\s*@export\S*\s+var\s+([A-Za-z_]\w*)", src, re.M):
        names.add(m.group(1))
    for m in re.finditer(r"^\s*enum\s*\w*\s*\{([^}]*)\}", src, re.M | re.S):
        for item in m.group(1).split(","):
            item = item.strip().split("=")[0].strip()
            if item:
                names.add(item)
    for m in re.finditer(r"^\s*enum\s+(\w+)", src, re.M):
        names.add(m.group(1))
    return names


def load_autoloads():
    text = read(os.path.join(ROOT, "project.godot"))
    section = re.search(r"\[autoload\](.*?)(?:\n\[|\Z)", text, re.S)
    if not section:
        return
    for m in re.finditer(r'^(\w+)="\*?(res://[^"]+)"', section.group(1), re.M):
        AUTOLOADS[m.group(1)] = m.group(2)


def check_basic(path, src):
    depth_stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    code = strip_code(src)
    for n, line in enumerate(code.split("\n"), 1):
        if re.match(r"^ +\S", line):
            bad(path, n, "indentado con espacios (el proyecto usa tabuladores)")
        for ch in line:
            if ch in "([{":
                depth_stack.append((ch, n))
            elif ch in ")]}":
                if not depth_stack or depth_stack[-1][0] != pairs[ch]:
                    bad(path, n, f"'{ch}' sin abrir")
                else:
                    depth_stack.pop()
    for ch, n in depth_stack:
        bad(path, n, f"'{ch}' sin cerrar")


def audio_events():
    src = read(os.path.join(ROOT, "audio", "audio.gd"))
    block = re.search(r"const CATALOG := \{(.*?)\n\}", src, re.S)
    names = set(re.findall(r'"(\w+)"', block.group(1))) if block else set()
    return {n for n in names if n not in {"music", "ui", "combat", "progression"}}


def parse_tscn(path):
    """{ruta_del_nodo: script_res_path|None}, ext_resources {id: (tipo, ruta)}."""
    src = read(path)
    ext = {}
    for m in re.finditer(r'\[ext_resource type="(\w+)"[^\]]*?path="([^"]+)"[^\]]*?id="([^"]+)"', src):
        ext[m.group(3)] = (m.group(1), m.group(2))
    nodes = {}
    instances = set()
    current = None
    for line in src.split("\n"):
        m = re.match(r'\[node name="([^"]+)"(?: type="[^"]*")?(?: parent="([^"]*)")?', line)
        if m:
            name, parent = m.group(1), m.group(2)
            if parent is None:
                current = ""
            elif parent == ".":
                current = name
            else:
                current = parent + "/" + name
            nodes[current] = None
            if "instance=ExtResource" in line:
                instances.add(current)
            continue
        if line.startswith("[") and not line.startswith("[node"):
            current = None
            continue
        m = re.match(r'script = ExtResource\("([^"]+)"\)', line)
        if m and current is not None and m.group(1) in ext:
            nodes[current] = ext[m.group(1)][1]
    nodes["__instances__"] = instances
    return nodes, ext


def main():
    load_autoloads()
    events = audio_events()
    scripts = [p for p in glob.glob(os.path.join(ROOT, "**", "*.gd"), recursive=True) if "/.godot/" not in p]
    autoload_members = {name: members_of(res(path)) for name, path in AUTOLOADS.items() if os.path.isfile(res(path))}

    # Escena -> script atado, para revisar los $Nodos.
    script_nodes = {}  # ruta_script -> [(tscn, ruta_nodo_dueño, nodos_de_la_escena)]
    for tscn in glob.glob(os.path.join(ROOT, "**", "*.tscn"), recursive=True):
        if "/.godot/" in tscn:
            continue
        nodes, ext = parse_tscn(tscn)
        for rid, (kind, path) in ext.items():
            if not path.startswith("res://"):
                continue
            if not os.path.exists(res(path)):
                bad(tscn, 0, f"recurso inexistente: {path}")
        instances = nodes.pop("__instances__", set())
        for node_path, script in nodes.items():
            if script:
                script_nodes.setdefault(script, []).append((tscn, node_path, set(nodes.keys()), instances))

    for path in sorted(scripts):
        raw = read(path)
        rel = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
        check_basic(path, raw)
        code = strip_code(raw)
        # 2) preload
        for m in re.finditer(r'preload\("(res://[^"]+)"\)', raw):
            if not os.path.exists(res(m.group(1))):
                bad(path, raw[: m.start()].count("\n") + 1, f"preload de un archivo que no existe: {m.group(1)}")
        # 3) miembros de autoloads
        for name, members in autoload_members.items():
            if AUTOLOADS[name] == rel:
                continue
            for m in re.finditer(r"(?<![\w.])%s\.([A-Za-z_]\w*)" % name, code):
                if m.group(1) not in members and m.group(1) not in BUILTIN_MEMBERS:
                    bad(path, code[: m.start()].count("\n") + 1, f"{name}.{m.group(1)} no esta declarado en {AUTOLOADS[name]}")
        # 4) constantes preload
        for m in re.finditer(r'^\s*const\s+(\w+)\s*(?::=|=)\s*preload\("(res://[^"]+\.gd)"\)', raw, re.M):
            cname, target = m.group(1), m.group(2)
            if not os.path.exists(res(target)):
                continue
            tmembers = members_of(res(target))
            for u in re.finditer(r"(?<![\w.])%s\.([A-Za-z_]\w*)" % cname, code):
                if u.group(1) not in tmembers and u.group(1) not in {"new", "instantiate", "get_script_constant_map"}:
                    bad(path, code[: u.start()].count("\n") + 1, f"{cname}.{u.group(1)} no esta declarado en {target}")
        # 6) sonidos
        for m in re.finditer(r'GameAudio\.(?:play|play_music)\(\s*"(\w+)"', raw):
            if m.group(1) not in events:
                bad(path, raw[: m.start()].count("\n") + 1, f"sonido '{m.group(1)}' no esta en el catalogo de audio")
        for m in re.finditer(r'set_meta\("sfx",\s*"(\w+)"\)', raw):
            if m.group(1) not in events:
                bad(path, raw[: m.start()].count("\n") + 1, f"sonido '{m.group(1)}' no esta en el catalogo de audio")
        # 5) nodos $Ruta
        owners = script_nodes.get(rel)
        if owners:
            for m in re.finditer(r"^\s*@onready\s+var\s+\w+\s*(?::\s*\w+)?\s*(?::=|=)\s*\$([\w/]+)", raw, re.M):
                rel_path = m.group(1)
                ok = False
                for tscn, owner, nodeset, instances in owners:
                    full = (owner + "/" + rel_path) if owner else rel_path
                    if full in nodeset:
                        ok = True
                    # Un nodo dentro de una escena instanciada no esta en este .tscn.
                    if any(full.startswith(inst + "/") for inst in instances):
                        ok = True
                if not ok:
                    bad(path, raw[: m.start()].count("\n") + 1, f"el nodo ${rel_path} no existe en la escena de este script")

    print(f"Scripts revisados: {len(scripts)} | autoloads: {', '.join(sorted(AUTOLOADS))}")
    print(f"PROBLEMAS: {len(problems)}")
    for p in problems:
        print("  ", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
