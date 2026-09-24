extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_streaming.gd
## Covers RouteStreamer in isolation, without a real vehicle: a plain Node3D
## stands in for the tracked target and gets moved by hand along the road,
## since what's under test is the spawn/cull bookkeeping, not vehicle physics.
## Endless bends now (tareas de Nacho N-206): the target rides 5 km of road
## that must never come back across itself, with the live road -- and the
## nodes behind it -- staying bounded all the way.

const DRIVE_METRES: float = 5000.0
const STEP_METRES: float = 25.0
const ROAD_WIDTH: float = 12.0
## Closer than this along the road, two points are the same stretch.
const NEIGHBOUR_ALONG: float = 60.0

var _failures: int = 0


func _initialize() -> void:
	await process_frame

	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 31337)
	var streamer := RouteStreamer.new()
	root.add_child(streamer)
	var target := Node3D.new()
	root.add_child(target)

	streamer.start(target)
	_expect((streamer.get(&"_active") as Array).size() > 0,
		"start() spawns at least one segment ahead of the target immediately")
	_expect(float(streamer.get(&"_next_distance")) >= float(streamer.get(&"lookahead_distance")),
		"The first lookahead_distance of road is built before anyone moves")

	# Ride the road STEP_METRES at a time, the same way _physics_process would
	# across many frames -- called directly so the test doesn't depend on real
	# frame timing. Every stretch of centre line ever built is kept here.
	var seen: Dictionary = {}  # rounded distance -> position (world)
	var peak_children: int = 0
	var lookahead_ok: bool = true
	var stale_found: bool = false
	var repeated_type: bool = false
	var bends: int = 0
	var heading_ok: bool = true
	var ridden: float = 0.0
	while ridden < DRIVE_METRES:
		ridden += STEP_METRES
		target.global_position = streamer.point_at(ridden)
		streamer.call(&"_fill_ahead")
		streamer.call(&"_cull_behind")
		# Culled segments are queue_free()d: let them go before counting.
		await process_frame
		for sample: Dictionary in streamer.get(&"_path"):
			seen[roundi(float(sample.distance))] = streamer.to_global(sample.position)
		var at: float = streamer.distance_along(target.global_position)
		if float(streamer.get(&"_next_distance")) < at + float(streamer.get(&"lookahead_distance")):
			lookahead_ok = false
		var active: Array = streamer.get(&"_active")
		for index: int in range(active.size()):
			var segment: Node = active[index]
			if float(segment.get_meta(&"route_end", 0.0)) < at - float(streamer.get(&"behind_keep_distance")):
				stale_found = true
			if index > 0 and segment.get_script() == active[index - 1].get_script():
				repeated_type = true
		peak_children = maxi(peak_children, streamer.get_child_count())
		if absf(float(streamer.get(&"_heading_deg"))) > RouteStreamer.MAX_HEADING_DEG + 0.01:
			heading_ok = false
	for child: Node in streamer.get_children():
		if child is CurveSegment:
			bends += 1

	_expect(absf(streamer.distance_along(target.global_position) - DRIVE_METRES) < 15.0,
		"The target really rode %.0f m of road (at %.0f)" % [DRIVE_METRES, streamer.distance_along(target.global_position)])
	_expect(lookahead_ok, "Always keeps at least lookahead_distance of road already built ahead of the target")
	_expect(not stale_found, "Segments well behind the target get freed, not kept forever")
	_expect(peak_children < 40, "The live road stays bounded over 5 km (at most %d nodes under the streamer)" % peak_children)
	_expect(not repeated_type, "Combination rule holds: no two consecutive segments are the same type")
	_expect(heading_ok, "The road never heads more than %.0f degrees off -Z" % RouteStreamer.MAX_HEADING_DEG)
	_expect(bends > 0 or _has_bent(seen), "Endless actually bends now")
	_expect(streamer.distance_from_path(target.global_position) < 0.5, "Riding the centre line reads as on the road")
	var along: Vector3 = (streamer.point_at(ridden + 5.0) - streamer.point_at(ridden)).normalized()
	var aside: Vector3 = along.cross(Vector3.UP).normalized() * 30.0
	_expect(streamer.distance_from_path(target.global_position + aside) > 20.0,
		"30 m to the side of the road reads as off it (%.1f m)" % streamer.distance_from_path(target.global_position + aside))

	# No crossings: two points far apart along the road stay a road apart.
	var keys: Array = seen.keys()
	keys.sort()
	var grid: Dictionary = {}
	var crossing: String = ""
	for key: int in keys:
		var here: Vector3 = seen[key]
		var cell := Vector2i(floori(here.x / ROAD_WIDTH), floori(here.z / ROAD_WIDTH))
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for other: int in grid.get(cell + Vector2i(dx, dz), []):
					var there: Vector3 = seen[other]
					if key - other > NEIGHBOUR_ALONG and Vector2(here.x - there.x, here.z - there.z).length() < ROAD_WIDTH and crossing.is_empty():
						crossing = "at %d m over %d m" % [key, other]
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(key)
	_expect(crossing.is_empty(), "5 km of road never come back across themselves (%s)" % crossing)

	network.set(&"world_seed", 0)
	if _failures == 0:
		print("PASS: RouteStreamer bends, spawns ahead and culls behind along the road, and 5 km never cross themselves")
	quit(_failures)


## Whether the recorded road strays off the Z axis at all.
func _has_bent(seen: Dictionary) -> bool:
	for position: Vector3 in seen.values():
		if absf(position.x) > 5.0:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
