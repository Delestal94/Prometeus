#!/usr/bin/env bash
# Checks tools/affected-tests.sh (what the pre-push hook runs) on a fake tree,
# no Godot, under a second: a push that only touches the expansion's data
# (data/products/) runs the filter "company" and nothing else (D-2015); a
# changed .gd brings the tests that name it, and "company" only when it lives
# in an expansion folder; docs alone bring nothing; past PRE_PUSH_MAX_TESTS
# only the changed tests stay, plus "company". CI runs it in the lint job.
#
#   tools/test-affected-tests.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/test-affected-tests-$$")"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
failures=0

P="$WORK/do-not-drop"
mkdir -p "$P/tests" "$P/scripts/gameplay/vehicle" "$P/scripts/core/company" "$P/data/products"
printf 'class_name Horn\nextends Node\n' >"$P/scripts/gameplay/vehicle/horn.gd"
printf 'class_name CompanyClock\nextends Node\n' >"$P/scripts/core/company/company_clock.gd"
printf 'var h := Horn.new()\n' >"$P/tests/test_horn.gd"
printf 'preload("res://scripts/core/company/company_clock.gd")\n' >"$P/tests/test_company_clock.gd"
printf '[gd_resource]\n' >"$P/data/products/soap.tres"

run() {
	printf '%s\n' "$@" | AFFECTED_ROOT="$WORK" bash "$ROOT/tools/affected-tests.sh" | tr '\n' ' ' | sed 's/ $//'
}
check() {
	local got="$1" want="$2" what="$3"
	if [ "$got" != "$want" ]; then
		echo "FAIL: $what: esperaba '$want', salió '$got'"
		failures=$((failures + 1))
	fi
}

check "$(run do-not-drop/data/products/soap.tres)" "company" \
	"solo data/products/ corre el filtro company y nada más"
check "$(run do-not-drop/data/zones/centro.tres do-not-drop/data/gates/a.tres)" "company" \
	"zones y gates también son de la expansión"
check "$(run do-not-drop/scripts/gameplay/vehicle/horn.gd)" "test_horn" \
	"un .gd del juego actual trae el test que lo nombra, sin company"
check "$(run do-not-drop/scripts/core/company/company_clock.gd)" "test_company_clock company" \
	"un .gd de scripts/core/company/ trae su test y el filtro company"
check "$(run docs/README.md do-not-drop/data/traps/x.tres)" "" \
	"docs y datos del juego actual no traen nada"
check "$(run do-not-drop/scripts/gameplay/districts/x.gd)" "company" \
	"un .gd nuevo de districts/ que ningún test nombra igual trae company"
check "$(printf '%s\n' do-not-drop/tests/test_horn.gd do-not-drop/scripts/gameplay/vehicle/horn.gd do-not-drop/scripts/core/company/company_clock.gd \
	| PRE_PUSH_MAX_TESTS=1 AFFECTED_ROOT="$WORK" bash "$ROOT/tools/affected-tests.sh" | tr '\n' ' ' | sed 's/ $//')" \
	"test_horn company" "pasado el tope quedan los tests cambiados y company"

if [ $failures -eq 0 ]; then
	echo "test-affected-tests: OK"
fi
exit $failures
