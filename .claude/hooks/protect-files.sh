#!/usr/bin/env bash
# PreToolUse (Edit/Write/MultiEdit/NotebookEdit):
#   - bloquea archivos que genera Godot (*.uid, *.import, .godot/) y el addon
#     de terceros godotsteam: editarlos a mano rompe referencias o se pisa solo;
#   - pide confirmación antes de tocar un archivo del dominio del otro
#     integrante (docs/colaboracion-equipo.md).
set -u
. "$(dirname "$0")/lib.sh"
read_hook_file
[ -n "$HOOK_FILE" ] || exit 0

case "$HOOK_FILE" in
	*.uid|*.import|*/.godot/*)
		echo "No edites $HOOK_REL a mano: lo genera Godot (se regenera al importar el proyecto). Si falta un .uid, corré el import (tools/run-tests.sh lo hace la primera vez)." >&2
		exit 2 ;;
	*/do-not-drop/addons/godotsteam/*)
		echo "do-not-drop/addons/godotsteam/ es el addon de terceros GodotSteam: no se edita, se actualiza bajando otra versión." >&2
		exit 2 ;;
esac

owner="$(current_owner)"
domain="$(file_domain "$HOOK_REL")"
if [ -n "$owner" ] && { [ "$domain" = nacho ] || [ "$domain" = slatex ]; } && [ "$domain" != "$owner" ]; then
	other="Nacho"; [ "$domain" = slatex ] && other="Slatex"
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s es del dominio de %s. Si lo tocás, dejá un aviso en docs/colaboracion-equipo.md (ver CONTRIBUTING.md, Dominios)."}}\n' "$HOOK_REL" "$other"
fi
exit 0
