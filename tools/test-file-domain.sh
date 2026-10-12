#!/usr/bin/env bash
# Checks file_domain in .claude/hooks/lib.sh (who owns a file, the table of
# docs/colaboracion-equipo.md) without Godot, under a second: one file of each
# expansion folder of D-0220 is Nacho's, and the old owners did not move
# (a vehicle script is Nacho's, a player script Slatex's, a module shared).
# CI runs it in the lint job.
#
#   tools/test-file-domain.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../.claude/hooks/lib.sh
. "$ROOT/.claude/hooks/lib.sh"
failures=0

check() {
	local file="$1" want="$2" got
	got="$(file_domain "$file")"
	if [ "$got" != "$want" ]; then
		echo "FAIL: $file -> '$got', expected '$want'"
		failures=$((failures + 1))
	fi
}

for f in \
	do-not-drop/scripts/core/company/company_state.gd \
	do-not-drop/scripts/gameplay/business/inventory.gd \
	do-not-drop/scripts/gameplay/districts/zone_definition.gd \
	do-not-drop/scripts/gameplay/fleet/vehicle_definition.gd \
	do-not-drop/scenes/company/company_world.tscn \
	do-not-drop/data/products/hen.tres \
	do-not-drop/data/zones/centro.tres \
	do-not-drop/data/vehicles/van.tres \
	do-not-drop/data/boxes/box_m.tres \
	do-not-drop/data/suppliers/distribuidora_central.tres \
	do-not-drop/data/gates/gate_puerto.tres \
	do-not-drop/data/order_requirements/fragile.tres \
	do-not-drop/data/placeables/shelf.tres; do
	check "$f" nacho
done
check do-not-drop/scripts/gameplay/vehicle/vehicle.gd nacho
check do-not-drop/scripts/gameplay/player/player.gd slatex
check do-not-drop/modules/day_clock/day_clock.gd compartida
check do-not-drop/scripts/core/event_bus.gd compartida
check do-not-drop/data/contents/hen.tres ""

if [ "$failures" -gt 0 ]; then
	echo "test-file-domain: $failures failure(s)"
	exit 1
fi
echo "test-file-domain: OK"
