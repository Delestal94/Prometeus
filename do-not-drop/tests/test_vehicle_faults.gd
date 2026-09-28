extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_faults.gd
##
## N-214.1: truck faults (gameplay/vehicle/vehicle_faults.gd), decided by the
## host from the relayed EventBus.vehicle_impact:
## - a soft knock never breaks anything; a hard hit may;
## - the same world seed and the same hits break the same thing on the same
##   hit (deterministic by seed);
## - at most max_faults_per_run per delivery, and run_started resets it;
## - repair() relays vehicle_fault_repaired and every peer's list clears it.

## Loaded at run time: the script uses the EventBus autoload, which a
## SceneTree test can't resolve while it compiles.
const VEHICLE_FAULTS_PATH: String = "res://scripts/gameplay/vehicle/vehicle_faults.gd"

var _failures: int = 0
var _started: Array = []
var _repaired: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	bus.connect(&"vehicle_fault_started", func(id: StringName, _at: Vector3) -> void: _started.append(id))
	bus.connect(&"vehicle_fault_repaired", func(id: StringName, how: StringName) -> void: _repaired.append([id, how]))
	var faults_script: Script = load(VEHICLE_FAULTS_PATH)
	var faults: Node = faults_script.new()
	root.add_child(faults)
	await process_frame

	# Soft knocks: nothing breaks, however many.
	faults.set(&"fault_chance", 1.0)
	for i: int in 20:
		bus.relay(&"vehicle_impact", [4.0, Vector3.ZERO])
	_expect(_started.is_empty(), "A pothole-sized knock never breaks anything")

	# A sure hard hit breaks one thing; the cap stops the rest.
	bus.relay(&"vehicle_impact", [12.0, Vector3(1, 0, 2)])
	bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	_expect(_started.size() == 1, "At most one fault per delivery (got %d)" % _started.size())
	var broken: StringName = _started[0] if not _started.is_empty() else &""
	_expect(broken in [&"rear_door", &"mirror"], "The fault is one of this version's two")
	_expect(bool(faults.call(&"is_broken", broken)), "Every peer's list has the fault")

	# Repair, relayed; a second repair does nothing.
	_expect(bool(faults.call(&"repair", broken, &"kit")), "The host can repair a broken fault")
	_expect(_repaired == [[broken, &"kit"]], "The repair is relayed with how it was done")
	_expect(not bool(faults.call(&"is_broken", broken)), "A repaired fault leaves the list")
	_expect(not bool(faults.call(&"repair", broken, &"kit")), "Repairing an intact part does nothing")
	bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	_expect(_started.size() == 1, "A repaired fault still counts toward the cap")

	# A new run resets the cap; with a cap of two, both faults can break, then no more.
	bus.emit_signal(&"run_started", &"test", [])
	faults.set(&"max_faults_per_run", 2)
	_started.clear()
	for i: int in 4:
		bus.relay(&"vehicle_impact", [12.0, Vector3.ZERO])
	_expect(_started.size() == 2 and _started[0] != _started[1],
			"Two different faults with a cap of two (got %s)" % [_started])

	# Deterministic by seed: same seed, same hits, same result.
	faults.set(&"fault_chance", 0.5)
	faults.set(&"max_faults_per_run", 1)
	var first: Array = _hits_with_seed(faults, network, 4242)
	var second: Array = _hits_with_seed(faults, network, 4242)
	_expect(first == second and not first.is_empty(), "Same seed and hits break the same thing on the same hit (%s vs %s)" % [first, second])
	var seen_any: bool = false
	for world_seed: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		seen_any = seen_any or not _hits_with_seed(faults, network, world_seed).is_empty()
	_expect(seen_any, "A 50% chance does break something across a few seeds")

	faults.queue_free()
	if _failures == 0:
		print("PASS: truck faults break on hard hits only, one per delivery, repeat by seed and repair on every peer")
	quit(_failures)


## Ten hard hits on a fresh run with world_seed: [hit index, fault] of what broke.
func _hits_with_seed(faults: Node, network: Node, world_seed: int) -> Array:
	network.set(&"world_seed", world_seed)
	faults.call(&"reset_for_run")
	_started.clear()
	var result: Array = []
	for i: int in 10:
		root.get_node(^"/root/EventBus").relay(&"vehicle_impact", [12.0, Vector3.ZERO])
		if not _started.is_empty() and result.is_empty():
			result = [i, _started[0]]
	return result


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
