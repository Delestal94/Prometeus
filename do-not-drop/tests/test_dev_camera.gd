extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dev_camera.gd
## Covers item #75 of docs/tareas-nacho.md / docs/especificaciones-visuales.md:
## a development-only third-person camera to see the van from outside.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.start_debug_delivery()
	var van: VehicleBody3D = level.vehicle
	var visual: Node3D = van.get_node(^"VehiclePresentation")
	var dev_camera: Camera3D = visual.get(&"_dev_camera")

	_expect(OS.is_debug_build(), "Sanity check: this test run is a debug build (the dev camera only builds itself in one)")
	_expect(dev_camera != null, "The dev camera exists in a debug build")
	_expect(not dev_camera.current, "Starts inactive -- the seat camera should still be what's actually showing")

	var seat_camera: Node = level.get_node(^"World/Vehicle/CabinInterior/DriverEyePoint/FirstPersonCamera")
	_expect(bool(seat_camera.get(&"current")), "The driver's seat camera is the one actually active before toggling")

	visual.call(&"_toggle_dev_camera")
	_expect(dev_camera.current, "Toggling on activates the dev camera")
	_expect(not bool(seat_camera.get(&"current")), "...and the seat camera stops being current (only one camera renders at a time)")

	visual.call(&"_toggle_dev_camera")
	_expect(not dev_camera.current, "Toggling again deactivates the dev camera")
	_expect(bool(seat_camera.get(&"current")), "...and correctly restores whatever was active before, not just any camera")

	level.free()
	if _failures == 0:
		print("PASS: the dev-only third-person camera toggles on and off, restoring the previous camera correctly")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
