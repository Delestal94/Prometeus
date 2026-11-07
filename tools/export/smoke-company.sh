#!/usr/bin/env bash
# Smoke test of an exported build (D-2019): the two boots of the PC build routine, then a look inside the
# pack. Last line: "Empresa OK", or "Empresa FALLA: <why>" (the routine copies it to docs/rendimiento-pc.md).
#
#   GODOT=<editor binary> tools/export/smoke-company.sh [folder of the build, builds/windows if left out]
#
# Each boot ends itself with --quit-after: killing the exe with `timeout` makes the engine log dozens of
# "ERROR: BUG: Unreferenced static string" on its way out (Windows), so "no ERROR in the log" could never
# pass. `timeout` stays only as the guard against a hang. A quiet log proves little by itself, so the boot
# must also write the company's save, and tools/export/probe_company.gd must find the world up inside the
# pack. Runs on a user folder of its own: the real saves are never read or touched.
#
# The boots run with --verbose for one line of the log: "Resource still in use: <what>" is how to tell the menu
# music's race at exit (see errors_in) from a real leak, and only the music is forgiven.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="${1:-$ROOT/builds/windows}"
if [ ! -d "$BUILD" ]; then
	echo "Empresa FALLA: no existe la carpeta de la build ($BUILD)"
	exit 2
fi
BUILD="$(cd "$BUILD" && pwd)"
# ~55 s of the running game, headless. A boot that ends earlier than the load only fails, it never passes.
COMPANY_FRAMES=6000
MENU_FRAMES=300
GUARD_SECONDS=150
ERRORS='SCRIPT ERROR|ERROR|Failed to load|Cannot open|Parse Error'
EXIT_LEAK='ERROR: [0-9]+ resources still in use at exit'
MENU_TRACK='mus_menu_loop\.ogg'

fail() {
	echo "Empresa FALLA: $1"
	exit 1
}

EXE="$BUILD/TakeMyPackage.exe"
[ -f "$EXE" ] || EXE="$BUILD/TakeMyPackage.x86_64"
[ -f "$EXE" ] || fail "no hay ejecutable en $BUILD"
[ -f "$BUILD/TakeMyPackage.pck" ] || fail "no hay TakeMyPackage.pck en $BUILD"
[ -n "${GODOT:-}" ] || fail "falta GODOT (el editor de la misma versión, para la sonda)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export APPDATA XDG_DATA_HOME
APPDATA="$(native "$WORK")"
XDG_DATA_HOME="$WORK"

# The errors of a boot's log. Leaving from the menu, the music can be caught mid-mix as the engine closes (half
# of the boots, all of them under --verbose): AudioServer keeps the stopped playback until it mixes again, and
# the log ends in "1 resources still in use at exit". An engine race, nothing the game holds and nothing a player
# sees, so that line goes only when the track is all the engine names. Anything else still in use keeps it.
errors_in() {
	if grep 'Resource still in use:' "$1" | grep -qv "$MENU_TRACK"; then
		grep -E "$ERRORS" "$1"
	else
		grep -E "$ERRORS" "$1" | grep -vE "$EXIT_LEAK"
	fi
}

boot() {
	local name="$1" status found
	shift
	timeout "$GUARD_SECONDS" "$EXE" --headless --verbose "$@" >"$WORK/$name.log" 2>&1
	status=$?
	found="$(errors_in "$WORK/$name.log")"
	[ "$status" -eq 0 ] && [ -z "$found" ] && return 0
	echo "$found" | head -5
	fail "el arranque '$name' falló (salió con $status)"
}

boot menu --quit-after "$MENU_FRAMES"
boot empresa --quit-after "$COMPANY_FRAMES" -- --mode=company

SAVE="$(find "$WORK" -path '*saves/company/company.json' | head -1)"
[ -n "$SAVE" ] || fail "el arranque no llegó al mundo: no escribió saves/company/company.json"

timeout "$GUARD_SECONDS" "$GODOT" --headless --main-pack "$(native "$BUILD/TakeMyPackage.pck")" \
	--script "$(native "$ROOT/tools/export/probe_company.gd")" -- --mode=company >"$WORK/probe.log" 2>&1
status=$?
if [ "$status" -ne 0 ] || ! grep -q '^COMPANY_PROBE OK' "$WORK/probe.log"; then
	grep 'COMPANY_PROBE' "$WORK/probe.log" | head -10
	fail "la sonda terminó con $status"
fi

du -sh "$BUILD" | cut -f1 | sed 's/^/Build: /'
echo "Empresa OK"
