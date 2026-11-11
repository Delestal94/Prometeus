extends RefCounted
## The company-day bot's driver (tests/bot_company_day.gd, D-2016.2 drive and return, D-2016.3 autopilot).
## Not a test: preloaded. It drives the fleet's van (CompanyFleet, the real node in CompanyTrips' group)
## the way a player does, with no hand on the gate: the player opens the cab door and takes the wheel
## (SeatPoint.interact, as the host does), the driving actions are held down (Input, read by
## VehicleInputComponent) and CompanyTrips, which follows the node every physics tick, sees it cross.
## drive_out: the pedal until the van's Trip starts, then the handbrake outside the yard.
## drive_to / drive_in: the autopilot (D-2016.3, D-0304.3). It plans with RoadNavigator.route over the
## street graph (RoadGraph, the company world's own) from where the van is to a point of the map and
## follows the polyline tick by tick, pure pursuit: it aims at the point `lookahead_for(speed)` metres
## ahead on the line, the steering is proportional to the heading error (pure pursuit's curvature,
## analog: Input.action_press with a strength), the speed is capped lower in bends and ends at the
## brake. It reports how far outside the roadway the van ever was while on the street (off_road_max,
## D-0304.3's OFF_ROAD: under OFF_ROAD_LIMIT_M; the centre line's distance, line_max, is no measure of it: a
## right-angle corner is cut by up to 3.6 m at the van's turning radius, inside the roadway). The way between the
## yard and the street is not in the graph (its node `shed` is the shed's centre): a Bezier leg (leg())
## joins the van's exit to the avenue and back, and the line is that leg plus the route.
## The calculation (closest(), point_at(), steer_toward(), lookahead_for(), target_speed(), leg(),
## plan()) is static and pure, tests/test_company_bot_autopilot.gd checks it without physics.
## Each drive waits at most a number of ticks proportional to the line (ticks_for()) and then stops
## the van with the handbrake. The physics runs in real time (60 ticks a second): the whole way to
## Centro takes about a minute and a half each way, so a test may cap it (`cap_m`, metres past the yard's leg).

## The driver's seat of the van scene (as test_company_van_drive.gd) and the door it is boarded by.
const SEAT_PATH: NodePath = ^"CabinInterior/DriverEyePoint/InteractionArea"
const DRIVER_DOOR: StringName = &"cab_left"
const ACCELERATE: StringName = &"drive_accelerate"
const BRAKE: StringName = &"drive_brake"
const HANDBRAKE: StringName = &"drive_handbrake"
## Physics ticks the van may take to cross the gate (out or back in) before the stage fails.
const DRIVE_TICKS: int = 900
## Physics ticks the van may take to stop once the pedal is let go.
const STOP_TICKS: int = 300
## Speed (m/s) under which the van counts as stopped.
const STOPPED_MPS: float = 0.3

# --- The autopilot's numbers ---
const STEER_RIGHT: StringName = &"drive_right"
const STEER_LEFT: StringName = &"drive_left"
## Wheelbase of the van (m) and the wheel angle (rad) that is full steering at speed: pure pursuit's
## curvature becomes the wheel angle atan(wheelbase * curvature), as a fraction of the full lock.
const WHEELBASE_M: float = 3.2
const FULL_LOCK_RAD: float = 0.32
## How far ahead on the line it aims (m): LOOKAHEAD_MIN_M at a stand, a LOOKAHEAD_PER_MPS more for every
## m/s, no more than LOOKAHEAD_MAX_M.
const LOOKAHEAD_MIN_M: float = 7.0
const LOOKAHEAD_PER_MPS: float = 0.5
const LOOKAHEAD_MAX_M: float = 14.0
## Cruise speed on a straight (m/s, about 50 km/h) and the slowest it goes round a bend.
const CRUISE_MPS: float = 16.0
const BEND_MPS: float = 4.0
## The bend ahead is read over the next bend_span_for(speed) metres of the line (the turn of its direction,
## rad, where BEND_FULL_RAD is the slowest).
const BEND_SPAN_MIN_M: float = 14.0
const BEND_SPAN_PER_MPS: float = 2.0
const BEND_SPAN_MAX_M: float = 40.0
const BEND_FULL_RAD: float = 1.4
## How far apart the two points that give a direction of the line are (m).
const DIRECTION_STEP_M: float = 3.0
## Braking the autopilot plans for when it comes to the end (m/s^2) and the speed it creeps in at.
const BRAKE_MPS2: float = 2.5
const CREEP_MPS: float = 1.5
## Throttle per m/s of speed missing (analog, 1 is the whole pedal).
const THROTTLE_GAIN: float = 0.35
## The most the van's centre may be outside the roadway (m), checked every OFF_ROAD_CHECK_TICKS: it
## is 2.2 m wide, so its wheels are on the kerb at one metre. D-0304.3's OFF_ROAD = 0 is "in the street".
const OFF_ROAD_LIMIT_M: float = 1.0
const OFF_ROAD_CHECK_TICKS: int = 6
## A K-turn takes more road than the street has (the van's turning circle is about 14 m across, a street 8 to
## 12): it may take its centre this far outside the roadway while it turns (the kerb, a bit of the verge).
const TURN_OFF_ROAD_LIMIT_M: float = 5.0
## Turning round (a van facing away from its line, at a stand): strokes at full lock, forward and in reverse,
## each until the nose swung TURN_SWING_RAD or it rolled TURN_STROKE_M; done when the nose is within
## TURN_DONE_RAD of the line; it starts when it is farther than TURN_START_RAD from it.
const TURN_START_RAD: float = 1.9
const TURN_DONE_RAD: float = 0.9
const TURN_SWING_RAD: float = 0.9
const TURN_STROKE_M: float = 14.0
const TURN_STROKES: int = 8
const TURN_STROKE_TICKS: int = 480
const TURN_MPS: float = 2.5
## The van has arrived when it is this close (m) to the end of the line.
const ARRIVE_M: float = 4.0
## The van is stuck when, with the line ahead, it stays under STOPPED_MPS this many ticks.
const STUCK_TICKS: int = 240
## Time the whole drive may take: the line over MIN_AVG_MPS plus a fixed grace (s). 60 ticks a second.
const MIN_AVG_MPS: float = 4.0
const GRACE_SECONDS: float = 25.0
## Spacing of the points of a leg (m).
const LEG_STEP_M: float = 6.0
## How far past the best segment closest() keeps looking (m), so a bend does not end the search early.
const CLOSEST_WINDOW_M: float = 30.0
## How far the leg's handles reach (as a fraction of the distance between its ends).
const LEG_HANDLE: float = 0.5


## The fleet's vehicle `vehicle_id` of `level` (a CompanyRoot), or null.
static func van_of(level: CompanyRoot, vehicle_id: StringName) -> VehicleBody3D:
	return level.fleet.vehicle(String(vehicle_id)) as VehicleBody3D if level.fleet != null else null


## The player opens the cab door and sits at the wheel of the van (SeatPoint.interact, as the host does;
## the seat has no reach check: no walk to the door). "" when it is at the wheel, else why.
static func take_wheel(tree: SceneTree, level: CompanyRoot, vehicle_id: StringName) -> String:
	var van: VehicleBody3D = van_of(level, vehicle_id)
	if van == null:
		return "no_van"
	var seat := van.get_node_or_null(SEAT_PATH) as SeatPoint
	if seat == null:
		return "no_driver_seat"
	van.call(&"set_door_open", DRIVER_DOOR, true)
	seat.interact(level.player)
	await tree.physics_frame
	if int(van.get(&"driver_peer_id")) != level.player.get_multiplayer_authority():
		return "not_at_wheel"
	return ""


## The player takes the wheel of the van parked in the yard and drives it out until its Trip starts,
## then lets it stop outside, still at the wheel. {"reason": "" when it left, else why; "metres": how
## far the van ended from where it was parked}.
static func drive_out(tree: SceneTree, level: CompanyRoot, vehicle_id: StringName) -> Dictionary:
	var trips: CompanyTrips = level.trips
	var van: VehicleBody3D = van_of(level, vehicle_id)
	if van == null:
		return {"reason": "no_van", "metres": 0.0}
	if trips.gate == null or trips.gate.side_of(van.global_position) != TripGate.INSIDE \
			or trips.trips_out() != 0:
		return {"reason": "van_not_in_yard", "metres": 0.0}
	var seated: String = await take_wheel(tree, level, vehicle_id)
	if seated != "":
		return {"reason": seated, "metres": 0.0}
	var start: Vector3 = van.global_position
	var left: bool = await hold_until(tree, ACCELERATE, func() -> bool: return trips.trip_of(vehicle_id) != null)
	await stop(tree, van)
	var metres: float = van.global_position.distance_to(start)
	if not left or trips.trips_out() != 1:
		return {"reason": "not_departed", "metres": metres}
	if trips.gate.side_of(van.global_position) != TripGate.OUTSIDE:
		return {"reason": "van_not_out", "metres": metres}
	return {"reason": "", "metres": metres}


## The driver takes the van back to the yard with the autopilot: along the street to `street` (a point
## of the map on the avenue, where the yard's leg joins it), then the leg `home` to a point inside the
## yard, which closes the Trip as the van crosses the gate. It lets the van stop, gets out and checks it
## is inside. {"reason": "" when it is back inside, else why; the rest of drive_to() (metres, off_road_max,
## length)}.
static func drive_in(
	tree: SceneTree, level: CompanyRoot, vehicle_id: StringName, street: Vector2,
	home: PackedVector2Array
) -> Dictionary:
	var trips: CompanyTrips = level.trips
	var van: VehicleBody3D = van_of(level, vehicle_id)
	if van == null or int(van.get(&"driver_peer_id")) == 0:
		return {"reason": "nobody_at_wheel", "metres": 0.0, "off_road_max": 0.0}
	var driven: Dictionary = await drive_to(tree, level, vehicle_id, street, PackedVector2Array(), home)
	(level.player as Player).leave_seat()
	await tree.process_frame
	if driven["reason"] == "" and (
			trips.trip_of(vehicle_id) != null or trips.gate.side_of(van.global_position) != TripGate.INSIDE):
		driven["reason"] = "not_returned"
	return driven


## Holds the driving `action` down, a physics tick at a time, until `done` says so (true) or
## DRIVE_TICKS pass (false). The pedal is let go either way.
static func hold_until(tree: SceneTree, action: StringName, done: Callable) -> bool:
	Input.action_press(action)
	var reached: bool = false
	for _tick: int in DRIVE_TICKS:
		await tree.physics_frame
		if done.call():
			reached = true
			break
	Input.action_release(action)
	return reached


## Off the pedal, the handbrake held until the van stands (at most STOP_TICKS), then let go.
static func stop(tree: SceneTree, van: VehicleBody3D) -> void:
	Input.action_press(HANDBRAKE)
	for _tick: int in STOP_TICKS:
		await tree.physics_frame
		if van.freeze or van.linear_velocity.length() < STOPPED_MPS:
			break
	Input.action_release(HANDBRAKE)


# --- The autopilot ---


## Drives the van of `vehicle_id` (somebody at its wheel) along the street graph to `target` (a point of
## the map, x z): the line is `before` (points the van goes through first, off the graph), then the
## quickest route from the last of them (or from the van) to `target`, then `after`. It follows the line
## tick by tick (pure pursuit, see the header), brakes at its end and lets the van stand. `cap_m` > 0 ends
## the drive after that many metres of the route's part (the line past `before`; a test's short run).
## {"reason": "" when it got there (or to the cap), else why: no_van, no_route:<why>, stuck, timeout,
## cannot_turn; "metres" driven; "length" of the line; "turn_strokes" and "turn_off_road_max" of its K-turn if
## it faced away from the line (turn_around()); "off_road_max": the most the van's centre was outside the
## roadway while on the route's part
## (outside_roadway(); D-0304.3: it stays in the street if that is under OFF_ROAD_LIMIT_M) and "off_road_at"
## where; "line_max" the most it was from the route's centre line; "half_width" of the narrowest street used;
## "end": where it stood}.
static func drive_to(
	tree: SceneTree, level: CompanyRoot, vehicle_id: StringName, target: Vector2,
	before: PackedVector2Array = PackedVector2Array(), after: PackedVector2Array = PackedVector2Array(),
	cap_m: float = 0.0
) -> Dictionary:
	var van: VehicleBody3D = van_of(level, vehicle_id)
	var result: Dictionary = {
		"reason": "no_van", "metres": 0.0, "length": 0.0, "off_road_max": 0.0, "half_width": 0.0,
		"end": Vector2.ZERO,
	}
	if van == null:
		return result
	var net: RoadGraph = RoadGraph.load_default()
	var plan_: Dictionary = plan(net, ground_of(van), target, before, after)
	if not bool(plan_["ok"]):
		result["reason"] = "no_route:%s" % plan_["why"]
		return result
	var line: PackedVector2Array = plan_["line"]
	var length: float = float(plan_["length"])
	var road_from: float = float(plan_["road_from_m"])
	var end_m: float = minf(length, road_from + cap_m) if cap_m > 0.0 else length
	result["length"] = length
	result["half_width"] = float(plan_["half_width"])
	var max_ticks: int = ticks_for(end_m)
	var road_to: float = float(plan_["road_to_m"])
	var turned: int = 0
	var turn_off: float = 0.0
	var first: Vector2 = point_at(line, DIRECTION_STEP_M * 3.0) - point_at(line, 0.0)
	if absf(forward_of(van).angle_to(first)) > TURN_START_RAD and absf(forward_speed(van)) < 2.0:
		var spun: Dictionary = await turn_around(tree, van, net, first)
		turned = int(spun["strokes"])
		turn_off = float(spun["outside_max"])
		if not bool(spun["ok"]):
			result["reason"] = "cannot_turn"
			result["turn_strokes"] = turned
			result["turn_off_road_max"] = turn_off
			return result
	var off_max: float = 0.0
	var off_at: Vector2 = Vector2.ZERO
	var line_max: float = 0.0
	var ticks: int = 0
	var index: int = 0
	var along: float = 0.0
	var last: Vector2 = ground_of(van)
	var metres: float = 0.0
	var slow_ticks: int = 0
	var reason: String = "timeout"
	for _tick: int in max_ticks:
		await tree.physics_frame
		ticks += 1
		var here: Vector2 = ground_of(van)
		metres += here.distance_to(last)
		last = here
		var near: Dictionary = closest(line, here, index)
		index = int(near["index"])
		along = float(near["along"])
		if along >= road_from and along <= road_to and ticks % OFF_ROAD_CHECK_TICKS == 0:
			var outside: float = outside_roadway(net, here)
			if outside > off_max:
				off_max = outside
				off_at = here
			line_max = maxf(line_max, float(near["distance"]))
		var speed: float = forward_speed(van)
		if along >= (end_m if cap_m > 0.0 else end_m - ARRIVE_M):
			reason = ""
			break
		if absf(speed) < STOPPED_MPS:
			slow_ticks += 1
			if slow_ticks > STUCK_TICKS:
				reason = "stuck"
				break
		else:
			slow_ticks = 0
		var aim: Vector2 = point_at(line, minf(end_m, along + lookahead_for(speed)))
		var steer: float = steer_toward(forward_of(van), aim - here, here.distance_to(aim))
		var wanted: float = target_speed(line, along, end_m, steer, speed)
		_drive_inputs(clampf((wanted - speed) * THROTTLE_GAIN, -1.0, 1.0), steer)
	_drive_inputs(0.0, 0.0)
	await stop(tree, van)
	result["reason"] = reason
	result["metres"] = metres
	result["off_road_max"] = off_max
	result["off_road_at"] = off_at
	result["line_max"] = line_max
	result["turn_strokes"] = turned
	result["turn_off_road_max"] = turn_off
	result["end"] = ground_of(van)
	return result


## Turns the van round at a stand until its nose is within TURN_DONE_RAD of `want` (a direction, x z): a K-turn,
## strokes at full lock (forward turns the nose toward the side it is steered to, in reverse the other way),
## each ending with the handbrake, then the other gear. {"ok", "strokes", "outside_max": the most its centre was
## outside the roadway of `net` meanwhile}.
static func turn_around(tree: SceneTree, van: VehicleBody3D, net: RoadNetwork, want: Vector2) -> Dictionary:
	var outside_max: float = 0.0
	var gear: float = 1.0
	var strokes: int = 0
	for _stroke: int in TURN_STROKES:
		var error: float = forward_of(van).angle_to(want)
		if absf(error) <= TURN_DONE_RAD:
			return {"ok": true, "strokes": strokes, "outside_max": outside_max}
		strokes += 1
		var side: float = signf(error)
		var start_nose: Vector2 = forward_of(van)
		var start_at: Vector2 = ground_of(van)
		for tick: int in TURN_STROKE_TICKS:
			await tree.physics_frame
			if absf(start_nose.angle_to(forward_of(van))) >= TURN_SWING_RAD \
					or ground_of(van).distance_to(start_at) >= TURN_STROKE_M:
				break
			if tick % OFF_ROAD_CHECK_TICKS == 0:
				outside_max = maxf(outside_max, outside_roadway(net, ground_of(van)))
			var throttle: float = clampf((TURN_MPS - forward_speed(van) * gear) * THROTTLE_GAIN, -1.0, 1.0)
			_drive_inputs(throttle * gear, side * gear)
		_drive_inputs(0.0, 0.0)
		await stop(tree, van)
		gear = -gear
	return {
		"ok": absf(forward_of(van).angle_to(want)) <= TURN_DONE_RAD, "strokes": strokes,
		"outside_max": outside_max,
	}


## The line of a drive: {ok, why, line: PackedVector2Array, length (m), road_from_m / road_to_m (where
## along the line the route's part is: before it and after it the van is on a leg, not on a street),
## half_width (m, of the narrowest street the route uses)}.
static func plan(
	net: RoadNetwork, from: Vector2, to: Vector2,
	before: PackedVector2Array = PackedVector2Array(), after: PackedVector2Array = PackedVector2Array()
) -> Dictionary:
	var failed: Dictionary = {
		"ok": false, "why": "", "line": PackedVector2Array(), "length": 0.0, "road_from_m": 0.0,
		"road_to_m": 0.0, "half_width": 0.0,
	}
	if net == null:
		failed["why"] = "no_graph"
		return failed
	var start: Vector2 = before[before.size() - 1] if not before.is_empty() else from
	var route: Dictionary = RoadNavigator.route(net, start, to)
	if not bool(route.get("ok", false)):
		failed["why"] = str(route.get("reason", "unknown"))
		return failed
	var line := PackedVector2Array()
	_join(line, before)
	var road_from: float = path_length(line)
	_join(line, route["polyline"])
	var road_to: float = path_length(line)
	_join(line, after)
	var half: float = INF
	for edge_id: StringName in route["edges"]:
		var edge: RoadEdge = net.edge_by_id(edge_id)
		if edge != null:
			half = minf(half, edge.half_width())
	return {
		"ok": true, "why": "", "line": line, "length": path_length(line), "road_from_m": road_from,
		"road_to_m": road_to, "half_width": half if half != INF else 0.0,
	}


## A leg off the graph from `a` leaving along `dir_a` to `b` arriving along `dir_b`: a cubic Bezier with
## handles of LEG_HANDLE of the distance, a point every LEG_STEP_M (a first point `a` is left out: the
## van is there).
static func leg(a: Vector2, dir_a: Vector2, b: Vector2, dir_b: Vector2) -> PackedVector2Array:
	var reach: float = a.distance_to(b) * LEG_HANDLE
	var c1: Vector2 = a + dir_a.normalized() * reach
	var c2: Vector2 = b - dir_b.normalized() * reach
	var steps: int = maxi(2, ceili(a.distance_to(b) * 1.3 / LEG_STEP_M))
	var points := PackedVector2Array()
	for i: int in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		points.append(a.bezier_interpolate(c1, c2, b, t))
	return points


## `points` reversed, from its end to its start.
static func reversed(points: PackedVector2Array) -> PackedVector2Array:
	var back := PackedVector2Array()
	for i: int in range(points.size() - 1, -1, -1):
		back.append(points[i])
	return back


static func path_length(line: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	return total


## The closest point of `line` to `p`, looking at the segments from `from_index` on (the line may come
## back near itself: the van only moves forward along it). {index (of the segment), point, along (m from
## the start of the line), distance (m from p)}. The search stops once a segment is farther than the
## best found and a few more have gone by.
static func closest(line: PackedVector2Array, p: Vector2, from_index: int = 0) -> Dictionary:
	var found: Dictionary = {"index": 0, "point": p, "along": 0.0, "distance": 0.0}
	if line.size() < 2:
		if line.size() == 1:
			found["point"] = line[0]
			found["distance"] = p.distance_to(line[0])
		return found
	var best: float = INF
	var walked: float = 0.0
	var first: int = clampi(from_index, 0, line.size() - 2)
	for i: int in first:
		walked += line[i].distance_to(line[i + 1])
	for i: int in range(first, line.size() - 1):
		var on_segment: Vector2 = Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		var d: float = p.distance_to(on_segment)
		if d < best:
			best = d
			found = {
				"index": i, "point": on_segment, "along": walked + line[i].distance_to(on_segment),
				"distance": d,
			}
		elif d > best + CLOSEST_WINDOW_M:
			break
		walked += line[i].distance_to(line[i + 1])
	return found


## The point `distance` metres along `line` (its end past the end).
static func point_at(line: PackedVector2Array, distance: float) -> Vector2:
	var walked: float = 0.0
	for i: int in line.size() - 1:
		var seg: float = line[i].distance_to(line[i + 1])
		if seg > 0.0 and walked + seg >= distance:
			return line[i].lerp(line[i + 1], (distance - walked) / seg)
		walked += seg
	return line[line.size() - 1] if not line.is_empty() else Vector2.ZERO


## How far ahead on the line the autopilot aims at `speed` (m/s).
static func lookahead_for(speed: float) -> float:
	return clampf(LOOKAHEAD_MIN_M + LOOKAHEAD_PER_MPS * maxf(speed, 0.0), LOOKAHEAD_MIN_M, LOOKAHEAD_MAX_M)


## The steering input (-1 full left .. 1 full right, what drive_right minus drive_left reads) that pure
## pursuit asks to reach `to_target` (the vector from the van to the aim point, at `distance`) from a van
## looking along `forward` (both x z, the map's axes: +x east, +z south, so a target to the east of a van
## facing north is on its right, positive). The curvature of the arc through the aim is 2 sin(a) / d;
## as a wheel angle it is atan(wheelbase * curvature), over the full lock.
static func steer_toward(forward: Vector2, to_target: Vector2, distance: float) -> float:
	if forward.length() < 0.001 or to_target.length() < 0.001:
		return 0.0
	var error: float = forward.angle_to(to_target)
	var curvature: float = 2.0 * sin(error) / maxf(distance, 0.5)
	# Past a right angle the target is behind: full lock to the side it is on.
	if absf(error) > PI * 0.5:
		return signf(error)
	return clampf(atan(WHEELBASE_M * curvature) / FULL_LOCK_RAD, -1.0, 1.0)


## The speed (m/s) the autopilot wants at `along` metres of `line`, which ends at `end_m`, going at `speed`: cruise
## on a straight, down to BEND_MPS as the line turns over the next bend_span_for(speed) metres (or as the steering
## asks for a lot), and no more than what brakes to a creep over what is left.
static func target_speed(
	line: PackedVector2Array, along: float, end_m: float, steer: float, speed: float = CRUISE_MPS
) -> float:
	var turn: float = absf(turn_ahead(line, along, bend_span_for(speed)))
	var bend: float = clampf(maxf(turn / BEND_FULL_RAD, absf(steer) * 0.6), 0.0, 1.0)
	var wanted: float = lerpf(CRUISE_MPS, BEND_MPS, bend)
	var left: float = maxf(0.0, end_m - along - ARRIVE_M * 0.5)
	return minf(wanted, CREEP_MPS + sqrt(2.0 * BRAKE_MPS2 * left))


## How far ahead the autopilot looks for a bend at `speed` (m/s): about the distance it needs to slow down.
static func bend_span_for(speed: float) -> float:
	return clampf(BEND_SPAN_MIN_M + BEND_SPAN_PER_MPS * maxf(speed, 0.0), BEND_SPAN_MIN_M, BEND_SPAN_MAX_M)


## How much the direction of `line` turns (rad, signed, positive to the right) between `along` and `span`
## metres further: the angle between the direction there and the direction here.
static func turn_ahead(line: PackedVector2Array, along: float, span: float) -> float:
	var here: Vector2 = point_at(line, along + DIRECTION_STEP_M) - point_at(line, along)
	var there: Vector2 = point_at(line, along + span + DIRECTION_STEP_M) - point_at(line, along + span)
	if here.length() < 0.01 or there.length() < 0.01:
		return 0.0
	return here.angle_to(there)


## Physics ticks a drive of `metres` of line may take.
static func ticks_for(metres: float) -> int:
	return int(ceilf((metres / MIN_AVG_MPS + GRACE_SECONDS) * 60.0))


## How far (m) `p` is outside the roadway of the streets of `net`: the distance to the nearest street's centre
## line less its half width, 0 on a street (D-0304.3's OFF_ROAD).
static func outside_roadway(net: RoadNetwork, p: Vector2) -> float:
	var near: Dictionary = net.nearest_point(p)
	if near.is_empty():
		return INF
	var edge: RoadEdge = net.edge_by_id(near["edge"])
	return maxf(0.0, float(near["distance"]) - (edge.half_width() if edge != null else 0.0))


## Distance (m) from `p` to the nearest point of `line`.
static func distance_to_line(line: PackedVector2Array, p: Vector2) -> float:
	return float(closest(line, p)["distance"])


## The van's place on the map: x z.
static func ground_of(body: Node3D) -> Vector2:
	return Vector2(body.global_position.x, body.global_position.z)


## The way the van's nose points (its -Z, vehicle.gd), x z, unit.
static func forward_of(body: Node3D) -> Vector2:
	var nose: Vector3 = -body.global_basis.z
	return Vector2(nose.x, nose.z).normalized()


## The van's speed along its nose (m/s), negative backwards.
static func forward_speed(body: RigidBody3D) -> float:
	var nose: Vector3 = -body.global_basis.z
	return body.linear_velocity.dot(nose)


## Appends `points` to `line` without repeating a joint.
static func _join(line: PackedVector2Array, points: PackedVector2Array) -> void:
	for p: Vector2 in points:
		if line.is_empty() or line[line.size() - 1].distance_to(p) > 0.001:
			line.append(p)


## Holds the pedal (`throttle` -1..1: the brake below zero) and the wheel (`steer` -1..1) at those strengths.
static func _drive_inputs(throttle: float, steer: float) -> void:
	_hold(ACCELERATE, maxf(throttle, 0.0))
	_hold(BRAKE, maxf(-throttle, 0.0))
	_hold(STEER_RIGHT, maxf(steer, 0.0))
	_hold(STEER_LEFT, maxf(-steer, 0.0))


static func _hold(action: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)
