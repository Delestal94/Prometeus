#!/bin/bash
# SessionStart (solo Claude Code en la web): deja la sesión en la nube lista para
# correr la batería headless y el lint de GDScript, igual que en una PC o en CI.
#   - Godot 4.7.2 (misma versión que .github/workflows/tests.yml) en ~/godot
#   - gdtoolkit (gdlint/gdformat) para el hook de lint
#   - el hook pre-push del repo (tools/setup-hooks.sh)
#   - el import de recursos hecho una vez, así el primer test no lo paga
# Idempotente: si ya está todo, no descarga nada.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
GODOT_VERSION="4.7.2"
GODOT_DIR="$HOME/godot"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64"

if [ ! -x "$GODOT_BIN" ]; then
	mkdir -p "$GODOT_DIR"
	zip="$(mktemp --suffix=.zip)"
	curl -fsSL --retry 4 -o "$zip" \
		"https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
	python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$GODOT_DIR"
	rm -f "$zip"
	chmod +x "$GODOT_BIN"
fi

if ! command -v gdlint >/dev/null 2>&1; then
	pip install --quiet --disable-pip-version-check --root-user-action=ignore "gdtoolkit==4.*" >&2
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	echo "export GODOT=\"$GODOT_BIN\"" >>"$CLAUDE_ENV_FILE"
fi

bash "$ROOT/tools/setup-hooks.sh" >&2

if [ ! -d "$ROOT/do-not-drop/.godot/imported" ]; then
	timeout 600 "$GODOT_BIN" --headless --path "$ROOT/do-not-drop" --import >/dev/null 2>&1 || true
fi
