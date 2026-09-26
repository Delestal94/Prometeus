extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_traps.gd
## Covers the three traps added in Fase 2. Package instances are kept out of
## the SceneTree so autoload startup is irrelevant, same as test_fragile.gd.

var _failures: int = 0


func _initialize() -> void:
	# root isn't in the tree yet this early, and the balance trap needs real
	# world transforms, so let one frame go by before building anything.
	await process_frame
	# In-tree packages honour the run gate, so impacts only land during a run.
	var run_manager: Node = root.get_node_or_null(^"/root/RunManager")
	if run_manager != null:
		run_manager.call(&"start_run")
	_test_growing_weight()
	_test_balance()
	_test_noisy()
	_test_shared_contract()
	if _failures == 0:
		print("PASS: growing weight, balance and noisy traps behave as designed")
	quit(_failures)


func _test_growing_weight() -> void:
	var package: RigidBody3D = _make_package("res://data/traps/growing_weight.tres")
	var trap: Resource = package.get(&"trap_behavior")
	var base_mass: float = package.mass

	_step(package, 7.0)
	_expect(is_equal_approx(package.mass, base_mass), "Weight holds steady inside the time limit")
	_expect(int(trap.call(&"get_state")) == 0, "Untouched but in time is still OK")

	_step(package, 3.0)
	_expect(package.mass > base_mass, "Weight grows once the timer runs out")

	# Solving the sequence puts it back to base weight.
	for direction: StringName in (trap.get(&"sequence") as Array[StringName]).duplicate():
		trap.call(&"press_direction", direction)
	_expect(is_equal_approx(float(trap.get(&"mass_multiplier")), 1.0), "Solving the sequence resets the weight")
	_expect(is_equal_approx(float(package.get(&"integrity")), 100.0), "A solved box reads full integrity")

	# A wrong press restarts the sequence instead of advancing it. The wrong
	# key has to differ from the *next* expected one, not just the first.
	var steps: Array[StringName] = (trap.get(&"sequence") as Array[StringName]).duplicate()
	trap.call(&"press_direction", steps[0])
	var wrong: StringName = &"up" if steps[1] != &"up" else &"down"
	trap.call(&"press_direction", wrong)
	_expect(int(trap.get(&"sequence_index")) == 0, "A wrong press sends the sequence back to the start")

	# Left alone long enough it becomes unmanageable.
	_step(package, 40.0)
	_expect(int(trap.call(&"get_state")) == 2, "Neglected long enough, the box is ruined")
	_expect(is_equal_approx(float(package.get(&"integrity")), 0.0), "A ruined box reads zero integrity")
	package.free()


func _test_balance() -> void:
	var package: RigidBody3D = _make_package("res://data/traps/balance.tres")
	var trap: Resource = package.get(&"trap_behavior")

	_step(package, 1.0)
	_expect(is_equal_approx(float(package.get(&"integrity")), 100.0), "Upright cargo takes no damage")
	_expect(int(trap.call(&"get_state")) == 0, "Upright cargo is OK")

	_tilt(package, 20.0)
	_step(package, 1.0)
	_expect(float(package.get(&"integrity")) < 100.0, "Past the safe angle it bleeds integrity")
	_expect(int(trap.call(&"get_state")) == 1, "A tilted box reports AT_RISK")

	# Holding steady pulls it back toward upright.
	var tilt_before: float = float(trap.get(&"tilt_degrees"))
	_step(package, 0.5, {"steady": true})
	_expect(float(trap.get(&"tilt_degrees")) < tilt_before, "Holding steady reduces the tilt")

	_tilt(package, 50.0)
	_step(package, 2.0)
	_expect(int(trap.call(&"get_state")) == 2, "Held past the danger angle it spills")
	package.free()


func _test_noisy() -> void:
	var package: RigidBody3D = _make_package("res://data/traps/noisy.tres")
	var trap: Resource = package.get(&"trap_behavior")

	package.call(&"apply_impact", 0.29)
	_expect(is_equal_approx(float(trap.get(&"agitation")), 0.0), "A gentle bump doesn't stir it")

	package.call(&"apply_impact", 0.30)
	_expect(is_equal_approx(float(trap.get(&"agitation")), 16.0), "A recorded shake adds tuned agitation")
	_expect(is_equal_approx(float(package.get(&"integrity")), 84.0), "Agitation reads on the shared integrity scale")

	# Unattended it settles slowly; calming is much faster.
	_step(package, 1.0)
	_expect(is_equal_approx(float(trap.get(&"agitation")), 11.0), "It settles 5/s on its own")
	_step(package, 1.0, {"calm": true})
	_expect(_about(float(trap.get(&"agitation")), 0.0), "Calming drains it at 16/s")

	for _index: int in range(7):
		package.call(&"apply_impact", 0.30)
	_expect(is_equal_approx(float(trap.get(&"agitation")), 100.0), "Agitation tops out at its maximum")
	_expect(int(trap.call(&"get_state")) == 1, "At max but not yet loose, it's AT_RISK")
	_step(package, 0.9)
	_expect(int(trap.call(&"get_state")) == 2, "Pinned at max long enough, it escapes")
	package.free()


func _test_shared_contract() -> void:
	# Every trap has to answer the same questions, or the HUD and the score
	# would need to special-case them.
	for path: String in [
		"res://data/traps/fragile.tres",
		"res://data/traps/growing_weight.tres",
		"res://data/traps/balance.tres",
		"res://data/traps/noisy.tres",
	]:
		var package: RigidBody3D = _make_package(path)
		var name: String = path.get_file()
		_expect(float(package.get(&"integrity")) > 0.0, "%s starts with integrity" % name)
		_expect(int(package.get(&"trap_state")) == 0, "%s starts OK" % name)
		_expect(String(package.call(&"get_hint")) != "", "%s offers a HUD hint" % name)
		package.free()


func _make_package(definition_path: String) -> RigidBody3D:
	# In the tree, because the balance trap reads world-space tilt and Godot
	# refuses global_transform on an orphan node -- same path as the real game.
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	package.set(&"trap_definition", load(definition_path))
	package.call(&"initialize_trap")
	return package


func _step(package: RigidBody3D, seconds: float, input: Dictionary = {}) -> void:
	var trap: Resource = package.get(&"trap_behavior")
	var step: float = 1.0 / 60.0
	var elapsed: float = 0.0
	while elapsed < seconds:
		trap.call(&"on_physics_process", package, step, {"input": input})
		elapsed += step


func _tilt(package: RigidBody3D, degrees: float) -> void:
	var transform: Transform3D = package.global_transform
	package.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(degrees)), transform.origin)


func _about(value: float, target: float, tolerance: float = 0.5) -> bool:
	return absf(value - target) <= tolerance


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
