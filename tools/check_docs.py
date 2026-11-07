#!/usr/bin/env python3
"""Docs hygiene check (CI + pre-push).

Fails on:
  1. Broken relative markdown links, or absolute file:// links, in any tracked .md.
  2. A docs/*.md that docs/README.md (the index) does not link: nothing orphaned.
  3. A link in docs/README.md to a doc that no longer exists.
  4. A backticked repo path (`do-not-drop/...`, `docs/...`, `tools/...`) in docs/*.md
     that does not exist -- the usual symptom of a stale doc after a rename.
Run: python3 tools/check_docs.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

LINK = re.compile(r"\]\(([^)#\s]+)(#[^)]*)?\)")
TICK = re.compile(r"`((?:do-not-drop|docs|tools)/[A-Za-z0-9_./-]+)`")
SKIP = ("do-not-drop/addons/",)


def tracked(pattern):
    out = subprocess.check_output(["git", "ls-files", pattern], text=True)
    return [f for f in out.splitlines() if not f.startswith(SKIP) and os.path.exists(f)]


def top_docs():
    return [f for f in tracked("docs/*.md") if f.count("/") == 1]


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


errors = []

for f in tracked("*.md"):
    for m in LINK.finditer(read(f)):
        target = m.group(1)
        if target.startswith(("http:", "https:", "mailto:")):
            continue
        if target.startswith("file:"):
            errors.append(f"{f}: absolute link {target} (use a relative one)")
        elif not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(f), target))):
            errors.append(f"{f}: broken link {target}")

index = "docs/README.md"
linked = set()
if os.path.exists(index):
    for m in LINK.finditer(read(index)):
        linked.add(os.path.normpath(os.path.join("docs", m.group(1))).replace("\\", "/"))
else:
    errors.append(f"{index} is missing (index of every docs/*.md)")
for f in top_docs():
    if f != index and f not in linked:
        errors.append(f"{f}: not listed in {index}")

for f in top_docs():
    for m in TICK.finditer(read(f)):
        p = m.group(1).rstrip(".")
        if "*" in p or "<" in p or "AAAA" in p or "YYYY" in p:
            continue
        if not os.path.exists(p):
            errors.append(f"{f}: `{p}` does not exist")

if errors:
    print("check_docs: %d problem(s)" % len(errors))
    for e in sorted(set(errors)):
        print("  " + e)
    sys.exit(1)
print("check_docs: ok")
