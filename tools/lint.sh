#!/usr/bin/env bash
# Lints the GDScript code with gdlint (gdtoolkit 4, config in /gdlintrc) and
# compares the result with tools/lint-baseline.txt: problems that were already
# there when the linter was adopted are tolerated, new ones fail. The baseline
# is a ratchet -- it may only go down.
#
#   tools/lint.sh                    # check (CI, pre-push)
#   tools/lint.sh --update-baseline  # rewrite the baseline after fixing problems
#
# Needs gdlint on PATH: pip install "gdtoolkit==4.5.0".
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="$ROOT/tools/lint-baseline.txt"
cd "$ROOT" || exit 1

if ! command -v gdlint >/dev/null 2>&1; then
	echo "lint: gdlint no está instalado (pip install \"gdtoolkit==4.5.0\")." >&2
	exit 1
fi

# One "path|rule count" line per file and rule, sorted, with / separators so
# the baseline is the same on Windows and Linux.
current="$(gdlint do-not-drop/scripts do-not-drop/modules do-not-drop/tests 2>&1 \
	| sed -n 's#\\#/#g; s#^\(do-not-drop/[^:]*\):[0-9]*: Error: .*(\([a-z-]*\))$#\1|\2#p' \
	| sort | uniq -c | awk '{print $2, $1}')"

if [ "${1:-}" = "--update-baseline" ]; then
	printf '%s\n' "$current" | sed '/^$/d' >"$BASELINE"
	echo "lint: baseline actualizada ($(wc -l <"$BASELINE") entradas)."
	exit 0
fi

touch "$BASELINE"
worse="$(printf '%s\n' "$current" | sed '/^$/d' | awk '
	FILENAME == ARGV[1] { allowed[$1] = $2; next }
	{ if ($2 > allowed[$1] + 0) printf "  %s: %d (baseline %d)\n", $1, $2, allowed[$1] + 0 }
' "$BASELINE" -)"
better="$(printf '%s\n' "$current" | sed '/^$/d' | awk '
	FILENAME == ARGV[1] { now[$1] = $2; next }
	{ if ($2 > now[$1] + 0) n++ }
	END { print n + 0 }
' - "$BASELINE")"

if [ -n "$worse" ]; then
	echo "lint: problemas nuevos (archivo|regla: cantidad):"
	printf '%s\n' "$worse"
	echo "Detalle: gdlint <archivo>. Si bajaste otros, corré tools/lint.sh --update-baseline."
	exit 1
fi
if [ "$better" -gt 0 ]; then
	echo "lint: OK, y $better entradas mejoraron: corré tools/lint.sh --update-baseline y commiteá la baseline."
else
	echo "lint: OK"
fi
