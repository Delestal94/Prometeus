#!/usr/bin/env bash
# Checks tools/run-tests.sh itself with a fake Godot (no engine needed, a few
# seconds): with GITHUB_ACTIONS set, every failing test gets one
# "::error title=FAIL <test> (<reason>)::<first ERROR line>" annotation (a
# hang gets one too, with its timeout as the reason); without it there is no
# annotation; and pass/fail (the exit code) is the same either way (N-240).
# Filter "company" (D-2014) keeps the districts expansion's tests by prefix,
# none of the current game's, and is not an error while there are none.
# CI runs it in the lint job.
#
#   tools/test-run-tests.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/test-run-tests-$$")"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
failures=0

expect() {
	if [ "$1" -ne 0 ]; then
		echo "FAIL: $2"
		failures=$((failures + 1))
	fi
}

# Fake Godot: "--import" does nothing; "--script res://<path>" passes, fails
# with an ERROR line (when <path> contains FAKE_FAIL) or hangs (FAKE_HANG).
cat >"$WORK/godot" <<'EOF'
#!/usr/bin/env bash
script=""
while [ $# -gt 0 ]; do
	[ "$1" = "--script" ] && script="$2"
	shift
done
[ -n "$script" ] || exit 0
case "$script" in
	*"$FAKE_FAIL"*) echo "ERROR: 100% broken in $script"; echo "ERROR: second line"; exit 1 ;;
	*"$FAKE_HANG"*) sleep 5; exit 0 ;;
esac
echo "PASS"
EOF
chmod +x "$WORK/godot"

# Three real test names; the fake decides how each one ends.
FILTERS=(test_rpc_guard test_world_determinism test_modal_layers)
run() {
	GODOT="$WORK/godot" FAKE_FAIL=test_world_determinism FAKE_HANG=test_modal_layers \
		TEST_TIMEOUT=1 JOBS=3 CI= PROGRESS= "$@" bash "$ROOT/tools/run-tests.sh" "${FILTERS[@]}" >"$WORK/out" 2>&1
}

run env GITHUB_ACTIONS=true
code=$?
expect $(( code == 0 )) "a failing suite still exits non-zero with GITHUB_ACTIONS (got $code)"
grep -qF '::error title=FAIL test_world_determinism (exit 1)::ERROR: 100%25 broken in res://tests/test_world_determinism.gd' "$WORK/out"
expect $? "the failure is annotated with its first ERROR line, % escaped"
grep -qF '::error title=FAIL test_modal_layers (timeout 1s)::no ERROR line in the log' "$WORK/out"
expect $? "a hang is annotated with its timeout"
[ "$(grep -c '^::error' "$WORK/out")" -eq 2 ]
expect $? "one annotation per failure, none for a pass ($(grep -c '^::error' "$WORK/out"))"
grep -q '^FAIL test_world_determinism (exit 1)' "$WORK/out"
expect $? "the plain summary line is still there"

run env -u GITHUB_ACTIONS
code=$?
expect $(( code == 0 )) "without GITHUB_ACTIONS the suite still fails (got $code)"
! grep -q '::error' "$WORK/out"
expect $? "no annotation outside GitHub Actions"

FILTERS=(test_rpc_guard)
run env GITHUB_ACTIONS=true
code=$?
expect "$code" "a passing suite exits 0 with GITHUB_ACTIONS (got $code)"
! grep -q '::error' "$WORK/out"
expect $? "no annotation when everything passes"

# Filter "company" on a fake project: the expansion's prefixes, also in a
# module, and nothing of the current game's with a look-alike name.
FAKE="$WORK/project"
mkdir -p "$FAKE/tests" "$FAKE/modules/order_queue/tests" "$FAKE/.godot/imported"
for name in test_company_net test_inventory test_zone_definitions test_reference_truck_4x4 \
	test_world_seed test_order_balancer test_reference_truck test_world_mood; do
	touch "$FAKE/tests/$name.gd"
done
touch "$FAKE/modules/order_queue/tests/test_order_queue.gd"
GODOT="$WORK/godot" FAKE_FAIL=none FAKE_HANG=none TESTS_PROJECT="$FAKE" REPORT_FILE="$WORK/company.csv" TEST_TIMEOUT=5 JOBS=3 CI= PROGRESS= \
	bash "$ROOT/tools/run-tests.sh" company >"$WORK/out" 2>&1
expect $? "filter company passes on the fake project"
picked="$(tail -n +2 "$WORK/company.csv" | cut -d, -f1 | sort | tr '\n' ' ')"
[ "$picked" = "order_queue__test_order_queue test_company_net test_inventory test_reference_truck_4x4 test_zone_definitions " ]
expect $? "filter company picks the expansion's tests only (got: $picked)"

# On the real tree: no current-game test sneaks in, and no expansion test
# yet is "0/0 PASS", not "no test matches".
rm -f "$WORK/company.csv"
GODOT="$WORK/godot" FAKE_FAIL=none FAKE_HANG=none REPORT_FILE="$WORK/company.csv" TEST_TIMEOUT=5 JOBS=3 CI= PROGRESS= \
	bash "$ROOT/tools/run-tests.sh" company >"$WORK/out" 2>&1
expect $? "filter company exits 0 on the real tree"
! grep -qE '^(test_world_|test_order_balancer|test_reference_truck,)' "$WORK/company.csv" 2>/dev/null
expect $? "filter company leaves the current game's look-alike tests out"

if [ $failures -gt 0 ]; then
	echo "--- last run-tests.sh output:"
	cat "$WORK/out"
	exit 1
fi
echo "test-run-tests: PASS"
