extends SceneTree
## Tests real wheel physics as well as presentation isolation and lifecycle.
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.start_debug_delivery()
	var van: VehicleBody3D = level.vehicle
	van.controls_enabled = false  # Deterministic driver rather than keyboard input.
	var visual: Node3D = van.get_node("VehiclePresentation")
	visual.set_process(false)
	var wheel: VehicleWheel3D = van.get_node("FrontLeftWheel")
	var initial_wheel: Transform3D = wheel.transform
	for tick in range(75):
		await physics_frame
	var settled_wheel: Transform3D = wheel.transform
	# While frozen for loading the wheels are already posed where the settled
	# suspension holds them (vehicle.gd), so starting the delivery must not
	# make them visibly drop or jump.
	_expect(absf(settled_wheel.origin.y - initial_wheel.origin.y) < 0.03, "Wheels start where the suspension settles them: no drop when the run begins")
	van.set_controls(0.8, 0.0, false)
	for tick in range(100):
		await physics_frame
	_expect(van.linear_velocity.length() > 1.0, "Physics vehicle actually accelerates")
	_expect(not wheel.basis.is_equal_approx(settled_wheel.basis), "Godot rotates wheel meshes through their parent natively")
	_expect(absf(wheel.get_rpm()) > 1.0, "Rotating wheel reports RPM")
	van.set_controls(0.5, 0.7, false)
	for tick in range(20):
		await physics_frame
	_expect(absf(wheel.basis.x.z) > 0.05, "Native wheel axle changes direction while steering")
	var physics_pose: Transform3D = van.transform
	var wheel_pose: Transform3D = wheel.transform
	visual.update_presentation(0.1)
	_expect(van.transform.is_equal_approx(physics_pose) and wheel.transform.is_equal_approx(wheel_pose), "Presentation never moves physics bodies or double-rotates wheels")
	_expect(not visual.steering_wheel.basis.is_equal_approx(visual._steering_rest), "Steering wheel follows road wheel steering")
	_expect(visual.steering_wheel.has_node("Hub"), "Steering wheel has hub and spokes for readable rotation")
	_expect(visual.headlights.size() == 2 and visual.headlights[0].light_energy > 0.0, "Two functional headlights illuminate during delivery")
	var baseline_rear: float = visual._rear_materials[0].emission_energy_multiplier
	van.set_controls(0.0, 0.0, true)
	await physics_frame
	await physics_frame
	visual.update_presentation(0.1)
	_expect(visual._rear_materials[0].emission_energy_multiplier > baseline_rear, "Actual handbraking increases tail light emission")
	visual._on_impact(10.0, van.global_position)
	visual.update_presentation(0.01)
	# The route's weather/time of day scales the beams (world_mood.gd).
	var full_beam: float = visual.headlight_energy * minf(float(WorldMood.active.get("headlight_boost", 1.0)), visual.HEADLIGHT_ENERGY_BOOST_CAP)
	_expect(visual.headlights[0].light_energy < full_beam, "Strong impact briefly dims headlights")
	visual.update_presentation(0.3)
	_expect(is_equal_approx(visual.headlights[0].light_energy, full_beam), "Headlights recover without persistent flashing")
	# At night the beams reach further by falling off slower, not by burning
	# brighter: 4x energy washed out everything near the truck.
	var mood_before: Dictionary = WorldMood.active
	WorldMood.active = mood_before.duplicate()
	WorldMood.active["headlight_boost"] = 4.0
	visual.update_presentation(0.3)
	_expect(visual.headlights[0].light_energy <= visual.headlight_energy * visual.HEADLIGHT_ENERGY_BOOST_CAP + 0.001,
		"Night beams stay under the energy cap (%.2f)" % visual.headlights[0].light_energy)
	_expect(visual.headlights[0].spot_range > 50.0 and visual.headlights[0].spot_attenuation < 1.0,
		"...and reach far with a flatter falloff (range %.0f, attenuation %.2f)" % [visual.headlights[0].spot_range, visual.headlights[0].spot_attenuation])
	WorldMood.active = mood_before
	visual.update_presentation(0.3)
	var original_velocity: Vector3 = van.linear_velocity
	van.linear_velocity = Vector3.ZERO
	van.engine_force = 0.0
	visual.update_presentation(2.0)
	var idle_pitch: float = visual.engine_player.pitch_scale
	van.linear_velocity = Vector3(0, 0, -15)
	van.engine_force = van.maximum_engine_force
	visual.update_presentation(2.0)
	_expect(visual.engine_player.playing and visual.engine_player.pitch_scale > idle_pitch, "Engine pitch responds to speed and throttle load")
	van.linear_velocity = original_velocity
	van.presentation_engine_running = false
	van.presentation_braking = false
	visual.update_presentation(1.0)
	_expect(not visual.engine_player.playing and visual.headlights[0].light_energy == 0.0, "Engine and lights turn off outside a delivery")
	var audio: AudioStreamWAV = visual.engine_player.stream
	_expect(audio.loop_mode == AudioStreamWAV.LOOP_FORWARD and audio.data.size() == audio.loop_end * 2, "Engine loop has valid 16-bit PCM loop bounds")
	_expect(abs(audio.data.decode_s16(0) - audio.data.decode_s16(audio.data.size() - 2)) < 1000, "Engine waveform loop has no large discontinuity")
	level.free()
	await create_timer(0.1).timeout  # Let the audio server retire stopped playback.
	if failures == 0:
		print("PASS: native wheel roll/steer/suspension, steering wheel, brakes, beams, impact dip and engine lifecycle")
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
