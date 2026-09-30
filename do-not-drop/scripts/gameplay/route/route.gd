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

## How many path points either side of the last hit the nearest-path lookups
## check before falling back to a full scan (N-223): path points are ~10 m
## apart and a tick moves the truck about a metre. The segment boundaries
## (_progress_samples, up to ~70 m apart) are not windowed: a hairpin can put
## a later stretch nearer than the truck's own boundaries, and there are few
## enough of them to scan every tick. The trust radius (2 x widest path gap,
## <= ~30 m) must stay under level_base's 42 m off-road limit, so a windowed
## hit never decides a ruin on its own.
const PATH_WINDOW: int = 4

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
## The base at the end of the road (route_goal_lot.gd): where the run ends,
## with the truck stopped in its free bay.
var goal_lot: RouteGoalLot

const ROAD := Color("394a50")
const SHOULDER := Color("63736f")
const MARKING := Color("d4d9c2")
const WARNING := Color("e7be51")
const TEAL := Color("65b5a1")
const CONCRETE := Color("8c9791")

var _delivery_vehicles: Array[Node3D] = []

var _rng := RandomNumberGenerator.new()
## The seed the spine was planned from (the session's, or a random one in solo
## play): the goal lot draws its own stream from it.
var _spine_seed: int = 0
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
## Where the last nearest-path-point lookups landed, so the
## next one (a tick later, the truck a metre further on) only looks around
## there instead of scanning the whole route (N-223). -1 = no hint yet.
var _path_hint: int = -1
var _path_hint_3d: int = -1
## _progress_samples' positions as a flat array for the lookup (built on first
## use, and again after _finish_terrain() moves them), and the widest gap
## between path points: a windowed hit further than twice that is not trusted.
var _sample_points: Array[Vector3] = []
var _path_gap: float = -1.0
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


## Host: closes the order whose box was left on the road (N-213.4). False
## when no door is waiting for that box (Endless, or already resolved).
func close_lost_order(package_id: StringName) -> bool:
	for house: DeliveryHouse in houses:
		if is_instance_valid(house) and not house.delivered and house.assigned_package_id == package_id:
			house.close_lost()
			return true
	return false


## Overrides house_count before the node builds itself. Call before
## add_child()-ing this into the tree -- _ready() already builds geometry
## from house_count, same convention as any other @export here.
func configure_houses(count: int) -> void:
	house_count = maxi(count, 1)


## The road this route builds, planned by RoutePlanner (see there).
static func plan_spine(session_seed: int, houses: int, avoid_tunnel_at_start: bool = false) -> Dictionary:
	return RoutePlanner.plan_spine(session_seed, houses, avoid_tunnel_at_start)


static func leg_target_length(houses: int) -> float:
	return RoutePlanner.leg_target_length(houses)


static func crew_house_count(player_count: int) -> int:
	return RoutePlanner.crew_house_count(player_count)


## Which box each house is waiting for, decided once the run starts (see
## level_base.gd): [[package_id, trap_key, code], ...] in house order
## (Depot.assignments()); the trap is translated here, on each peer. A house
## past the end of the list takes whatever it's handed, as before.
func assign_packages(assignments: Array) -> void:
	for index: int in range(houses.size()):
		var house: DeliveryHouse = houses[index]
		var entry: Array = assignments[index] if index < assignments.size() else []
		house.assigned_package_id = StringName(entry[0]) if entry.size() > 0 else &""
		house.assigned_label = tr(String(entry[1])) if entry.size() > 1 else ""
		if entry.size() > 2:
			house.assigned_label += " %s" % entry[2]
		if house.waiting_marker != null:
			house.waiting_marker.set_order(house.assigned_label)
		var label := get_node_or_null(NodePath("HouseNumber%d" % index)) as Label3D
		if label != null:
			label.text = tr("WORLD_HOUSE_NUMBER") % (index + 1) if house.assigned_label.is_empty() else "%s%s%s" % [tr("WORLD_HOUSE_NUMBER") % (index + 1), NEWLINE, house.assigned_label.to_upper()]


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
	_spine_seed = session_seed if session_seed != 0 else _rng.randi()
	_plan = RoutePlanner.plan_spine(_spine_seed, house_count, start_yard.has_area())
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
	var sign_at: Vector3 = cursor.origin + Vector3(-7.6, 0.0, -5.0)
	RouteProps.sign(self, "Salida", tr("WORLD_ROUTE_START_SIGN"), sign_at, _ground_height_at(sign_at.x), TEAL)
	RouteProps.box(self, "StartLine", Vector3(11.4, 0.02, 0.35), cursor.origin + Vector3(0.0, 0.03, -4.0), TEAL)


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
		# Where this segment's own stretch of _path_points starts and ends --
		# _clamp_river_reach() needs it to tell "another part of the road" a
		# river might run into from the river's own straight stretch under it.
		var path_start_index: int = _path_points.size()
		for slot: Transform3D in segment.get_dressing_slots(10.0):
			_path_points.append((cursor * slot).origin)
		if segment is HillSegment:
			var exit: Vector3 = (cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)).origin
			terrain.crests.append({"a": Vector2(cursor.origin.x, cursor.origin.z), "b": Vector2(exit.x, exit.z), "height": (segment as HillSegment).crest_height})
		# The riverbed under a narrow bridge (N-132 follow-up): carves the
		# ground itself so it reads as a real crossing instead of guard
		# rails standing over flat grass. The span exactly matches this
		# straight segment (it never turns), so the deck/rails/water --
		# all flagged &"ignore_river" -- float over the drop. `bank_width`
		# starts at the segment's own preference and _clamp_river_reach()
		# (called once the whole route exists) shrinks it if it would
		# otherwise run into another stretch of road, a house or the yard.
		if segment is NarrowBridgeSegment:
			var bridge: NarrowBridgeSegment = segment as NarrowBridgeSegment
			var river_end: Vector3 = (cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn),
					segment.exit_offset)).origin
			terrain.rivers.append({
				"a": Vector2(cursor.origin.x, cursor.origin.z), "b": Vector2(river_end.x, river_end.z),
				"depth": bridge.river_depth, "full_width": bridge.river_width, "bank_width": bridge.river_reach,
				"path_start": path_start_index, "path_end": _path_points.size(), "route_start": route_length,
			})
		route_length += segment.length
		cursor = cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)
		_progress_samples.append({"cumulative": route_length, "position": cursor.origin, "leg_index": leg_index})
	return cursor


## A river reaches for its own preferred `bank_width` (NarrowBridgeSegment's
## river_reach, up to 60 m out) so it fades into the landscape instead of
## reading as a rectangular pool -- but a winding route can bring another
## stretch of road, a house or the depot yard back within that reach. Run
## once the whole route (every leg, every house) exists, so unlike the
## registration in _build_leg() this sees what comes both before AND after
## the bridge. Shrinks `bank_width` to stop RIVER_HAZARD_MARGIN short of
## whatever's closest, never below its own `full_width` + a visible margin,
## so the crossing itself is never swallowed. The margin has to clear
## route_terrain.gd's RIVER_MAX_DRIFT (how far the meander can ever swing the
## actual wet edge past the plain `bank_width` this measures against) plus
## some slack, or the meander could still carry the real river into what
## this thought it had already cleared.
const RIVER_HAZARD_MARGIN: float = 4.0 + Terrain.RIVER_MAX_DRIFT
## The road immediately before and after the bridge is the SAME straight
## lane the river runs under -- at zero sideways distance from its own
## centreline, so without this it would always read as the nearest "hazard"
## and clamp every river down to the floor. Matches test_route_fuzz.gd's
## NEIGHBOUR_ALONG for the same idea: anything within this far along the
## route of the bridge's own span is its approach/exit, not another part of
## the road that happens to have come back close by.
const RIVER_SELF_BUFFER: float = 60.0


func _clamp_river_reach() -> void:
	var cumulative: PackedFloat32Array = _path_cumulative()
	for river: Dictionary in terrain.rivers:
		var a: Vector2 = river.a
		var edge: Vector2 = (river.b as Vector2) - a
		var length: float = maxf(edge.length(), 0.001)
		var dir: Vector2 = edge / length
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var route_start: float = float(river.get("route_start", 0.0))
		var route_end: float = route_start + length
		var hazard: float = INF
		for index: int in range(_path_points.size()):
			var travelled: float = cumulative[index] if index < cumulative.size() else 0.0
			if travelled > route_start - RIVER_SELF_BUFFER and travelled < route_end + RIVER_SELF_BUFFER:
				continue  # this bridge's own approach/exit, not a hazard
			var q := Vector2(_path_points[index].x, _path_points[index].z)
			var s: float = (q - a).dot(dir)
			if s < -RIVER_HAZARD_MARGIN or s > length + RIVER_HAZARD_MARGIN:
				continue
			hazard = minf(hazard, absf((q - a).dot(perp)))
		for house: DeliveryHouse in houses:
			var q := Vector2(house.position.x, house.position.z)
			var s: float = (q - a).dot(dir)
			if s < -RIVER_HAZARD_MARGIN or s > length + RIVER_HAZARD_MARGIN:
				continue
			hazard = minf(hazard, absf((q - a).dot(perp)) - HOUSE_CLEAR_RADIUS)
		if start_yard.has_area():
			var center: Vector2 = start_yard.position + start_yard.size * 0.5
			var s: float = (center - a).dot(dir)
			if s >= -RIVER_HAZARD_MARGIN and s <= length + RIVER_HAZARD_MARGIN:
				hazard = minf(hazard, absf((center - a).dot(perp)) - maxf(start_yard.size.x, start_yard.size.y) * 0.5)
		var full_width: float = float(river.full_width)
		var desired: float = float(river.bank_width)
		river.bank_width = clampf(hazard - RIVER_HAZARD_MARGIN, full_width + 6.0, desired) if hazard < INF else desired


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
		RouteProps.label(self, "HouseNumber%d" % index, tr("WORLD_HOUSE_NUMBER") % (index + 1), label_at, 0.01, TEAL, true)
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


## The base at the end of the road (N-116): a levelled lot at the cursor,
## sized and dressed by RouteGoalLot. The ground under it is made level here
## (a platform in the terrain), nothing is planted on it, and the road's dense
## path carries on into its free bay so the GPS and the off-road check know
## the way.
func _build_goal(cursor: Transform3D) -> void:
	terrain.add_span(cursor.origin, cursor * Vector3(0.0, 0.0, -24.0))
	goal_lot = RouteGoalLot.new()
	goal_lot.name = "GoalLot"
	var names: Array[String] = TownSign.names_for_seed(_spine_seed)
	goal_lot.configure(_spine_seed, names[-1], mood.darkness())
	var level: float = terrain.base_height(Vector2(cursor.origin.x, cursor.origin.z))
	goal_lot.transform = Transform3D(cursor.basis, Vector3(cursor.origin.x, level, cursor.origin.z))
	terrain.platforms.append(goal_lot.terrain_platform())
	_clear_zones.append_array(goal_lot.clear_zones())
	_path_points.append_array(goal_lot.path_points())
	add_child(goal_lot)
	goal_lot.bay_occupied_changed.connect(_on_bay_occupied_changed)


## Where the truck has to end up, in the world: the middle of the free bay.
func goal_target() -> Vector3:
	return goal_lot.bay_centre() if goal_lot != null else to_global(goal_transform.origin)


## The number painted on the free bay ("Estacioná en la bahía 7").
func goal_bay_number() -> int:
	return goal_lot.bay_number if goal_lot != null else 0


func get_progress(world_position: Vector3) -> float:
	if route_length <= 0.0:
		return 0.0
	return clampf(_nearest_sample(world_position).get("cumulative", 0.0) / route_length, 0.0, 1.0)


## Metres along the road from the start to where `world_position` is (its
## nearest point on the road), for the dashboard GPS (N-502). Resolution is
## _path_points' ~10 m.
func road_distance(world_position: Vector3) -> float:
	var cumulative: PackedFloat32Array = _path_cumulative()
	if cumulative.is_empty():
		return 0.0
	var local_position: Vector3 = to_local(world_position)
	_path_hint = _nearest_index(_path_points, local_position, true, [_path_hint, PATH_WINDOW, _path_gap_size()])
	return cumulative[_path_hint]


## Metres along the road from the start to house `index`'s stop, or to the
## goal for an index past the last house.
func stop_road_distance(index: int) -> float:
	var cumulative: PackedFloat32Array = _path_cumulative()
	if cumulative.is_empty():
		return 0.0
	if index >= _house_anchors.size():
		return cumulative[-1]
	var stop: Vector3 = (_house_anchors[index].cursor as Transform3D).origin
	return cumulative[_nearest_index(_path_points, stop, true)]


func _path_cumulative() -> PackedFloat32Array:
	if _path_distances.size() != _path_points.size():
		_path_distances.resize(_path_points.size())
		var total: float = 0.0
		for index: int in range(_path_points.size()):
			if index > 0:
				total += _path_points[index].distance_to(_path_points[index - 1])
			_path_distances[index] = total
	return _path_distances


## Same result as scanning every point (the first one wins a tie), but when
## `hint` (where the last lookup landed) is given, only the `radius` points
## either side of it are looked at first. The windowed answer is trusted only
## if it isn't at the window's edge (the road may go on getting closer beyond
## it) and isn't further than twice the widest gap between neighbours (a jump:
## teleport, restart, a house's position); otherwise the whole array is
## scanned. `planar` measures on the ground plane only. `window` is
## [hint, radius, widest gap between neighbours], empty for a full scan.
func _nearest_index(points: Array[Vector3], query: Vector3, planar: bool, window: Array = []) -> int:
	var count: int = points.size()
	if count == 0:
		return 0
	var hint: int = int(window[0]) if not window.is_empty() else -1
	var radius: int = int(window[1]) if not window.is_empty() else 0
	var gap: float = float(window[2]) if not window.is_empty() else 0.0
	var low: int = 0
	var high: int = count - 1
	if hint >= 0 and hint < count:
		low = maxi(0, hint - radius)
		high = mini(count - 1, hint + radius)
	var nearest: int = low
	var best: float = INF
	for index: int in range(low, high + 1):
		var gap_squared: float = _gap_squared(points[index], query, planar)
		if gap_squared < best:
			best = gap_squared
			nearest = index
	var windowed: bool = low > 0 or high < count - 1
	var at_edge: bool = (nearest == low and low > 0) or (nearest == high and high < count - 1)
	if windowed and (at_edge or best > 4.0 * gap * gap):
		return _nearest_index(points, query, planar)
	return nearest


static func _gap_squared(point: Vector3, query: Vector3, planar: bool) -> float:
	if planar:
		return Vector2(point.x - query.x, point.z - query.z).length_squared()
	return point.distance_squared_to(query)


## Widest distance between consecutive points, to size "close enough to trust".
static func _widest_gap(points: Array[Vector3]) -> float:
	var widest: float = 1.0
	for index: int in range(1, points.size()):
		widest = maxf(widest, points[index].distance_to(points[index - 1]))
	return widest


func _path_gap_size() -> float:
	if _path_gap < 0.0:
		_path_gap = _widest_gap(_path_points)
	return _path_gap


func get_section_name(world_position: Vector3) -> String:
	var leg_index: int = int(_nearest_sample(world_position).get("leg_index", 0))
	if leg_index >= house_count:
		return tr("WORLD_ROUTE_SECTION_GOAL") % goal_bay_number()
	if leg_index == 0:
		return tr("WORLD_ROUTE_SECTION_LEG") % [1, house_count]
	return tr("WORLD_ROUTE_SECTION_LEG") % [leg_index + 1, house_count]


## Nearest-boundary lookup rather than exact arc-length math: with segment
## boundaries every ~10-60m, the error this introduces is well under a
## segment's own length -- plenty for a HUD "distance remaining" readout,
## not something gameplay-critical reads.
func _nearest_sample(world_position: Vector3) -> Dictionary:
	if _progress_samples.is_empty():
		return {}
	if _sample_points.size() != _progress_samples.size():
		_sample_points.clear()
		for sample: Dictionary in _progress_samples:
			_sample_points.append(sample["position"])
	return _progress_samples[_nearest_index(_sample_points, to_local(world_position), false)]


## How far `world_position` is from the nearest known point on the actual
## generated path -- level_base.gd's "you left the route" safety net used to
## just check abs(world x) > 42, which only worked because the old road
## never left world x≈0. A curving road drifts the asphalt itself well past
## that on a wide turn while the vehicle is still perfectly on it, so the
## safety net needed to start measuring distance from the real path instead
## of from a world axis that stopped meaning anything once the road bent.
func distance_from_path(world_position: Vector3) -> float:
	if _path_points.is_empty():
		return INF
	var local_position: Vector3 = to_local(world_position)
	# A truck blown to NaN is off the road (the old full scan answered INF).
	if not local_position.is_finite():
		return INF
	_path_hint_3d = _nearest_index(_path_points, local_position, false, [_path_hint_3d, PATH_WINDOW, _path_gap_size()])
	return _path_points[_path_hint_3d].distance_to(local_position)


func _finish_terrain() -> void:
	_keep_houses_off_road()
	_clamp_river_reach()
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
				# No tree on the rails.
				_clear_zones.append(Vector3(pad.x, pad.z, 4.0))
			# A tunnel at each end, a hill over it; nothing grows in the
			# cutting or out of the portal.
			for mouth: Dictionary in (segment as RailCrossingSegment).tunnel_mouths():
				mouth["level"] = level
				terrain.tunnels.append(mouth)
				var front: Vector2 = (mouth.at as Vector2) + (mouth.dir as Vector2) * 2.0
				_clear_zones.append(Vector3(front.x, front.y, 11.0))
	terrain.build()
	for child: Node in get_children():
		if child == terrain or child == goal_lot or child is DeliveryHouse or String(child.name).begins_with("HouseNumber"):
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
	# Halos round the lamps after dark (N-304), found while they're still nodes.
	var flares: MultiMeshInstance3D = NightFlares.build(self)
	if flares != null:
		add_child(flares)
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
	_sample_points.clear()
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
## from its origin (see RoutePlacement.base_offset).
func _mesh_base_offset(node: Node3D) -> float:
	return RoutePlacement.base_offset(node)


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


## The truck is in the free bay (or left it): what the old goal area said.
func _on_bay_occupied_changed(occupied: bool, body: Node3D) -> void:
	if occupied:
		_on_delivery_body_entered(body)
	else:
		_on_delivery_body_exited(body)


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


const NEWLINE: String = "\n"


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
	var count: int = RoutePlanner.crew_house_count((network.get(&"peer_ids") as Array).size())
	if int(network.get(&"world_seed")) != 0 and bool(network.call(&"is_host")):
		network.set(&"world_house_count", count)
	return count
