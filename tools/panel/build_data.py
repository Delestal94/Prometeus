"""Arma panel/data.json para el panel del flujo de trabajo (panel/index.html).

Lee lo que el repo ya dice del equipo de agentes: frontmatter de .claude/agents/*.md, la tabla
"Ciclo completo" de CLAUDE.md, la tabla de rutinas de .claude/rutinas/README.md, los carriles de
desarrollador.md, docs/tareas-nacho.md, la expansión y los avisos. Lo en vivo (PRs, CI, ramas,
eventos) lo trae la página de la API de GitHub.

Uso: python tools/panel/build_data.py [--strict] [salida]   (por defecto panel/data.json)
--strict sale con 1 si algo no se pudo leer (una rutina sin horario, una tabla que cambió de forma).
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Horario de cada rutina en cron UTC (los triggers de la nube y el Programador de la PC).
# Mantener con la tabla de .claude/rutinas/README.md: una fila sin entrada acá sale con un aviso.
ROUTINES = {
    "Desarrollador 1-5": {"kind": "nube", "lanes": True},
    "Construcción A": {"kind": "nube", "cron": "7 * * * *", "branch": r"^nacho/"},
    "Construcción B": {"kind": "nube", "cron": "37 * * * *", "branch": r"^nacho/S-", "paused": True},
    "QA (juego actual)": {"kind": "nube", "cron": "0 12 * * *", "branch": r"^rutina/qa-\d"},
    "QA expansión A y B": {"kind": "nube", "cron": "0 4,16 * * *", "branch": r"^rutina/qa-exp-"},
    "Auditoría integral": {"kind": "nube", "cron": "0 10 */2 * *", "branch": r"^rutina/auditoria-"},
    "Revisión (la contra)": {"kind": "nube", "cron": "0 12 * * 1", "branch": r"^rutina/revision-"},
    "Mantenimiento": {"kind": "nube", "cron": "0 12 * * 4", "branch": r"^rutina/mant-"},
    "Lanzamiento": {"kind": "nube", "cron": "0 13 1 * *", "branch": r"^rutina/lanzamiento-"},
    "Sesión de arte (PC)": {"kind": "pc", "cron": "30 1,3,5,7,9,11,13,15,17,19,21,23 * * *", "branch": r"^arte/"},
    "Build y rendimiento (PC)": {"kind": "pc", "cron": "15 6 * * *", "branch": r"^rutina/pc-"},
}
# Carriles 1 y 5 (Opus) cada 3 h; 2, 3 y 4 cada 2 h, alternados (2026-10-04: repartir el cupo semanal).
LANE_CRONS = ["2 */3 * * *", "14 */2 * * *", "26 1-23/2 * * *", "38 */2 * * *", "50 1-23/3 * * *"]

# Pilares del desarrollo: el home del panel. Cada agente pertenece a uno; una tarea, al pilar de su
# primer agente (o por palabras del título si no nombra ninguno).
PILLARS = [
    ("diseno", "Diseño y balance", "Qué se construye y si es divertido: ideas, la contra, tiempos y números.",
     ["critico-diseno", "abogado-del-diablo", "pulidor-jugabilidad"]),
    ("sistemas", "Sistemas y economía", "Plata, mérito, cartas, desbloqueos, negocio, trampas y pedidos.",
     ["constructor-progresion", "constructor-negocio", "constructor-trampas"]),
    ("mundo", "Mundo y mecánicas", "Camión, ruta, depósito, distritos, jugador y paquete.",
     ["constructor-camion", "constructor-tramos", "constructor-mundo", "constructor-jugador", "Plan", "claude"]),
    ("arte", "Arte y animación", "Modelos, texturas, shaders, efectos y animaciones.",
     ["modelador-blender", "artista-conceptual", "artista-shaders", "artista-vfx", "animador", "director-arte"]),
    ("audio", "Audio", "Sonido sintetizado, mezcla y música.", ["disenador-audio"]),
    ("ui", "Interfaz", "Menús, HUD, tutorial, celular y mando.", ["constructor-ui"]),
    ("red", "Red y multijugador", "Host autoritativo, ENet, Steam, sincronización.", ["constructor-red", "auditor-red"]),
    ("calidad", "Calidad y rendimiento", "Tests, QA, CI, bugs y FPS.",
     ["ejecutor-tests", "escritor-tests", "probador-qa", "cazador-bugs", "revisor-gdscript", "revisor-visual",
      "perfilador-rendimiento", "vigilante-ci", "ingeniero-ci"]),
    ("produccion", "Producción", "Planificación, dominios, documentación y auditorías.",
     ["planificador-tareas", "guardian-dominios", "documentador", "auditor-integral"]),
    ("lanzamiento", "Lanzamiento", "Página de Steam, builds y calendario.", ["estratega-steam", "empaquetador-release"]),
]
AGENT_PILLAR = {a: key for key, _, _, agents in PILLARS for a in agents}
KEYWORD_PILLAR = [
    (r"Steam Direct|Steamworks|AppID|precio|p[aá]gina|tr[aá]iler|captura|build|lanzamiento|wishlist", "lanzamiento"),
    (r"\bred\b|RPC|Steam|protocolo|lobby|cliente|sincron|voz", "red"),
    (r"test|\bCI\b|\bQA\b|regresi|rendimiento|FPS|leak|bench|intermitente|f[ií]sica|calidad|archivos", "calidad"),
    (r"HUD|men[uú]|\bUI\b|pantalla|tutorial|bot[oó]n|mando", "ui"),
    (r"sonido|audio|m[uú]sica", "audio"),
    (r"shader|modelo|textura|anim|asset|ragdoll", "arte"),
    (r"plata|cobra|bono|carta|m[eé]rito|tienda|econom", "sistemas"),
]


# Grupo de la expansión -> pilar, para las tareas D- que no nombran un agente conocido.
GROUP_PILLAR = {"01": "diseno", "02": "produccion", "03": "mundo", "04": "sistemas", "05": "sistemas", "06": "sistemas",
                "07": "sistemas", "08": "sistemas", "09": "mundo", "10": "sistemas", "11": "sistemas", "12": "mundo",
                "13": "mundo", "14": "mundo", "15": "mundo", "16": "mundo", "17": "mundo", "18": "arte", "19": "ui",
                "20": "calidad"}


def pillar_for(agents, title, group=None):
    for a in agents:
        if a.rstrip("*") in AGENT_PILLAR:
            return AGENT_PILLAR[a.rstrip("*")]
    if group in GROUP_PILLAR:
        return GROUP_PILLAR[group]
    for pat, key in KEYWORD_PILLAR:
        if re.search(pat, title, re.I):
            return key
    return "mundo"


def ordered_agents(text, names):
    seen = []
    for a in AGENT_RE.findall(text):
        if a in names and a not in seen:
            seen.append(a)
    return seen


WARNINGS = []


def warn(msg):
    WARNINGS.append(msg)
    print("aviso: " + msg, file=sys.stderr)


AGENT_RE = re.compile(r"`([a-z]+(?:-[a-z]+)+|Plan)`")


def read(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8") if p.exists() else ""


def table_rows(text, header_start):
    """Filas (lista de celdas) de la primera tabla markdown cuyo encabezado empieza con header_start."""
    rows, inside = [], False
    for line in text.splitlines():
        if line.startswith("| " + header_start):
            inside = True
            continue
        if inside:
            if not line.startswith("|"):
                break
            if set(line.replace("|", "").strip()) <= set("-: "):
                continue
            rows.append([c.strip() for c in line.strip().strip("|").split("|")])
    return rows


def plain(md):
    return re.sub(r"[`*~]", "", md).strip()


def frontmatter(text):
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    out = {}
    for line in (m.group(1) if m else "").splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def build_agents():
    stages = {}
    for etapa, agentes in table_rows(read("CLAUDE.md"), "Etapa | Agentes"):
        for name in AGENT_RE.findall(agentes):
            stages.setdefault(name, etapa)
    agents = []
    for f in sorted((ROOT / ".claude/agents").glob("*.md")):
        fm = frontmatter(f.read_text(encoding="utf-8"))
        name = fm.get("name", f.stem)
        desc = fm.get("description", "")
        tools = fm.get("tools", "")
        agents.append({
            "name": name,
            "summary": re.split(r"(?<=[a-z\)])\. ", desc)[0][:240],
            "model": "Opus" if "opus" in fm.get("model", "") else "Sonnet" if "sonnet" in fm.get("model", "") else fm.get("model", ""),
            "effort": fm.get("effort", ""),
            "pillar": AGENT_PILLAR.get(name, "produccion"),
            "stage": stages.get(name, "Verificar" if name == "vigilante-ci" else "Otros"),
            "pc": "mcp__blender" in tools or "mcp__comfy" in tools,
            "readonly": bool(tools) and "Edit" not in tools and "Write" not in tools,
        })
    return agents


def build_routines(agent_names):
    readme = read(".claude/rutinas/README.md")
    routines = []
    for cells in table_rows(readme, "Rutina | Archivo"):
        if len(cells) < 5:
            continue
        name = plain(cells[0]).replace(" ⏸", "").strip()
        meta = ROUTINES.get(name)
        if meta is None:
            warn(f"la rutina '{name}' no tiene horario en ROUTINES")
            meta = {"kind": "nube"}
        file = re.search(r"`([\w-]+\.md)`", cells[1])
        file = file.group(1) if file else ""
        body = read(f".claude/rutinas/{file}") if file else ""
        used = ordered_agents(body, agent_names)
        base = {
            "name": name, "file": file, "when": plain(cells[2]), "branchText": plain(cells[3]),
            "produces": plain(cells[4]), "kind": meta["kind"], "paused": meta.get("paused", False) or "⏸" in cells[0],
            "agents": used,
        }
        if meta.get("lanes"):
            for lane in build_lanes():
                routines.append({**base, "name": f"Desarrollador {lane['n']}", "lane": lane["n"],
                                 "laneTitle": lane["title"], "cron": LANE_CRONS[lane['n'] - 1],
                                 "branch": r"^exp/D-(" + "|".join(lane["groups"]) + r")\d\d",
                                 "model": lane["model"], "agents": lane["agents"]})
        else:
            routines.append({**base, "cron": meta.get("cron", ""), "branch": meta.get("branch", "")})
    return routines


def build_lanes():
    lanes = []
    for cells in table_rows(read(".claude/rutinas/desarrollador.md"), "Carril | Modelo"):
        n, title = plain(cells[0]).split(" · ", 1) if " · " in cells[0] else (plain(cells[0]), "")
        lanes.append({
            "n": int(n), "title": title, "model": "Opus" if "Opus" in cells[1] else "Sonnet",
            "groups": re.findall(r"\b(\d\d)\b", cells[2]), "agents": AGENT_RE.findall(cells[3]),
        })
    return lanes


def status_of(header, body):
    if "⚠ Bloqueada" in header or "⚠ Bloqueada" in body[:300]:
        return "bloqueada"
    if header.startswith("~~") or "[x]" in header or "[x] Hecho" in body[:200] or "[x] Decidido" in header:
        return "hecha"
    if "⏸ decide" in header:
        return "decide"
    if "⏸" in header:
        return "pausada"
    return "abierta"


def build_tasks(agent_names):
    text = read("docs/tareas-nacho.md")
    tasks, milestone = [], ""
    parts = re.split(r"^(#{2,3} .*)$", text, flags=re.M)
    for i in range(1, len(parts), 2):
        head, body = parts[i], parts[i + 1]
        if head.startswith("## "):
            milestone = plain(head[3:])
            continue
        m = re.match(r"### (~~)?\**([NS]-\d+(?:\.\d+)?)\** · (.*)", head)
        if not m:
            continue
        rest = m.group(3)
        title = plain(rest.split(" — ")[0])
        meta = rest.split(" — ", 1)[1] if " — " in rest else ""
        eff = re.search(r"(Opus|Sonnet) 5\.5 · (\w+)", meta)
        agents = ordered_agents(body, agent_names)
        tasks.append({
            "id": m.group(2), "title": title.replace("⏸ decide el usuario: ", ""),
            "prio": (re.match(r"\s*([ABC])\b", plain(meta)) or [None, ""])[1],
            "effort": eff.group(2) if eff else "", "section": milestone,
            "status": status_of(head[4:], body),
            "pc": "necesita PC" in head,
            "subOpen": len(re.findall(r"^- \[ \]", body, re.M)), "subDone": len(re.findall(r"^- \[x\]", body, re.M)),
            "agents": agents, "pillar": pillar_for(agents, title),
        })
    return tasks


def build_expansion():
    base = ROOT / "docs/expansion-distritos"
    if not base.exists():
        return {}
    status, titles = {}, {}
    for f in (base / "detalle").glob("*.md"):
        parts = re.split(r"^(### .*)$", f.read_text(encoding="utf-8"), flags=re.M)
        for i in range(1, len(parts), 2):
            m = re.search(r"(D-\d{4}) · (.*?)(?: — |~~|$)", parts[i])
            if m:
                status[m.group(1)] = status_of(parts[i][4:], parts[i + 1])
                titles[m.group(1)] = plain(m.group(2)).replace("⏸ decide el usuario: ", "").replace("decide el usuario: ", "")
    groups, tasks = [], []
    for f in sorted(base.glob("[0-9][0-9]-*.md")):
        text = f.read_text(encoding="utf-8")
        title = re.search(r"^# (.*)", text, re.M)
        ids = []
        for cells in (r.split("|")[1:-1] for r in re.findall(r"^\| D-\d{4} \|.*\|$", text, re.M)):
            cells = [c.strip() for c in cells]
            tid, name, agent = cells[0], plain(cells[1]), plain(cells[2]) if len(cells) > 2 else ""
            st = status.get(tid, "abierta")
            ids.append(st)
            tasks.append({"id": tid, "title": titles.get(tid, name)[:140], "group": f.name[:2], "status": st,
                          "agent": agent.rstrip("*"), "pillar": pillar_for([agent], name, f.name[:2])})
        groups.append({
            "n": f.name[:2], "title": plain(title.group(1)) if title else f.stem, "total": len(ids),
            "done": ids.count("hecha"), "paused": ids.count("decide") + ids.count("pausada"),
            "blocked": ids.count("bloqueada"),
        })
    bugs = [p.stem for p in (base / "bugs").glob("*.md") if p.name.lower() != "readme.md"] if (base / "bugs").exists() else []
    art = [p.stem for p in (base / "arte-pendiente").glob("*.md") if p.name.lower() != "readme.md"] if (base / "arte-pendiente").exists() else []
    return {"groups": groups, "tasks": tasks, "bugs": bugs, "artPending": art}


def build_notes():
    out = []
    for f in sorted((ROOT / "docs/avisos").glob("20*.md"), reverse=True)[:12]:
        first = next((l for l in f.read_text(encoding="utf-8").splitlines() if l.strip()), f.stem)
        out.append({"file": f.name, "date": f.name[:10], "title": plain(first.lstrip("# "))[:140]})
    return out


def git_head():
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True,
                              text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def main():
    args = [a for a in sys.argv[1:] if a != "--strict"]
    out = Path(args[0]) if args else ROOT / "panel/data.json"
    agents = build_agents()
    names = {a["name"] for a in agents} | {"Plan"}
    data = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "commit": git_head(),
        "repo": "Delestal94/Prometeus",
        "paused": (ROOT / ".claude/rutinas/PAUSA").exists(),
        "pillars": [{"key": k, "title": t, "about": d, "agents": a} for k, t, d, a in PILLARS],
        "agents": agents,
        "routines": build_routines(names),
        "tasks": build_tasks(names),
        "expansion": build_expansion(),
        "notes": build_notes(),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    for key, label in (("agents", "agentes"), ("routines", "rutinas"), ("tasks", "tareas")):
        if not data[key]:
            warn(f"no se encontraron {label}")
    if len(data["routines"]) < 10:
        warn(f"solo {len(data['routines'])} rutinas: ¿cambió la tabla de .claude/rutinas/README.md?")
    t = data["tasks"]
    print(f"{out}: {len(agents)} agentes, {len(data['routines'])} rutinas, {len(t)} tareas "
          f"({sum(x['status'] == 'abierta' for x in t)} abiertas)")
    if WARNINGS and "--strict" in sys.argv:
        sys.exit(1)


if __name__ == "__main__":
    main()
