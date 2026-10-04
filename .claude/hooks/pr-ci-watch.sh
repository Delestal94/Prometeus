#!/usr/bin/env bash
# PostToolUse (Bash y la herramienta MCP de GitHub que crea PRs): cuando se acaba
# de crear un PR, le pide a la sesión que lance el agente vigilante-ci con ese
# número, así ningún PR queda rojo esperando en la cola (pedido del usuario,
# 2026-10-04). Sin jq ni python, como el resto de los hooks.
set -u
input="$(cat)"

tool="$(printf '%s' "$input" | grep -oE '"tool_name" *: *"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')"
case "$tool" in
	Bash)
		# Solo `gh pr create`, no cualquier comando que nombre un PR.
		printf '%s' "$input" | grep -qE 'gh pr create' || exit 0
		;;
	mcp__github__create_pull_request) ;;
	*) exit 0 ;;
esac

pr="$(printf '%s' "$input" | grep -oE 'github\.com/[^/"]+/[^/"]+/pull/[0-9]+' | head -1 | grep -oE '[0-9]+$')"
if [ -z "$pr" ]; then
	pr="$(printf '%s' "$input" | grep -oE '\\?"number\\?" *: *[0-9]+' | head -1 | grep -oE '[0-9]+$')"
fi
[ -n "$pr" ] || exit 0

msg="Se creó el PR #$pr. Lanzá ahora el agente vigilante-ci con el número $pr y su rama: espera el CI, confirma el auto-merge si queda verde y arregla lo obvio si queda rojo. En una rutina, esperá su resultado antes de terminar la corrida; en una sesión interactiva, lanzalo en segundo plano y seguí."
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$msg"
exit 0
