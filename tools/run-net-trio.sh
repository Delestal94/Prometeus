#!/usr/bin/env bash
# Three-process network check (tareas de Nacho N-207): starts a host and two
# ENet clients on localhost -- the second one joining late -- runs
# do-not-drop/tests/net_trio.gd in each, and checks they all saw the same
# world: session seed, house count, the depot's orders, the generated road
# and the rail crossing's phase once the host set it off.
#
#   tools/run-net-trio.sh
#
# Env: GODOT (path to the Godot 4 binary). On Windows use the plain, non
# "_console" executable: the firewall rule is tied to that exact .exe.
# LATE_JOIN_SECONDS (default 6): how long after the first client the second
# one connects.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/do-not-drop"
LATE="${LATE_JOIN_SECONDS:-6}"

find_godot() {
	if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
	for candidate in godot godot4 Godot_v4.7.2-stable_linux.x86_64; do
		if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return; fi
	done
	for candidate in /d/Descargas/Godot_v4.7.2-stable_win64.exe "D:/Descargas/Godot_v4.7.2-stable_win64.exe" \
			/d/Descargas/Godot_v4.7.2-stable_win64_console.exe "D:/Descargas/Godot_v4.7.2-stable_win64_console.exe"; do
		if [ -f "$candidate" ]; then echo "$candidate"; return; fi
	done
}
GODOT_BIN="$(find_godot)"
if [ -z "$GODOT_BIN" ]; then
	echo "run-net-trio: no Godot binary found (set GODOT)" >&2
	exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
run() {
	timeout 120 "$GODOT_BIN" --headless --path "$PROJECT" --script res://tests/net_trio.gd -- "$@"
}

run --host >"$WORK/host.log" 2>&1 &
HOST_PID=$!
sleep 2
run --client --name=a >"$WORK/a.log" 2>&1 &
A_PID=$!
sleep "$LATE"
run --client --name=b >"$WORK/b.log" 2>&1 &
B_PID=$!

wait "$HOST_PID"; HOST_CODE=$?
wait "$A_PID"; A_CODE=$?
wait "$B_PID"; B_CODE=$?

status=0
for role in host a b; do
	line="$(grep -m1 '^TRIO ' "$WORK/$role.log" || true)"
	echo "${line:-TRIO role=$role (no line)}"
	# Everything but the role must match across the three.
	echo "$line" | sed 's/^TRIO role=[^ ]* //' >"$WORK/$role.fingerprint"
	case "$line" in
		*FAIL*|"") status=1 ;;
	esac
done
# Same rule as run-tests.sh: crashing on a signal while shutting down,
# after the TRIO line is out, is the engine's unstable exit, not a failure.
unstable=()
check_exit() {
	local role="$1" code="$2"
	if [ "$code" -eq 0 ]; then return; fi
	if [ "$code" -ge 128 ] && [ "$code" -ne 124 ] && grep -q '^TRIO ' "$WORK/$role.log" && ! grep -q '^TRIO .*FAIL' "$WORK/$role.log"; then
		unstable+=("$role")
		return
	fi
	status=1
}
check_exit host "$HOST_CODE"
check_exit a "$A_CODE"
check_exit b "$B_CODE"
if ! cmp -s "$WORK/host.fingerprint" "$WORK/a.fingerprint" || ! cmp -s "$WORK/host.fingerprint" "$WORK/b.fingerprint"; then
	echo "The three peers don't agree on the world."
	status=1
fi
if [ "$status" -ne 0 ]; then
	echo "Exit codes: host $HOST_CODE, a $A_CODE, b $B_CODE"
	for role in host a b; do
		echo "--- $role (last 15 lines) ---"
		tail -n 15 "$WORK/$role.log"
	done
	echo "FAIL: net trio"
	exit 1
fi
[ ${#unstable[@]} -gt 0 ] && echo "  cierre inestable (imprimieron, el motor crasheó al salir): ${unstable[*]}"
echo "PASS: host and two clients (one late) see the same seed, houses, orders, road and crossing"
