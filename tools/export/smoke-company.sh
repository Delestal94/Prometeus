#!/usr/bin/env bash
# Smoke test of an exported build (D-2019): the two boots of the PC build routine, then a look inside the
# pack. Last line: "Empresa OK", or "Empresa FALLA: <why>" (the routine copies it to docs/rendimiento-pc.md),
# and the exit status is 0 only with "Empresa OK".
#
#   GODOT=<editor binary> tools/export/smoke-company.sh [folder of the build, builds/windows if left out]
#
# Windows (TakeMyPackage.exe, the PC build routine) or Linux (TakeMyPackage.x86_64, the release workflow, D-2020).
#   SMOKE_GUARD_SECONDS  seconds after which a boot counts as hung (150). A slow CI runner asks for more.
#   SMOKE_COMPANY_FRAMES frames of the company boot (6000). A machine that has not written the company's save
#                        by then asks for more (raise SMOKE_GUARD_SECONDS with it).
#   SMOKE_LOGS           folder that keeps menu.log, empresa.log and probe.log; left out, they go with the run.
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
# Headless there is nothing to draw and the engine sleeps between frames (~130 a second, measured on Windows):
# about a minute of the running game (45 to 70 s measured on Windows). A boot that ends earlier than the load
# only fails, it never passes.
COMPANY_FRAMES="${SMOKE_COMPANY_FRAMES:-6000}"
MENU_FRAMES=300
# The flag README.md gives players (main_menu.gd; --mode=company is its older alias).
COMPANY_FLAG='--autostart-company'
GUARD_SECONDS="${SMOKE_GUARD_SECONDS:-150}"
# A process that ignores the guard's TERM is killed this much later: a step of CI must end.
KILL_AFTER_SECONDS=10
ERRORS='SCRIPT ERROR|ERROR|Failed to load|Cannot open|Parse Error'
EXIT_LEAK='ERROR: [0-9]+ resources still in use at exit'
MENU_TRACK='mus_menu_loop\.ogg'

fail() {
	echo "Empresa FALLA: $1"
	exit 1
}

case "$GUARD_SECONDS" in
	'' | *[!0-9]* | 0*) fail "SMOKE_GUARD_SECONDS tiene que ser un entero positivo (vino '$GUARD_SECONDS')" ;;
esac
case "$COMPANY_FRAMES" in
	'' | *[!0-9]* | 0*) fail "SMOKE_COMPANY_FRAMES tiene que ser un entero positivo (vino '$COMPANY_FRAMES')" ;;
esac

EXE="$BUILD/TakeMyPackage.exe"
[ -f "$EXE" ] || EXE="$BUILD/TakeMyPackage.x86_64"
[ -f "$EXE" ] || fail "no hay ejecutable en $BUILD"
# A build unzipped without its permissions (Linux) would only say "exit 126".
[ -x "$EXE" ] || fail "$EXE no tiene permiso de ejecución"
[ -f "$BUILD/TakeMyPackage.pck" ] || fail "no hay TakeMyPackage.pck en $BUILD"
[ -n "${GODOT:-}" ] || fail "falta GODOT (el editor de la misma versión, para la sonda)"
# The probe runs from another folder (see below): a GODOT given as a path has to survive the cd.
case "$GODOT" in
	*/*) [ -f "$GODOT" ] && GODOT="$(cd "$(dirname "$GODOT")" && pwd)/$(basename "$GODOT")" ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export APPDATA XDG_DATA_HOME
APPDATA="$(native "$WORK")"
XDG_DATA_HOME="$WORK"
LOGS="${SMOKE_LOGS:-$WORK}"
mkdir -p "$LOGS" || fail "no se pudo crear la carpeta de logs ($LOGS)"
LOGS="$(cd "$LOGS" && pwd)"

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

# 124 is the guard's own status, 137 the kill that follows it: the process never quit by itself.
hung() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ]; }

boot() {
	local name="$1" status found
	shift
	timeout -k "$KILL_AFTER_SECONDS" "$GUARD_SECONDS" "$EXE" --headless --verbose "$@" >"$LOGS/$name.log" 2>&1
	status=$?
	hung "$status" && fail "el arranque '$name' no terminó en $GUARD_SECONDS s (salió con $status)"
	found="$(errors_in "$LOGS/$name.log")"
	[ "$status" -eq 0 ] && [ -z "$found" ] && return 0
	echo "$found" | head -20
	fail "el arranque '$name' falló (salió con $status)"
}

boot menu --quit-after "$MENU_FRAMES"
boot empresa --quit-after "$COMPANY_FRAMES" -- "$COMPANY_FLAG"

SAVE="$(find "$WORK" -path '*saves/company/company.json' | head -1)"
[ -n "$SAVE" ] || fail "el arranque no llegó al mundo: no escribió saves/company/company.json"

# From an empty folder: with a pack mounted by the editor, a res:// path the pack lacks falls through to the
# working directory. Run from do-not-drop/, the probe would find tests/ "in the pack" and fail a good build, and a
# file the export lost would be read from the source tree and pass.
mkdir "$WORK/empty"
(
	cd "$WORK/empty" || exit 2
	timeout -k "$KILL_AFTER_SECONDS" "$GUARD_SECONDS" "$GODOT" --headless \
		--main-pack "$(native "$BUILD/TakeMyPackage.pck")" \
		--script "$(native "$ROOT/tools/export/probe_company.gd")" -- "$COMPANY_FLAG" >"$LOGS/probe.log" 2>&1
)
status=$?
hung "$status" && fail "la sonda no terminó en $GUARD_SECONDS s (salió con $status)"
if [ "$status" -ne 0 ] || ! grep -q '^COMPANY_PROBE OK' "$LOGS/probe.log"; then
	grep 'COMPANY_PROBE' "$LOGS/probe.log" | head -10
	fail "la sonda terminó con $status"
fi

du -sh "$BUILD" | cut -f1 | sed 's/^/Build: /'
echo "Empresa OK"
