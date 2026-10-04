#!/usr/bin/env bash
# What tools/run-tests.sh should run for a set of changed files (one repo
# path per line on stdin): one test name or filter per line on stdout. Used by
# the pre-push hook (.githooks/pre-push); tools/test-affected-tests.sh checks it.
#
#   git diff --name-only origin/main | tools/affected-tests.sh
#
# - every changed test (game or module) by name;
# - every test that names a changed .gd by file name or by its class_name;
# - more than PRE_PUSH_MAX_TESTS (default 25) of those means a wide change:
#   only the changed tests, CI covers the rest;
# - the filter "company" when anything under the districts expansion's
#   folders changed (EXPANSION_DIRS below, D-2015): their data (.tres) and
#   scenes name no test, and run-tests.sh's "company" keeps the expansion's
#   tests by prefix (D-2014).
#
# Env: AFFECTED_ROOT (another repo root; the test uses a fake tree).
set -u

ROOT="${AFFECTED_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT="$ROOT/do-not-drop"

# Folders of the expansion (docs/expansion-distritos/detalle/F0-20-red-y-ci.md).
# A new expansion folder goes here too.
EXPANSION_DIRS=(
	do-not-drop/scripts/core/company/
	do-not-drop/scripts/gameplay/business/
	do-not-drop/scripts/gameplay/districts/
	do-not-drop/scripts/gameplay/fleet/
	do-not-drop/scenes/company/
	do-not-drop/data/products/
	do-not-drop/data/zones/
	do-not-drop/data/vehicles/
	do-not-drop/data/boxes/
	do-not-drop/data/suppliers/
	do-not-drop/data/gates/
)

selected=""
direct=""
company=0
while IFS= read -r file; do
	[ -n "$file" ] || continue
	for dir in "${EXPANSION_DIRS[@]}"; do
		case "$file" in "$dir"*) company=1 ;; esac
	done
	case "$file" in
		do-not-drop/*.gd) ;;
		*) continue ;;
	esac
	[ -f "$ROOT/$file" ] || continue
	stem="$(basename "$file" .gd)"
	case "$stem" in
		test_*) direct="$direct"$'\n'"$stem"; continue ;;
	esac
	selected="$selected"$'\n'"$(grep -lF "$stem.gd" "$PROJECT"/tests/test_*.gd "$PROJECT"/modules/*/tests/test_*.gd 2>/dev/null)"
	cls="$(sed -n 's/^class_name[[:space:]]\{1,\}\([A-Za-z0-9_]*\).*/\1/p' "$ROOT/$file" | head -1)"
	if [ -n "$cls" ]; then
		selected="$selected"$'\n'"$(grep -lw "$cls" "$PROJECT"/tests/test_*.gd "$PROJECT"/modules/*/tests/test_*.gd 2>/dev/null)"
	fi
done
selected="$(echo "$selected" | sed '/^$/d' | xargs -r -n1 basename 2>/dev/null | sed 's/\.gd$//')"
all="$(printf '%s\n%s\n' "$direct" "$selected" | sed '/^$/d' | sort -u)"
if [ "$(echo "$all" | sed '/^$/d' | wc -l)" -gt "${PRE_PUSH_MAX_TESTS:-25}" ]; then
	echo "$direct" | sed '/^$/d' | sort -u
else
	echo "$all" | sed '/^$/d'
fi
[ $company -eq 1 ] && echo company
exit 0
