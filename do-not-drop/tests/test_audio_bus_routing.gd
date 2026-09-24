extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_audio_bus_routing.gd
## Covers items #80/#81 of docs/tareas-nacho.md: the van's own sounds route
## through "Interior" or "Exterior" depending on whether this client's own
## active camera is one of this vehicle's own seats, not a fixed bus. The
## horn too (N-203), though vehicle.gd creates it, not the presentation.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_expect(AudioServer.get_bus_index("Interior") != -1, "The Interior bus exists in the project's audio layout")
	_expect(AudioServer.get_bus_index("Exterior") != -1, "The Exterior bus exists in the project's audio layout")

	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var van: VehicleBody3D = level.vehicle
	var visual: Node3D = van.get_node(^"VehiclePresentation")
	var seat_camera: Camera3D = van.get_node(^"CabinInterior/DriverEyePoint/FirstPersonCamera")
	var outside_camera := Camera3D.new()
	root.add_child(outside_camera)

	outside_camera.current = true
	visual.call(&"update_presentation", 0.0)
	_expect(visual.engine_player.bus == &"Exterior", "Listening from outside the van routes its sounds to Exterior")

	seat_camera.current = true
	visual.call(&"update_presentation", 0.0)
	_expect(visual.engine_player.bus == &"Interior", "Sitting in one of the van's own seats routes to Interior")
	_expect(visual.impact_player.bus == &"Interior", "Impact thud follows the same routing")
	_expect(visual.screech_player.bus == &"Interior", "Tire screech follows the same routing")
	_expect(visual.horn_player != null and visual.horn_player == van.get_node_or_null(^"HornAudio"),
		"The presentation found the truck's own horn")
	if visual.horn_player != null:
		_expect(visual.horn_player.bus == &"Interior", "The horn follows the same routing (tareas de Nacho N-203)")

	outside_camera.current = true
	visual.call(&"update_presentation", 0.0)
	_expect(visual.engine_player.bus == &"Exterior", "Stepping back outside switches back")
	if visual.horn_player != null:
		_expect(visual.horn_player.bus == &"Exterior", "The horn switches back too")

	level.free()
	outside_camera.free()
	if _failures == 0:
		print("PASS: the van's own sounds route to Interior/Exterior based on whether you're actually inside it")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
