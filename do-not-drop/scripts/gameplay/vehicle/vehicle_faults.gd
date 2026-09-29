extends Node
class_name VehicleFaults
## Truck faults the kit can fix (tareas de Nacho N-214.1). Lives next to the
## van, not inside it: vehicle.gd is frozen, so this only listens to the
## relayed EventBus.vehicle_impact it already sends.
##
## The host decides: a hard hit (strength >= hard_hit_strength) may break
## one thing, at most max_faults_per_run per delivery, rolled from the
## session's world seed so the same run with the same hits breaks the same
## things. The decision goes out as EventBus.vehicle_fault_started and every
## peer keeps the same list of active faults from it; repair() does the same
## with vehicle_fault_repaired.
##
## critico-diseno's verdict (N-704.3) caps the first version at two faults
## (the rear door that swings open and the fallen mirror), one per delivery,
## none of them ending the run. N-214.2 gives them their effect: the rear
## door won't stay latched (the host swings it open on the hit and again on
## every bump while it's broken, and the crew has to keep closing it), and
## the driver's mirror breaks off (VehicleFaultEffects, on every peer).
## N-214.3 fixes them at a repair spot on the van (FaultRepairSpot): the
## rear door is tied shut with a strap from the shared kit; the depot's
## spare part (CrewProgression.SUPPLIES "spare_part") fixes either one when
## the kit can't. The mirror's improvised fix (a passenger's phone) is pending.

## Every fault this version can roll, in roll order.
const FAULTS: Array[StringName] = [&"rear_door", &"mirror"]
## Preloaded, not by class_name: a new global class isn't in the class cache
## until the editor imports again, and headless runs load this first.
const EFFECTS: Script = preload("res://scripts/gameplay/vehicle/vehicle_fault_effects.gd")
const REPAIR_SPOT: Script = preload("res://scripts/gameplay/vehicle/fault_repair_spot.gd")
## The improvised fix from the shared kit (RunManager.care_supplies), per
## fault. No new tools: only what the kit already carries.
const IMPROVISED: Dictionary = {&"rear_door": &"strap"}
## Repair spot prompt per fault and method. Spelled out, not built, so the
## translation test finds every key in use.
const REPAIR_PROMPTS: Dictionary = {
	&"rear_door": {&"spare": "WORLD_FAULT_REAR_DOOR_SPARE", &"strap": "WORLD_FAULT_REAR_DOOR_STRAP"},
	&"mirror": {&"spare": "WORLD_FAULT_MIRROR_SPARE"},
}
## Where each repair spot hangs, in the van's frame: the rear door's right
## post (the rescue hook has the left one, the door control the middle), and
## the driver's mirror (moved onto the model's mirror when it's there).
const SPOT_POSITIONS: Dictionary = {
	&"rear_door": Vector3(0.85, 1.1, 4.3),
	&"mirror": Vector3(-1.2, 1.9, -2.4),
}
## Mixed into the world seed so faults don't share their sequence with other
## seeded rolls of the run.
const SEED_SALT: int = 214

## Impact strength (m/s of velocity change, as vehicle.gd measures it) that
## counts as a hard hit. The same one that makes the cabin's picture shake
## (vehicle_effects.gd ABERRATION_MIN_STRENGTH): a crash, not a pothole.
var hard_hit_strength: float = 9.0
## Chance that a hard hit breaks something, while under the cap.
var fault_chance: float = 0.5
var max_faults_per_run: int = 1
## While the rear door is broken, a bump this hard knocks its latch open
## again: a badén or a curb does it, not just a crash. Above the 3.0 floor
## vehicle.gd reports impacts from, so the lightest knocks don't.
var door_pop_strength: float = 4.5

## The van whose parts break. LevelCommon sets it before adding the node;
## null (the rolls-only test) leaves just the list.
var vehicle: Node3D

## Every peer: fault_id -> true while it's broken.
var active: Dictionary = {}
## Host-only: faults decided since the run started (repaired ones count too).
var faults_this_run: int = 0
## Host-only: times the broken rear door swung open by itself this run.
var door_pops: int = 0
## Every peer: spare parts the run took from the depot, one per fix. Kept
## until the run ends, not reset by run_started (the depot hands them over
## around the same moment).
var spares: int = 0
## fault_id -> its FaultRepairSpot on the van (none without a van).
var spots: Dictionary = {}
var effects: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.vehicle_impact.connect(_on_vehicle_impact)
	EventBus.run_started.connect(_on_run_started)
	EventBus.vehicle_fault_started.connect(_on_fault_started)
	EventBus.vehicle_fault_repaired.connect(_on_fault_repaired)
	effects = EFFECTS.new()
	effects.name = "Effects"
	effects.set(&"vehicle", vehicle)
	add_child(effects)
	add_to_group(&"vehicle_faults")
	EventBus.run_ended.connect(func(_score: int, _results: Dictionary) -> void: _set_spares(0))
	_hang_repair_spots()
	reset_for_run()


## Back to an intact van with a fresh roll sequence from the world seed.
func reset_for_run() -> void:
	active.clear()
	faults_this_run = 0
	door_pops = 0
	_rng.seed = hash([NetworkManager.world_seed, SEED_SALT])


func is_broken(fault_id: StringName) -> bool:
	return active.has(fault_id)


## Host-only: fixes a fault (whoever fixed it, officially or with the kit)
## and tells every peer. Returns false if it wasn't broken.
func repair(fault_id: StringName, method: StringName) -> bool:
	if not NetworkManager.is_host() or not active.has(fault_id):
		return false
	EventBus.relay(&"vehicle_fault_repaired", [fault_id, method])
	return true


## Host-only: the run leaving the depot took spare parts (depot.gd begin_run).
func stock_spares(count: int) -> void:
	if not NetworkManager.is_host():
		return
	_set_spares(count)
	if NetworkManager.is_online():
		_set_spares.rpc(count)


@rpc("authority", "call_remote", "reliable")
func _set_spares(count: int) -> void:
	spares = maxi(0, count)


## How the crew would fix fault_id right now: the kit supply of its
## improvised fix, else &"spare", or &"" if it isn't broken or there's
## nothing to fix it with. The kit goes first so the paid spare is kept for
## a fault the kit can't fix (the mirror).
func repair_method(fault_id: StringName) -> StringName:
	if not active.has(fault_id):
		return &""
	var tool: StringName = IMPROVISED.get(fault_id, &"")
	if not tool.is_empty() and RunManager.care_supply_count(tool) > 0:
		return tool
	if spares > 0:
		return &"spare"
	return &""


## Translation key of the repair spot's prompt, or "" when it can't be fixed.
func repair_prompt(fault_id: StringName) -> String:
	var method: StringName = repair_method(fault_id)
	if method.is_empty():
		return ""
	return String((REPAIR_PROMPTS.get(fault_id, {}) as Dictionary).get(method, ""))


## Host-only: fixes fault_id the best way available (repair_method()) and
## spends what it took. Returns false if it couldn't.
func fix(fault_id: StringName) -> bool:
	if not NetworkManager.is_host():
		return false
	var method: StringName = repair_method(fault_id)
	if method.is_empty():
		return false
	if method != &"spare" and not RunManager.consume_care_supply(method):
		return false
	return repair(fault_id, method)


func _hang_repair_spots() -> void:
	if vehicle == null:
		return
	for fault_id: StringName in FAULTS:
		var spot: Interactable = REPAIR_SPOT.new()
		spot.name = "FaultRepair_%s" % fault_id
		spot.set(&"fault_id", fault_id)
		spot.set(&"faults", self)
		spot.position = SPOT_POSITIONS[fault_id]
		vehicle.add_child(spot)
		spots[fault_id] = spot
	var mirror: Array = effects.call(&"driver_mirror_parts")
	if not mirror.is_empty():
		var part: Node3D = mirror[0]
		spots[&"mirror"].position = vehicle.to_local(part.global_position) \
				if part.is_inside_tree() and vehicle.is_inside_tree() else part.position


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	reset_for_run()


func _on_vehicle_impact(strength: float, impact_position: Vector3) -> void:
	if not NetworkManager.is_host():
		return
	if active.has(&"rear_door") and strength >= door_pop_strength:
		_pop_rear_door()
	if strength < hard_hit_strength:
		return
	if faults_this_run >= max_faults_per_run:
		return
	var candidates: Array[StringName] = []
	for fault_id: StringName in FAULTS:
		if not active.has(fault_id):
			candidates.append(fault_id)
	if candidates.is_empty():
		return
	# Both rolls every hard hit, so the sequence only depends on the hits.
	var roll: float = _rng.randf()
	var pick: int = _rng.randi_range(0, candidates.size() - 1)
	if roll >= fault_chance:
		return
	faults_this_run += 1
	EventBus.relay(&"vehicle_fault_started", [candidates[pick], impact_position])


func _on_fault_started(fault_id: StringName, _impact_position: Vector3) -> void:
	active[fault_id] = true
	if fault_id == &"rear_door" and NetworkManager.is_host():
		_pop_rear_door()


## Host-only: the broken latch lets go. The van's synchronizer carries the
## open door to every peer, and with it the N-213 overboard risk.
func _pop_rear_door() -> void:
	if vehicle == null or not vehicle.has_method(&"set_rear_cargo_open"):
		return
	if bool(vehicle.call(&"is_door_open", &"rear")):
		return
	vehicle.call(&"set_rear_cargo_open", true)
	door_pops += 1


func _on_fault_repaired(fault_id: StringName, method: StringName) -> void:
	active.erase(fault_id)
	if method == &"spare":
		spares = maxi(0, spares - 1)
