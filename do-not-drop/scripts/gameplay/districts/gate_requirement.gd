class_name GateRequirement
extends Resource
## What closes a gate of the continuous map and what opens it (expansion D-0306).
##
## Data only, like ZoneDefinition: one .tres per gate in data/gates/, the same id
## ZoneDefinition.gates lists. Nothing here names autoloads or UI classes
## (lesson N-919); the answers come from plain values (the milestones, vehicles
## and equipment the company owns) so a test can ask without a scene.

enum Kind { BARRIER, ROADBLOCK, WATER, EQUIPMENT, ALTITUDE }

## Same id (and file name) as the .tres in data/gates/ (gate_<place>).
@export var id: StringName = &""
@export var kind: Kind = Kind.BARRIER
## Milestone (CompanyState.milestones_done) that opens it. Empty: none needed.
@export var milestone: StringName = &""
## Fleet key the company must own to cross (water: boat, altitude: plane).
@export var vehicle_key: StringName = &""
## Equipment ids the company must own (snow and volcano checkpoints).
@export var equipment: Array[StringName] = []
## Money that opens a roadblock without the milestone ("pay for the works"). 0: not for sale.
@export var cost: int = 0
## Map position (x, z) in meters from docs/expansion-distritos/diseno/mapa.md.
@export var position_xz: Vector2 = Vector2.ZERO


## Water and altitude are the edge of what a vehicle can cross: no wall, only a
## rule. Everything else is a body that stops whoever hits it.
func has_collision() -> bool:
	return kind != Kind.WATER and kind != Kind.ALTITUDE


## "" when the company meets every requirement, otherwise the translation key of
## the first thing missing (WORLD_GATE_NEEDS_*). `reason_args` receives the
## values to format it with.
func missing_key(owned: Dictionary, reason_args: Array = []) -> String:
	var missing: String = ""
	var args: Array = []
	var vehicles: Array = owned.get("vehicles", [])
	var gear: Array = owned.get("equipment", [])
	var done: Array = owned.get("milestones", [])
	if vehicle_key != &"" and not vehicles.has(vehicle_key):
		missing = "WORLD_GATE_NEEDS_VEHICLE"
		args = [str(vehicle_key)]
	if missing.is_empty():
		for item: StringName in equipment:
			if not gear.has(item):
				missing = "WORLD_GATE_NEEDS_EQUIPMENT"
				args = [str(item)]
				break
	if missing.is_empty() and milestone != &"" and not done.has(milestone):
		missing = "WORLD_GATE_NEEDS_MILESTONE"
		args = [str(milestone)]
	reason_args.clear()
	reason_args.append_array(args)
	return missing


func is_met(owned: Dictionary) -> bool:
	return missing_key(owned).is_empty()


## True when paying `cost` opens it even without the milestone (only that is
## missing: vehicle and equipment can't be bought on the spot).
func can_buy_open(owned: Dictionary, money: int) -> bool:
	if cost <= 0 or milestone == &"" or money < cost:
		return false
	var done: Array = owned.get("milestones", [])
	if done.has(milestone):
		return false
	var rest := duplicate() as GateRequirement
	rest.milestone = &""
	return rest.is_met(owned)
