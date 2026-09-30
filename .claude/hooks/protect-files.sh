#!/usr/bin/env bash
# PreToolUse (Edit/Write/MultiEdit/NotebookEdit):
#   - bloquea archivos que genera Godot (*.uid, *.import, .godot/) y el addon
#     de terceros godotsteam: editarlos a mano rompe referencias o se pisa solo;
#   - al tocar un archivo del dominio del otro integrante no frena: le
#     recuerda a Claude el aviso de qué cambió (docs/avisos/).
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
	# Decisión del usuario (2026-09-29): tocar el dominio del otro no se frena ni pide
	# confirmación (las rutinas corren sin nadie que conteste); se avisa. Este recordatorio
	# le llega a Claude para que el aviso vaya en el mismo commit.
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s es del dominio de %s: se puede tocar, pero en el mismo commit tiene que ir un aviso nuevo en docs/avisos/ (AAAA-MM-DD-tema.md) con qué cambió: archivo, función o señal, si cambió una firma y qué tiene que hacer %s."}}\n' "$HOOK_REL" "$other" "$other"
fi
exit 0
