#!/usr/bin/env python3
"""Nacho's task list, one file per task: docs/tareas/<ID>.md.

Until 2026-10-04 every task was a block of docs/tareas-nacho.md, and ~80 % of the PRs edited that
one file (181 of 233 commits in 5 days), so parallel routines kept colliding on it. Now each task is
its own file and a construction PR only touches its task's file. docs/tareas-nacho.md keeps what is
shared and rarely edited: how to read the list, the "Orden de ataque" table and each section's intro.

Usage (python 3.8+, standard library only):
    python tools/tareas.py lista [--abiertas | --estado E] [--seccion TEXTO] [--todas] [--json]
    python tools/tareas.py libre N-9          # next free ID in a hundred (N-9xx); also S-2, N-24...
    python tools/tareas.py revisar            # CI check: format, sections, nothing left in tareas-nacho.md
    python tools/tareas.py archivar           # finished files -> docs/tareas/hechas/ (weekly maintenance)
    python tools/tareas.py migrar             # one-off: blocks of tareas-nacho.md -> files (re-runnable)

A task file:
    # N-919 · Title — B · `Opus 5.5 · high` · Aviso: no · M8      <- same heading as before, one '#'
    <blank>
    Sección: QA — bugs abiertos                                   <- a '##' heading of tareas-nacho.md
    <blank>                                                          (S- tasks: "Heredadas de Slatex › 3. Arte…")
    body: context, "- [ ] **N-919.1** …" subtasks, "**[x] Hecho (AAAA-MM-DD)** …"

Status comes from the heading and the start of the body, as the panel always read it:
"⚠ Bloqueada" -> bloqueada; "~~", "[x]" or "[x] Hecho" -> hecha; "⏸ decide" -> decide; other "⏸" ->
pausada; else abierta.
"""
import argparse
import io
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "docs" / "tareas-nacho.md"
DIR = ROOT / "docs" / "tareas"
DONE_DIR = DIR / "hechas"
OTHER_LISTS = [ROOT / "docs" / "tareas-nacho-archivo.md", ROOT / "docs" / "tareas-slatex.md"]

ID = r"[NS]-\d+(?:\.\d+)?[a-z]?"
TASK_HEAD = re.compile(rf"^(#{{1,4}}) (~~)?\**({ID})\**(.*)$")
SECTION_LINE = re.compile(r"^Sección: (.+)$")
PATH_SEP = " › "
LIST_HINT = 'Tareas de esta sección: `python tools/tareas.py lista --seccion "{}"` (cada una en `docs/tareas/<ID>.md`).'


def read(path):
    return path.read_bytes().decode("utf-8").replace("\r\n", "\n")


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def plain(md):
    return re.sub(r"[*`~]|\[([^\]]*)\]\([^)]*\)", lambda m: m.group(1) or "", md).strip()


def id_key(task_id):
    """N-224.4 -> ('N', 224, 4): natural order."""
    letter, rest = task_id.split("-", 1)
    nums = [int(n) for n in re.findall(r"\d+", rest)]
    return (letter, *nums)


def status_of(header, body):
    if "⚠ Bloqueada" in header or "⚠ Bloqueada" in body[:300]:
        return "bloqueada"
    if header.lstrip().startswith("~~") or "[x]" in header or "[x] Hecho" in body[:200] or "[x] Decidido" in header:
        return "hecha"
    if "⏸ decide" in header:
        return "decide"
    if "⏸" in header:
        return "pausada"
    return "abierta"


# ---------------------------------------------------------------- sections of the index

def index_sections(text):
    """Section paths in document order: '## A' -> 'A', '### B' under it -> 'A › B' (non-task headings)."""
    paths, top = [], None
    for line in text.split("\n"):
        if TASK_HEAD.match(line):
            continue
        m = re.match(r"^(#{2,3}) (.+?)\s*$", line)
        if not m:
            continue
        name = plain(m.group(2))
        if len(m.group(1)) == 2:
            top = name
            paths.append(name)
        elif top:
            paths.append(top + PATH_SEP + name)
    return paths


# ---------------------------------------------------------------- task files

def parse_task(path):
    lines = read(path).split("\n")
    head = TASK_HEAD.match(lines[0]) if lines else None
    section = ""
    for line in lines[1:6]:
        m = SECTION_LINE.match(line)
        if m:
            section = m.group(1).strip()
            break
    if not head:
        return {"file": path, "error": "la primera línea no es '# <ID> · título — …'"}
    header = lines[0].lstrip("#").strip()
    rest = head.group(4)
    rest = re.sub(r"^\**\s*·\s*", "", rest)
    title = plain(rest.split(" — ")[0])
    meta = rest.split(" — ", 1)[1] if " — " in rest else ""
    body = "\n".join(lines[1:])
    eff = re.search(r"(Opus|Sonnet) 5\.5 · (\w+)", meta)
    return {
        "id": head.group(3), "file": path, "header": header, "title": title.replace("⏸ decide el usuario: ", ""),
        "prio": (re.match(r"\s*([ABC])\b", plain(meta)) or [None, ""])[1],
        "effort": eff.group(2) if eff else "", "section": section,
        "status": status_of(header, body), "pc": "necesita PC" in lines[0],
        "subOpen": len(re.findall(r"^- \[ \]", body, re.M)),
        "subDone": len(re.findall(r"^- \[x\]", body, re.M)),
        "body": body,
    }


def task_files(include_done=False):
    files = sorted(p for p in DIR.glob("*.md") if p.name != "README.md")
    if include_done and DONE_DIR.exists():
        files += sorted(DONE_DIR.glob("*.md"))
    return files


def load(include_done=False):
    tasks = [parse_task(p) for p in task_files(include_done)]
    order = {name: i for i, name in enumerate(index_sections(read(INDEX)))} if INDEX.exists() else {}
    return sorted((t for t in tasks if "id" in t),
                  key=lambda t: (order.get(t["section"], len(order)), id_key(t["id"])))


# ---------------------------------------------------------------- commands

def cmd_lista(args):
    tasks = load(include_done=args.todas)
    if args.abiertas:
        tasks = [t for t in tasks if t["status"] == "abierta"]
    if args.estado:
        tasks = [t for t in tasks if t["status"] == args.estado]
    if args.seccion:
        needle = args.seccion.lower()
        tasks = [t for t in tasks if needle in t["section"].lower()]
    if args.json:
        print(json.dumps([{k: (str(v.relative_to(ROOT)).replace("\\", "/") if k == "file" else v)
                           for k, v in t.items() if k != "body"} for t in tasks], ensure_ascii=False, indent=1))
        return 0
    section = None
    for t in tasks:
        if t["section"] != section:
            section = t["section"]
            print(f"\n## {section or '(sin sección)'}")
        sub = f" [{t['subDone']}/{t['subOpen'] + t['subDone']}]" if t["subOpen"] + t["subDone"] else ""
        pc = " · necesita PC" if t["pc"] else ""
        print(f"{t['id']:<9} {t['status']:<9} {t['prio'] or '-'}  {t['title']}{sub}{pc}")
    print(f"\n{len(tasks)} tareas")
    return 0


def all_ids():
    ids = {t["id"] for t in load(include_done=True)}
    for path in OTHER_LISTS + [INDEX]:
        if path.exists():
            ids |= set(re.findall(ID, read(path)))
    return ids


def cmd_libre(args):
    prefix = args.prefijo.upper()
    m = re.fullmatch(r"([NS])-(\d*)", prefix)
    if not m:
        print("prefijo como N-9 (las N-9xx), S-2 o N-24", file=sys.stderr)
        return 2
    letter, digits = m.groups()
    width = 3
    taken = set()
    for task_id in all_ids():
        mm = re.fullmatch(rf"{letter}-(\d+)(?:\..*)?", task_id)
        if mm and mm.group(1).startswith(digits) and len(mm.group(1)) == width:
            taken.add(int(mm.group(1)))
    low = int(digits.ljust(width, "0")) if digits else 1
    high = int(digits.ljust(width, "9")) if digits else 999
    candidates = [n for n in range(max(taken) + 1 if taken else low, high + 1) if n not in taken]
    if not candidates:
        print(f"no quedan IDs libres en {prefix}", file=sys.stderr)
        return 1
    print(f"{letter}-{candidates[0]:0{width}d}")
    return 0


def cmd_revisar(_args):
    errors = []
    index = read(INDEX)
    for n, line in enumerate(index.split("\n"), 1):
        m = TASK_HEAD.match(line)
        if m and len(m.group(1)) >= 2:
            errors.append(
                f"docs/tareas-nacho.md:{n}: la tarea {m.group(3)} está escrita adentro de tareas-nacho.md. Desde el "
                f"2026-10-04 cada tarea vive en su archivo: mové ese bloque a docs/tareas/{m.group(3)}.md (primera "
                f"línea '# {m.group(3)} · …', después 'Sección: <su sección>'; ver docs/tareas/README.md). Si la "
                f"tarea ya tiene archivo, aplicá ahí lo que cambiaste y borrá el bloque.")
    sections = set(index_sections(index))
    seen = {}
    for path in task_files(include_done=True):
        rel = str(path.relative_to(ROOT)).replace("\\", "/")
        t = parse_task(path)
        if "error" in t:
            errors.append(f"{rel}: {t['error']}")
            continue
        if path.stem != t["id"]:
            errors.append(f"{rel}: el archivo se llama {path.stem} pero la tarea es {t['id']} (renombralo a {t['id']}.md)")
        if t["id"] in seen:
            errors.append(f"{rel}: {t['id']} repetida (también en {seen[t['id']]})")
        seen[t["id"]] = rel
        if not t["section"]:
            errors.append(f"{rel}: falta la línea 'Sección: <sección de tareas-nacho.md>' después del título")
        elif t["section"] not in sections:
            errors.append(f"{rel}: la sección '{t['section']}' no es un título de docs/tareas-nacho.md "
                          f"(usá uno existente o agregá el '## ' allá)")
    for e in errors:
        print(f"::error::{e}" if "GITHUB_ACTIONS" in __import__("os").environ else f"ERROR {e}")
    if not errors:
        print(f"tareas: {len(seen)} archivos en docs/tareas/ bien formados")
    return 1 if errors else 0


def git_mv(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(["git", "mv", str(src), str(dst)], cwd=ROOT, check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        shutil.move(str(src), str(dst))


def cmd_archivar(_args):
    moved = 0
    for t in load():
        if t["status"] != "hecha":
            continue
        body = t["body"]
        if "[ ]" in body or "⏸" in body or "⚠" in body:
            continue
        git_mv(t["file"], DONE_DIR / t["file"].name)
        moved += 1
    print(f"archivadas: {moved} (en docs/tareas/hechas/)")
    return 0


def cmd_migrar(_args):
    """Move every task block of tareas-nacho.md to docs/tareas/<ID>.md. Re-running is safe."""
    raw = read(INDEX)
    lines = raw.split("\n")
    kept, created = [], []
    top = sub = None
    hinted = set()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = TASK_HEAD.match(line)
        if m and len(m.group(1)) >= 2:
            level = len(m.group(1))
            j = i + 1
            while j < len(lines):
                h = re.match(r"^(#{1,6}) ", lines[j])
                if h and len(h.group(1)) <= level:
                    break
                j += 1
            block = lines[i:j]
            tail = []
            while block and (not block[-1].strip() or block[-1].strip() == "---"):
                tail.insert(0, block.pop())
            section = top if level == 3 or not sub else top + PATH_SEP + sub
            task_id = m.group(3)
            head = "# " + line[level + 1:]
            write(DIR / f"{task_id}.md", "\n".join([head, "", f"Sección: {section}", ""] + block[1:]).rstrip("\n") + "\n")
            created.append(task_id)
            if section not in hinted:
                kept += [LIST_HINT.format(section), ""]
                hinted.add(section)
            kept += [t for t in tail if t.strip() == "---"]
            i = j
            continue
        h = re.match(r"^(#{2,3}) (.+?)\s*$", line)
        if h:
            if len(h.group(1)) == 2:
                top, sub = plain(h.group(2)), None
            else:
                sub = plain(h.group(2))
        kept.append(line)
        i += 1
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(kept))
    write(INDEX, text)
    print(f"migradas: {len(created)} tareas a docs/tareas/; tareas-nacho.md: {len(lines)} -> {text.count(chr(10)) + 1} líneas")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("lista")
    p.add_argument("--abiertas", action="store_true", help="solo las tomables (estado abierta)")
    p.add_argument("--estado", choices=["abierta", "hecha", "pausada", "decide", "bloqueada"])
    p.add_argument("--seccion", default="")
    p.add_argument("--todas", action="store_true", help="incluye docs/tareas/hechas/")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("libre")
    p.add_argument("prefijo")
    sub.add_parser("revisar")
    sub.add_parser("archivar")
    sub.add_parser("migrar")
    args = parser.parse_args()
    return {"lista": cmd_lista, "libre": cmd_libre, "revisar": cmd_revisar,
            "archivar": cmd_archivar, "migrar": cmd_migrar}[args.cmd](args)


if __name__ == "__main__":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    sys.exit(main())
