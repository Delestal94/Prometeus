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
## the driver's mirror breaks off (VehicleFaultEffects, on every peer). The
## fixes are N-214.3.

## Every fault this version can roll, in roll order.
const FAULTS: Array[StringName] = [&"rear_door", &"mirror"]
## Preloaded, not by class_name: a new global class isn't in the class cache
## until the editor imports again, and headless runs load this first.
const EFFECTS: Script = preload("res://scripts/gameplay/vehicle/vehicle_fault_effects.gd")
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


func _on_fault_repaired(fault_id: StringName, _method: StringName) -> void:
	active.erase(fault_id)
