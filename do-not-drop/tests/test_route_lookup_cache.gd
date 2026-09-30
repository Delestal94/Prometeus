extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_lookup_cache.gd
## N-223, less work per frame. (1) route.gd's nearest-sample / nearest-path
## lookups look only around where the last one landed; driving the whole road
## forwards, backwards, sideways and jumping around (back to the start, to the
## goal, into the middle) they must answer exactly what a scan of every point
## answers -- progress, section, road distance, distance from the road.
## (2) RouteStreamer (Endless) answers the same as a full scan of its centre
## line while the road grows and is culled behind the target. (3) level_base
## sends the HUD's route and delivery signals at ~8 Hz instead of every tick,
## a change of delivery state at once, while stopped_seconds keeps counting
## every tick.

const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
var _failures: int = 0
var _progress_signals: int = 0
var _status_signals: int = 0
var _last_status: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		_failures += 1


const ROUTE_SEEDS: Array[int] = [4242, 1, 2, 3, 4, 5, 6, 7]


func _run() -> void:
	await process_frame
	# Several built routes, so a hairpin or a stretch passing close to an
	# earlier one turns up in at least some of them.
	for seed_value: int in ROUTE_SEEDS:
		root.get_node(^"/root/NetworkManager").set(&"world_seed", seed_value)
		await _check_route()
	root.get_node(^"/root/NetworkManager").set(&"world_seed", 4242)
	await _check_streamer()
	await _check_level_throttle()
	quit(_failures)


# --- the delivery route ---------------------------------------------------

func _brute_sample(route: Node3D, world: Vector3) -> Dictionary:
	var local: Vector3 = route.to_local(world)
	var best: Dictionary = {}
	var best_distance: float = INF
	for sample: Dictionary in route.get(&"_progress_samples"):
		var d: float = (sample["position"] as Vector3).distance_to(local)
		if d < best_distance:
			best_distance = d
			best = sample
	return best


func _brute_path_index(route: Node3D, world: Vector3) -> int:
	var local: Vector3 = route.to_local(world)
	var points: Array[Vector3] = route.get(&"_path_points")
	var best: float = INF
	var nearest: int = 0
	for index: int in range(points.size()):
		var gap: float = Vector2(points[index].x - local.x, points[index].z - local.z).length_squared()
		if gap < best:
			best = gap
			nearest = index
	return nearest


func _brute_distance_from_path(route: Node3D, world: Vector3) -> float:
	var local: Vector3 = route.to_local(world)
	var best: float = INF
	for point: Vector3 in route.get(&"_path_points"):
		best = minf(best, point.distance_to(local))
	return best


func _compare_route(route: Node3D, world: Vector3, label: String) -> void:
	var expected: Dictionary = _brute_sample(route, world)
	var length: float = float(route.get(&"route_length"))
	var progress: float = float(route.call(&"get_progress", world))
	_expect(is_equal_approx(progress, clampf(float(expected["cumulative"]) / length, 0.0, 1.0)),
		"get_progress differs from a full scan %s (%f)" % [label, progress])
	var leg: int = int(expected["leg_index"])
	var houses: int = int(route.get(&"house_count"))
	var expected_name: String = tr("WORLD_ROUTE_SECTION_GOAL") if leg >= houses \
		else tr("WORLD_ROUTE_SECTION_LEG") % [leg + 1, houses]
	_expect(String(route.call(&"get_section_name", world)) == expected_name, "get_section_name differs %s" % label)
	var cumulative: PackedFloat32Array = route.call(&"_path_cumulative")
	_expect(is_equal_approx(float(route.call(&"road_distance", world)), cumulative[_brute_path_index(route, world)]),
		"road_distance differs from a full scan %s" % label)
	_expect(is_equal_approx(float(route.call(&"distance_from_path", world)), _brute_distance_from_path(route, world)),
		"distance_from_path differs from a full scan %s" % label)


func _check_route() -> void:
	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var route: Node3D = level.get_node("World/Route")
	var points: Array[Vector3] = route.get(&"_path_points")
	_expect(points.size() > 20, "the route has a path to look up (%d points)" % points.size())
	var samples: Array = route.get(&"_progress_samples")

	# Drive the road end to end, a metre at a time, drifting from side to side.
	var checks: int = 0
	for index: int in range(1, points.size()):
		var a: Vector3 = route.to_global(points[index - 1])
		var b: Vector3 = route.to_global(points[index])
		var side: Vector3 = (b - a).normalized().cross(Vector3.UP)
		var steps: int = maxi(int(a.distance_to(b)), 1)
		for step: int in range(steps):
			var world: Vector3 = a.lerp(b, float(step) / float(steps)) + side * sin(float(checks) * 0.07) * 6.0
			_compare_route(route, world, "driving forwards at point %d" % index)
			checks += 1
	# ...and back again.
	for index: int in range(points.size() - 1, 0, -1):
		_compare_route(route, route.to_global(points[index]), "reversing at point %d" % index)
		checks += 1
	# Jumps: the start, the goal, the middle, off to the side, and the start again.
	var world_points: Array[Vector3] = [
		route.to_global(points[0]), route.to_global(points[-1]),
		route.to_global(points[points.size() / 2]),
		route.to_global(points[points.size() / 3] + Vector3(30.0, 0.0, 12.0)),
		route.to_global(points[0]), route.to_global(points[-1]), route.to_global(points[points.size() / 2]),
		route.to_global(points[0]) + Vector3(0.0, 0.0, 400.0),
		route.to_global(samples[samples.size() - 1]["position"]), route.to_global(samples[0]["position"]),
	]
	for world: Vector3 in world_points:
		_compare_route(route, world, "after a jump to %s" % world)
		checks += 1
	# A truck blown to NaN is off the road, as the full scan always said.
	var lost: Vector3 = Vector3(NAN, NAN, NAN)
	_expect(route.distance_from_path(lost) > 42.0, "a NaN position reads as off the road")
	print("route lookups compared with a full scan: %d" % checks)
	level.queue_free()
	await process_frame


# --- Endless's streamer ---------------------------------------------------

func _brute_nearest_on_path(streamer: Node3D, local: Vector3) -> Dictionary:
	var path: Array = streamer.get(&"_path")
	var flat := Vector2(local.x, local.z)
	var best: Dictionary = {"position": path[0].position, "distance": path[0].distance}
	var best_gap: float = INF
	for index: int in range(maxi(path.size() - 1, 1)):
		var a: Dictionary = path[index]
		var b: Dictionary = path[mini(index + 1, path.size() - 1)]
		var a2 := Vector2((a.position as Vector3).x, (a.position as Vector3).z)
		var b2 := Vector2((b.position as Vector3).x, (b.position as Vector3).z)
		var span: Vector2 = b2 - a2
		var t: float = clampf((flat - a2).dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
		var gap: float = flat.distance_squared_to(a2 + span * t)
		if gap < best_gap:
			best_gap = gap
			best = {
				"position": (a.position as Vector3).lerp(b.position, t),
				"distance": lerpf(float(a.distance), float(b.distance), t),
			}
	return best


func _check_streamer() -> void:
	var streamer := RouteStreamer.new()
	root.add_child(streamer)
	var target := Node3D.new()
	root.add_child(target)
	streamer.start(target)
	var checks: int = 0
	var ridden: float = 0.0
	var culled: bool = false
	while ridden < 2500.0:
		ridden += 1.5
		target.global_position = streamer.point_at(ridden) + Vector3(sin(ridden * 0.05) * 5.0, 0.0, 0.0)
		streamer.call(&"_fill_ahead")
		var before: int = (streamer.get(&"_path") as Array).size()
		streamer.call(&"_cull_behind")
		culled = culled or (streamer.get(&"_path") as Array).size() < before
		var local: Vector3 = streamer.to_local(target.global_position)
		var expected: Dictionary = _brute_nearest_on_path(streamer, local)
		var got: Dictionary = streamer.call(&"_nearest_on_path", local)
		var same: bool = is_equal_approx(float(got.distance), float(expected.distance)) \
			and (got.position as Vector3).is_equal_approx(expected.position)
		if not same:
			_expect(false, "streamer lookup differs from a full scan at %.1f m" % ridden)
			break
		# A jump back to the start of the live road and to the far end of it.
		if checks % 97 == 0:
			for far: Vector3 in [Vector3(0.0, 0.0, 200.0), (streamer.get(&"_path") as Array)[-1].position]:
				var far_expected: Dictionary = _brute_nearest_on_path(streamer, far)
				var far_got: Dictionary = streamer.call(&"_nearest_on_path", far)
				_expect(is_equal_approx(float(far_got.distance), float(far_expected.distance)),
					"streamer lookup differs after a jump at %.1f m" % ridden)
		checks += 1
	_expect(culled, "the streamer culled the road behind (so the lookup's index shifted)")
	print("streamer lookups compared with a full scan: %d" % checks)
	streamer.queue_free()
	target.queue_free()
	await process_frame


# --- the HUD throttle -----------------------------------------------------

func _on_progress(_progress: float, _meters: float, _section: String) -> void:
	_progress_signals += 1


func _on_status(in_zone: bool, stopped: float) -> void:
	_status_signals += 1
	_last_status = [in_zone, stopped]


func _check_level_throttle() -> void:
	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	var run: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	var route: Node3D = level.get_node("World/Route")
	var vehicle: RigidBody3D = level.get_node("World/Vehicle")
	vehicle.freeze = true
	run.start_run()
	_expect(run.is_running, "the run started")
	bus.route_progress_changed.connect(_on_progress)
	bus.delivery_status_changed.connect(_on_status)
	var delta: float = 1.0 / 60.0
	# Outside the delivery zone: 45 ticks (0.75 s) of driving.
	route.is_vehicle_in_delivery = false
	for tick: int in range(45):
		level._physics_process(delta)
	_expect(_progress_signals >= 5 and _progress_signals <= 8,
		"route_progress_changed is throttled to ~8 Hz (%d in 0.75 s, was 45)" % _progress_signals)
	_expect(float(level.stopped_seconds) == 0.0, "not in the zone, nothing accumulates")
	_expect(_status_signals <= 8, "delivery_status_changed is throttled outside a state change (%d)" % _status_signals)
	# Stopping in the zone: the state change goes out at once, the count runs every tick.
	route.is_vehicle_in_delivery = true
	var before: int = _status_signals
	level._physics_process(delta)
	_expect(_status_signals == before + 1 and _last_status[0] == true and float(_last_status[1]) > 0.0,
		"entering the zone and holding still is signalled on the very tick")
	_progress_signals = 0
	_status_signals = 0
	for tick: int in range(40):
		level._physics_process(delta)
	var stopped: float = level.stopped_seconds
	_expect(is_equal_approx(stopped, 41.0 * delta), "stopped_seconds counts every tick (%f)" % stopped)
	_expect(_progress_signals >= 4 and _progress_signals <= 6,
		"still ~8 Hz while stopped (%d in 0.67 s)" % _progress_signals)
	_expect(_status_signals >= 4 and _status_signals <= 6,
		"delivery status at ~8 Hz while stopped (%d)" % _status_signals)
	# The run still ends on stopped_seconds, however rarely the HUD hears it.
	for tick: int in range(30):
		level._physics_process(delta)
	_expect(not run.is_running, "stopping in the zone for a second still ends the run")
	bus.route_progress_changed.disconnect(_on_progress)
	bus.delivery_status_changed.disconnect(_on_status)
	level.queue_free()
	await process_frame
