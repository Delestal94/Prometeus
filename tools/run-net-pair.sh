#!/usr/bin/env bash
# Starts one ENet host and one client for tests/net_pair.gd, then combines
# their exit codes and compact PAIR result lines. Intended for local use and CI.
# Prints a WARNING line when the joiner's level load came within 10 s of the
# 45 s network load budget (N-235.2): still a pass, but close to flaking.
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
# Three level loads on the client (join, rejoin, rejoin over a ghost): 18-34 s each on CI.
run() {
	timeout 240 "$GODOT_BIN" --headless --path "$PROJECT" res://tests/net_pair.tscn -- "$@"
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
	# What the F3 network overlay read on that side (N-216).
	grep -m1 "^NETSTATS " "$WORK/$role.log" || true
	# Join timing: how close the level load came to the handshake timeout.
	grep "^NETLOG " "$WORK/$role.log" || true
	case "$line" in
		*PASS*) ;;
		*) status=1 ;;
	esac
done
for code in "$HOST_CODE" "$CLIENT_CODE"; do
	[ "$code" -eq 0 ] || status=1
done
# N-221: a ghost the host drops leaves SceneMultiplayer at once
# (NetAdmission.close_dropped); a send to an ENet link that is closing means
# it stayed listed and the engine kept writing to it.
closing="$(grep -h "Unable to send packet" "$WORK/host.log" "$WORK/client.log" || true)"
if [ -n "$closing" ]; then
	echo "A peer kept sending to a closing ENet link (a dropped ghost still listed):"
	echo "$closing" | head -n 3
	status=1
fi
# N-235.2: a joiner's level load close to the network's 45 s load budget. Not
# a failure yet, but the next slower runner drops it mid-load.
slow="$(grep -h "^NETLOG .*WARNING slow level load" "$WORK/host.log" "$WORK/client.log" || true)"
if [ -n "$slow" ]; then
	echo "WARNING: the joiner's level load came within 10 s of the 45 s network load budget:"
	echo "$slow" | sed 's/^NETLOG /  /'
	[ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning title=Net pair: slow joiner load::$(echo "$slow" | head -n1 | sed 's/^NETLOG //')"
fi
if [ "$status" -ne 0 ]; then
	echo "Exit codes: host $HOST_CODE, client $CLIENT_CODE"
	for role in host client; do
		echo "--- $role (last 30 lines) ---"
		tail -n 30 "$WORK/$role.log"
	done
	echo "FAIL: net pair"
	exit 1
fi
echo "PASS: two-process cosmetics, gameplay races, rejoin and rejoin over a ghost"
