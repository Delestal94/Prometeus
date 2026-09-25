extends Node3D
## Procedurally generated first delivery route (2026-09-22 rework): the road
## actually bends now, and each stretch between one house and the next is a
## mini-adventure, as long as the route's time budget allows
## (leg_target_length()), built from the same
## segment pool RouteStreamer uses for modo endless -- straight, speed bump,
## chicane, narrow bridge, S-curve, gravel, construction zone -- plus
## CurveSegment, which is the one segment type that actually changes the
## road's heading instead of just adding obstacles inside a straight lane.
## Segments are chained by walking a Transform3D cursor forward (position +
## heading), not a flat -Z offset -- every previous segment type still
## builds itself in its own local space exactly as before, so none of them
## needed to change; only the chaining and the dressing (forest/props, which
## used to assume "the road is the Z axis") needed to become curve-aware.
##
## Modo endless (RouteStreamer) chains its segments the same way since
## N-206, streaming and culling along the road instead of along -Z.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")

signal delivery_entered
signal delivery_exited
## Fires whenever any house resolves (delivered ok/ruined/missed) -- forwards
## DeliveryHouse.resolved so level_base.gd or the HUD can react without
## walking the house list themselves.
signal house_resolved(house_index: int, outcome: StringName, package_id: StringName)

@export var route_length: float = 0.0
## How many delivery houses this run has: one per passenger, i.e. players
## minus the driver, never fewer than one (docs/tareas-nacho.md #104). 0 means
## "work it out" when the route builds: the session's number if the host
## already decided one (NetworkManager.world_house_count), otherwise from the
## crew -- and an online host records that as the session's number. Set it
## (or call configure_houses()) before this node enters the tree to force one.
@export var house_count: int = 0
## Folds the static dressing into MultiMesh batches once it's placed, and
## each segment's road furniture into one mesh (see dressing_batcher.gd) --
## the difference between ~16k draw calls a frame and a couple of thousand.
## Tests that inspect individual placed pieces turn it off.
@export var batch_dressing: bool = true
## Ground kept level and clear of trees and props behind the start line, in
## route space (x/z): where the level puts its depot (depot.gd). Empty for no
## yard at all.
@export var start_yard: Rect2 = Rect2()
var is_vehicle_in_delivery: bool = false
var houses: Array[DeliveryHouse] = []

## The golden rule: a delivery lasts 2-5 minutes whatever the house count
## (tareas de Nacho N-102). The road is cut to a time budget instead of a
## fixed length per leg, so one house gets long legs (a mini adventure) and
## four get short ones. Measured with tests/bench_route_duration.gd; the
## table is in docs/parametros-diseno.md ("Duración de la entrega").
const ROUTE_TARGET_SECONDS: float = 240.0
## Stopping at a house: get out, walk, ring, come back.
const HOUSE_STOP_SECONDS: float = 25.0
## Average driving speed over a whole route, m/s: the bench's autopilot
## cruising at 50 km/h, easing off in bends and braking for every stop,
## averaged 46 km/h on every house count.
const ROUTE_CRUISE_SPEED: float = 12.8
## Bounds on a leg (start->house, house->house, house->goal): under the
## floor a leg is over before anything happens on it; over the cap one house
## alone would be a long, empty drive. The cap was 600 m, but one house then
## came to 1.9 minutes, under the 2-minute floor: 700 keeps it at ~2.2.
const LEG_MIN_LENGTH: float = 250.0
const LEG_MAX_LENGTH: float = 700.0
## Each leg varies this much around its budget, so they don't all match.
const LEG_LENGTH_JITTER: float = 0.1
## House/road proportions carried over unchanged from the old handcrafted
## route -- only WHERE the road goes changed, not how wide it or a house
## approach is.
const HOUSE_LATERAL_OFFSET: float = 10.5
const HOUSE_PATH_LATERAL_OFFSET: float = 7.9
## Closest a house's front (porch step, roof eaves) may come to the road
## centreline. Houses are dealt in different sizes -- the farmhouse's porch
## reaches 4.3 m out of its origin -- so a fixed HOUSE_LATERAL_OFFSET put
## some decks right over the edge line; each house steps back as needed.
const HOUSE_FRONT_CLEARANCE: float = 7.6
## Clear ground left between any part of a house and the asphalt's edge,
## checked against the WHOLE finished road: a bend right before or after a
## stop (or a later leg doubling back) can swing the road toward the house.
## 3.0, was 1.4: the front yard needs room for the waiting house's sign and
## mailbox (house_waiting_marker.gd) between the porch and the asphalt.
const HOUSE_ROAD_MARGIN: float = 3.0
const HOUSE_PUSH_STEP: float = 0.5
const HOUSE_MAX_PUSH: float = 12.0
## How far above the house's own roof its "CASA N" label floats. 1.0 let the
## roof's peak cut the second line (the ordered box) from the road.
const HOUSE_LABEL_CLEARANCE: float = 1.8
## Kept clear of trees and roadside props: the lines of sight from the road,
## every SIGHT_LINE_STEP metres over the last SIGHT_LINE_LENGTH before a
## house, to the house itself -- the truck must see it coming (N-501). They
## follow the real road, so a bend just before the house is covered too.
const SIGHT_LINE_LENGTH: float = 120.0
const SIGHT_LINE_STEP: float = 30.0
const SIGHT_LINE_RADIUS: float = 3.5

## How many segments in a row are allowed to leave the heading unchanged
## before a CurveSegment is forced -- this is the actual fix for "no quiero
## tramos rectos": without it, the "never repeat the same type twice" rule
## alone still allows Straight, Bump, Straight, Gravel, Straight... for as
## long as the RNG allows, all dead straight in world space.
const MAX_STRAIGHT_STREAK: int = 2
## Pacing inside each leg (tareas de Nacho N-103), see plan_spine(): something
## happens at least every MOMENT_SPACING metres -- a hard segment, a bend of
## SHARP_CURVE_DEG or more, or a house stop -- and the last QUIET_ZONE metres
## before a house are straight or bend at most GENTLE_CURVE_DEG, so the crew
## gets out without a bump throwing a box.
const MOMENT_SPACING: float = 250.0
const QUIET_ZONE: float = 80.0
const SHARP_CURVE_DEG: float = 45.0
const GENTLE_CURVE_DEG: float = 30.0
## The longest spine segment (HillSegment): how far one pick can run before
## the next rule gets a say.
const MAX_SEGMENT_LENGTH: float = 70.0
const CURVE_TURN_MIN_DEG: float = 25.0
const CURVE_TURN_MAX_DEG: float = 70.0
## How far the road may ever head away from the start's -Z. Past 90 degrees
## a run of same-way curves brought it back around onto road already built:
## two stretches overlapping, lines crossing the asphalt and roadworks
## standing on the other lane. Kept under 90, every stretch still advances
## along -Z, so the road can never cross itself.
const MAX_HEADING_DEG: float = 80.0

## How far before a house its "entrega adelante" sign goes up.
const DELIVERY_SIGN_LEAD: float = 80.0
## Trees keep this far from a house centre: enough room for the yard (fence
## line sits ~7-8 m out) without the forest growing through the porch.
const HOUSE_CLEAR_RADIUS: float = 9.0
## Every house model's porch deck is 0.30 m tall (both Blender batches).
const PORCH_DECK_HEIGHT: float = 0.3

## Where the goal actually ended up -- with a curved, randomized-length road
## this is no longer reliably near world (0,0,something), so anything that
## needs the goal's real location (tests, mainly) reads this instead of
## assuming an axis.
var goal_transform: Transform3D = Transform3D.IDENTITY

const ROAD := Color("394a50")
const SHOULDER := Color("63736f")
const MARKING := Color("d4d9c2")
const WARNING := Color("e7be51")
const TEAL := Color("65b5a1")
const CONCRETE := Color("8c9791")

var _materials: Dictionary = {}
var _delivery_vehicles: Array[Node3D] = []

var _rng := RandomNumberGenerator.new()
## What plan_spine() decided for this route: the segments to build, in order.
var _plan: Dictionary = {}
## This session's weather and time of day, picked once: the dressing (storm
## debris in the rain) and the sky (RouteSky) both follow it. Picked twice,
## solo play (seed 0) would roll two different ones.
var mood: WorldMood
## [{"cumulative": float, "position": Vector3, "leg_index": int}, ...] one
## entry per segment boundary, in build order -- get_progress()/
## get_section_name() find the nearest one instead of trusting local Z,
## which stopped meaning "distance along the road" the moment the road
## started bending.
var _progress_samples: Array[Dictionary] = []
## Denser than _progress_samples (every ~10m along the actual, possibly
## curved, path instead of only at segment boundaries up to 60m apart) --
## distance_from_path() needs this resolution, since a vehicle perfectly
## centered mid-segment on a long straight would otherwise read as tens of
## meters "off path" just from boundary sparsity, dangerously close to the
## safety net's own threshold.
var _path_points: Array[Vector3] = []
## Metres along the road to each of _path_points, worked out on first use.
var _path_distances := PackedFloat32Array()
var _house_deck: Array[int] = []
## Road cursor and side each house was dealt, for furnishing it once its
## final spot is known (see _keep_houses_off_road()).
var _house_anchors: Array[Dictionary] = []
## What placed the dressing, and how much of each kind (for tests/tuning).
var dresser: RouteDresser
## (x, z, radius) circles in route space where no tree or roadside prop may
## stand -- each house with its yard, plus the farmhouse's barn.
## RouteDresser reads these; see route_dresser.gd for the placement rules.
var _clear_zones: Array[Vector3] = []
## Lines of sight from the road to each house (see _clear_sight_lines()):
## kept clear of trees and props, but not of road signs.
var _sight_zones: Array[Vector3] = []
const Terrain = preload("res://scripts/gameplay/route/route_terrain.gd")
var terrain: Node3D
var _segments: Array[RouteSegment] = []
## Distance from the very start that only gets Straight/SpeedBump/Hill/
## Tunnel -- segments that don't need steering input to survive. Below this
## length the plan never picks a hard segment or a CurveSegment. It was
## 150 m; 100 still covers the runway below, and leaves room for the first
## leg's "something happens" before the approach to the first house (N-103). Same problem RouteStreamer's
## first_segment_script already solved for its own pool (a driver needs a
## second to get their bearings) -- this route needed a longer buffer, not
## just one segment, because test_vehicle_presentation.gd and
## test_dust_and_ambience.gd drive 90-100 physics ticks at full throttle
## with zero steering input to check headlights/dust, and caught it when a
## single straight segment wasn't enough runway.
const SAFE_START_LENGTH: float = 100.0


## Overrides house_count before the node builds itself. Call before
## add_child()-ing this into the tree -- _ready() already builds geometry
## from house_count, same convention as any other @export here.
func configure_houses(count: int) -> void:
	house_count = maxi(count, 1)


## How long each leg aims to be for this many houses: the driving time left
## once every stop is paid for, shared out over the legs, in metres. Actual
## legs vary LEG_LENGTH_JITTER around it, and overshoot a little since a leg
## only ends once the segment that crosses its target finishes.
static func leg_target_length(houses: int) -> float:
	var driving_seconds: float = ROUTE_TARGET_SECONDS - houses * HOUSE_STOP_SECONDS
	return clampf(driving_seconds * ROUTE_CRUISE_SPEED / float(houses + 1), LEG_MIN_LENGTH, LEG_MAX_LENGTH)


## The whole spine, decided before anything is built, from its own stream
## off the session seed so every peer plans the same road (and a test can
## check hundreds of seeds without building one). Returns
## {"segments": [{"script", "turn_deg", "length", "leg", "start", "hard",
## "moment", "delivery_sign"}, ...], "house_distances": [...], "total"}.
##
## Rules: no repeat of the previous type; the first SAFE_START_LENGTH metres
## easy and straight; never two hard segments in a row; at most
## MAX_STRAIGHT_STREAK segments without a bend; something happening at least
## every MOMENT_SPACING metres (a house stop counts); a calm last QUIET_ZONE
## metres before every house; and hard segments getting likelier from the
## first house to the last, on the same curve as Endless
## (RouteStreamer.hard_weight_at()) stretched over this delivery's length.
static func plan_spine(session_seed: int, houses: int, avoid_tunnel_at_start: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([session_seed, &"route_spine"])
	# Not a const: GDScript can't fold an array of global class_names.
	var pool: Array[Script] = [
		StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
		SCurveSegment, GravelSegment, ConstructionZoneSegment,
		CurveSegment, CurveSegment,  # weighted up: this is the one that turns
		HillSegment, TunnelSegment, RailCrossingSegment,
	]
	# Same "needs real steering/braking" set RouteStreamer uses, plus the
	# rail crossing. CurveSegment isn't on it: turning is what driving here
	# is; only a sharp bend counts as a moment.
	var hard: Array[Script] = [ChicaneSegment, NarrowBridgeSegment, SCurveSegment, GravelSegment, ConstructionZoneSegment, RailCrossingSegment]
	var leg_length_target: float = leg_target_length(houses)
	var planned_total: float = leg_length_target * (houses + 1)
	var state := {"distance": 0.0, "heading": 0.0, "last": null, "straight_streak": 0, "since_moment": 0.0, "after_house": false}
	var segments: Array[Dictionary] = []
	var stops: Array[float] = []
	for leg: int in range(houses + 1):
		var jitter: float = rng.randf_range(1.0 - LEG_LENGTH_JITTER, 1.0 + LEG_LENGTH_JITTER)
		var target: float = clampf(leg_length_target * jitter, LEG_MIN_LENGTH, LEG_MAX_LENGTH)
		var to_house: bool = leg < houses
		# The last leg ends at the goal, not at a house: no warning, no calm.
		var sign_placed: bool = not to_house
		var leg_length: float = 0.0
		while leg_length < target:
			var remaining: float = target - leg_length
			# Whatever comes now could reach into the last QUIET_ZONE metres
			# (a leg ends once the segment crossing its target finishes).
			var quiet: bool = to_house and remaining <= QUIET_ZONE + MAX_SEGMENT_LENGTH
			# Something has to happen now if one more uneventful segment could
			# leave MOMENT_SPACING without anything, or if what's left before
			# the house (the calm approach included) would.
			var since: float = state.since_moment
			var must_move: bool = not quiet and (since + MAX_SEGMENT_LENGTH > MOMENT_SPACING
				or (to_house and remaining <= QUIET_ZONE + 2.0 * MAX_SEGMENT_LENGTH and since + remaining + MAX_SEGMENT_LENGTH > MOMENT_SPACING))
			var progress: float = clampf(float(state.distance) / planned_total, 0.0, 1.0)
			var hard_weight: float = lerpf(RouteStreamer.HARD_WEIGHT_START, RouteStreamer.HARD_WEIGHT_END, progress)
			var script: Script = _plan_pick(rng, pool, hard, state, quiet, must_move, hard_weight, avoid_tunnel_at_start)
			var turn: float = _plan_turn(rng, state.heading, quiet, must_move) if script == CurveSegment else 0.0
			var length: float = CurveSegment.length_for_turn(turn) if script == CurveSegment else _segment_length(script)
			var is_hard: bool = hard.has(script)
			var entry := {
				"script": script, "turn_deg": turn, "length": length, "leg": leg,
				"start": state.distance, "hard": is_hard,
				"moment": is_hard or (script == CurveSegment and absf(turn) >= SHARP_CURVE_DEG),
				# "Entrega adelante" lands on whichever segment covers the last
				# DELIVERY_SIGN_LEAD metres before the house.
				"delivery_sign": not sign_placed and leg_length + length >= target - DELIVERY_SIGN_LEAD,
			}
			sign_placed = sign_placed or entry.delivery_sign
			segments.append(entry)
			leg_length += length
			state.distance += length
			state.heading += turn
			state.since_moment = 0.0 if entry.moment else float(state.since_moment) + length
			state.last = script
			state.after_house = false
			state.straight_streak = 0 if script == CurveSegment else int(state.straight_streak) + 1
		if to_house:
			stops.append(state.distance)
			state.since_moment = 0.0
			state.after_house = true
	return {"segments": segments, "house_distances": stops, "total": state.distance}


static func _plan_pick(rng: RandomNumberGenerator, pool: Array[Script], hard: Array[Script], state: Dictionary,
		quiet: bool, must_move: bool, hard_weight: float, avoid_tunnel_at_start: bool) -> Script:
	var candidates: Array[Script] = pool.duplicate()
	var rules: Array[Callable] = []
	if quiet:
		rules.append(func(s: Script) -> bool: return s == StraightSegment or s == CurveSegment)
	if float(state.distance) < SAFE_START_LENGTH:
		rules.append(func(s: Script) -> bool: return not hard.has(s) and s != CurveSegment)
	# Nor a tunnel mouth right in front of the depot's door: its portal would
	# stand against the forecourt and wall off the view of the building.
	if avoid_tunnel_at_start and float(state.distance) < 1.0:
		rules.append(func(s: Script) -> bool: return s != TunnelSegment)
	# Nor right past a house: the portal stood against its yard and hid it.
	if bool(state.after_house):
		rules.append(func(s: Script) -> bool: return s != TunnelSegment)
	var last: Script = state.last
	if last != null:
		rules.append(func(s: Script) -> bool: return s != last)
		if hard.has(last):
			rules.append(func(s: Script) -> bool: return not hard.has(s))
	if must_move:
		rules.append(func(s: Script) -> bool: return hard.has(s) or s == CurveSegment)
	elif int(state.straight_streak) >= MAX_STRAIGHT_STREAK:
		rules.append(func(s: Script) -> bool: return s == CurveSegment)
	# In order of importance: a rule that would leave nothing is skipped.
	for rule: Callable in rules:
		var kept: Array[Script] = candidates.filter(rule)
		if not kept.is_empty():
			candidates = kept
	var total: float = 0.0
	for script: Script in candidates:
		total += hard_weight if hard.has(script) else 1.0
	var roll: float = rng.randf() * total
	for script: Script in candidates:
		roll -= hard_weight if hard.has(script) else 1.0
		if roll <= 0.0:
			return script
	return candidates[-1]


## A bend's angle in degrees: gentle on a house's approach, sharp when it's
## the moment the pacing asked for. It turns back the other way rather than
## head more than MAX_HEADING_DEG off the start's -Z, so the road can never
## come round and cross itself.
static func _plan_turn(rng: RandomNumberGenerator, heading: float, gentle: bool, sharp: bool) -> float:
	var sign_: float = -1.0 if rng.randf() < 0.5 else 1.0
	var smallest: float = SHARP_CURVE_DEG if sharp else CURVE_TURN_MIN_DEG
	var largest: float = GENTLE_CURVE_DEG if gentle else CURVE_TURN_MAX_DEG
	var turn: float = sign_ * rng.randf_range(smallest, largest)
	if absf(heading + turn) > MAX_HEADING_DEG:
		turn = -turn
	return clampf(turn, -MAX_HEADING_DEG - heading, MAX_HEADING_DEG - heading)


static func _segment_length(script: Script) -> float:
	var probe := script.new() as RouteSegment
	var length: float = probe.length
	probe.free()
	return length


## Players minus the driver, at least one house even playing alone.
static func crew_house_count(player_count: int) -> int:
	return maxi(player_count - 1, 1)


## Which box each house is waiting for, decided once the run starts (see
## level_base.gd): [[package_id, display_name], ...] in house order. A house
## past the end of the list takes whatever it's handed, as before.
func assign_packages(assignments: Array) -> void:
	for index: int in range(houses.size()):
		var house: DeliveryHouse = houses[index]
		var entry: Array = assignments[index] if index < assignments.size() else []
		house.assigned_package_id = StringName(entry[0]) if entry.size() > 0 else &""
		house.assigned_label = String(entry[1]) if entry.size() > 1 else ""
		if house.waiting_marker != null:
			house.waiting_marker.set_order(house.assigned_label)
		var label := get_node_or_null(NodePath("HouseNumber%d" % index)) as Label3D
		if label != null:
			label.text = "CASA %d" % (index + 1) if house.assigned_label.is_empty() else "CASA %d%s%s" % [index + 1, NEWLINE, house.assigned_label.to_upper()]


func _ready() -> void:
	# One seed per session, not per machine: see NetworkManager.world_seed.
	# Solo play leaves it at 0, which still means "a different route every
	# time you press play".
	var session_seed: int = _session_seed()
	if session_seed != 0:
		_rng.seed = session_seed
	else:
		_rng.randomize()
	if house_count <= 0:
		house_count = _session_house_count()
	_plan = plan_spine(session_seed if session_seed != 0 else _rng.randi(), house_count, start_yard.has_area())
	mood = WorldMood.pick(session_seed)
	_house_deck = _shuffled_house_variants()
	terrain = Terrain.new()
	terrain.name = "ContinuousTerrain"
	add_child(terrain)
	_reserve_start_yard()
	var cursor: Transform3D = Transform3D.IDENTITY
	_progress_samples.append({"cumulative": 0.0, "position": cursor.origin, "leg_index": 0})
	_start_leg(cursor)
	for leg_index: int in range(house_count + 1):
		cursor = _build_leg(cursor, leg_index)
		if leg_index < house_count:
			cursor = _build_house(cursor, leg_index)
	goal_transform = cursor
	_build_goal(cursor)
	_finish_terrain()
	_build_ambience()
	var sky := RouteSky.new()
	sky.name = "Sky"
	add_child(sky)


## Deals the house models out like a deck so a route never repeats one until
## all of them have been used, drawn from the session RNG so every peer builds
## the same street.
func _shuffled_house_variants() -> Array[int]:
	var deck: Array[int] = []
	for variant: int in range(DeliveryHouse.HOUSE_VISUALS.size()):
		deck.append(variant)
	for i: int in range(deck.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: int = deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	return deck


## Each spine segment only builds ground/road from its own local z=0 back to
## z=-length -- there's nothing covering POSITIVE z. The old handcrafted
## route always had a forward margin there (its single big ground/shoulder
## box started well past z=0) because the vehicle spawns at z=0 exactly and
## the on-foot spawn points go up to z=+5 -- without this apron the vehicle
## spawns with no ground under it at all and free-falls (caught by
## test_vehicle_presentation.gd and test_dust_and_ambience.gd: the vehicle
## fell out from under them before their checks ever ran).
func _start_leg(cursor: Transform3D) -> void:
	terrain.add_span(cursor.origin + Vector3(0.0, 0.0, 20.0), cursor.origin)
	_sign("Salida", "SALIDA\nCuidá la carga -- el camino serpentea", cursor.origin + Vector3(-7.6, 0.0, -5.0), TEAL)
	_box("StartLine", Vector3(11.4, 0.02, 0.35), cursor.origin + Vector3(0.0, 0.03, -4.0), TEAL)


## The depot stands behind the start line: its footprint stays level and no
## tree or roadside prop may grow into it. (Ground tiles already reach it:
## the start apron's span makes them for 64 m around.)
func _reserve_start_yard() -> void:
	if not start_yard.has_area():
		return
	terrain.flat_zones.append(start_yard)
	var step: float = 8.0
	var x: float = start_yard.position.x + step * 0.5
	while x < start_yard.end.x:
		var z: float = start_yard.position.y + step * 0.5
		while z < start_yard.end.y:
			_clear_zones.append(Vector3(x, z, step * 0.75))
			z += step
		x += step


## Builds one leg's worth of road (leg_target_length() m of chained
## segments) starting at `cursor`, and returns the cursor at the far end so
## the caller can place a house or the goal there.
func _build_leg(cursor: Transform3D, leg_index: int) -> Transform3D:
	for planned: Dictionary in _plan.segments:
		if int(planned.leg) != leg_index:
			continue
		var segment: RouteSegment = (planned.script as Script).new() as RouteSegment
		if segment is CurveSegment:
			(segment as CurveSegment).turn_deg = planned.turn_deg
		segment.continuous_terrain = true
		# "Entrega adelante", on the house's side.
		if planned.delivery_sign:
			segment.set_meta(&"delivery_sign_side", -1.0 if leg_index % 2 == 0 else 1.0)
		segment.transform = cursor
		# Where along the road it starts: RouteDresser's zones (forest,
		# countryside) are laid out over this distance.
		segment.set_meta(&"route_distance", route_length)
		# A stable name, the same on every peer: segments with state of their
		# own (RailCrossingSegment) are reached by RPC through their path.
		segment.name = "Segment%d" % _segments.size()
		add_child(segment)
		_segments.append(segment)
		var road_slots: Array[Transform3D] = segment.get_dressing_slots(10.0)
		road_slots.append(Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset))
		for i: int in range(road_slots.size() - 1):
			terrain.add_span((cursor * road_slots[i]).origin, (cursor * road_slots[i + 1]).origin, segment is GravelSegment, 3.0 if segment is NarrowBridgeSegment else 6.0)
		for slot: Transform3D in segment.get_dressing_slots(10.0):
			_path_points.append((cursor * slot).origin)
		if segment is HillSegment:
			var exit: Vector3 = (cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)).origin
			terrain.crests.append({"a": Vector2(cursor.origin.x, cursor.origin.z), "b": Vector2(exit.x, exit.z), "height": (segment as HillSegment).crest_height})
		route_length += segment.length
		cursor = cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)
		_progress_samples.append({"cumulative": route_length, "position": cursor.origin, "leg_index": leg_index})
	return cursor


## One house per package (docs/tareas-nacho.md house delivery system), one
## per leg, positioned and oriented relative to the cursor's OWN heading at
## this point in the road -- a fixed world-space side offset (the old
## approach) would plant the house in the middle of the asphalt the moment
## the road had turned away from the +X/-Z axes. Returns the cursor
## unchanged: the house is a detour off the road, not part of the chain.
func _build_house(cursor: Transform3D, index: int) -> Transform3D:
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var house := DeliveryHouse.new()
	house.name = "House%d" % index
	house.visual_variant = _house_deck[index % _house_deck.size()]
	house.house_index = index
	# The house model's entrance is on local -Z. Rotate that face toward the
	# asphalt rather than along the road, so stops address the route.
	house.transform = _house_transform(cursor, side, HOUSE_LATERAL_OFFSET)
	add_child(house)
	houses.append(house)
	# Step back far enough that this model's porch clears the road.
	var visual: Node3D = house.get_node_or_null(^"HouseVisual")
	if visual != null:
		var reach: float = -_local_bounds(house, visual).position.z
		house.transform = _house_transform(cursor, side, maxf(HOUSE_LATERAL_OFFSET, HOUSE_FRONT_CLEARANCE + reach))
	_house_anchors.append({"cursor": cursor, "side": side})
	var captured_index: int = index
	house.resolved.connect(func(outcome: StringName, package_id: StringName) -> void: house_resolved.emit(captured_index, outcome, package_id))
	return cursor


func _house_transform(cursor: Transform3D, side: float, lateral: float) -> Transform3D:
	return cursor * Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * lateral, _ground_height_at(lateral), 0.0))


## Runs once the whole road exists: backs any house away (along its own
## back, keeping it square to its stop) until every corner of it -- porch,
## eaves, side bay -- stands HOUSE_ROAD_MARGIN clear of the asphalt, then
## lays out its yard, path and number around where it finally stands.
func _keep_houses_off_road() -> void:
	for index: int in range(houses.size()):
		var house: DeliveryHouse = houses[index]
		var visual: Node3D = house.get_node_or_null(^"HouseVisual")
		if visual != null:
			var bounds: AABB = _local_bounds(house, visual)
			var pushed: float = 0.0
			while _house_road_gap(house, bounds) < HOUSE_ROAD_MARGIN and pushed < HOUSE_MAX_PUSH:
				house.position += house.basis.z.normalized() * HOUSE_PUSH_STEP
				pushed += HOUSE_PUSH_STEP
		_build_yard(house, index)
		var anchor: Dictionary = _house_anchors[index]
		_build_house_path(anchor.cursor, anchor.side, house)
		var top: float = _local_bounds(house, visual).end.y if visual != null else 4.0
		var label_at: Vector3 = house.position + Vector3.UP * (top + HOUSE_LABEL_CLEARANCE)
		_label("HouseNumber%d" % index, "CASA %d" % (index + 1), label_at, 0.01, TEAL, true)
		get_node(NodePath("HouseNumber%d" % index)).set_meta(&"height_above_house", top + HOUSE_LABEL_CLEARANCE)


## Smallest distance from the house's footprint outline (corners and edge
## midpoints of its model's bounds) to the edge of any asphalt on the route.
func _house_road_gap(house: Node3D, bounds: AABB) -> float:
	var gap: float = INF
	var x0: float = bounds.position.x
	var x1: float = bounds.end.x
	var z0: float = bounds.position.z
	var z1: float = bounds.end.z
	for local: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1),
			Vector2((x0 + x1) * 0.5, z0), Vector2((x0 + x1) * 0.5, z1), Vector2(x0, (z0 + z1) * 0.5), Vector2(x1, (z0 + z1) * 0.5)]:
		var p: Vector3 = house.transform * Vector3(local.x, 0.0, local.y)
		var road: Vector3 = terrain.nearest(Vector2(p.x, p.z))
		gap = minf(gap, road.x - road.z)
	return gap


## A narrow worn path makes each stop feel connected to the road. It stops
## at the shoulder rather than widening the driving lane or blocking traffic.
func _build_house_path(cursor: Transform3D, side: float, house: Node3D) -> void:
	var a: Vector3 = cursor * Vector3(side * 5.8, 0.0, 0.0)
	var b: Vector3 = house.position
	terrain.paths.append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z)})


## Yard dressing so a delivery stop reads as someone's home, not a box
## dropped by the road. Houses stand only ~10 m from the centreline and their
## porch reaches to ~7 m, so there's no front garden to speak of: the doormat
## and pots ride on the porch deck (part of the house, never moved), and the
## lot -- fence down both sides, gnome, dog house, the farm's barn -- runs
## along the sides and back. Lot pieces are only proposals: RouteDresser
## validates each one like any other prop and drops what doesn't fit (which
## is how a fence once ended up on the asphalt, before it did).
## Choices come from the house index, not the RNG, so adding dressing never
## reshuffles the road itself.
func _build_yard(house: DeliveryHouse, index: int) -> void:
	var yard := Node3D.new()
	yard.name = "Yard"
	house.add_child(yard)
	var visual: Node3D = house.get_node_or_null(^"HouseVisual")
	var bounds: AABB = _local_bounds(house, visual) if visual != null else AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 3.0, 6.0))
	var front: float = bounds.position.z
	var flip: float = 1.0 if index % 2 == 0 else -1.0
	# `front` includes the porch step (0.23 m); these sit back on the deck,
	# between the door frame and the porch posts.
	_yard_piece(yard, YARD_DOORMAT, Vector3(0.0, PORCH_DECK_HEIGHT, front + 0.75), 0.0, 0.5, true)
	for x: float in [-0.95, 0.95]:
		_yard_piece(yard, YARD_FLOWER_POT, Vector3(x, PORCH_DECK_HEIGHT, front + 0.6), 0.0, 0.3, true)
	# Side fences: 2 m panels turned to run front-to-back beside the house.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (bounds.size.x * 0.5 + 1.6)
		var z: float = front + 1.0
		while z < bounds.end.z + 2.0:
			# 0.95, not 1.0: 2 m panels end to end would "touch" and fail the overlap check.
			_yard_piece(yard, YARD_FENCE, Vector3(x, 0.0, z), PI * 0.5, 0.95, false)
			z += 2.0
	_yard_piece(yard, YARD_GNOME, Vector3((bounds.size.x * 0.5 + 0.7) * flip, 0.0, front + 1.6), deg_to_rad(20.0 * flip), 0.3, false)
	if index % 2 == 1:
		_yard_piece(yard, YARD_DOG_HOUSE, Vector3(-flip * (bounds.size.x * 0.5 + 0.8), 0.0, bounds.end.z - 0.4), PI, 0.7, false)
	_clear_zones.append(Vector3(house.position.x, house.position.z, HOUSE_CLEAR_RADIUS))
	_clear_sight_lines(house, (_house_anchors[index].cursor as Transform3D).origin)
	# The farmhouse gets its barn beside it -- a farm, not a lone house.
	if DeliveryHouse.HOUSE_VISUALS[posmod(house.visual_variant, DeliveryHouse.HOUSE_VISUALS.size())].ends_with("farmhouse.glb"):
		# Turned a quarter, the barn's 12.7 m length runs sideways: 11 m out
		# leaves a proper farmyard gap instead of a lean-to.
		var barn: Node3D = _yard_piece(yard, BARN, Vector3(bounds.position.x - 11.0, 0.0, 4.0), PI * 0.5, 6.4, false)
		if barn != null:
			var barn_at: Vector3 = to_local(barn.global_position)
			_clear_zones.append(Vector3(barn_at.x, barn_at.z, 9.0))


## Nothing between the arriving truck and the house: walks the road back
## from the house's stop and clears a line from each sample to the house.
func _clear_sight_lines(house: Node3D, stop: Vector3) -> void:
	var nearest: int = 0
	for index: int in range(_path_points.size()):
		if _path_points[index].distance_squared_to(stop) < _path_points[nearest].distance_squared_to(stop):
			nearest = index
	var travelled: float = 0.0
	var next_sample: float = SIGHT_LINE_STEP
	var index: int = nearest
	while index > 0 and travelled < SIGHT_LINE_LENGTH:
		travelled += _path_points[index].distance_to(_path_points[index - 1])
		index -= 1
		if travelled < next_sample:
			continue
		next_sample += SIGHT_LINE_STEP
		var from: Vector3 = _path_points[index]
		var length: float = Vector2(house.position.x - from.x, house.position.z - from.z).length()
		var along: float = 0.0
		while along <= length:
			var at: Vector3 = from.lerp(house.position, along / maxf(length, 0.01))
			_sight_zones.append(Vector3(at.x, at.z, SIGHT_LINE_RADIUS))
			along += SIGHT_LINE_RADIUS * 2.0


func _yard_piece(yard: Node3D, path: String, local_position: Vector3, yaw: float, footprint: float, on_porch: bool) -> Node3D:
	var piece := _instantiate_dressing(path)
	if piece == null:
		return null
	piece.transform = Transform3D(Basis(Vector3.UP, yaw), local_position)
	piece.set_meta(&"footprint", footprint)
	piece.set_meta(&"on_porch", on_porch)
	yard.add_child(piece)
	return piece


## A model's visible extent in `root`'s space, so yard pieces line up with
## whichever house shape was dealt instead of assuming one footprint.
func _local_bounds(root_node: Node3D, node: Node) -> AABB:
	var result := AABB()
	var first: bool = true
	for child: Node in node.find_children("*", "VisualInstance3D", true, false):
		var xform: Transform3D = root_node.global_transform.affine_inverse() * (child as Node3D).global_transform
		var box: AABB = xform * (child as VisualInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _build_goal(cursor: Transform3D) -> void:
	terrain.add_span(cursor.origin, cursor * Vector3(0.0, 0.0, -18.0))
	var arch_left: Transform3D = cursor * Transform3D(Basis.IDENTITY, Vector3(-4.5, 2.0, 0.0))
	var arch_right: Transform3D = cursor * Transform3D(Basis.IDENTITY, Vector3(4.5, 2.0, 0.0))
	var arch_top: Transform3D = cursor * Transform3D(Basis.IDENTITY, Vector3(0.0, 4.0, 0.0))
	_box_at("GoalArchLeft", Vector3(0.5, 4.0, 0.5), arch_left, CONCRETE, true)
	_box_at("GoalArchRight", Vector3(0.5, 4.0, 0.5), arch_right, CONCRETE, true)
	_box_at("GoalArchTop", Vector3(9.6, 0.5, 0.5), arch_top, TEAL, true)
	_label("GoalTitle", "META", arch_top.origin + Vector3(0.0, 0.9, 0.0), 0.014, TEAL)
	var end_barrier: Transform3D = cursor * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -10.0))
	_box_at("EndBarrier", Vector3(15.0, 1.0, 0.6), end_barrier, CONCRETE, true)
	var area := Area3D.new()
	area.name = "GoalArea"
	area.transform = cursor * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 3.0))
	area.collision_layer = 32
	area.collision_mask = 2
	area.monitorable = false
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(9.0, 4.0, 6.0)
	collider.shape = shape
	area.add_child(collider)
	add_child(area)
	area.body_entered.connect(_on_delivery_body_entered)
	area.body_exited.connect(_on_delivery_body_exited)


func get_progress(world_position: Vector3) -> float:
	if route_length <= 0.0:
		return 0.0
	return clampf(_nearest_sample(world_position).get("cumulative", 0.0) / route_length, 0.0, 1.0)


## Metres along the road from the start to where `world_position` is (its
## nearest point on the road), for the dashboard GPS (N-502). Resolution is
## _path_points' ~10 m.
func road_distance(world_position: Vector3) -> float:
	var cumulative: PackedFloat32Array = _path_cumulative()
	return cumulative[_nearest_path_index(to_local(world_position))] if not cumulative.is_empty() else 0.0


## Metres along the road from the start to house `index`'s stop, or to the
## goal for an index past the last house.
func stop_road_distance(index: int) -> float:
	var cumulative: PackedFloat32Array = _path_cumulative()
	if cumulative.is_empty():
		return 0.0
	if index >= _house_anchors.size():
		return cumulative[-1]
	return cumulative[_nearest_path_index((_house_anchors[index].cursor as Transform3D).origin)]


func _path_cumulative() -> PackedFloat32Array:
	if _path_distances.size() != _path_points.size():
		_path_distances.resize(_path_points.size())
		var total: float = 0.0
		for index: int in range(_path_points.size()):
			if index > 0:
				total += _path_points[index].distance_to(_path_points[index - 1])
			_path_distances[index] = total
	return _path_distances


func _nearest_path_index(local_position: Vector3) -> int:
	var nearest: int = 0
	var best: float = INF
	for index: int in range(_path_points.size()):
		var gap: float = Vector2(_path_points[index].x - local_position.x, _path_points[index].z - local_position.z).length_squared()
		if gap < best:
			best = gap
			nearest = index
	return nearest


func get_section_name(world_position: Vector3) -> String:
	var leg_index: int = int(_nearest_sample(world_position).get("leg_index", 0))
	if leg_index >= house_count:
		return "Meta"
	if leg_index == 0:
		return "Camino a casa 1/%d" % house_count
	return "Camino a casa %d/%d" % [leg_index + 1, house_count]


## Nearest-boundary lookup rather than exact arc-length math: with segment
## boundaries every ~10-60m, the error this introduces is well under a
## segment's own length -- plenty for a HUD "distance remaining" readout,
## not something gameplay-critical reads.
func _nearest_sample(world_position: Vector3) -> Dictionary:
	var local_position: Vector3 = to_local(world_position)
	var best: Dictionary = {}
	var best_distance: float = INF
	for sample: Dictionary in _progress_samples:
		var distance: float = (sample["position"] as Vector3).distance_to(local_position)
		if distance < best_distance:
			best_distance = distance
			best = sample
	return best


## How far `world_position` is from the nearest known point on the actual
## generated path -- level_base.gd's "you left the route" safety net used to
## just check abs(world x) > 42, which only worked because the old road
## never left world x≈0. A curving road drifts the asphalt itself well past
## that on a wide turn while the vehicle is still perfectly on it, so the
## safety net needed to start measuring distance from the real path instead
## of from a world axis that stopped meaning anything once the road bent.
func distance_from_path(world_position: Vector3) -> float:
	var local_position: Vector3 = to_local(world_position)
	var best_distance: float = INF
	for point: Vector3 in _path_points:
		var distance: float = point.distance_to(local_position)
		if distance < best_distance:
			best_distance = distance
	return best_distance


func _finish_terrain() -> void:
	_keep_houses_off_road()
	# Level building pads blend back into the landscape, so the doorstep and
	# access path remain walkable even on a hillside.
	for house: Node3D in houses:
		var p: Vector3 = house.position
		p.y = terrain.base_height(Vector2(p.x, p.z)) - 0.08
		terrain.pads.append(p)
	# Level crossings: the ground along the tracks is levelled to the road, so
	# the train runs flat instead of through the roadside hills.
	for segment: RouteSegment in _segments:
		if segment is RailCrossingSegment:
			var centre: Vector3 = segment.transform * Vector3(0.0, 0.0, (segment as RailCrossingSegment).track_z)
			var level: float = terrain.base_height(Vector2(centre.x, centre.z))
			for pad: Vector3 in (segment as RailCrossingSegment).track_pads():
				terrain.pads.append(Vector3(pad.x, level, pad.z))
	terrain.build()
	for child: Node in get_children():
		if child == terrain or child is DeliveryHouse or String(child.name).begins_with("HouseNumber"):
			continue
		terrain.conform_geometry(child)
	for segment: RouteSegment in _segments:
		if segment is RailCrossingSegment:
			var track: Vector3 = segment.transform * Vector3(0.0, 0.0, (segment as RailCrossingSegment).track_z)
			segment.set_meta(&"track_height", terrain.height_at(track))
	for house: Node3D in houses:
		house.position.y = terrain.height_at(house.position)
		var label: Node3D = get_node(NodePath("HouseNumber%d" % house.house_index))
		label.position.y = house.position.y + float(label.get_meta(&"height_above_house", 4.0))
	# One draw from the session RNG after the whole road exists, so dressing
	# can never change the road itself -- and every peer gets the same draw.
	dresser = RouteDresser.new(self, terrain, _rng.randi())
	dresser.raining = mood.is_raining()
	dresser.dress(_segments, houses, _clear_zones, _sight_zones)
	if batch_dressing:
		var yards: Array = houses.map(func(house: DeliveryHouse) -> Node: return house.get_node_or_null(^"Yard"))
		DressingBatcher.bake(self, _segments, yards)
		DressingBatcher.merge_segment_geometry(_segments)
	for i: int in range(_path_points.size()):
		_path_points[i].y = terrain.height_at(_path_points[i])
	for sample: Dictionary in _progress_samples:
		var p: Vector3 = sample.position
		p.y = terrain.height_at(p)
		sample.position = p
	goal_transform.origin.y = terrain.height_at(goal_transform.origin)


const YARD_DIR: String = "res://assets/models/environment/yard/"
const YARD_DOORMAT: String = YARD_DIR + "sm_env_yard_doormat.glb"
const YARD_FLOWER_POT: String = YARD_DIR + "sm_env_yard_flower_pot.glb"
const YARD_FENCE: String = YARD_DIR + "sm_env_yard_picket_fence.glb"
const YARD_GNOME: String = YARD_DIR + "sm_env_yard_garden_gnome.glb"
const YARD_DOG_HOUSE: String = YARD_DIR + "sm_env_yard_dog_house.glb"
const BARN: String = "res://assets/models/architecture/sm_arch_barn.glb"


func _instantiate_dressing(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	LowpolyMaterials.apply(node)
	return node


## Kept for tests and older callers: how far a model's visible base sits
## from its origin (see RouteDresser.base_offset).
func _mesh_base_offset(node: Node3D) -> float:
	return RouteDresser.base_offset(node)


## The road, shoulder and terrain sit at three distinct elevations. Imported
## props have their local origin at their base, so every dressed object needs
## to be placed on the surface below it instead of blindly at world y = 0.
## Pure function of lateral distance -- doesn't care whether the segment
## it's dressing is straight or curved, so it needed no changes at all.
func _ground_height_at(x: float) -> float:
	var lateral: float = absf(x)
	if lateral <= 6.0:
		return 0.0
	if lateral <= 14.0:
		return -0.1
	return -0.3


## World ambience (item #45): a quiet, looping wind bed. Non-positional
## (AudioStreamPlayer, not the 3D variant) -- it's meant to sit under
## everything else no matter where the camera is, not attenuate with
## distance from some single point in space. Splitting this by interior vs.
## exterior (item #46, buses) is a separate follow-up once those buses
## exist; for now it's just always-on world presence instead of dead
## silence outside the vehicle.
func _build_ambience() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "AmbientWind"
	player.stream = SynthAudio.ambient_wind()
	player.volume_db = WorldMix.WIND_DB
	player.autoplay = true
	add_child(player)


func _on_delivery_body_entered(body: Node3D) -> void:
	if body not in _delivery_vehicles:
		_delivery_vehicles.append(body)
	if not is_vehicle_in_delivery:
		is_vehicle_in_delivery = true
		delivery_entered.emit()
		# Reaching the goal is the honest ending, even for a house nobody
		# rang -- "te olvidaste un paquete, bajate a dar explicaciones,"
		# forced automatically instead of just letting it go unresolved.
		for house: DeliveryHouse in houses:
			house.force_resolve_if_missed()


func _on_delivery_body_exited(body: Node3D) -> void:
	_delivery_vehicles.erase(body)
	if _delivery_vehicles.is_empty() and is_vehicle_in_delivery:
		is_vehicle_in_delivery = false
		delivery_exited.emit()


func _box(node_name: String, size: Vector3, location: Vector3, color: Color, solid: bool = false) -> Node3D:
	return _box_at(node_name, size, Transform3D(Basis.IDENTITY, location), color, solid)


func _box_at(node_name: String, size: Vector3, transform_: Transform3D, color: Color, solid: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = node_name
	root.transform = transform_
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	root.add_child(mesh)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 6
		var collider := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)
	return root


const SIGN_FONT: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const SIGN_BOARD_SIZE := Vector2(4.6, 1.4)
const NEWLINE: String = "\n"


## A route board: the first caption line is the big title, the rest a
## smaller message wrapped to the board's width, both in the game's cartoon
## display font. The post stands behind the board (text faces +Z), so it
## never shows through the face.
func _sign(node_name: String, caption: String, location: Vector3, accent: Color) -> void:
	var ground_y: float = _ground_height_at(location.x)
	var board_center_y: float = ground_y + 2.65
	var board_top: float = board_center_y + SIGN_BOARD_SIZE.y * 0.5
	_box(node_name + "Post", Vector3(0.16, board_top - 0.1 - ground_y, 0.16), location + Vector3(0.0, ground_y + (board_top - 0.1 - ground_y) * 0.5, -0.15), CONCRETE, true)
	_box(node_name + "Board", Vector3(SIGN_BOARD_SIZE.x, SIGN_BOARD_SIZE.y, 0.12), location + Vector3(0.0, board_center_y, 0.0), Color("263b3e"))
	_box(node_name + "Stripe", Vector3(SIGN_BOARD_SIZE.x, 0.10, 0.13), location + Vector3(0.0, board_top - 0.05, 0.0), accent)
	var lines: PackedStringArray = caption.split(NEWLINE, false, 1)
	var title: String = lines[0]
	var message: String = lines[1].replace(" -- ", " · ") if lines.size() > 1 else ""
	var face_z: float = 0.075
	if message.is_empty():
		_sign_text(node_name + "Title", title, location + Vector3(0.0, board_center_y - 0.03, face_z), 84, MARKING)
	else:
		_sign_text(node_name + "Title", title, location + Vector3(0.0, board_center_y + 0.26, face_z), 76, MARKING)
		_sign_text(node_name + "Text", message, location + Vector3(0.0, board_center_y - 0.26, face_z), 44, accent.lerp(MARKING, 0.35))


func _sign_text(node_name: String, text: String, location: Vector3, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = SIGN_FONT
	label.font_size = font_size
	label.pixel_size = 0.0055
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color("16252a")
	# Wraps inside the board with a margin instead of running off its edges.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = (SIGN_BOARD_SIZE.x - 0.4) / label.pixel_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = location
	add_child(label)


func _label(node_name: String, caption: String, location: Vector3, pixel_size: float, color: Color, face_camera: bool = false) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = caption
	label.position = location
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = Color("1e3035")
	# Free-floating labels (house numbers) turn to the camera around Y: the
	# road bends, so a fixed facing read backwards ("1 ASAC") from half the
	# approaches. Text printed on a board must not -- it would swing out in
	# front of its own board and get cut by it ("SAL...erpentea").
	if face_camera:
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(label)


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		# Back faces culled: double-sided, the underside of every flat marking
		# z-fought the terrain a few millimetres below it (flicker) and box
		# sides shadowed themselves in fine stripes.
		_materials[color] = material
	return _materials[color] as StandardMaterial3D


## Looked up by node path rather than by the NetworkManager identifier on
## purpose. A test that names this script's class_name compiles it before
## the autoloads exist, and a bare `NetworkManager.world_seed` is a compile
## error at that point -- the same node-path pattern the rest of the project
## already uses for EventBus.
func _session_seed() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return int(network.get(&"world_seed")) if network != null else 0


## Every peer has to build the same number of houses, and a client's own
## roster can't tell it (see NetworkManager.world_house_count): the host
## decides once per session, joiners use what it sent. Solo play (seed 0)
## just counts the crew every time.
func _session_house_count() -> int:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network == null:
		return 1
	var decided: int = int(network.get(&"world_house_count"))
	if decided > 0:
		return decided
	var count: int = crew_house_count((network.get(&"peer_ids") as Array).size())
	if int(network.get(&"world_seed")) != 0 and bool(network.call(&"is_host")):
		network.set(&"world_house_count", count)
	return count
