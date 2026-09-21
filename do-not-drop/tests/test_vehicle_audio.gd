extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_audio.gd
## Covers items #42 (impact thud) and #44 (tire screech) of
## docs/especificaciones-visuales.md, added to VehiclePresentation
## alongside the engine/headlight/brake presentation it already had.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var bus: Node = root.get_node(^"/root/EventBus")
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.start_debug_delivery()
	var van: VehicleBody3D = level.vehicle
	var visual: Node3D = van.get_node(^"VehiclePresentation")
	visual.set_process(false)  # deterministic: drive updates by hand

	_expect(not visual.impact_player.playing, "Impact thud starts silent")
	bus.emit_signal(&"vehicle_impact", 14.0, van.global_position)
	_expect(visual.impact_player.playing, "A strong impact near the van plays the thud")
	var loud_db: float = visual.impact_player.volume_db
	# 8.0 still clears the >= 7.0 gate in _on_impact (same threshold the
	# headlight flicker already uses) -- below that, nothing should even play.
	bus.emit_signal(&"vehicle_impact", 8.0, van.global_position)
	_expect(visual.impact_player.volume_db < loud_db, "A weaker (but still qualifying) impact plays quieter than a strong one")
	var quiet_db: float = visual.impact_player.volume_db
	bus.emit_signal(&"vehicle_impact", 14.0, van.global_position + Vector3(50.0, 0.0, 0.0))
	_expect(is_equal_approx(visual.impact_player.volume_db, quiet_db),
		"A distant impact doesn't retrigger the sound at all, same gate the headlight flicker uses")

	_expect(not visual.screech_player.playing, "No screeching while parked")
	# Real physics, not hand-set velocity: get_skidinfo() only means anything
	# once the wheels have actually rolled/contacted the road under load.
	# controls_enabled = false stops VehicleInputComponent from overwriting
	# these direct set_controls() calls with the (all-zero) real keyboard
	# state every frame, same trick test_vehicle_presentation.gd uses.
	van.controls_enabled = false
	for wheel: Node in van.get_children():
		if wheel is VehicleWheel3D:
			wheel.set(&"wheel_friction_slip", 0.3)  # reduced grip: a hard turn actually breaks traction
	van.set_controls(0.9, 0.0, false)
	for _i: int in range(80):
		await physics_frame
	van.set_controls(1.0, 1.0, false)
	visual.set_process(true)
	for _i: int in range(50):
		await physics_frame
	_expect(visual.screech_player.playing, "Sliding wheels under a hard turn start the screech")

	for wheel: Node in van.get_children():
		if wheel is VehicleWheel3D:
			wheel.set(&"wheel_friction_slip", 3.5)
	van.set_controls(0.0, 0.0, true)
	for _i: int in range(60):
		await physics_frame
	_expect(not visual.screech_player.playing, "Screech stops once the van isn't sliding anymore")

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: impact thud scales with strength and ignores distant hits; tire screech follows wheel skid")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
