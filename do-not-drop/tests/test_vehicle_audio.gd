extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_audio.gd
## Covers items #42 (impact thud) and #44 (tire screech) of
## docs/especificaciones-visuales.md, added to VehiclePresentation
## alongside the engine/headlight/brake presentation it already had, and
## N-401: the engine's three layers follow a rev counter with a gearbox --
## idle loudest parked, the revving layer loudest at speed, a dip in the revs
## at each gear change, and the agile truck revving higher and shifting faster.

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

	_check_engine_layers(visual, van)

	level.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: impact thud scales with strength and ignores distant hits; tire screech follows wheel skid; the engine's layers follow the revs")
	quit(_failures)


## Drives the rev counter by hand (speed and load as the truck would report
## them), for each truck, and reads the layers back.
func _check_engine_layers(visual: Node3D, van: VehicleBody3D) -> void:
	var results: Dictionary = {}
	for variant: StringName in [&"classic", &"agile"]:
		van.set(&"variant_id", variant)
		visual.set(&"engine_rpm", 0.0)
		visual.set(&"engine_gear", 0)
		visual.set(&"shift_remaining", 0.0)
		var step: float = 1.0 / 60.0
		for tick: int in range(30):
			visual.call(&"update_rev_counter", step, 0.0, 0.0)
		var parked: Vector3 = visual.call(&"engine_layer_weights")
		_expect(parked.x > 0.9 and parked.z < 0.05, "%s parked: the idle layer carries the sound (weights %s)" % [variant, parked])
		# Flat out from a standstill to top speed over 20 s.
		var top: float = float(van.get(&"maximum_speed_kmh"))
		var shifts: int = 0
		var deepest_dip: float = 0.0
		var peak: float = 0.0
		var shift_time: float = 0.0
		var last_gear: int = 0
		var before: float = 0.0
		for tick: int in range(60 * 20):
			var speed: float = top * minf(float(tick) / (60.0 * 18.0), 1.0)
			before = float(visual.get(&"engine_rpm"))
			visual.call(&"update_rev_counter", step, speed, 1.0)
			peak = maxf(peak, float(visual.get(&"engine_rpm")))
			var gear: int = int(visual.get(&"engine_gear"))
			if gear != last_gear:
				shifts += 1
				last_gear = gear
				# How far the revs fall over the change, and how long it takes.
				var lowest: float = before
				for probe: int in range(30):
					if float(visual.get(&"shift_remaining")) > 0.0:
						shift_time += step
					visual.call(&"update_rev_counter", step, speed, 1.0)
					lowest = minf(lowest, float(visual.get(&"engine_rpm")))
				deepest_dip = maxf(deepest_dip, 1.0 - lowest / before)
		var fast: Vector3 = visual.call(&"engine_layer_weights")
		var ratios: Array = ((visual.get_script() as Script).get_script_constant_map()["ENGINE_PROFILES"] as Dictionary)[variant].ratios
		_expect(shifts >= ratios.size() - 1, "%s: works up through its gears (%d changes)" % [variant, shifts])
		_expect(deepest_dip > 0.15, "%s: each change drops the revs audibly (deepest dip %.0f %%)" % [variant, deepest_dip * 100.0])
		_expect(fast.z > parked.z + 0.3 and fast.x < 0.05, "%s at top speed: the revving layer takes over (weights %s)" % [variant, fast])
		results[variant] = {"peak": peak, "shift_time": shift_time / maxf(shifts, 1)}
	_expect(float(results[&"agile"].peak) > float(results[&"classic"].peak) * 1.2,
		"The agile truck revs higher (%.0f vs %.0f rpm)" % [results[&"agile"].peak, results[&"classic"].peak])
	_expect(float(results[&"agile"].shift_time) < float(results[&"classic"].shift_time) * 0.6,
		"...and snaps through its gears faster (%.2f vs %.2f s a change)" % [results[&"agile"].shift_time, results[&"classic"].shift_time])
	van.set(&"variant_id", &"classic")

	# The players themselves: louder idle parked, louder high layer flat out.
	visual.set(&"_motor_mix", 1.0)
	visual.set(&"engine_rpm", 0.0)
	visual.set(&"engine_gear", 0)
	for tick: int in range(20):
		visual.call(&"update_rev_counter", 1.0 / 60.0, 0.0, 0.0)
	var idle_parked: float = _layer_db(visual, 0)
	var high_parked: float = _layer_db(visual, 2)
	for tick: int in range(60 * 12):
		visual.call(&"update_rev_counter", 1.0 / 60.0, 70.0 * minf(float(tick) / 400.0, 1.0), 1.0)
	_expect(_layer_db(visual, 2) > high_parked + 6.0 and _layer_db(visual, 0) < idle_parked - 6.0,
		"At speed the revving layer is louder and the idle quieter (high %.1f → %.1f dB, idle %.1f → %.1f dB)" % [high_parked, _layer_db(visual, 2), idle_parked, _layer_db(visual, 0)])


## The level each layer's player would get from the current revs (idle, mid, high).
func _layer_db(visual: Node3D, index: int) -> float:
	var weights: Vector3 = visual.call(&"engine_layer_weights")
	return float(visual.get(&"engine_volume_db")) + linear_to_db(maxf(sqrt(weights[index]), 0.001))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
