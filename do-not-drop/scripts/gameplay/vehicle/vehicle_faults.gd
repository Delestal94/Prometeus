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
## none of them ending the run. Their visible effects and the fixes are
## N-214.2 and N-214.3.

## Every fault this version can roll, in roll order.
const FAULTS: Array[StringName] = [&"rear_door", &"mirror"]
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

## Every peer: fault_id -> true while it's broken.
var active: Dictionary = {}
## Host-only: faults decided since the run started (repaired ones count too).
var faults_this_run: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.vehicle_impact.connect(_on_vehicle_impact)
	EventBus.run_started.connect(_on_run_started)
	EventBus.vehicle_fault_started.connect(_on_fault_started)
	EventBus.vehicle_fault_repaired.connect(_on_fault_repaired)
	reset_for_run()


## Back to an intact van with a fresh roll sequence from the world seed.
func reset_for_run() -> void:
	active.clear()
	faults_this_run = 0
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
	if not NetworkManager.is_host() or strength < hard_hit_strength:
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


func _on_fault_repaired(fault_id: StringName, _method: StringName) -> void:
	active.erase(fault_id)
