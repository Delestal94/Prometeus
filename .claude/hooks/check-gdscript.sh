#!/usr/bin/env bash
# PostToolUse (Edit/Write/MultiEdit): revisa que el .gd recién editado compile,
# en medio segundo, antes de gastar un minuto en la batería de tests.
#   - Con Godot a mano y el proyecto importado: lo carga el propio motor con
#     los autoloads (check_script.gd), así que ve errores de sintaxis y de tipos.
#   - Si no: gdparse (gdtoolkit), que no conoce todo (p. ej. strings de varias
#     líneas en depot.gd), así que ahí solo avisa.
# Si el archivo es de la zona compartida, además le recuerda a Claude el aviso.
set -u
. "$(dirname "$0")/lib.sh"
read_hook_file
case "$HOOK_REL" in
	do-not-drop/*.gd) ;;
	*) exit 0 ;;
esac
[ -f "$HOOK_FILE" ] || exit 0
ROOT="$(repo_root)"
PROJECT="$ROOT/do-not-drop"
res="res://${HOOK_REL#do-not-drop/}"

godot="$(find_godot)"
if [ -n "$godot" ] && { [ -f "$godot" ] || command -v "$godot" >/dev/null 2>&1; } && [ -d "$PROJECT/.godot/imported" ]; then
	checker="$ROOT/.claude/hooks/check_script.gd"
	command -v cygpath >/dev/null 2>&1 && checker="$(cygpath -m "$checker")"
	out="$(timeout 60 "$godot" --headless --path "$PROJECT" --script "$checker" -- "$res" 2>&1)"
	code=$?
	# Un preload de un asset nuevo que todavía no se importó no es un error del script.
	errors="$(printf '%s\n' "$out" | grep -E -A1 '^(SCRIPT ERROR|ERROR)' | grep -vE 'has no resource loaders|Failed to load script|^--$')"
	if [ $code -ne 0 ] && [ -n "$errors" ]; then
		printf '%s no compila (Godot):\n%s\n' "$HOOK_REL" "$(printf '%s\n' "$errors" | head -12)" >&2
		exit 2
	fi
elif command -v gdparse >/dev/null 2>&1; then
	if ! out="$(gdparse "$HOOK_FILE" 2>&1)"; then
		printf 'gdparse (gdtoolkit) no pudo parsear %s. Puede ser sintaxis que gdtoolkit no conoce; si no ves el error, confirmalo con Godot:\n%s\n' "$HOOK_REL" "$(printf '%s\n' "$out" | head -8)" >&2
		exit 2
	fi
fi

if [ "$(file_domain "$HOOK_REL")" = compartida ]; then
	printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s es zona compartida: commit chico y aislado, preferir agregar antes que cambiar firmas, y aviso en docs/colaboracion-equipo.md."}}\n' "$HOOK_REL"
fi
exit 0
