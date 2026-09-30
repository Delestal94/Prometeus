#!/usr/bin/env bash
# Runs the headless Godot test suite (do-not-drop/tests/test_*.gd) in
# parallel and prints a compact summary: one line per failure with its
# push_error() lines, nothing else. Used by the pre-push hook, by CI and by
# the ejecutor-tests agent.
#
#   tools/run-tests.sh                 # the whole suite
#   tools/run-tests.sh depot traps     # only tests whose name contains one of these
#   tools/run-tests.sh -v ...          # also print the log of every failure
#   SHARD=1/4 tools/run-tests.sh       # only the 2nd quarter (CI splits the suite)
#
# Env: GODOT (path to the Godot 4 console binary), JOBS (parallel processes,
# default: half the cores, at most 6), TEST_TIMEOUT (seconds per test, 300),
# SLOW_TEST_TIMEOUT (seconds for the SLOW_TESTS below, twice TEST_TIMEOUT),
# REPORT_FILE (optional CSV path for per-test status and duration),
# SHARD (i/n: run only every n-th test from the i-th, 0-based).
#
# Not run here, on purpose: render_*.gd and check_*.gd need a real display and
# someone looking at the images -- that's the revisor-visual agent's job.
# Tests that say they need a display are reported as SKIP, not as failures.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/do-not-drop"
VERBOSE=0
FILTERS=()
for arg in "$@"; do
	case "$arg" in
		-v|--verbose) VERBOSE=1 ;;
		*) FILTERS+=("$arg") ;;
	esac
done

find_godot() {
	if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
	for candidate in godot godot4 Godot_v4.7.2-stable_linux.x86_64; do
		if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return; fi
	done
	# ~/godot: where the Claude Code cloud session hook installs it.
	for candidate in "$HOME/godot/Godot_v4.7.2-stable_linux.x86_64" /d/Descargas/Godot_v4.7.2-stable_win64_console.exe "D:/Descargas/Godot_v4.7.2-stable_win64_console.exe"; do
		if [ -x "$candidate" ] || [ -f "$candidate" ]; then echo "$candidate"; return; fi
	done
}
# A test's key for its log and result: a module's test is prefixed with the
# module, so modules/x/tests/test_a.gd never collides with tests/test_a.gd.
key_of() {
	case "$1" in
		modules/*) echo "$(echo "$1" | cut -d/ -f2)__$(basename "$1" .gd)" ;;
		*) basename "$1" .gd ;;
	esac
}
GODOT_BIN="$(find_godot)"
if [ -z "$GODOT_BIN" ]; then
	echo "run-tests: no encuentro Godot. Definí GODOT=/ruta/al/Godot_v4.x_console" >&2
	exit 2
fi

cores="$(nproc 2>/dev/null || echo 4)"
JOBS="${JOBS:-$(( cores / 2 > 6 ? 6 : (cores / 2 < 1 ? 1 : cores / 2) ))}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
SLOW_TEST_TIMEOUT="${SLOW_TEST_TIMEOUT:-$(( TEST_TIMEOUT * 2 ))}"
WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/tmp-tests-$$")"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# The tests: every test_*.gd, each portable module's own tests
# (modules/<name>/tests/, docs/modulos.md) and the route smoke check,
# filtered by name.
TESTS=()
for file in "$PROJECT"/tests/test_*.gd "$PROJECT"/modules/*/tests/test_*.gd "$PROJECT"/scripts/gameplay/route/route_smoke_check.gd; do
	[ -f "$file" ] || continue
	name="$(basename "$file" .gd)"
	if [ ${#FILTERS[@]} -gt 0 ]; then
		keep=0
		for filter in "${FILTERS[@]}"; do
			case "$name" in *"$filter"*) keep=1 ;; esac
		done
		[ $keep -eq 1 ] || continue
	fi
	TESTS+=("${file#"$PROJECT"/}")
done
if [ ${#TESTS[@]} -eq 0 ]; then
	echo "run-tests: ningún test coincide con: ${FILTERS[*]}" >&2
	exit 2
fi

# Keep historically slow tests at the front of xargs' work queue. With a small
# worker pool, longest-first scheduling reduces the tail without changing test
# isolation, coverage or parallelism. Refresh this list from the per-test
# durations printed in CI; names not listed retain their normal discovery order.
# These also get SLOW_TEST_TIMEOUT: test_route_fuzz takes 80-115 s on a normal
# CI runner and went past the 120 s limit whenever the runner was slower.
SLOW_TESTS=(
	test_route_fuzz
	test_vehicle_stress
	test_roadside_stories
	test_vehicle_handling
	test_route_duration_budget
	test_reference_truck
	test_road_hazards
	test_trailer_shots
	test_world_seed
	test_more_route_segments
	test_town_signs
	test_level_endless
	test_start_yard
	test_package_handling
)
ORDERED_TESTS=()
for slow_name in "${SLOW_TESTS[@]}"; do
	for rel in "${TESTS[@]}"; do
		if [ "${rel##*/}" = "$slow_name.gd" ]; then
			ORDERED_TESTS+=("$rel")
			break
		fi
	done
done
for rel in "${TESTS[@]}"; do
	is_slow=0
	for slow_name in "${SLOW_TESTS[@]}"; do
		if [ "${rel##*/}" = "$slow_name.gd" ]; then
			is_slow=1
			break
		fi
	done
	[ "$is_slow" -eq 1 ] || ORDERED_TESTS+=("$rel")
done
TESTS=("${ORDERED_TESTS[@]}")
# SHARD=i/n deals the longest-first list round-robin, so each of CI's n
# runners gets its share of the slow tests and they finish close together.
if [ -n "${SHARD:-}" ]; then
	shard_i="${SHARD%/*}"; shard_n="${SHARD#*/}"
	case "$shard_i/$shard_n" in
		*[!0-9/]*|/*|*/) echo "run-tests: SHARD tiene que ser i/n (0 <= i < n), no '$SHARD'" >&2; exit 2 ;;
	esac
	if [ "$shard_n" -lt 1 ] || [ "$shard_i" -ge "$shard_n" ]; then
		echo "run-tests: SHARD tiene que ser i/n (0 <= i < n), no '$SHARD'" >&2
		exit 2
	fi
	SHARDED=()
	for index in "${!TESTS[@]}"; do
		[ $(( index % shard_n )) -eq "$shard_i" ] && SHARDED+=("${TESTS[$index]}")
	done
	if [ ${#SHARDED[@]} -eq 0 ]; then
		echo "Tests: 0/0 PASS, 0 FAIL, 0 SKIP  (shard $SHARD vacío)"
		exit 0
	fi
	TESTS=("${SHARDED[@]}")
fi
# Space-padded so run_one can match whole names (arrays don't cross export).
SLOW_NAMES=" ${SLOW_TESTS[*]} "

# A fresh clone has no .godot/ import cache: build it once, before the
# parallel runs, so they don't all race to write it.
if [ ! -d "$PROJECT/.godot/imported" ]; then
	echo "run-tests: importando recursos (primera vez)..."
	timeout 600 "$GODOT_BIN" --headless --path "$PROJECT" --import >"$WORK/import.log" 2>&1 || true
fi

start=$(date +%s)

# One test, one process, its own user:// (APPDATA on Windows, XDG_DATA_HOME
# on Linux) so parallel tests never share a save file. Writes
# "<status> <exit>" to <name>.result; status is PASS, FAIL, SKIP or FLAKY
# (every check passed, then the engine crashed while shutting down -- a known
# Godot teardown crash, see docs/colaboracion-equipo.md).
run_one() {
	local rel="$1" name
	name="$(key_of "$rel")"
	local data="$WORK/userdata/$name" log="$WORK/$name.log"
	mkdir -p "$data"
	local data_native="$data"
	command -v cygpath >/dev/null 2>&1 && data_native="$(cygpath -w "$data")"
	local attempt code began status duration limit="$TEST_TIMEOUT"
	case "$SLOW_NAMES" in *" $name "*) limit="$SLOW_TEST_TIMEOUT" ;; esac
	began=$(date +%s)
	for attempt in 1 2; do
		APPDATA="$data_native" XDG_DATA_HOME="$data" \
			timeout "$limit" "$GODOT_BIN" --headless --path "$PROJECT" --script "res://$rel" >"$log" 2>&1
		code=$?
		if [ $code -eq 0 ]; then
			status=PASS; break
		fi
		if grep -q "needs a display\|needs a rendering display" "$log"; then
			status=SKIP; break
		fi
		# Crashed (signal) after printing PASS: retry once, then accept it.
		if [ $code -ge 128 ] && [ $code -ne 124 ] && grep -q "^PASS" "$log"; then
			status=FLAKY
			[ $attempt -eq 2 ] && break
			continue
		fi
		status=FAIL; break
	done
	duration=$(( $(date +%s) - began ))
	echo "$status $code $duration" >"$WORK/$name.result"
	# CI logs get a line per test as it finishes, so a hang shows which one.
	if [ -n "${PROGRESS:-}" ]; then
		echo "  $status $name (${duration}s)" >&3
	fi
}
export -f run_one key_of
export WORK GODOT_BIN PROJECT TEST_TIMEOUT SLOW_TEST_TIMEOUT SLOW_NAMES
# Per-test progress lines: on in CI (GitHub sets CI=true), off locally.
PROGRESS="${PROGRESS:-${CI:-}}"
export PROGRESS
exec 3>&1

# stderr off: bash's own "Segmentation fault" notices for the known
# shutdown crash; each test's output is already in its log.
printf '%s\n' "${TESTS[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} 2>/dev/null

pass=0; fail=0; skip=0; flaky=0
failed=(); skipped=(); flakies=()
for rel in "${TESTS[@]}"; do
	name="$(key_of "$rel")"
	read -r status code duration <"$WORK/$name.result" 2>/dev/null || { status=FAIL; code="?"; duration=0; }
	case "$status" in
		PASS) pass=$((pass + 1)) ;;
		FLAKY) pass=$((pass + 1)); flaky=$((flaky + 1)); flakies+=("$name") ;;
		SKIP) skip=$((skip + 1)); skipped+=("$name") ;;
		*) fail=$((fail + 1)); failed+=("$name:$code") ;;
	esac
done
elapsed=$(( $(date +%s) - start ))

if [ -n "${REPORT_FILE:-}" ]; then
	mkdir -p "$(dirname "$REPORT_FILE")"
	{
		echo 'test,status,exit_code,duration_seconds'
		for rel in "${TESTS[@]}"; do
			name="$(key_of "$rel")"
			read -r status code duration <"$WORK/$name.result" 2>/dev/null || { status=FAIL; code="?"; duration=0; }
			printf '%s,%s,%s,%s\n' "$name" "$status" "$code" "$duration"
		done
	} >"$REPORT_FILE"
fi

echo "Tests: $pass/${#TESTS[@]} PASS, $fail FAIL, $skip SKIP  (${elapsed}s, $JOBS en paralelo)"
[ $flaky -gt 0 ] && echo "  cierre inestable (pasaron, el motor crasheó al salir): ${flakies[*]}"
[ $skip -gt 0 ] && echo "  necesitan pantalla (revisor-visual): ${skipped[*]}"
for entry in "${failed[@]+"${failed[@]}"}"; do
	name="${entry%%:*}"; code="${entry#*:}"
	limit="$TEST_TIMEOUT"
	case "$SLOW_NAMES" in *" $name "*) limit="$SLOW_TEST_TIMEOUT" ;; esac
	[ "$code" = "124" ] && reason="timeout ${limit}s" || reason="exit $code"
	echo "FAIL $name ($reason)"
	# Only the test's own failures, not engine noise from the dummy renderer.
	grep -E "^(ERROR|SCRIPT ERROR|Parse Error)" "$WORK/$name.log" \
		| grep -vE 'material" is null|resources still in use|unknown peer ID|is_inside_tree\(\)' \
		| sort | uniq | head -6 | sed 's/^/    /'
	if [ $VERBOSE -eq 1 ]; then
		sed 's/^/    | /' "$WORK/$name.log" | tail -40
	fi
done
[ $fail -eq 0 ]
