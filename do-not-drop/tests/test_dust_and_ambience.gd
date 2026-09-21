extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dust_and_ambience.gd
## Covers items #45 (ambient exterior sound) and #49 (dust under the
## wheels) of docs/tareas-nacho.md / docs/especificaciones-visuales.md.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_test_ambience()
	await _test_dust()
	if _failures == 0:
		print("PASS: the world has ambient wind, and the wheels kick up dust while moving")
	quit(_failures)


func _test_ambience() -> void:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
	root.add_child(route)
	var player: AudioStreamPlayer = route.get_node(^"AmbientWind")
	_expect(player != null, "The route builds itself an ambient wind player")
	_expect(player.autoplay, "Ambience starts on its own, no trigger needed")
	var stream: AudioStreamWAV = player.stream
	_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Loops seamlessly instead of restarting with a click")
	var has_signal: bool = false
	for byte: int in stream.data:
		if byte != 0:
			has_signal = true
			break
	_expect(has_signal, "Actual filtered noise, not a silent buffer")
	route.free()


func _test_dust() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.start_debug_delivery()
	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false
	var visual: Node3D = van.get_node(^"VehiclePresentation")
	var dust: Array[GPUParticles3D] = visual.get(&"_dust_emitters")
	_expect(dust.size() == 4, "One dust emitter per wheel (got %d)" % dust.size())
	_expect(not dust[0].emitting, "No dust while parked")

	van.set_controls(0.9, 0.0, false)
	for _i: int in range(90):
		await physics_frame
	var any_emitting: bool = false
	for particles: GPUParticles3D in dust:
		if particles.emitting:
			any_emitting = true
	_expect(any_emitting, "Driving at speed kicks up dust from at least one wheel")

	van.set_controls(0.0, 0.0, true)
	van.linear_velocity = Vector3.ZERO
	for _i: int in range(30):
		await physics_frame
	var still_emitting: bool = false
	for particles: GPUParticles3D in dust:
		if particles.emitting:
			still_emitting = true
	_expect(not still_emitting, "Dust stops once the van is stationary again")

	level.free()
	await create_timer(0.1).timeout


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
