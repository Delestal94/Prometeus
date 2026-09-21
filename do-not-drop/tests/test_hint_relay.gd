extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_hint_relay.gd
## Verifies the bug fixed this pass: a package's hint text now reaches
## EventBus (and so every client's HUD) instead of staying something only
## the package's own local, host-only trap_behavior knows about. Runs real
## physics frames rather than faking them, since the relay throttle lives
## inside _integrate_forces.

var _failures: int = 0
var _received: Array = []


func _initialize() -> void:
	await process_frame
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.call(&"start_run")

	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"package_hint_changed", func(id: StringName, hint: String) -> void:
		_received.append([id, hint]))

	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/growing_weight.tres"))
	root.add_child(package)
	await process_frame
	package.call(&"initialize_trap")

	package.call(&"report_to_run")
	_expect(_received.size() == 1, "report_to_run sends an immediate hint (got %d events)" % _received.size())
	if not _received.is_empty():
		_expect(not String(_received[0][1]).is_empty(), "The initial hint isn't blank")

	# Real physics frames, package unfrozen: this is what actually drives
	# _integrate_forces and, inside it, the hint relay throttle.
	package.freeze = false
	for _i in range(60):  # ~1s at 60Hz -- well past the 0.25s throttle
		await physics_frame
	_expect(_received.size() >= 2, "the throttle fires again after ~1s of real physics (got %d events total)" % _received.size())

	package.free()
	if _failures == 0:
		print("PASS: package hints report to the run immediately and relay again on a throttle")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
