extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_low_visibility_event.gd
##
## The low-visibility event (N-113, low_visibility_event.gd, low_visibility_plan.gd): mud over the
## driver's windshield for 10-20 seconds, a rare route event the host draws
## from the world seed:
## - the draw is a pure function of seed and check number (the same seed always
##   rolls the same event, other seeds differ); over many seeds every event
##   lasts 10-20 s, none starts inside the run's first seconds, the cooldown
##   between two is respected, a delivery gets at most one, Endless can repeat,
##   and they are rare (a minority of deliveries see one);
## - the host starts one only in the right moment: a driver moving, no route
##   event open, far enough from the next house or goal that it ends before the
##   quiet zone (RoutePlanner.QUIET_ZONE); it ends by itself on time, ends
##   early if the truck gets into the quiet zone, and the cooldown holds it
##   back afterwards;
## - it ends with the run, a peer arriving late gets the rest of it, and the
##   level carries the node and reads its route's stops;
## - the windshield's mud overlay (windshield_rain.gd, windshield_mud.gdshader)
##   shows only from a seat and only to the driver, follows the event's fade,
##   is drawn by the copy of the wipers' sweep the rain uses, and the wipers
##   run against it;
## - the HUD tells the driver to get guided and the rest to guide them.

const SHADER: Shader = preload("res://shaders/windshield_mud.gdshader")
const RAIN_SHADER: Shader = preload("res://shaders/windshield_rain.gdshader")
## Loaded at run time: it names the autoloads, which are not up while this compiles.
const EVENT_PATH: String = "res://scripts/gameplay/route/low_visibility_event.gd"
const VEHICLE_SOURCE: String = "extends Node3D\nvar driver_peer_id: int = 0\n"

var _failures: int = 0
var _signals: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	var run: Node = root.get_node(^"/root/RunManager")
	bus.connect(&"low_visibility_changed", func(on: bool, kind: StringName, length: float, seconds_in: float) -> void:
		_signals.append([on, kind, length, seconds_in]))

	_check_plan()
	network.set(&"world_seed", 9001)
	await _check_host(network, bus)
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 1)
	await _check_level_and_windshield(network, run)
	await _check_hud(network, bus)

	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	run.call(&"reset_run")
	if _failures == 0:
		print("PASS: low-visibility event: 10-20 s, rare, seeded, never near a stop, mud only on the driver's glass")
	quit(_failures)


# --- The draw, on paper -----------------------------------------------------

func _check_plan() -> void:
	var first: Dictionary = LowVisibilityPlan.draw(77, 0, 12)
	var again: Dictionary = LowVisibilityPlan.draw(77, 0, 12)
	_expect(first == again, "The same seed and check roll the same draw (%s vs %s)" % [first, again])
	var different: bool = false
	for index: int in range(1, 60):
		if LowVisibilityPlan.draw(77, 0, index) != LowVisibilityPlan.draw(78, 0, index):
			different = true
	_expect(different, "Another seed rolls other draws")
	var plan_a: Array[Dictionary] = LowVisibilityPlan.plan(31, 900.0)
	var plan_b: Array[Dictionary] = LowVisibilityPlan.plan(31, 900.0)
	_expect(plan_a == plan_b, "A seed's whole plan repeats")

	var with_event: int = 0
	var seeds: int = 400
	var typical_run: float = 180.0
	var endless_repeats: int = 0
	for seed_value: int in range(1, seeds + 1):
		var delivery: Array[Dictionary] = LowVisibilityPlan.plan(seed_value, typical_run)
		_expect(delivery.size() <= LowVisibilityPlan.MAX_PER_DELIVERY,
				"Seed %d: at most one per delivery (%d)" % [seed_value, delivery.size()])
		with_event += 1 if not delivery.is_empty() else 0
		var long_run: Array[Dictionary] = LowVisibilityPlan.plan(seed_value, 3600.0, 0, LowVisibilityPlan.CHANCE, true)
		endless_repeats += 1 if long_run.size() >= 2 else 0
		var previous_end: float = -INF
		for entry: Dictionary in long_run:
			var duration: float = float(entry.duration)
			var start: float = float(entry.at)
			if duration < LowVisibilityPlan.MIN_DURATION or duration > LowVisibilityPlan.MAX_DURATION:
				_expect(false, "Seed %d: lasts 10-20 s (got %.2f)" % [seed_value, duration])
			if start < LowVisibilityPlan.START_GRACE_SECONDS:
				_expect(false, "Seed %d: nothing in the run's first seconds (started at %.0f)" % [seed_value, start])
			if start - previous_end < LowVisibilityPlan.COOLDOWN_SECONDS:
				_expect(false, "Seed %d: cooldown between two (%.0f s apart)" % [seed_value, start - previous_end])
			previous_end = start + duration
	_expect(LowVisibilityPlan.COOLDOWN_SECONDS >= 120.0, "The cooldown is at least two minutes")
	var share: float = float(with_event) / float(seeds)
	_expect(share > 0.1 and share < 0.5,
			"Rare in a typical three-minute delivery, not never (%.0f%% of %d seeds)" % [share * 100.0, seeds])
	_expect(endless_repeats > 0, "In Endless a long run can see it more than once (%d seeds)" % endless_repeats)


# --- The host's rules ---------------------------------------------------------

func _make_event(chance: float) -> Node:
	var event: Node = (load(EVENT_PATH) as GDScript).new()
	event.set(&"chance", chance)
	# The test ticks it by hand.
	event.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(event)
	return event


func _context(overrides: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {"running": true, "driver": true, "speed": 12.0, "stop_gap": 900.0,
			"route_event": false, "endless": false}
	context.merge(overrides, true)
	return context


## Ticks `seconds` of run at 0.1 s a step; returns the second the event began (or -1).
func _run_for(event: Node, seconds: float, context: Dictionary) -> float:
	var began: float = -1.0
	var time: float = 0.0
	while time < seconds:
		event.call(&"tick", 0.1, context)
		time += 0.1
		if began < 0.0 and event.call(&"is_active"):
			began = time
			break
	return began


func _check_host(network: Node, bus: Node) -> void:
	var event: Node = _make_event(1.0)
	await process_frame
	var grace: float = LowVisibilityPlan.START_GRACE_SECONDS

	# Nothing in the first seconds, however sure the draw is.
	_expect(_run_for(event, grace - 5.0, _context()) < 0.0, "Nothing starts inside the run's first %.0f s" % grace)
	# The wrong moments.
	for wrong: Dictionary in [{"driver": false}, {"speed": 1.0}, {"route_event": true}, {"running": false},
			{"stop_gap": 100.0}, {"stop_gap": RoutePlanner.QUIET_ZONE + 12.0 * 10.0 - 1.0}]:
		var probe: Node = _make_event(1.0)
		probe.set(&"run_seconds", grace)
		probe.set(&"seconds_since_end", INF)
		_expect(_run_for(probe, 30.0, _context(wrong)) < 0.0, "Not started when %s" % wrong)
		probe.free()
	_expect(_signals.is_empty(), "No signal went out for any of them (%s)" % [_signals])

	# The right moment: it starts on a draw, lasts 10-20 s, ends by itself.
	event.set(&"run_seconds", grace)
	var began: float = _run_for(event, 30.0, _context())
	_expect(began > 0.0 and began <= LowVisibilityPlan.SPACING + 0.2, "It starts at the next draw (%.1f s)" % began)
	_expect(_signals.size() == 1 and _signals[0][0] == true and _signals[0][1] == &"mud",
			"Everyone is told it started (%s)" % [_signals])
	var duration: float = float(_signals[0][2]) if not _signals.is_empty() else 0.0
	_expect(duration >= LowVisibilityPlan.MIN_DURATION and duration <= LowVisibilityPlan.MAX_DURATION,
			"It is announced with a 10-20 s duration (%.2f)" % duration)
	var lasted: float = 0.0
	while event.call(&"is_active") and lasted < 40.0:
		event.call(&"tick", 0.1, _context())
		lasted += 0.1
	_expect(absf(lasted - duration) < 0.25, "It lasts what was announced (%.1f of %.1f s)" % [lasted, duration])
	_expect(_signals.size() == 2 and _signals[1][0] == false, "Everyone is told it ended (%s)" % [_signals])
	_expect(int(event.get(&"events_this_run")) == 1, "The run counts it")

	# One per delivery; in Endless the cooldown alone holds it back.
	_expect(_run_for(event, 600.0, _context()) < 0.0, "A delivery gets only one")
	event.call(&"reset_for_run")
	event.set(&"run_seconds", grace)
	var endless: Dictionary = _context({"endless": true})
	_expect(_run_for(event, 30.0, endless) > 0.0, "Endless: the first one starts")
	while event.call(&"is_active"):
		event.call(&"tick", 0.1, endless)
	var quiet: float = _run_for(event, LowVisibilityPlan.COOLDOWN_SECONDS - 1.0, endless)
	_expect(quiet < 0.0, "Endless: nothing during the two-minute cooldown")
	var second: float = _run_for(event, 30.0, endless)
	_expect(second > 0.0, "Endless: the next one comes once it has passed (%.1f s later)" % second)

	# Getting into the quiet zone before a stop ends it early.
	while event.call(&"is_active"):
		event.call(&"tick", 0.1, endless)
	event.call(&"reset_for_run")
	event.set(&"run_seconds", grace)
	_signals.clear()
	_run_for(event, 30.0, _context())
	event.call(&"tick", 0.1, _context({"stop_gap": RoutePlanner.QUIET_ZONE - 1.0}))
	_expect(not event.call(&"is_active"), "It ends when the truck is in the quiet zone before a stop")

	# The run ending switches it off everywhere.
	event.call(&"reset_for_run")
	event.set(&"run_seconds", grace)
	_run_for(event, 30.0, _context())
	_expect(event.call(&"is_active"), "Another one is on")
	bus.emit_signal(&"run_ended", 0, {})
	_expect(not event.call(&"is_active"), "The run ending clears it")
	_expect(not _signals.is_empty() and _signals[-1][0] == false,
			"...and tells the glass and the HUD (%s)" % [_signals[-1] if not _signals.is_empty() else null])

	# Deterministic by seed: two runs of the same seed start on the same tick
	# with the same duration; another seed does not.
	var results: Array = []
	for seed_value: int in [9001, 9001, 31337]:
		network.set(&"world_seed", seed_value)
		var copy: Node = _make_event(LowVisibilityPlan.CHANCE * 6.0)
		copy.set(&"run_seconds", grace)
		_signals.clear()
		var at: float = _run_for(copy, 2000.0, _context({"endless": true}))
		results.append([at, _signals[0][2] if not _signals.is_empty() else -1.0])
		copy.free()
	network.set(&"world_seed", 9001)
	_expect(results[0] == results[1],
			"The same seed starts at the same moment with the same duration (%s vs %s)" % [results[0], results[1]])
	_expect(results[0] != results[2], "Another seed does not (%s vs %s)" % [results[0], results[2]])

	# A peer that joins mid-event gets the rest of it.
	event.call(&"reset_for_run")
	_signals.clear()
	event.call(&"_receive_state", &"mud", 14.0, 5.0)
	_expect(event.call(&"is_active") and is_equal_approx(float(event.get(&"elapsed")), 5.0),
			"A late joiner picks it up 5 s in (%s)" % [event.get(&"active")])
	_expect(_signals.size() == 1 and _signals[0][0] == true and is_equal_approx(float(_signals[0][3]), 5.0),
			"...and its glass and HUD hear it (%s)" % [_signals])
	event.call(&"reset_for_run")

	# The fade: the mud lands, holds, clears.
	var clean_start: float = LowVisibilityPlan.coverage(0.0, 14.0)
	var clean_end: float = LowVisibilityPlan.coverage(14.0, 14.0)
	_expect(is_zero_approx(clean_start) and is_zero_approx(clean_end), "The glass is clean at both ends")
	_expect(is_equal_approx(LowVisibilityPlan.coverage(7.0, 14.0), 1.0), "...and fully covered in the middle")
	_expect(LowVisibilityPlan.coverage(0.4, 14.0) > 0.0 and LowVisibilityPlan.coverage(0.4, 14.0) < 1.0,
			"...filling in gradually")
	event.free()


# --- The level and the windshield ---------------------------------------------

func _check_level_and_windshield(network: Node, run: Node) -> void:
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var event: Node = level.get_node_or_null(^"LowVisibilityEvent")
	_expect(event != null, "The level carries the event")
	var van: VehicleBody3D = level.get(&"vehicle")
	if event != null:
		var context: Dictionary = event.call(&"_context")
		# From here the glass is driven by hand: the host's own ticking would
		# end the event at once (no run is on).
		event.process_mode = Node.PROCESS_MODE_DISABLED
		_expect(float(context.stop_gap) > 0.0 and float(context.stop_gap) < 100000.0,
			"It reads how far the next stop is from the route (%s m)" % context.get("stop_gap"))
		_expect(not bool(context.driver) and not bool(context.running),
				"Parked with nobody at the wheel it has no driver (%s)" % [context])
	var rain := van.find_child("WindshieldRain", true, false) as WindshieldRain
	_expect(rain != null and rain.mud_overlay != null, "The windshield has its mud overlay")
	if rain == null or rain.mud_overlay == null:
		level.queue_free()
		return
	_expect(rain.mud_overlay.mesh == rain.overlay.mesh, "It shares the glass's mesh with the rain (one shape)")
	_expect(not rain.mud_overlay.visible, "Clean glass at first")

	# Shader: the uniforms the script drives are there; the wiper maths is the rain's.
	var uniforms: Array = SHADER.get_shader_uniform_list().map(func(entry: Dictionary) -> String: return entry.name)
	var wanted: Array[String] = ["coverage", "pattern", "brightness", "wiper_time", "wipers_on", "mud_since",
			"pivot_a", "pivot_b", "aspect"]
	for uniform_name: String in wanted:
		_expect(uniform_name in uniforms, "The mud shader has a %s uniform" % uniform_name)
	var mud_sweep: String = _function_text(SHADER.code, "last_sweep")
	_expect(not mud_sweep.is_empty() and mud_sweep == _function_text(RAIN_SHADER.code, "last_sweep"),
			"The mud is thinned by the same blade sweep the rain is cleared with")

	var seat: Camera3D = null
	for camera: Camera3D in van.get_node(^"VehiclePresentation").get(&"_seat_cameras"):
		seat = camera
		break
	var outside := Camera3D.new()
	level.add_child(outside)
	outside.global_position = van.to_global(Vector3(0.0, 2.0, -9.0))
	var me: int = int(network.call(&"local_id"))
	WorldMood.active["rain"] = false
	WorldMood.active["time"] = 2
	if seat != null:
		seat.make_current()
	var bus: Node = root.get_node(^"/root/EventBus")
	van.set(&"driver_peer_id", 0)
	bus.emit_signal(&"low_visibility_changed", true, &"mud", 12.0, 0.0)
	await process_frame
	_expect(not rain.mud_overlay.visible,
			"From a seat that is not the driver's, the glass is clear (the guide sees the road)")
	van.set(&"driver_peer_id", me)
	await process_frame
	await process_frame
	_expect(rain.mud_overlay.visible, "The driver, from the seat, sees the mud")
	var mid_cover: float = float(rain.mud_material.get_shader_parameter(&"coverage"))
	_expect(mid_cover > 0.0, "It starts to cover the glass (%.2f)" % mid_cover)
	_expect(float(rain.mud_material.get_shader_parameter(&"brightness")) < 0.5,
			"At night the mud is dimmed (%s)" % rain.mud_material.get_shader_parameter(&"brightness"))
	rain.mud_elapsed = 6.0
	await process_frame
	_expect(float(rain.mud_material.get_shader_parameter(&"coverage")) > 0.95,
			"Mid-event the glass is covered (%s)" % rain.mud_material.get_shader_parameter(&"coverage"))
	outside.make_current()
	await process_frame
	_expect(not rain.mud_overlay.visible, "From outside the truck nothing is drawn")
	if seat != null:
		seat.make_current()

	# The wipers work against it, with the engine on, even when it is dry. The
	# run starting wipes any mud, so it lands after.
	level.call(&"start_debug_delivery")
	van.set(&"driver_peer_id", me)
	await process_frame
	bus.emit_signal(&"low_visibility_changed", true, &"mud", 12.0, 0.0)
	for frame: int in range(90):
		await process_frame
	_expect(rain.wiper_time > 0.5,
			"With the engine on the wipers run against the mud, dry weather or not (%.2f s)" % rain.wiper_time)
	_expect(float(rain.mud_material.get_shader_parameter(&"wipers_on")) > 0.5, "...and the mud shader knows")

	bus.emit_signal(&"low_visibility_changed", false, &"mud", 0.0, 0.0)
	await process_frame
	_expect(not rain.mud_overlay.visible, "When it ends the glass is clean again")
	WorldMood.active["time"] = 0
	level.queue_free()
	await process_frame
	run.call(&"reset_run")


## The text of `function_name` in a shader, from its signature to the brace that closes it.
func _function_text(code: String, function_name: String) -> String:
	var start: int = code.find(" %s(" % function_name)
	if start < 0:
		return ""
	var open: int = code.find("{", start)
	var depth: int = 0
	var index: int = open
	while index < code.length():
		if code[index] == "{":
			depth += 1
		elif code[index] == "}":
			depth -= 1
			if depth == 0:
				return code.substr(start, index - start + 1)
		index += 1
	return ""


# --- The HUD ---------------------------------------------------------------------

func _check_hud(network: Node, bus: Node) -> void:
	var me: int = int(network.call(&"local_id"))
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	var script := GDScript.new()
	script.source_code = VEHICLE_SOURCE
	script.reload()
	var vehicle := Node3D.new()
	vehicle.set_script(script)
	vehicle.add_to_group(&"vehicle")
	root.add_child(vehicle)
	await process_frame
	vehicle.set(&"driver_peer_id", me)
	bus.emit_signal(&"low_visibility_changed", true, &"mud", 14.0, 0.0)
	_expect(hud.event_label.text == hud.tr("HUD_LOW_VISIBILITY_DRIVER") and not hud.event_label.text.is_empty(),
		"The driver's HUD says they can't see and should be guided (%s)" % hud.event_label.text)
	_expect(hud.event_label.text != "HUD_LOW_VISIBILITY_DRIVER", "...translated")
	bus.emit_signal(&"low_visibility_changed", false, &"mud", 0.0, 0.0)
	_expect(hud.event_label.text.is_empty(), "...and the notice goes when it ends (%s)" % hud.event_label.text)
	vehicle.set(&"driver_peer_id", me + 1)
	bus.emit_signal(&"low_visibility_changed", true, &"mud", 14.0, 0.0)
	_expect(hud.event_label.text.is_empty(), "A passenger does not get the driver's notice")
	_expect(hud.toast_label.text.contains("(") and hud.toast_label.text != "HUD_LOW_VISIBILITY_GUIDE_KEY",
		"...they are told to guide with the phrase wheel (%s)" % hud.toast_label.text)
	bus.emit_signal(&"low_visibility_changed", false, &"mud", 0.0, 0.0)
	hud.queue_free()
	vehicle.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
