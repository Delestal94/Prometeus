#!/usr/bin/env python3
"""Release notes for Take My Package from the commit prefixes on main, as Markdown on stdout.

Usage:
    python tools/release/changelog.py --from v0.3.0 --to <sha>   # since the previous version
    python tools/release/changelog.py --since-days 7             # first version: the last week only

Commits follow "<type>: <summary> (#PR)" (CLAUDE.md). They are grouped by type, and the districts
expansion (a D-xxxx in the summary) gets its own section. Used by .github/workflows/release-train.yml;
also useful by hand to see what a build has. Only the standard library and git.
"""
import argparse
import re
import subprocess
from collections import defaultdict

SECTIONS = [
    ("feat", "Novedades"),
    ("fix", "Arreglos"),
    ("perf", "Rendimiento"),
    ("refactor", "Código por dentro"),
    ("style", "Estilo y arte"),
    ("test", "Tests"),
    ("docs", "Documentación y planificación"),
    ("ci", "CI y herramientas"),
    ("chore", "CI y herramientas"),
    ("build", "CI y herramientas"),
]
LINE = re.compile(r"^(?P<type>[a-z]+)(?:\([^)]*\))?(?P<bang>!)?: (?P<text>.+)$")


def commits(rev_range, since_days):
    cmd = ["git", "log", "--first-parent", "--format=%h\x1f%s"]
    if since_days:
        cmd.append(f"--since={since_days} days ago")
    cmd.append(rev_range)
    out = subprocess.run(cmd, check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return [line.split("\x1f", 1) for line in out.splitlines() if "\x1f" in line]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--from", dest="start", default="")
    parser.add_argument("--to", default="HEAD")
    parser.add_argument("--since-days", type=int, default=0)
    args = parser.parse_args()
    rev_range = f"{args.start}..{args.to}" if args.start else args.to

    titles = dict(SECTIONS)
    order = list(dict.fromkeys(title for _, title in SECTIONS)) + ["Otros"]
    groups, expansion, breaking = defaultdict(list), [], []
    for sha, subject in commits(rev_range, args.since_days):
        if subject.startswith("chore: claim ") or subject.startswith("chore: reclaim "):
            continue
        m = LINE.match(subject)
        kind, text = (m.group("type"), m.group("text")) if m else ("", subject)
        entry = f"- {text} (`{sha}`)"
        if m and m.group("bang"):
            breaking.append(entry)
        if re.search(r"\bD-\d{4}\b", text):
            expansion.append(entry)
        else:
            groups[titles.get(kind, "Otros")].append(entry)

    total = sum(len(v) for v in groups.values()) + len(expansion)
    print(f"{total} cambios mezclados en `main`.\n")
    if breaking:
        print("## ⚠ Rompe compatibilidad\n")
        print("\n".join(breaking) + "\n")
    for title in order:
        if groups.get(title):
            print(f"## {title}\n")
            print("\n".join(groups[title]) + "\n")
    if expansion:
        print("## Expansión de distritos (`D-xxxx`)\n")
        print("\n".join(expansion) + "\n")


if __name__ == "__main__":
    main()
