extends RefCounted
## The company-day bot's road follower (D-0304.3). Not a test: preloaded by tests/test_company_road_follow.gd.
## It drives the fleet's van along the GPS's route over the street graph (RoadNavigator.route() on
## RoadGraph.load_default()) with the driving actions held down, the way a player with the arrow does:
## the steering aims at the waypoint `AHEAD_M` meters on along the route (RoadNavigator.guidance()), the
## pedal is held. Pure functions (steer_toward, map_point, half_width, off_road_m) are static so a test
## can check them without a world.
## Map points are Vector2 (x, z of the graph); the graph's node "shed" is the shed's position in the world.

const VAN := preload("res://tests/bot_company_van.gd")
const STEER_LEFT: StringName = &"drive_left"
const STEER_RIGHT: StringName = &"drive_right"
## The angle off the nose (radians) at which the steering is at full lock; below it, proportional.
const STEER_FULL_LOCK: float = 0.5
## How far ahead along the route the bot aims, meters.
const AHEAD_M: float = 18.0
## Physics ticks the follow may take (60 a second).
const MAX_TICKS: int = 3600
## The bot has joined the road once it is this close (meters) to the route's center line.
const JOINED_WITHIN_M: float = 3.0


## The steering (-1 full left .. 1 full right, as Input.get_axis(drive_left, drive_right)) that points a
## vehicle at `van_transform` to `target` (world), proportional to the angle off its nose on the ground.
static func steer_toward(van_transform: Transform3D, target: Vector3) -> float:
	var forward: Vector3 = -van_transform.basis.z
	forward.y = 0.0
	var wanted: Vector3 = target - van_transform.origin
	wanted.y = 0.0
	if forward.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
		return 0.0
	# Counter-clockwise seen from above is to the left, so the steering is the angle with its sign flipped.
	return clampf(-forward.signed_angle_to(wanted, Vector3.UP) / STEER_FULL_LOCK, -1.0, 1.0)


## The map point (x, z of the graph) of a world position, with the shed at the graph's "shed" node.
static func map_point(world: Vector3, shed_origin: Vector3) -> Vector2:
	return Vector2(world.x - shed_origin.x, world.z - shed_origin.z)


## The world position of a map point.
static func world_point(map: Vector2, shed_origin: Vector3) -> Vector3:
	return Vector3(shed_origin.x + map.x, shed_origin.y, shed_origin.z + map.y)


## Half the width of the narrowest street a planned route runs on (meters).
static func half_width(net: RoadNetwork, planned: Dictionary) -> float:
	var narrowest: float = INF
	for edge_id: StringName in planned.get("edges", []):
		narrowest = minf(narrowest, float(net.edge_by_id(edge_id).width))
	return narrowest * 0.5 if narrowest < INF else 0.0


## Meters from `position` (map) to the route's center line.
static func off_road_m(planned: Dictionary, position: Vector2) -> float:
	var line: PackedVector2Array = planned.get("polyline", PackedVector2Array())
	var best: float = INF
	for i in line.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(position, line[i], line[i + 1])
		best = minf(best, position.distance_to(closest))
	return best


## The player at the wheel of `vehicle_id`'s van, parked in the yard, drives it along the route from where it
## stands to `to` (map) until it is within `arrive_m` of the end or MAX_TICKS pass, then stops it.
## { ok, reason, ticks, metres (driven), off_road_ticks (joined the road, then farther than its half width),
## off_road_max_m (the largest distance to the center line after joining), joined, remaining_m (route left) }.
static func follow(tree: SceneTree, level: CompanyRoot, vehicle_id: StringName, graph: RoadGraph,
		to: Vector2, arrive_m: float = 12.0) -> Dictionary:
	var van: VehicleBody3D = VAN.van_of(level, vehicle_id)
	var out := {"ok": false, "reason": "", "ticks": 0, "metres": 0.0, "off_road_ticks": 0,
		"off_road_max_m": 0.0, "joined": false, "remaining_m": INF}
	if van == null:
		out.reason = "no_van"
		return out
	var origin: Vector3 = level.shed.global_position
	var planned: Dictionary = RoadNavigator.route(graph, map_point(van.global_position, origin), to)
	if not planned.ok:
		out.reason = String(planned.reason)
		return out
	var seat := van.get_node_or_null(VAN.SEAT_PATH) as SeatPoint
	if seat == null:
		out.reason = "no_driver_seat"
		return out
	van.call(&"set_door_open", VAN.DRIVER_DOOR, true)
	seat.interact(level.player)
	await tree.physics_frame
	if int(van.get(&"driver_peer_id")) != level.player.get_multiplayer_authority():
		out.reason = "not_at_wheel"
		return out
	var half: float = half_width(graph, planned)
	var start: Vector3 = van.global_position
	var last: Vector3 = start
	Input.action_press(VAN.ACCELERATE)
	for tick: int in MAX_TICKS:
		await tree.physics_frame
		out.ticks = tick + 1
		var here: Vector2 = map_point(van.global_position, origin)
		var guide: Dictionary = RoadNavigator.guidance(planned, here, AHEAD_M)
		out.remaining_m = float(guide.distance)
		out.metres += van.global_position.distance_to(last)
		last = van.global_position
		var away: float = off_road_m(planned, here)
		if not out.joined and away <= JOINED_WITHIN_M:
			out.joined = true
		if out.joined:
			out.off_road_max_m = maxf(out.off_road_max_m, away)
			if away > half:
				out.off_road_ticks += 1
		if guide.done or float(guide.distance) <= arrive_m:
			out.ok = true
			break
		_steer(steer_toward(van.global_transform, world_point(Vector2(guide.waypoint.x, guide.waypoint.z), origin)))
	Input.action_release(VAN.ACCELERATE)
	_steer(0.0)
	await VAN.stop(tree, van)
	return out


## Holds the steering actions at `amount` (-1 left .. 1 right).
static func _steer(amount: float) -> void:
	if amount < 0.0:
		Input.action_release(STEER_RIGHT)
		Input.action_press(STEER_LEFT, -amount)
	else:
		Input.action_release(STEER_LEFT)
		Input.action_press(STEER_RIGHT, amount)
