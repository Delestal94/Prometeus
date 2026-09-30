#!/usr/bin/env bash
# Index of the headless tests, benches and captures, read from each file's own
# header (the "## ..." comment under `extends SceneTree`, after the "## Run:"
# line). The header is the single description of a test: there's no list to
# keep in sync elsewhere.
#
#   tools/list-tests.sh            # every test_/bench_/net_/render_/check_ script
#   tools/list-tests.sh depot red  # only names containing "depot" or "red"
#   tools/list-tests.sh --missing  # scripts whose header has no description
set -euo pipefail

cd "$(dirname "$0")/../do-not-drop"

missing=0
filters=()
for arg in "$@"; do
	if [ "$arg" = "--missing" ]; then missing=1; else filters+=("$arg"); fi
done

status=0
for file in tests/test_*.gd tests/bench_*.gd tests/net_*.gd tests/render_*.gd tests/check_*.gd modules/*/tests/test_*.gd; do
	[ -f "$file" ] || continue
	name="$(basename "$file" .gd)"
	case "$file" in modules/*) name="${file#modules/}"; name="${name%%/*}/$(basename "$file" .gd)" ;; esac
	if [ ${#filters[@]} -gt 0 ]; then
		keep=0
		for f in "${filters[@]}"; do [[ "$name" == *"$f"* ]] && keep=1; done
		[ $keep -eq 1 ] || continue
	fi
	# The first block of "##" lines, minus the Run: line and empty "##" lines.
	desc=$(awk 'NR == 1 { next } /^##/ { sub(/^## ?/, ""); if ($0 !~ /^Run:/ && $0 != "") printf "%s ", $0; seen = 1; next } seen { exit }' "$file" | sed 's/  */ /g; s/ $//')
	if [ $missing -eq 1 ]; then
		if [ -z "$desc" ]; then echo "$file"; status=1; fi
		continue
	fi
	echo "- $name — ${desc:-(sin descripción en el encabezado)}"
done
exit $status
