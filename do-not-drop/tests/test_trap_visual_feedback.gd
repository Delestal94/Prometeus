extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trap_visual_feedback.gd
## Covers items #24 and #26 of docs/especificaciones-visuales.md: Peso
## Creciente and Ruidoso used to only exist as numbers (integrity/HUD text),
## with no visible reaction on the crate itself. Exercises
## package_feedback.gd's own reaction directly, the same way test_ping.gd
## calls EventBus.request_ping() directly -- the traps' own internal math
## (does mass_multiplier actually grow, does agitation actually rise) is
## already covered by test_traps.gd; this is only about what the crate does
## once package_integrity_changed reports that distress.
## (#25, Equilibrio visibly tilting, needs no new code: the package is a
## real RigidBody3D and the trap already rotates its actual global_transform,
## so whatever angle physics puts it at is what renders -- nothing to test
## here that test_traps.gd's tilt assertions don't already cover.)

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_growing_weight_visuals()
	_test_noisy_wobble()
	if _failures == 0:
		print("PASS: Peso Creciente visibly swells and sinks, Ruidoso visibly shudders")
	quit(_failures)


func _test_growing_weight_visuals() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/growing_weight.tres"))
	root.add_child(package)
	await process_frame

	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var box: MeshInstance3D = package.get_node(^"Box")
	_expect(box.scale.is_equal_approx(Vector3.ONE), "Starts at normal size")

	var package_id: StringName = package.get(&"package_id")
	feedback.call(&"_on_integrity_changed", package_id, 100.0, 100.0)
	_expect(box.scale.is_equal_approx(Vector3.ONE) and is_equal_approx(box.position.y, 0.0),
		"No distress, no swelling")

	feedback.call(&"_on_integrity_changed", package_id, 35.0, 100.0)  # 65% distress
	_expect(box.scale.x > 1.15, "The crate visibly swells as it gets heavier (got scale %.2f)" % box.scale.x)
	_expect(box.position.y < -0.03, "And visibly sinks under its own growing weight")

	feedback.call(&"_on_integrity_changed", package_id, 0.0, 100.0)  # about to fail
	_expect(is_equal_approx(box.scale.x, 1.35), "Reaches its full swelled size right at the failure edge")

	package.free()


func _test_noisy_wobble() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/noisy.tres"))
	root.add_child(package)
	await process_frame

	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var box: MeshInstance3D = package.get_node(^"Box")
	var base: Vector3 = box.position
	var package_id: StringName = package.get(&"package_id")

	feedback.call(&"_process", 1.0 / 60.0)
	_expect(box.position.is_equal_approx(base), "Calm box (no distress reported yet) doesn't wobble")

	feedback.call(&"_on_integrity_changed", package_id, 30.0, 100.0)  # agitated
	var moved: bool = false
	for _i: int in range(10):
		feedback.call(&"_process", 1.0 / 60.0)
		if not box.position.is_equal_approx(base):
			moved = true
	_expect(moved, "An agitated box visibly shudders instead of sitting dead still")

	feedback.call(&"_on_integrity_changed", package_id, 100.0, 100.0)  # calmed down
	feedback.call(&"_process", 1.0 / 60.0)
	_expect(box.position.is_equal_approx(base), "Calming back down snaps the wobble back to rest, no drift left behind")

	package.free()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
