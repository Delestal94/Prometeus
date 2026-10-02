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
##
## N-225.3: this script chains the road and stays the route's one public face (houses, goal, the
## queries, the signals); by responsibility the rest lives in route_houses.gd (each house, its yard,
## number and sight lines), route_path.gd (nearest-point lookups over the road), route_ground.gd
## (what the terrain is told about the road) and route_planner.gd (what to build where).

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const Terrain = preload("res://scripts/gameplay/route/route_terrain.gd")
const Houses = preload("res://scripts/gameplay/route/route_houses.gd")
const PathLookup = preload("res://scripts/gameplay/route/route_path.gd")
const Ground = preload("res://scripts/gameplay/route/route_ground.gd")
const Reveal = preload("res://scripts/gameplay/route/route_reveal.gd")

signal delivery_entered
signal delivery_exited
## The whole route stands: terrain, houses, dressing, everything (N-408). Until
## then it builds itself a slice per frame -- see is_built and loading_progress().
signal built
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
## Builds over several frames (a loading screen that never freezes, N-408), the
## terrain's numbers on worker threads, when a loading cover is up to wait for it
## (a SceneLoader in the tree: it holds the cover while this node is in
## SceneLoader.BUSY_GROUP). Off, or with no cover (a test, a tool, a restart),
## _ready() builds it all before it returns, on this thread, like it always did:
## whatever reads the route right after add_child() keeps working. Set before
## this node enters the tree.
@export var async_build: bool = true
## Slices the build even with no loading cover: the tests of the sliced build set
## this (and the net tests, to run the handshake over it).
static var always_slice: bool = false
## Whether the route is complete (`built` fired). It is by the time _ready()
## returns when async_build is off.
var is_built: bool = false
var is_vehicle_in_delivery: bool = false
var houses: Array[DeliveryHouse] = []
## The station on this road, if it is long enough for one (ServiceStop, N-110).
var service_stop: Node3D
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
const TEAL := Houses.TEAL
## The painted start line is road paint (worn white), not a glowing cyan strip.
const START_LINE := Color("d4d9c2")
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
## Where the road is, for the nearest-point lookups (route_path.gd); it shares `_path_points` and
## `_progress_samples` with this script.
var _path := PathLookup.new(_path_points, _progress_samples)
var _house_deck: Array[int] = []
## Road cursor and side each house was dealt, for furnishing it once its
## final spot is known (route_houses.gd keep_houses_off_road()).
var _house_anchors: Array[Dictionary] = []
## What placed the dressing, and how much of each kind (for tests/tuning).
var dresser: RouteDresser
## (x, z, radius) circles in route space where no tree or roadside prop may
## stand -- each house with its yard, plus the farmhouse's barn.
## RouteDresser reads these; see route_dresser.gd for the placement rules.
var _clear_zones: Array[Vector3] = []
## Lines of sight from the road to each house (route_houses.gd):
## kept clear of trees and props, but not of road signs.
var _sight_zones: Array[Vector3] = []
var terrain: TerrainField
var _segments: Array[RouteSegment] = []
## Deals the houses their spots and furnishes them (route_houses.gd), once the terrain exists.
var _house_builder: Houses
## Cuts the build into frames (null: all at once), and where the loading bar stands.
var _slicer: FrameSlicer
var _stage_start: float = 0.0
var _stage_span: float = 0.0
var _stage_fraction: float = 0.0
var _stage_probe: Callable = Callable()
var _progress: float = 0.0
## [node, its process_mode] of what was built before the ground existed, held
## still (see _freeze()) until the terrain stands.
var _frozen: Array = []
var _started_usec: int = 0
## Wall time up to the end of each stage of the build, in ms, the whole of it,
## and the longest slice the main thread held between two frames (tuning, tests).
var build_stats: Dictionary = {}
## Where each stage of the build ends on the loading bar: roughly by the time they take.
const STAGE_LEGS: Vector2 = Vector2(0.0, 0.10)
const STAGE_TERRAIN: Vector2 = Vector2(0.10, 0.36)
const STAGE_CONFORM: Vector2 = Vector2(0.36, 0.62)
const STAGE_DRESS: Vector2 = Vector2(0.62, 0.80)
const STAGE_BAKE: Vector2 = Vector2(0.80, 0.97)
## What the main thread works at a stretch before a frame is drawn, milliseconds.
const BUILD_SLICE_MSEC: float = 12.0


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


## How bad the ground is under a runner (N-115, player_sprint.gd): 0 on the
## asphalt, the yard and the depot's apron, VERGE_ROUGHNESS on the verge and the
## fields, 1 on a gravel stretch. Feeds the chance to trip while running with a box.
const VERGE_ROUGHNESS: float = 0.25


func ground_roughness(world_point: Vector3) -> float:
	if terrain == null:
		return 0.0
	var point := Vector2(world_point.x, world_point.z)
	for zone: Rect2 in terrain.flat_zones:
		if zone.has_point(point):
			return 0.0
	var road: Vector3 = terrain.nearest(point)  # x: distance to the road's centreline, y: gravel, z: its width.
	if road.x <= road.z * 0.5 + 0.5:
		return 1.0 if road.y > 0.5 else 0.0
	return VERGE_ROUGHNESS


func _ready() -> void:
	add_to_group(&"route")  # The runner asks it how rough the ground is (ground_roughness()).
	# A scene that builds itself over frames holds the loading cover up (SceneLoader).
	add_to_group(SceneLoader.BUSY_GROUP)
	_started_usec = Time.get_ticks_usec()
	if async_build and (always_slice or _loading_cover_up()):
		_slicer = FrameSlicer.new(get_tree(), BUILD_SLICE_MSEC)
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
	_house_builder = Houses.new(self, terrain, houses, _house_anchors, _house_deck, _path_points, _clear_zones, _sight_zones)
	Ground.reserve_start_yard(terrain, start_yard, _clear_zones)
	_build()


## Whether a loading cover is up (a SceneLoader under the root) and will wait for this node.
func _loading_cover_up() -> bool:
	for node: Node in get_tree().root.get_children():
		if node is SceneLoader:
			return true
	return false


## The whole build, a slice per frame when there is a slicer (see FrameSlicer).
func _build() -> void:
	var cursor: Transform3D = Transform3D.IDENTITY
	_progress_samples.append({"cumulative": 0.0, "position": cursor.origin, "leg_index": 0})
	_start_leg(cursor)
	_enter_stage(STAGE_LEGS)
	for leg_index: int in range(house_count + 1):
		cursor = await _build_leg(cursor, leg_index)
		if leg_index < house_count:
			cursor = _build_house(cursor, leg_index)
			await _tick()
	goal_transform = cursor
	_build_goal(cursor)
	_reserve_service_stop()
	await _tick()
	await _finish_terrain()
	_build_ambience()
	_mark_stage("ambience")
	await _tick()
	var sky := RouteSky.new()
	sky.name = "Sky"
	add_child(sky)
	_mark_stage("sky")
	_complete()


## The build is over: the route counts as built and the loading cover may lift.
func _complete() -> void:
	is_built = true
	_progress = 1.0
	var total: float = float(Time.get_ticks_usec() - _started_usec) / 1000.0
	build_stats["total_msec"] = total
	build_stats["longest_slice_msec"] = float(_slicer.longest_slice_usec) / 1000.0 if _slicer != null else total
	build_stats["frames"] = _slicer.frames_waited if _slicer != null else 0
	remove_from_group(SceneLoader.BUSY_GROUP)
	built.emit()


## How far the build has got, 0..1 and never going back: the loading bar follows
## it (SceneLoader reads it from the nodes in BUSY_GROUP).
func loading_progress() -> float:
	if is_built:
		return 1.0
	var fraction: float = _stage_fraction
	if _stage_probe.is_valid():
		fraction = float(_stage_probe.call())
	_progress = maxf(_progress, _stage_start + _stage_span * clampf(fraction, 0.0, 1.0))
	return minf(_progress, 0.999)


## The route's first draw in pieces, one per frame under the loading cover
## (SceneLoader, like Depot.reveal_steps()): see route_reveal.gd.
func reveal_steps() -> Array[Callable]:
	if not is_built:
		var whole: Array[Callable] = [func() -> void: visible = true]
		return whole
	return Reveal.steps(self, terrain)


## The build moves on to the stage that fills `bar` (from, to) of the loading
## bar; `probe` (optional) tells how far through it is, else _stage_fraction does.
func _enter_stage(bar: Vector2, probe: Callable = Callable()) -> void:
	_stage_start = bar.x
	_stage_span = bar.y - bar.x
	_stage_fraction = 0.0
	_stage_probe = probe


## Between two steps of the build: lets a frame draw if this one's slice is spent.
func _tick() -> void:
	if _slicer != null:
		await _slicer.tick()


## A long route has one service station (N-110, ServiceStopSegment): its yard
## is levelled to the road's height (terrain pads that fade out before the
## lane, ServiceStopRules.YARD_PADS), and no tree or roadside prop
## grows where the forecourt, kiosk and price pole stand.
func _reserve_service_stop() -> void:
	for segment: RouteSegment in _segments:
		if segment.get_script() != RoutePlanner.SERVICE_STOP.SEGMENT:
			continue
		service_stop = segment.get(&"stop")
		for local: Vector3 in RoutePlanner.SERVICE_STOP.YARD_PADS:
			var at: Vector3 = segment.transform * local
			var road: Vector3 = segment.transform * Vector3(0.0, 0.0, local.z)
			terrain.pads.append(Vector3(at.x, terrain.base_height(Vector2(road.x, road.z)), at.z))
		for z: int in range(-40, -104, -8):
			for x: float in [16.0, 24.0]:
				var at: Vector3 = segment.transform * Vector3(x, 0.0, z)
				_clear_zones.append(Vector3(at.x, at.z, 7.0))


## Whether a world point is on the service station's lay-by (a truck pulled in
## to shop), so a crew that parked there isn't counted as stuck.
func in_service_bay(world_point: Vector3) -> bool:
	return is_instance_valid(service_stop) and bool(service_stop.call(&"in_bay", world_point))


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
	RouteProps.sign(self, "Salida", tr("WORLD_ROUTE_START_SIGN"), sign_at, Houses.ground_height_at(sign_at.x), TEAL)
	RouteProps.box(self, "StartLine", Vector3(11.4, 0.02, 0.35), cursor.origin + Vector3(0.0, 0.03, -4.0), START_LINE)


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
		_freeze(segment)
		add_child(segment)
		_segments.append(segment)
		Ground.register_spans(terrain, segment, cursor)
		# Where this segment's own stretch of _path_points starts and ends.
		var path_start_index: int = _path_points.size()
		for slot: Transform3D in segment.get_dressing_slots(10.0):
			_path_points.append((cursor * slot).origin)
		Ground.register_features(terrain, segment, cursor, path_start_index, _path_points.size(), route_length)
		route_length += segment.length
		cursor = cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)
		_progress_samples.append({"cumulative": route_length, "position": cursor.origin, "leg_index": leg_index})
		_stage_fraction = float(_segments.size()) / float(maxi(_plan.segments.size(), 1))
		await _tick()
	return cursor


## One house per package, one per leg (route_houses.gd build_house() deals it a spot beside the road at
## the cursor's own heading). Returns the cursor unchanged: the house is a detour off the road, not
## part of the chain.
func _build_house(cursor: Transform3D, index: int) -> Transform3D:
	var house: DeliveryHouse = _house_builder.build_house(cursor, index)
	_freeze(house)
	var captured_index: int = index
	house.resolved.connect(func(outcome: StringName, package_id: StringName) -> void: house_resolved.emit(captured_index, outcome, package_id))
	return cursor


## What tests (test_route_fuzz.gd) ask of the house builder: a model's extent in the house's space,
## and how far the house stands from the asphalt.
func _local_bounds(root_node: Node3D, node: Node) -> AABB:
	return Houses.local_bounds(root_node, node)


func _house_road_gap(house: Node3D, bounds: AABB) -> float:
	return _house_builder.house_road_gap(house, bounds)

## The base at the end of the road (N-116): a levelled lot at the cursor,
## sized and dressed by RouteGoalLot. The ground under it is made level here
## (a platform in the terrain), nothing is planted on it, and the road's dense
## path carries on into its free bay so the GPS and the off-road check know
## the way.
func _build_goal(cursor: Transform3D) -> void:
	terrain.add_span(cursor.origin, cursor * Vector3(0.0, 0.0, -24.0))
	goal_lot = RouteGoalLot.new()
	goal_lot.name = "GoalLot"
	_freeze(goal_lot)
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
	return clampf(_path.nearest_sample(to_local(world_position)).get("cumulative", 0.0) / route_length, 0.0, 1.0)


## Metres along the road from the start to where `world_position` is (its
## nearest point on the road), for the dashboard GPS (N-502). Resolution is
## _path_points' ~10 m.
func road_distance(world_position: Vector3) -> float:
	return _path.road_distance(to_local(world_position))


## Metres along the road from the start to house `index`'s stop, or to the
## goal for an index past the last house.
func stop_road_distance(index: int) -> float:
	if index >= _house_anchors.size():
		return _path.total_distance()
	return _path.stop_distance((_house_anchors[index].cursor as Transform3D).origin)


## Metres along the road to each of _path_points (worked out on first use).
func _path_cumulative() -> PackedFloat32Array:
	return _path.cumulative()


func get_section_name(world_position: Vector3) -> String:
	var leg_index: int = int(_path.nearest_sample(to_local(world_position)).get("leg_index", 0))
	if leg_index >= house_count:
		return tr("WORLD_ROUTE_SECTION_GOAL") % goal_bay_number()
	if leg_index == 0:
		return tr("WORLD_ROUTE_SECTION_LEG") % [1, house_count]
	return tr("WORLD_ROUTE_SECTION_LEG") % [leg_index + 1, house_count]


## How far `world_position` is from the nearest known point on the actual
## generated path -- level_base.gd's "you left the route" safety net (see
## route_path.gd distance_from_path()).
func distance_from_path(world_position: Vector3) -> float:
	return _path.distance_from_path(to_local(world_position))


func _finish_terrain() -> void:
	_house_builder.keep_houses_off_road()
	Ground.clamp_river_reach(terrain, _path_points, _path_cumulative(), houses, start_yard)
	# Level building pads blend back into the landscape, so the doorstep and
	# access path remain walkable even on a hillside.
	for house: Node3D in houses:
		var p: Vector3 = house.position
		p.y = terrain.base_height(Vector2(p.x, p.z)) - 0.08
		terrain.pads.append(p)
	Ground.level_rail_crossings(terrain, _segments, _clear_zones)
	_mark_stage("legs")
	_enter_stage(STAGE_TERRAIN, func() -> float: return terrain.build_progress)
	await terrain.build_async(_slicer)
	_mark_stage("terrain")
	_enter_stage(STAGE_CONFORM, func() -> float: return terrain.conform_progress)
	var to_conform: Array[Node] = []
	for child: Node in get_children():
		if child == terrain or child == goal_lot or child is DeliveryHouse or String(child.name).begins_with("HouseNumber"):
			continue
		to_conform.append(child)
	await terrain.conform_all(to_conform, _slicer)
	for segment: RouteSegment in _segments:
		if segment is RailCrossingSegment:
			var track: Vector3 = segment.transform * Vector3(0.0, 0.0, (segment as RailCrossingSegment).track_z)
			segment.set_meta(&"track_height", terrain.height_at(track))
	for house: Node3D in houses:
		house.position.y = terrain.height_at(house.position)
		var label: Node3D = get_node(NodePath("HouseNumber%d" % house.house_index))
		label.position.y = house.position.y + float(label.get_meta(&"height_above_house", 4.0))
	_mark_stage("conform")
	await _thaw()
	# One draw from the session RNG after the whole road exists, so dressing
	# can never change the road itself -- and every peer gets the same draw.
	dresser = RouteDresser.new(self, terrain, _rng.randi())
	dresser.raining = mood.is_raining()
	_enter_stage(STAGE_DRESS, func() -> float: return dresser.progress)
	await dresser.dress(_segments, houses, _clear_zones, _sight_zones, _slicer)
	_mark_stage("dress")
	# Halos round the lamps after dark (N-304), found while they're still nodes.
	var flares: MultiMeshInstance3D = NightFlares.build(self)
	if flares != null:
		add_child(flares)
	await _tick()
	_enter_stage(STAGE_BAKE)
	if batch_dressing:
		var yards: Array = houses.map(func(house: DeliveryHouse) -> Node: return house.get_node_or_null(^"Yard"))
		await DressingBatcher.bake(self, _segments, yards, _slicer)
		_stage_fraction = 0.8
		await DressingBatcher.merge_segment_geometry(_segments, _slicer)
	for i: int in range(_path_points.size()):
		_path_points[i].y = terrain.height_at(_path_points[i])
	for sample: Dictionary in _progress_samples:
		var p: Vector3 = sample.position
		p.y = terrain.height_at(p)
		sample.position = p
	_path.invalidate_samples()
	goal_transform.origin.y = terrain.height_at(goal_transform.origin)
	_mark_stage("bake")


## Holds `node` (a segment, a house, the goal lot) out of the physics and the
## processing until the ground is there (_thaw()): the cones a segment drops are
## bodies, and the physics runs between the frames the build is spread over, so
## they would fall through the world before the terrain exists. Call it before
## or right after the node enters the tree. Nothing when the build isn't
## spread over frames.
func _freeze(node: Node) -> void:
	if _slicer == null:
		return
	_frozen.append([node, node.process_mode])
	node.process_mode = Node.PROCESS_MODE_DISABLED


## The terrain stands: whatever _freeze() held lives again, one at a time so no
## frame pays for all of them.
func _thaw() -> void:
	for entry: Array in _frozen:
		var node: Node = entry[0]
		node.process_mode = entry[1]
		await _tick()
	_frozen.clear()


## Writes down how long the build took, up to the end of `stage`.
func _mark_stage(stage: String) -> void:
	build_stats[stage + "_msec"] = float(Time.get_ticks_usec() - _started_usec) / 1000.0


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
