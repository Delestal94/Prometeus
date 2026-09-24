# Helpers compartidos por los hooks de Claude Code de este repo. Sin jq ni
# python: tienen que andar igual en Linux, en la nube y en Git Bash de Windows.

# Lee el JSON del hook por stdin y deja en HOOK_FILE la ruta del archivo que la
# herramienta va a tocar / tocó (vacío si no hay), con barras normales.
read_hook_file() {
	local input
	input="$(cat)"
	HOOK_FILE="$(printf '%s' "$input" | grep -o '"\(file_path\|notebook_path\)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
		| sed 's/^[^:]*:[[:space:]]*"//; s/"$//; s#\\\\#/#g')"
	# Ruta relativa a la raíz del repo, si cae adentro.
	HOOK_REL="${HOOK_FILE#"$(repo_root)"/}"
	case "$HOOK_REL" in
		/*|?:/*) HOOK_REL="$(printf '%s' "$HOOK_REL" | sed -n 's#.*/\(do-not-drop/.*\|docs/.*\|tools/.*\)#\1#p')" ;;
	esac
}

repo_root() {
	if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
		printf '%s' "$CLAUDE_PROJECT_DIR" | sed 's#\\#/#g'
	else
		cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
	fi
}

# Misma búsqueda que tools/run-tests.sh, más la instalación del hook de la nube.
find_godot() {
	if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
	local candidate
	for candidate in godot godot4 Godot_v4.7.2-stable_linux.x86_64; do
		if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return; fi
	done
	for candidate in "$HOME/godot/Godot_v4.7.2-stable_linux.x86_64" /d/Descargas/Godot_v4.7.2-stable_win64_console.exe "D:/Descargas/Godot_v4.7.2-stable_win64_console.exe"; do
		if [ -f "$candidate" ]; then echo "$candidate"; return; fi
	done
}

# nacho | slatex | vacío. TMP_DUENO manda (ponelo en .claude/settings.local.json,
# "env"); si no, se deduce del mail de git.
current_owner() {
	if [ -n "${TMP_DUENO:-}" ]; then echo "$TMP_DUENO"; return; fi
	case "$(git -C "$(repo_root)" config user.email 2>/dev/null)" in
		delestal.miguelignacio@gmail.com) echo nacho ;;
		skater.devil@gmail.com) echo slatex ;;
	esac
}

# Dueño de un archivo según docs/colaboracion-equipo.md: nacho | slatex |
# compartida | vacío (libre).
file_domain() {
	case "$1" in
		do-not-drop/scenes/gameplay/vehicle/*|do-not-drop/scripts/gameplay/vehicle/*|\
		do-not-drop/scenes/gameplay/route/*|do-not-drop/scripts/gameplay/route/*|\
		do-not-drop/scripts/gameplay/depot/*|\
		do-not-drop/scripts/presentation/vehicle_presentation.gd|docs/tareas-nacho.md)
			echo nacho ;;
		do-not-drop/scenes/gameplay/player/*|do-not-drop/scripts/gameplay/player/*|\
		do-not-drop/scenes/gameplay/package/*|do-not-drop/scripts/gameplay/package/*|\
		do-not-drop/scripts/gameplay/traps/*|do-not-drop/scripts/gameplay/interaction/*|\
		do-not-drop/scripts/ui/*|docs/tareas-slatex.md|docs/controles-y-ui.md)
			echo slatex ;;
		do-not-drop/scripts/core/event_bus.gd|do-not-drop/scripts/core/network_manager.gd|\
		do-not-drop/scripts/core/run_manager.gd|\
		do-not-drop/scripts/presentation/first_person_camera.gd|\
		do-not-drop/scripts/presentation/render_layers.gd|\
		do-not-drop/scripts/presentation/synth_audio.gd|\
		do-not-drop/scripts/gameplay/level_base.gd|do-not-drop/scenes/gameplay/level_base.tscn|\
		do-not-drop/project.godot)
			echo compartida ;;
	esac
}
