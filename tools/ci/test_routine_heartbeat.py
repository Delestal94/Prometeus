#!/usr/bin/env python3
"""Tests for routine_heartbeat.evaluate and fetch_prs: python3 tools/ci/test_routine_heartbeat.py"""
import datetime as dt
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import routine_heartbeat as hb  # noqa: E402

NOW = dt.datetime(2026, 10, 21, 12, 0, tzinfo=dt.timezone.utc)


def pr(branch, hours_ago):
    when = NOW - dt.timedelta(hours=hours_ago)
    return {"headRefName": branch, "createdAt": when.strftime("%Y-%m-%dT%H:%M:%SZ")}


def fresh():
    return [pr("nacho/N-1-x", 1), pr("exp/D-0101-x", 1), pr("rutina/pc-2026-10-21", 5), pr("arte/N-2-x", 10),
            pr("rutina/revision-2026-10-19", 40), pr("rutina/mant-2026-10-15", 150),
            pr("rutina/lanzamiento-2026-10", 300)]


def check(cond, msg):
    if not cond:
        print("FAIL:", msg)
        sys.exit(1)


check(hb.evaluate(fresh(), NOW, "normal") == {}, "all fresh: no alarms")
stale = [p for p in fresh() if not p["headRefName"].startswith("arte/")] + [pr("arte/N-2-x", 60)]
check(list(hb.evaluate(stale, NOW, "normal")) == ["Sesión de arte"], "arte at 60 h alarms")
check(hb.evaluate(stale, NOW, "minimo") == {}, "minimo leaves arte out")
check(hb.evaluate([p for p in fresh() if not p["headRefName"].startswith("rutina/pc-")], NOW, "minimo")
      == {"Build de la PC": "ningún PR de una rama `rutina/pc-*` (máximo 36 h)"},
      "no PC build PR alarms even in minimo")
check("Desarrollador" not in hb.evaluate([pr("nacho/x", 1)], NOW, "minimo"), "developer off in minimo")
check(hb.budget_level("") == "normal" and hb.budget_level("Ahorro: motivo") == "ahorro"
      and hb.budget_level("minimo") == "minimo" and hb.budget_level("otra cosa") == "normal", "budget_level")

# fetch_prs searches each prefix on its own: the monthly Lanzamiento PR (300 h old) is still found
# behind 300 newer developer PRs, which a single list of the newest 200 PRs missed (N-974.4).
crowded = [pr(f"exp/D-{i:04d}-x", 0.1 * i) for i in range(300)] + fresh()
searches = []


def fake_gh(*args):
    query = args[args.index("--search") + 1]
    searches.append(query)
    prefix = query.split()[0][len("head:"):]
    newest = sorted((p for p in crowded if p["headRefName"].startswith(prefix)),
                    key=lambda p: p["createdAt"], reverse=True)
    return json.dumps(newest[:int(args[args.index("--limit") + 1])])


hb.gh = fake_gh
found = hb.fetch_prs([])
check(len(searches) == len(hb.RULES) and all(" sort:created-desc" in q for q in searches), "one search per rule")
check(any(p["headRefName"].startswith("rutina/lanzamiento-") for p in found), "old monthly PR found")
check(hb.evaluate(found, NOW, "normal") == {}, "crowded but fresh: no alarms")
print("OK")
