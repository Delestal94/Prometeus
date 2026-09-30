#!/usr/bin/env python3
"""Resume una carpeta de registros de partidas de Take My Package en tablas.

Los registros los escribe el juego (do-not-drop/scripts/core/run_telemetry.gd)
cuando la opcion "Guardar registro de partidas" esta prendida: un JSON por
partida en la carpeta `telemetry` de los datos de usuario del juego. Nada se
manda por red; esto solo los lee.

Uso:
    python tools/telemetry-summary.py                 # carpeta por defecto del juego
    python tools/telemetry-summary.py CARPETA         # otra carpeta (p. ej. la de un amigo)
    python tools/telemetry-summary.py CARPETA --roles host,solo

Con varias personas jugando juntas, cada PC guarda su propio registro de la
misma partida. Para no contar una partida dos veces, junta solo los archivos del
anfitrion (`--roles host,solo`) o resume la carpeta de cada uno por separado.

Solo usa la libreria estandar de Python (3.8 o mas nuevo).
"""

import argparse
import json
import os
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

GAME_NAME = "Take My Package"


def default_folder() -> Path:
    """Donde Godot guarda user://telemetry segun el sistema."""
    home = Path.home()
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", home / "AppData" / "Roaming")) / "Godot" / "app_userdata"
    elif sys.platform == "darwin":
        base = home / "Library" / "Application Support" / "Godot" / "app_userdata"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share")) / "godot" / "app_userdata"
    return base / GAME_NAME / "telemetry"


def load_records(folder: Path):
    """Devuelve (registros, archivos_ilegibles). Un archivo roto no frena el resto."""
    records, broken = [], []
    for path in sorted(folder.glob("*.json")):
        try:
            with path.open(encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            broken.append(path.name)
            continue
        if isinstance(data, dict) and isinstance(data.get("boxes"), list):
            records.append(data)
        else:
            broken.append(path.name)
    return records, broken


def number(value, default=0.0) -> float:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else default


def mean(values) -> float:
    return statistics.fmean(values) if values else 0.0


def fmt_seconds(seconds: float) -> str:
    seconds = int(round(seconds))
    return "%d:%02d" % divmod(seconds, 60)


def table(headers, rows) -> str:
    """Tabla de texto alineada; la primera columna a la izquierda, el resto a la derecha."""
    if not rows:
        return "  (sin datos)"
    cells = [[str(c) for c in row] for row in rows]
    widths = [max(len(h), *(len(row[i]) for row in cells)) for i, h in enumerate(headers)]

    def line(row):
        parts = [row[0].ljust(widths[0])] + [row[i].rjust(widths[i]) for i in range(1, len(row))]
        return "  " + "  ".join(parts)

    rule = "  " + "  ".join("-" * w for w in widths)
    return "\n".join([line(headers), rule] + [line(r) for r in cells])


def overview(records) -> str:
    durations = [number(r.get("duration_seconds")) for r in records]
    scores = [number(r.get("score")) for r in records]
    delivered = sum(1 for r in records if r.get("delivered"))
    modes = Counter(str(r.get("mode", "?")) for r in records)
    crew = [number(r.get("crew_size"), 1) for r in records]
    rows = [
        ("Partidas", len(records)),
        ("Modos", ", ".join("%s %d" % (m, n) for m, n in sorted(modes.items()))),
        ("Entregas logradas", "%d (%.0f%%)" % (delivered, 100.0 * delivered / len(records))),
        ("Duracion media", fmt_seconds(mean(durations))),
        ("Duracion min / max", "%s / %s" % (fmt_seconds(min(durations)), fmt_seconds(max(durations)))),
        ("Puntaje medio", "%.0f" % mean(scores)),
        ("Tripulacion media", "%.1f" % mean(crew)),
    ]
    width = max(len(k) for k, _ in rows)
    return "\n".join("  %s  %s" % (k.ljust(width), v) for k, v in rows)


def traps_table(records) -> str:
    runs = defaultdict(set)      # trampa -> indices de partidas donde aparecio
    boxes = defaultdict(int)
    ruined = defaultdict(int)
    risk = defaultdict(list)
    for index, record in enumerate(records):
        for order in record.get("orders", []):
            if isinstance(order, dict):
                runs[str(order.get("trap", "unknown"))].add(index)
        for box in record.get("boxes", []):
            if not isinstance(box, dict):
                continue
            trap = str(box.get("trap", "unknown"))
            runs[trap].add(index)
            boxes[trap] += 1
            ruined[trap] += 1 if box.get("ruined") else 0
            risk[trap].append(number(box.get("risk_seconds")))
    rows = []
    for trap in sorted(runs, key=lambda t: (-len(runs[t]), t)):
        pct = 100.0 * ruined[trap] / boxes[trap] if boxes[trap] else 0.0
        rows.append((trap, len(runs[trap]), boxes[trap], "%.0f%%" % pct, "%.1f" % mean(risk[trap])))
    return table(("trampa", "partidas", "cajas", "arruinadas", "seg en riesgo (prom.)"), rows)


def causes_table(records) -> str:
    causes = Counter()
    for record in records:
        for box in record.get("boxes", []):
            if isinstance(box, dict) and box.get("ruined"):
                cause = str(box.get("ruin_cause") or "(sin causa)")
                causes[(str(box.get("trap", "unknown")), cause)] += 1
    rows = [(trap, cause, count) for (trap, cause), count in causes.most_common()]
    return table(("trampa", "que la rompio (texto del idioma de quien jugo)", "cajas"), rows)


def events_table(records) -> str:
    seen = Counter()
    solved = Counter()
    times = defaultdict(list)
    for record in records:
        events = [e for e in record.get("route_events", []) if isinstance(e, dict)]
        for event in events:
            name = str(event.get("id", "?"))
            seen[name] += 1
            if event.get("resolved") and event.get("success"):
                solved[name] += 1
                times[name].append(number(event.get("resolved_at_seconds")) - number(event.get("started_at_seconds")))
        if not events and record.get("route_event"):
            seen[str(record["route_event"])] += 1
    rows = []
    for name in sorted(seen, key=lambda n: (-seen[n], n)):
        rows.append((name, seen[name], "%.0f%%" % (100.0 * solved[name] / seen[name]),
                     "%.0f" % mean(times[name]) if times[name] else "-"))
    return table(("evento de ruta", "veces", "resuelto", "seg hasta resolver (prom.)"), rows)


def main(argv=None) -> int:
    # Un texto con tildes no debe romper la tabla en una consola que no sea UTF-8.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="replace")
    parser = argparse.ArgumentParser(description="Resume registros de partidas de Take My Package.")
    parser.add_argument("folder", nargs="?", type=Path, help="carpeta con los .json (por defecto, la del juego)")
    parser.add_argument("--roles", help="solo estos roles, separados por coma: solo, host, client")
    args = parser.parse_args(argv)

    folder = args.folder or default_folder()
    if not folder.is_dir():
        print("No existe la carpeta: %s" % folder, file=sys.stderr)
        print("Prende 'Guardar registro de partidas' en Opciones y juega una partida.", file=sys.stderr)
        return 1

    records, broken = load_records(folder)
    if args.roles:
        wanted = {r.strip() for r in args.roles.split(",") if r.strip()}
        records = [r for r in records if str(r.get("role", "solo")) in wanted]
    print("Carpeta: %s" % folder)
    if broken:
        print("Archivos ilegibles (se saltaron): %s" % ", ".join(broken))
    if not records:
        print("No hay partidas para resumir.")
        return 0

    print("\nGeneral")
    print(overview(records))
    print("\nPor trampa")
    print(traps_table(records))
    print("\nQue rompio las cajas")
    print(causes_table(records))
    print("\nEventos de ruta")
    print(events_table(records))
    return 0


if __name__ == "__main__":
    sys.exit(main())
