extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_pacing.gd
## Pacing inside each leg (tareas de Nacho N-103), over 200 seeds and 1-4
## houses, read from route.gd's plan (plan_spine(), the same one it builds):
##   - something happens at least every MOMENT_SPACING metres: a hard
##     segment (rail crossing included), a sharp bend, or a house stop;
##   - never two hard segments back to back;
##   - the last QUIET_ZONE metres before every house are straight or a gentle
##     bend, so nothing throws a box while the crew gets out;
##   - hard segments get likelier from the first house to the last.
## And one real build, to check the road it lays is that plan.

const Route = preload("res://scripts/gameplay/route/route.gd")
const SEEDS: int = 200

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var early_hard: int = 0
	var early_total: int = 0
	var late_hard: int = 0
	var late_total: int = 0
	for seed_value: int in range(1, SEEDS + 1):
		var houses: int = 1 + seed_value % 4
		var plan: Dictionary = Route.plan_spine(seed_value, houses)
		var segments: Array = plan.segments
		var stops: Array = plan.house_distances
		_expect(stops.size() == houses, "Seed %d: one stop per house (%d)" % [seed_value, stops.size()])
		# Everything that counts as something happening, as [from, to].
		var events: Array = [[0.0, 0.0]]
		for stop: float in stops:
			events.append([stop, stop])
		var previous_hard: bool = false
		for index: int in range(segments.size()):
			var segment: Dictionary = segments[index]
			if segment.moment:
				events.append([segment.start, segment.start + segment.length])
			if segment.hard and previous_hard:
				_expect(false, "Seed %d: two hard segments in a row at %.0f m" % [seed_value, segment.start])
			previous_hard = segment.hard
			for stop: float in stops:
				var overlaps: bool = segment.start < stop and segment.start + segment.length > stop - Route.QUIET_ZONE
				if overlaps and not _calm(segment):
					_expect(false, "Seed %d: %s in the last %.0f m before the house at %.0f m" % [seed_value, segment.script.get_global_name(), Route.QUIET_ZONE, stop])
			if segment.start < plan.total * 0.5:
				early_total += 1
				early_hard += int(segment.hard)
			else:
				late_total += 1
				late_hard += int(segment.hard)
		events.append([plan.total, plan.total])
		events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var reached: float = 0.0
		for event: Array in events:
			if event[0] - reached > Route.MOMENT_SPACING + 0.01:
				_expect(false, "Seed %d, %d houses: %.0f m with nothing happening (from %.0f m)" % [seed_value, houses, event[0] - reached, reached])
			reached = maxf(reached, event[1])

	var early: float = float(early_hard) / maxf(1.0, early_total)
	var late: float = float(late_hard) / maxf(1.0, late_total)
	_expect(late > early, "Hard segments get likelier as the delivery goes on (first half %.0f%%, second half %.0f%%)" % [early * 100.0, late * 100.0])
	print("PACING hard segments: first half %.0f%%, second half %.0f%%" % [early * 100.0, late * 100.0])

	await _test_build_follows_plan()
	if _failures == 0:
		print("PASS: over %d seeds every leg has something every %.0f m, no two hard in a row, a calm approach to every house and a rising difficulty" % [SEEDS, Route.MOMENT_SPACING])
	quit(_failures)


func _calm(segment: Dictionary) -> bool:
	if segment.script == StraightSegment:
		return true
	return segment.script == CurveSegment and absf(segment.turn_deg) <= Route.GENTLE_CURVE_DEG


func _test_build_follows_plan() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 4242)
	network.set(&"world_house_count", 3)
	var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
	route.set(&"batch_dressing", false)
	root.add_child(route)
	var plan: Dictionary = Route.plan_spine(4242, 3)
	var built: Array = route.get(&"_segments")
	_expect(built.size() == plan.segments.size(), "The built road has the planned %d segments (%d)" % [plan.segments.size(), built.size()])
	for index: int in range(mini(built.size(), plan.segments.size())):
		var segment: RouteSegment = built[index]
		var planned: Dictionary = plan.segments[index]
		if segment.get_script() != planned.script or not is_equal_approx(segment.length, planned.length):
			_expect(false, "Segment %d is %s %.0f m, planned %s %.0f m" % [index, segment.get_script().get_global_name(), segment.length, planned.script.get_global_name(), planned.length])
			break
	_expect(is_equal_approx(float(route.get(&"route_length")), plan.total), "The built road is as long as planned")
	route.free()
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
