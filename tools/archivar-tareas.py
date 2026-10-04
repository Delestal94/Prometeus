"""Move finished work out of docs/tareas-nacho.md into docs/tareas-nacho-archivo.md.

Usage: python tools/archivar-tareas.py [repo root]   (default: the current directory)

Run by the weekly maintenance routine (.claude/rutinas/mantenimiento.md). Keeps every "[ ]" and "⏸".

Moves, keeping the order and the "## section" each came from:
- every "### " task block with no "[ ]", no "⏸", no "⚠" and at least one "[x]" or "Hecho";
- whole "## " sections that are finished history (names in WHOLE_SECTIONS), leaving the heading and
  a one-line pointer.
Sections in KEEP are never touched. Re-running appends to the archive.
"""
import datetime
import io
import re
import sys
from pathlib import Path

KEEP = ("## Cómo leer esta lista", "## Orden de ataque", "## Para cuando haya playtesting")
WHOLE_SECTIONS = (
    "## Hecho fuera de lista",
    "## Qué pasó con la lista anterior",
    "## Bugs de multijugador del playtest (143-149)",
    "## Segunda tanda de multijugador (151-166)",
    "## Playtest del 2026-09-25 (172-177)",
)
POINTER = "Todo hecho: está en [`tareas-nacho-archivo.md`](tareas-nacho-archivo.md)."
ARCHIVE_HEADER = """# Tareas de Nacho — archivo de lo hecho

Lo terminado de [`tareas-nacho.md`](tareas-nacho.md), movido tal cual para que la lista viva sea corta
(cada rutina la lee). Mismo orden y mismas secciones que tenía allá. **Una tarea que está acá está hecha**:
para chequear una dependencia o si algo ya se hizo, buscá el ID con `grep`, no leas el archivo entero.
No se agregan tareas nuevas acá.
"""


def is_done_block(lines):
    text = "\n".join(lines)
    if "[ ]" in text or "⏸" in text or "⚠" in text:
        return False
    return "[x]" in text or "Hecho" in lines[0]


def split_sections(lines):
    """[(heading or None, [lines])] split at '## ' headings."""
    out = [(None, [])]
    for line in lines:
        if line.startswith("## "):
            out.append((line, [line]))
        else:
            out[-1][1].append(line)
    return out


def split_blocks(body):
    """Section body (heading excluded) -> [lead lines, block, block, ...] split at '### '."""
    parts = [[]]
    for line in body:
        if line.startswith("### "):
            parts.append([line])
        else:
            parts[-1].append(line)
    return parts


def trim(lines):
    while lines and not lines[-1].strip():
        lines = lines[:-1]
    return lines


def main(root):
    live_path = Path(root) / "docs" / "tareas-nacho.md"
    archive_path = Path(root) / "docs" / "tareas-nacho-archivo.md"
    raw = live_path.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.replace("\r\n", "\n").split("\n")

    kept, archived = [], []
    moved_blocks = moved_sections = 0
    for heading, sec in split_sections(lines):
        if heading is None or heading.startswith(KEEP):
            kept += sec
            continue
        if heading.startswith(WHOLE_SECTIONS) and POINTER not in sec:
            kept += [heading, "", POINTER, ""]
            archived += trim(sec) + [""]
            moved_sections += 1
            continue
        lead, *blocks = split_blocks(sec[1:])
        done = [b for b in blocks if is_done_block(b)]
        if not done:
            kept += sec
            continue
        archived += [heading, ""]
        kept += [heading] + lead
        for block in blocks:
            if block in done:
                archived += trim(block) + [""]
                moved_blocks += 1
            else:
                kept += block
        if not any(not is_done_block(b) for b in blocks):
            kept += [POINTER, ""]

    if archive_path.exists():
        old = archive_path.read_bytes().decode("utf-8").replace("\r\n", "\n").rstrip("\n").split("\n")
        if not archived:
            print("nothing to archive")
            return
        archive = old + ["", f"<!-- archivado {datetime.date.today().isoformat()} -->", ""] + archived
    else:
        archive = ARCHIVE_HEADER.split("\n") + archived
    live_text = re.sub(r"\n{3,}", "\n\n", "\n".join(kept))
    arch_text = re.sub(r"\n{3,}", "\n\n", "\n".join(archive)).rstrip("\n") + "\n"
    live_path.write_bytes(live_text.replace("\n", newline).encode("utf-8"))
    archive_path.write_bytes(arch_text.replace("\n", newline).encode("utf-8"))
    print(f"blocks moved: {moved_blocks}, sections moved: {moved_sections}")
    print(f"live: {len(lines)} -> {live_text.count(chr(10)) + 1} lines, {len(raw)} -> {len(live_text)} chars")


if __name__ == "__main__":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
