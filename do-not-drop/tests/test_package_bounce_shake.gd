extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_bounce_shake.gd
## Covers items #22 (settle bounce) and #23 (impact shake) of
## docs/especificaciones-visuales.md.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var run_manager: Node = root.get_node(^"/root/RunManager")
	run_manager.call(&"start_run")
	_test_settle_bounce()
	_test_impact_shake()
	_test_bounce_and_growth_dont_fight()
	if _failures == 0:
		print("PASS: packages bounce when placed and shudder on impact, independent of trap type")
	quit(_failures)


func _test_settle_bounce() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	package.global_position = Vector3(0.0, 2.0, 0.0)
	await process_frame
	var box: Node3D = package.get_node(^"Box")
	_expect(box.scale.is_equal_approx(Vector3.ONE), "Box starts at normal scale")

	var mount := Node3D.new()
	mount.global_position = Vector3(1.0, 0.0, 0.0)
	root.add_child(mount)
	package.call(&"place_at", mount)

	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var squashed: bool = false
	for _i: int in range(30):
		feedback.call(&"_process", 1.0 / 60.0)
		if not box.scale.is_equal_approx(Vector3.ONE):
			squashed = true
	_expect(squashed, "Being placed actually bounces the box, not an instant lock into place")

	for _i: int in range(60):
		feedback.call(&"_process", 1.0 / 60.0)
	_expect(box.scale.is_equal_approx(Vector3.ONE), "The bounce settles back to normal scale on its own")
	package.free()
	mount.free()


func _test_impact_shake() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	await process_frame
	var box: Node3D = package.get_node(^"Box")
	var base: Vector3 = box.position
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")

	feedback.call(&"_process", 1.0 / 60.0)
	_expect(box.position.is_equal_approx(base), "No shake before any hit")

	package.call(&"apply_impact", 5.0)  # fragile: well under the ruin threshold, just a hit
	var shook: bool = false
	for _i: int in range(10):
		feedback.call(&"_process", 1.0 / 60.0)
		if not box.position.is_equal_approx(base):
			shook = true
	_expect(shook, "A hit rattles the box on its own mesh, not only the camera shake")

	for _i: int in range(60):
		feedback.call(&"_process", 1.0 / 60.0)
	_expect(box.position.is_equal_approx(base), "The shake decays back to rest on its own")
	package.free()


## Peso Creciente's own growth-scale and the settle bounce both touch Box's
## scale -- confirms _update_box_scale() actually composes them instead of
## one silently overwriting the other.
func _test_bounce_and_growth_dont_fight() -> void:
	var package: RigidBody3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/growing_weight.tres"))
	root.add_child(package)
	await process_frame
	var box: Node3D = package.get_node(^"Box")
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	var package_id: StringName = package.get(&"package_id")

	feedback.call(&"_on_integrity_changed", package_id, 35.0, 100.0)  # partway grown
	feedback.call(&"_process", 1.0 / 60.0)
	var grown_scale: float = box.scale.x
	_expect(grown_scale > 1.0, "Growth alone already scaled the box up")

	feedback.call(&"_on_package_placed", package_id)
	feedback.call(&"_process", 1.0 / 60.0)
	_expect(not is_equal_approx(box.scale.x, grown_scale),
		"The bounce visibly modulates the already-grown scale instead of one effect erasing the other")

	for _i: int in range(60):
		feedback.call(&"_process", 1.0 / 60.0)
	_expect(is_equal_approx(box.scale.x, grown_scale),
		"Once the bounce ends, the box settles back to exactly the grown scale, not reset to 1.0")
	package.free()




func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
