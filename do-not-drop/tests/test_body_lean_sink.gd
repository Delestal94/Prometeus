extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_body_lean_sink.gd
## Covers items #21 (exaggerated body roll/pitch) and #96 (cargo sink) of
## docs/tareas-nacho.md / docs/especificaciones-visuales.md. Both only touch
## BodyVisuals, a purely cosmetic sibling of the real physics chassis, never
## the VehicleBody3D's own transform.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.start_debug_delivery()
	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false  # deterministic driver, same trick every vehicle test uses
	var visual: Node3D = van.get_node(^"VehiclePresentation")
	var body: Node3D = van.get_node(^"BodyVisuals")
	# Lean and sink are for viewers outside the truck; from inside it (seat or
	# aisle) the interior must stay put against the physics. Watch from the
	# dev third-person camera, as another player by the road would.
	visual.call(&"_toggle_dev_camera")

	_test_lean(van, visual, body)
	_test_sink(level, van, visual, body)

	level.free()
	if _failures == 0:
		print("PASS: the exterior shell leans into corners/braking and sinks with cargo weight, physics untouched")
	quit(_failures)


func _test_lean(van: VehicleBody3D, visual: Node3D, body: Node3D) -> void:
	_expect(body.rotation.is_equal_approx(Vector3.ZERO), "No lean while parked")

	van.set_controls(0.9, 0.0, false)
	for _i: int in range(90):
		await physics_frame
	var physics_transform_before: Transform3D = van.transform
	van.set_controls(0.9, 1.0, false)
	for _i: int in range(40):
		await physics_frame
	_expect(absf(body.rotation.z) > 0.01, "Steering into a turn at speed rolls the exterior shell")
	_expect(van.transform.origin.is_equal_approx(physics_transform_before.origin) == false,
		"Sanity check: the van is actually moving during this (otherwise the roll test proves nothing)")
	# Whatever BodyVisuals does, the real physics body's own transform is a
	# sibling, untouched by this presentation-only effect.
	var chassis_collision: CollisionShape3D = van.get_node(^"ChassisCollision")
	_expect(chassis_collision.position == Vector3(0, -0.03, 0.8), "Physics collision shapes are never moved by lean/sink")

	van.set_controls(0.0, 0.0, true)
	for _i: int in range(30):
		await physics_frame
	_expect(body.rotation.x < -0.005, "Hard braking dips the nose down")


func _test_sink(level: Node, van: VehicleBody3D, visual: Node3D, body: Node3D) -> void:
	var package: Node = level.get_node(^"World/Package")
	var baseline_sink: float = body.position.y
	_expect(is_equal_approx(baseline_sink, 0.0) or baseline_sink < 0.0, "Some baseline sink from the loaded starter package is fine")

	# A heavier load should visibly sink the body further than the light
	# starter package alone -- bypass the growing_weight puzzle entirely and
	# just set the mass directly, since this test is about the presentation
	# reacting to mass, not about the trap that changes it.
	package.set(&"mass", 60.0)
	for _i: int in range(60):
		visual.call(&"update_presentation", 1.0 / 60.0)
	_expect(body.position.y < baseline_sink - 0.02, "Heavier cargo visibly sinks the body further")

	package.set(&"is_loaded", false)
	for _i: int in range(120):
		visual.call(&"update_presentation", 1.0 / 60.0)
	_expect(is_equal_approx(body.position.y, 0.0), "Unloading all cargo settles the body back to flat")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
