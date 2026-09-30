#!/usr/bin/env bash
# Proves each portable module works outside the game (docs/modulos.md): for
# every do-not-drop/modules/<name>/, builds an empty Godot project holding
# only that module and the modules its module.cfg depends on, imports it and
# runs the module's own tests/test_*.gd headless there. A module that passes
# can be copied into another project and will work; one that leans on the
# game fails here before anyone finds out the hard way.
#
#   tools/portability-check.sh                 # every module
#   tools/portability-check.sh synth_audio     # only these modules
#   tools/portability-check.sh -v ...          # print each failing test's log
#
# Env: GODOT (path to the Godot 4 console binary), TEST_TIMEOUT (seconds per
# test, 300), KEEP=1 keeps the temporary projects for a look.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/do-not-drop"
MODULES="$PROJECT/modules"
VERBOSE=0
FILTERS=()
for arg in "$@"; do
	case "$arg" in
		-v|--verbose) VERBOSE=1 ;;
		*) FILTERS+=("$arg") ;;
	esac
done

find_godot() {
	if [ -n "${GODOT:-}" ]; then echo "$GODOT"; return; fi
	for candidate in godot godot4 Godot_v4.7.2-stable_linux.x86_64; do
		if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return; fi
	done
	for candidate in "$HOME/godot/Godot_v4.7.2-stable_linux.x86_64" /d/Descargas/Godot_v4.7.2-stable_win64_console.exe "D:/Descargas/Godot_v4.7.2-stable_win64_console.exe"; do
		if [ -x "$candidate" ] || [ -f "$candidate" ]; then echo "$candidate"; return; fi
	done
}
GODOT_BIN="$(find_godot)"
if [ -z "$GODOT_BIN" ]; then
	echo "portability-check: no encuentro Godot. Definí GODOT=/ruta/al/Godot_v4.x_console" >&2
	exit 2
fi
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/tmp-portability-$$")"
mkdir -p "$WORK"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT

# depends=["a", "b"] from module.cfg, one name per line.
deps_of() {
	sed -n 's/^depends=\[\(.*\)\]$/\1/p' "$MODULES/$1/module.cfg" | tr ',' '\n' | sed 's/[" ]//g' | sed '/^$/d'
}

# The module and everything it depends on, transitively, one per line.
closure() {
	local pending=("$1") seen=" " name dep
	while [ ${#pending[@]} -gt 0 ]; do
		name="${pending[0]}"; pending=("${pending[@]:1}")
		case "$seen" in *" $name "*) continue ;; esac
		seen="$seen$name "
		echo "$name"
		while read -r dep; do
			[ -n "$dep" ] && pending+=("$dep")
		done < <(deps_of "$name")
	done
}

NAMES=()
for dir in "$MODULES"/*/; do
	name="$(basename "$dir")"
	[ -f "$dir/module.cfg" ] || continue
	if [ ${#FILTERS[@]} -gt 0 ]; then
		keep=0
		for filter in "${FILTERS[@]}"; do
			case "$name" in *"$filter"*) keep=1 ;; esac
		done
		[ $keep -eq 1 ] || continue
	fi
	NAMES+=("$name")
done
if [ ${#NAMES[@]} -eq 0 ]; then
	echo "portability-check: ningún módulo coincide con: ${FILTERS[*]}" >&2
	exit 2
fi

start=$(date +%s)
pass=0; fail=0
failed=()
for name in "${NAMES[@]}"; do
	sandbox="$WORK/$name"
	mkdir -p "$sandbox/modules"
	# An empty project with the game's renderer, nothing else: no autoloads,
	# no scripts, no assets. Exactly what a module lands in elsewhere.
	cat >"$sandbox/project.godot" <<EOF
; Empty project for the portability check of module "$name".
config_version=5

[application]

config/name="Portability check: $name"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
	while read -r member; do
		cp -R "$MODULES/$member" "$sandbox/modules/$member"
	done < <(closure "$name")
	# Import builds the global class cache: class_name resolves as it would
	# in any project that copied the folder in.
	import_log="$sandbox/import.log"
	timeout 600 "$GODOT_BIN" --headless --path "$sandbox" --import >"$import_log" 2>&1 || true
	module_pass=1
	for test in "$MODULES/$name"/tests/test_*.gd; do
		[ -f "$test" ] || continue
		test_name="$(basename "$test" .gd)"
		log="$sandbox/$test_name.log"
		data="$sandbox/userdata"
		mkdir -p "$data"
		data_native="$data"
		command -v cygpath >/dev/null 2>&1 && data_native="$(cygpath -w "$data")"
		APPDATA="$data_native" XDG_DATA_HOME="$data" \
			timeout "$TEST_TIMEOUT" "$GODOT_BIN" --headless --path "$sandbox" --script "res://modules/$name/tests/$test_name.gd" >"$log" 2>&1
		code=$?
		# The known Godot teardown crash after a PASS is not a failure.
		if [ $code -ne 0 ] && ! { [ $code -ge 128 ] && [ $code -ne 124 ] && grep -q "^PASS" "$log"; }; then
			module_pass=0
			echo "FAIL $name/$test_name (exit $code)"
			grep -E "^(ERROR|SCRIPT ERROR|Parse Error)" "$log" | sort | uniq | head -8 | sed 's/^/    /'
			if [ $VERBOSE -eq 1 ]; then
				sed 's/^/    | /' "$log" | tail -40
			fi
		fi
	done
	if [ $module_pass -eq 1 ]; then
		pass=$((pass + 1))
		echo "OK   $name"
	else
		fail=$((fail + 1))
		failed+=("$name")
	fi
done
elapsed=$(( $(date +%s) - start ))
echo "Modules: $pass/${#NAMES[@]} portable, $fail FAIL  (${elapsed}s)"
[ $fail -eq 0 ]
