#!/usr/bin/env bash
# Smoke test of an exported build (D-2019): the two boots of the PC build routine, then a look inside the
# pack. Last line: "Empresa OK", or "Empresa FALLA: <why>" (the routine copies it to docs/rendimiento-pc.md).
#
#   GODOT=<editor binary> tools/export/smoke-company.sh [builds/windows]
#
# Each boot ends itself with --quit-after: killing the exe with `timeout` makes the engine log dozens of
# "ERROR: BUG: Unreferenced static string" on its way out (Windows), so "no ERROR in the log" could never
# pass. `timeout` stays only as the guard against a hang. A quiet log proves little by itself, so the boot
# must also write the company's save, and tools/export/probe_company.gd must find the world up inside the
# pack. Runs on a user folder of its own: the real saves are never read or touched.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(cd "${1:-$ROOT/builds/windows}" && pwd)" || exit 2
# ~55 s of the running game, headless. A boot that ends earlier than the load only fails, it never passes.
COMPANY_FRAMES=6000
MENU_FRAMES=300
GUARD_SECONDS=150
BOOT_TRIES=3
ERRORS='SCRIPT ERROR|ERROR|Failed to load|Cannot open|Parse Error'

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

# Up to BOOT_TRIES: a real problem fails every one of them. The menu's music can be caught mid-mix as the
# engine closes ("1 resources still in use at exit", AudioServer's playback of mus_menu_loop.ogg, 5 of 8 boots
# on a used user folder): an engine race at exit, nothing the game holds.
boot() {
	local name="$1" status try
	shift
	for ((try = 1; try <= BOOT_TRIES; try++)); do
		timeout "$GUARD_SECONDS" "$EXE" --headless "$@" >"$WORK/$name.log" 2>&1
		status=$?
		if [ "$status" -eq 0 ] && ! grep -qE "$ERRORS" "$WORK/$name.log"; then
			return 0
		fi
	done
	grep -E "$ERRORS" "$WORK/$name.log" | head -5
	fail "el arranque '$name' falló $BOOT_TRIES veces (la última con $status)"
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
