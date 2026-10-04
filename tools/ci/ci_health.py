#!/usr/bin/env python3
"""Weekly CI health report for Take My Package, as Markdown on stdout.

Usage: python tools/ci/ci_health.py [--days 7] [--repo owner/name]

Reads the GitHub API through the `gh` CLI (GH_TOKEN in CI, your login locally) and reports:
- delivery: PRs merged, lead time (opened -> merged), main runs and how long main stayed red;
- reliability: first-attempt pass rate, runs rescued by a re-run (flaky), real failures by job,
  open `test-inestable` issues;
- cost and speed: CI minutes, wall time of PR runs, per-job and per-shard p50/p90;
- the slowest tests of the latest green main run (from its per-test CSV artifacts).

`.github/workflows/ci-health.yml` runs it every Monday and puts the result in the issue
"Salud del CI" (label `salud-ci`); the `ingeniero-ci` agent and the maintenance routine read it.
Only the standard library.
"""
import argparse
import csv
import datetime as dt
import io
import json
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


def gh(*args, raw=False):
    out = subprocess.run(["gh", *args], check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return out if raw else json.loads(out or "null")


def api_pages(path, key):
    """All items of a paginated list endpoint (`key` is the list's field, e.g. workflow_runs)."""
    items, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        data = gh("api", f"{path}{sep}per_page=100&page={page}")
        batch = data.get(key, []) if isinstance(data, dict) else data
        items += batch
        if len(batch) < 100:
            return items
        page += 1


def ts(value):
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None


def minutes(a, b):
    return (b - a).total_seconds() / 60 if a and b else None


def pct(values, q):
    values = sorted(v for v in values if v is not None)
    if not values:
        return None
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def fmt_min(value):
    if value is None:
        return "—"
    return f"{value / 60:.1f} h" if value >= 90 else f"{value:.0f} min"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--repo", default="")
    args = parser.parse_args()
    repo = args.repo or gh("repo", "view", "--json", "nameWithOwner")["nameWithOwner"]
    now = dt.datetime.now(dt.timezone.utc)
    since = now - dt.timedelta(days=args.days)
    day = since.strftime("%Y-%m-%d")

    runs = api_pages(f"repos/{repo}/actions/workflows/tests.yml/runs?created=>={day}", "workflow_runs")
    runs = [r for r in runs if r["status"] == "completed" and r["conclusion"] in ("success", "failure")]

    # Jobs of every attempt: a run whose attempt 1 failed and whose last attempt passed was rescued.
    job_minutes = defaultdict(list)
    job_failures = Counter()
    ci_minutes = 0.0
    first_pass = rescued = real_fail = 0
    for run in runs:
        jobs = api_pages(f"repos/{repo}/actions/runs/{run['id']}/jobs?filter=all", "jobs")
        first = [j for j in jobs if j.get("run_attempt", 1) == 1]
        first_ok = all(j["conclusion"] in ("success", "skipped") for j in first)
        if first_ok:
            first_pass += 1
        elif run["conclusion"] == "success":
            rescued += 1
        else:
            real_fail += 1
        last_attempt = max((j.get("run_attempt", 1) for j in jobs), default=1)
        for job in jobs:
            took = minutes(ts(job.get("started_at")), ts(job.get("completed_at")))
            if took is not None:
                ci_minutes += took
                if job.get("run_attempt", 1) == last_attempt and job["conclusion"] == "success":
                    job_minutes[job["name"]].append(took)
            if run["conclusion"] == "failure" and job.get("run_attempt", 1) == last_attempt \
                    and job["conclusion"] == "failure" and not job["name"].startswith("Tests headless ("):
                job_failures[job["name"]] += 1

    pr_runs = [r for r in runs if r["event"] == "pull_request"]
    pr_wall = [minutes(ts(r["run_started_at"]), ts(r["updated_at"])) for r in pr_runs]

    # main: red stretches from a failed head to the next green one (time to restore).
    main_runs = sorted((r for r in runs if r["head_branch"] == "main" and r["event"] != "pull_request"),
                       key=lambda r: r["run_started_at"])
    red_since, red_spans = None, []
    for run in main_runs:
        if run["conclusion"] == "failure" and red_since is None:
            red_since = ts(run["updated_at"])
        elif run["conclusion"] == "success" and red_since is not None:
            red_spans.append(minutes(red_since, ts(run["updated_at"])))
            red_since = None
    main_red = sum(1 for r in main_runs if r["conclusion"] == "failure")

    prs = gh("pr", "list", "-R", repo, "--state", "merged", "--limit", "300", "--search", f"merged:>={day}",
             "--json", "number,createdAt,mergedAt,headRefName")
    lead = [minutes(ts(p["createdAt"]), ts(p["mergedAt"])) for p in prs]
    by_prefix = Counter(p["headRefName"].split("/")[0] for p in prs)

    flaky_issues = gh("issue", "list", "-R", repo, "--label", "test-inestable", "--state", "open",
                      "--limit", "100", "--json", "number,title,comments")

    slow = slowest_tests(repo, main_runs)

    out = io.StringIO()
    w = out.write
    w(f"# Salud del CI — {now:%Y-%m-%d} (últimos {args.days} días)\n\n")
    w("Generado por `tools/ci/ci_health.py` (`.github/workflows/ci-health.yml`). Lo lee `ingeniero-ci`.\n\n")
    w("## Entrega\n\n| Métrica | Valor |\n|---|---|\n")
    w(f"| PRs mezclados | {len(prs)} ({', '.join(f'{k} {v}' for k, v in by_prefix.most_common())}) |\n")
    w(f"| Tiempo de PR abierto → mezclado (p50 / p90) | {fmt_min(pct(lead, .5))} / {fmt_min(pct(lead, .9))} |\n")
    w(f"| Corridas de `main` / rojas | {len(main_runs)} / {main_red} |\n")
    w(f"| `main` roja hasta volver a verde (p50 / máx) | {fmt_min(pct(red_spans, .5))} / "
      f"{fmt_min(max(red_spans) if red_spans else None)}"
      f"{' · **sigue roja**' if red_since else ''} |\n\n")
    total = len(runs) or 1
    w("## Confiabilidad\n\n| Métrica | Valor |\n|---|---|\n")
    w(f"| Corridas de Tests terminadas | {len(runs)} |\n")
    w(f"| Verdes al primer intento | {first_pass} ({100 * first_pass / total:.0f} %) |\n")
    w(f"| Salvadas por el reintento (inestables) | {rescued} ({100 * rescued / total:.0f} %) |\n")
    w(f"| Rojas de verdad | {real_fail} ({100 * real_fail / total:.0f} %) |\n\n")
    if job_failures:
        w("Checks rojos al final (PRs y `main`; en un PR suele ser el propio cambio):\n\n")
        for name, n in job_failures.most_common():
            w(f"- {name}: {n}\n")
        w("\n")
    if flaky_issues:
        w("Tests inestables abiertos (issues `test-inestable`, más repetidos primero):\n\n")
        for issue in sorted(flaky_issues, key=lambda i: -len(i["comments"])):
            w(f"- #{issue['number']} {issue['title'].removeprefix('Test inestable: ')} — "
              f"{1 + len(issue['comments'])} vez/veces\n")
        w("\n")
    else:
        w("Sin tests inestables abiertos.\n\n")
    w("## Costo y velocidad\n\n")
    w(f"Minutos de CI en la ventana: **{ci_minutes:.0f}** (suma de jobs, todos los intentos). "
      f"Duración de una corrida de PR (p50 / p90): {fmt_min(pct(pr_wall, .5))} / {fmt_min(pct(pr_wall, .9))}.\n\n")
    w("| Job | p50 | p90 | corridas |\n|---|---|---|---|\n")
    for name, values in sorted(job_minutes.items(), key=lambda kv: -(pct(kv[1], .5) or 0)):
        w(f"| {name} | {pct(values, .5):.1f} min | {pct(values, .9):.1f} min | {len(values)} |\n")
    shards = {k: pct(v, .5) for k, v in job_minutes.items() if k.startswith("Tests headless ") and "/4" in k}
    if len(shards) > 1:
        lo, hi = min(shards.values()), max(shards.values())
        w(f"\nBalance de shards: la más lenta tarda {hi / lo:.2f}× la más rápida"
          f"{' — **rebalancear** (SLOW_TESTS / orden en run-tests.sh)' if hi / lo > 1.3 else ''}.\n")
    if slow:
        w("\n## Tests más lentos (última corrida verde de `main`)\n\n| Test | Segundos |\n|---|---|\n")
        for name, secs in slow:
            w(f"| {name} | {secs} |\n")
    sys.stdout.write(out.getvalue())


def slowest_tests(repo, main_runs, top=12):
    green = [r for r in main_runs if r["conclusion"] == "success"]
    if not green:
        return []
    run = green[-1]
    with tempfile.TemporaryDirectory() as tmp:
        try:
            gh("run", "download", str(run["id"]), "-R", repo, "-D", tmp, "-p", "godot-headless-audit-*", raw=True)
        except subprocess.CalledProcessError:
            return []
        rows = []
        for path in Path(tmp).rglob("*.csv"):
            for row in csv.DictReader(path.open(encoding="utf-8")):
                try:
                    rows.append((row["test"], int(row["duration_seconds"])))
                except (KeyError, ValueError):
                    pass
    return sorted(rows, key=lambda r: -r[1])[:top]


if __name__ == "__main__":
    main()
