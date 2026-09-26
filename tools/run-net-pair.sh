#!/usr/bin/env bash
# Starts one ENet host and one client for tests/net_pair.gd, then combines
# their exit codes and compact PAIR result lines. Intended for local use and CI.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/do-not-drop"

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
	echo "run-net-pair: no Godot binary found (set GODOT)" >&2
	exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
run() {
	timeout 60 "$GODOT_BIN" --headless --path "$PROJECT" res://tests/net_pair.tscn -- "$@"
}

run --host >"$WORK/host.log" 2>&1 &
HOST_PID=$!
sleep 2
run --client >"$WORK/client.log" 2>&1 &
CLIENT_PID=$!

wait "$HOST_PID"; HOST_CODE=$?
wait "$CLIENT_PID"; CLIENT_CODE=$?

status=0
for role in host client; do
	line="$(grep -m1 "^PAIR role=$role " "$WORK/$role.log" || true)"
	echo "${line:-PAIR role=$role (no result)}"
	grep -m1 "^NETMETRIC " "$WORK/$role.log" || true
	case "$line" in
		*PASS*) ;;
		*) status=1 ;;
	esac
done
for code in "$HOST_CODE" "$CLIENT_CODE"; do
	[ "$code" -eq 0 ] || status=1
done
if [ "$status" -ne 0 ]; then
	echo "Exit codes: host $HOST_CODE, client $CLIENT_CODE"
	for role in host client; do
		echo "--- $role (last 30 lines) ---"
		tail -n 30 "$WORK/$role.log"
	done
	echo "FAIL: net pair"
	exit 1
fi
echo "PASS: two-process cosmetics and gameplay races"
