extends Node3D
## Procedurally generated first delivery route (2026-09-22 rework): the road
## actually bends now, and each stretch between one house and the next is a
## long mini-adventure (LEG_MIN_LENGTH-LEG_MAX_LENGTH m) built from the same
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
## Deliberately NOT extended to modo endless (RouteStreamer) in this pass --
## that's still a straight-line streaming/culling system, and making ITS
## lookahead/cull math curve-aware is a separate, riskier follow-up.

signal delivery_entered
signal delivery_exited
## Fires whenever any house resolves (delivered ok/ruined/missed) -- forwards
## DeliveryHouse.resolved so level_base.gd or the HUD can react without
## walking the house list themselves.
signal house_resolved(house_index: int, outcome: StringName, package_id: StringName)

@export var route_length: float = 0.0
## How many delivery houses this run has -- one per package, per package per
## player minus the driver (docs/tareas-nacho.md: house delivery system).
## Defaults to 3 (the "4 players, 1 drives" example) since nothing wires
## live roster size into this yet -- that's the coordination point noted in
## tareas-nacho.md, not guessed at here. Call configure_houses() before this
## node enters the tree to override.
@export var house_count: int = 3
var is_vehicle_in_delivery: bool = false
var houses: Array[DeliveryHouse] = []

## Target length of each leg (start->house, house->house, house->goal),
## randomized per leg within this range -- "mini aventura" territory, not a
## quick hop. Actual length overshoots slightly since a leg only stops once
## the segment that crosses the target finishes.
const LEG_MIN_LENGTH: float = 400.0
const LEG_MAX_LENGTH: float = 600.0
## House/road proportions carried over unchanged from the old handcrafted
## route -- only WHERE the road goes changed, not how wide it or a house
## approach is.
const HOUSE_LATERAL_OFFSET: float = 10.5
const HOUSE_PATH_LATERAL_OFFSET: float = 7.9

## Populated in _ready(), not here -- GDScript can't fold a const array
## referencing several global class_names at parse time ("Assigned value...
## isn't a constant expression"), same issue route_streamer.gd already
## documents and works around the same way.
var _spine_segment_scripts: Array[Script] = []
## Same "needs real steering/braking" definition RouteStreamer uses --
## CurveSegment isn't on it: turning is the default expectation of driving
## anywhere on this route now, not a special hazard.
var _spine_hard_segments: Array[Script] = []
## How many segments in a row are allowed to leave the heading unchanged
## before a CurveSegment is forced -- this is the actual fix for "no quiero
## tramos rectos": without it, the "never repeat the same type twice" rule
## alone still allows Straight, Bump, Straight, Gravel, Straight... for as
## long as the RNG allows, all dead straight in world space.
const MAX_STRAIGHT_STREAK: int = 2
const CURVE_TURN_MIN_DEG: float = 25.0
const CURVE_TURN_MAX_DEG: float = 70.0

const TREE_ROW_SPACING: float = 3.1
const PLANT_SPACING: float = 0.43  # ~2.3 plants/m, matching the old density

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
var _last_script: Script = null
var _hard_streak: int = 0
var _straight_streak: int = 0
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
## Running counters for dressing variety, instead of restarting from 0 in
## every segment -- otherwise segment N's first tree row would always look
## identical to segment N+1's first tree row (same index -> same pseudo-
## random pick/rotation/scale), visibly repetitive with legs now built from
## many short segments instead of one long handcrafted stretch.
var _tree_index: int = 0
var _plant_index: int = 0
var _furniture_index: int = 0
var _vehicle_index: int = 0
## Distance from the very start that only gets Straight/SpeedBump/Gravel/
## NarrowBridge -- segments that don't need steering input to survive.
## Matches (with margin) how far the old handcrafted route's first real
## steering-hazard (the chicane, ~106m in) used to be. Below this length,
## _pick_spine_script() can't return CurveSegment, ChicaneSegment,
## SCurveSegment or ConstructionZoneSegment. Same problem RouteStreamer's
## first_segment_script already solved for its own pool (a driver needs a
## second to get their bearings) -- this route needed a longer buffer, not
## just one segment, because test_vehicle_presentation.gd and
## test_dust_and_ambience.gd drive 90-100 physics ticks at full throttle
## with zero steering input to check headlights/dust, and caught it when a
## single straight segment wasn't enough runway.
const SAFE_START_LENGTH: float = 150.0


## Overrides house_count before the node builds itself. Call before
## add_child()-ing this into the tree -- _ready() already builds geometry
## from house_count, same convention as any other @export here.
func configure_houses(count: int) -> void:
	house_count = maxi(count, 1)


func _ready() -> void:
	# One seed per session, not per machine: see NetworkManager.world_seed.
	# Solo play leaves it at 0, which still means "a different route every
	# time you press play".
	var session_seed: int = _session_seed()
	if session_seed != 0:
		_rng.seed = session_seed
	else:
		_rng.randomize()
	_spine_segment_scripts = [
		StraightSegment, SpeedBumpSegment, ChicaneSegment, NarrowBridgeSegment,
		SCurveSegment, GravelSegment, ConstructionZoneSegment,
		CurveSegment, CurveSegment,  # weighted up: this is the one that turns
	]
	_spine_hard_segments = [ChicaneSegment, NarrowBridgeSegment, SCurveSegment, GravelSegment, ConstructionZoneSegment]
	var cursor: Transform3D = Transform3D.IDENTITY
	_progress_samples.append({"cumulative": 0.0, "position": cursor.origin, "leg_index": 0})
	_start_leg(cursor)
	for leg_index: int in range(house_count + 1):
		cursor = _build_leg(cursor, leg_index)
		if leg_index < house_count:
			cursor = _build_house(cursor, leg_index)
	goal_transform = cursor
	_build_goal(cursor)
	_build_ambience()


## Each spine segment only builds ground/road from its own local z=0 back to
## z=-length -- there's nothing covering POSITIVE z. The old handcrafted
## route always had a forward margin there (its single big ground/shoulder
## box started well past z=0) because the vehicle spawns at z=0 exactly and
## the on-foot spawn points go up to z=+5 -- without this apron the vehicle
## spawns with no ground under it at all and free-falls (caught by
## test_vehicle_presentation.gd and test_dust_and_ambience.gd: the vehicle
## fell out from under them before their checks ever ran).
func _start_leg(cursor: Transform3D) -> void:
	_box("StartApronGround", Vector3(24.0, 1.0, 20.0), cursor.origin + Vector3(0.0, -0.8, 9.5), SHOULDER, true)
	_box("StartApronRoad", Vector3(12.0, 0.4, 20.0), cursor.origin + Vector3(0.0, -0.2, 9.5), ROAD, true)
	_sign("Salida", "SALIDA\nCuidá la carga -- el camino serpentea", cursor.origin + Vector3(-7.6, 0.0, -5.0), TEAL)
	_box("StartLine", Vector3(11.4, 0.02, 0.35), cursor.origin + Vector3(0.0, 0.015, -4.0), TEAL)


## Builds one leg's worth of road (LEG_MIN_LENGTH-LEG_MAX_LENGTH m of
## chained segments) starting at `cursor`, and returns the cursor at the
## far end so the caller can place a house or the goal there.
func _build_leg(cursor: Transform3D, leg_index: int) -> Transform3D:
	var target_length: float = _rng.randf_range(LEG_MIN_LENGTH, LEG_MAX_LENGTH)
	var leg_length: float = 0.0
	while leg_length < target_length:
		var script: Script = _pick_spine_script()
		var segment: RouteSegment = _instantiate_spine_segment(script)
		segment.transform = cursor
		add_child(segment)
		_dress_segment(segment)
		for slot: Transform3D in segment.get_dressing_slots(10.0):
			_path_points.append((cursor * slot).origin)
		leg_length += segment.length
		route_length += segment.length
		cursor = cursor * Transform3D(Basis(Vector3.UP, segment.exit_turn), segment.exit_offset)
		_progress_samples.append({"cumulative": route_length, "position": cursor.origin, "leg_index": leg_index})
		_last_script = script
		_straight_streak = 0 if script == CurveSegment else _straight_streak + 1
		_hard_streak = _hard_streak + 1 if _spine_hard_segments.has(script) else 0
	return cursor


func _instantiate_spine_segment(script: Script) -> RouteSegment:
	if script == CurveSegment:
		var curve := CurveSegment.new()
		var sign_: float = -1.0 if _rng.randf() < 0.5 else 1.0
		curve.turn_deg = sign_ * _rng.randf_range(CURVE_TURN_MIN_DEG, CURVE_TURN_MAX_DEG)
		return curve
	return script.new() as RouteSegment


func _pick_spine_script() -> Script:
	var candidates: Array[Script] = _spine_segment_scripts.duplicate()
	if route_length < SAFE_START_LENGTH:
		candidates = candidates.filter(func(s: Script) -> bool: return not _spine_hard_segments.has(s) and s != CurveSegment)
	if _last_script != null:
		candidates = candidates.filter(func(s: Script) -> bool: return s != _last_script)
	if _hard_streak >= 2:
		var easy_candidates: Array[Script] = candidates.filter(func(s: Script) -> bool: return not _spine_hard_segments.has(s))
		if not easy_candidates.is_empty():
			candidates = easy_candidates
	if _straight_streak >= MAX_STRAIGHT_STREAK and candidates.has(CurveSegment):
		candidates = [CurveSegment]
	return candidates[_rng.randi() % candidates.size()]


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
	house.visual_variant = index
	house.house_index = index
	# The house model's entrance is on local -Z. Rotate that face toward the
	# asphalt rather than along the road, so stops address the route.
	house.transform = cursor * Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * HOUSE_LATERAL_OFFSET, _ground_height_at(HOUSE_LATERAL_OFFSET), 0.0))
	add_child(house)
	houses.append(house)
	_build_house_path(cursor, index, side)
	var captured_index: int = index
	house.resolved.connect(func(outcome: StringName, package_id: StringName) -> void: house_resolved.emit(captured_index, outcome, package_id))
	var label_transform: Transform3D = cursor * Transform3D(Basis.IDENTITY, Vector3(side * HOUSE_LATERAL_OFFSET, _ground_height_at(HOUSE_LATERAL_OFFSET) + 4.0, 2.6))
	_label("HouseNumber%d" % index, "CASA %d" % (index + 1), label_transform.origin, 0.01, TEAL)
	return cursor


## A narrow worn path makes each stop feel connected to the road. It stops
## at the shoulder rather than widening the driving lane or blocking traffic.
func _build_house_path(cursor: Transform3D, index: int, side: float) -> void:
	var path_height: float = 0.025
	var path_transform: Transform3D = cursor * Transform3D(Basis.IDENTITY, Vector3(side * HOUSE_PATH_LATERAL_OFFSET, _ground_height_at(HOUSE_PATH_LATERAL_OFFSET) + path_height * 0.5, 0.0))
	var path := Node3D.new()
	path.name = "HousePath%d" % index
	path.transform = path_transform
	add_child(path)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(4.0, path_height, 1.45)
	mesh.mesh = box_mesh
	mesh.material_override = _material(Color("716b54"))
	path.add_child(mesh)


func _build_goal(cursor: Transform3D) -> void:
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


## Dressing (forest + roadside props) walks the segment's own
## get_dressing_slots(), which already accounts for CurveSegment's bent
## interior -- this function doesn't need to know or care whether `segment`
## is straight or curved.
func _dress_segment(segment: RouteSegment) -> void:
	_dress_forest(segment)
	_dress_landmarks(segment)


const TREE_PATHS: Array[String] = [
	"res://assets/models/environment/forest/sm_env_forest_oak.glb",
	"res://assets/models/environment/forest/sm_env_forest_birch.glb",
	"res://assets/models/environment/forest/sm_env_forest_pine_tall.glb",
	"res://assets/models/environment/forest/sm_env_forest_maple.glb",
	"res://assets/models/environment/forest/sm_env_forest_dead.glb",
	"res://assets/models/environment/forest/sm_env_forest_pine_sapling.glb",
]
const GROUND_PLANT_PATHS: Array[String] = [
	"res://assets/models/environment/forest/sm_env_forest_bush_round.glb",
	"res://assets/models/environment/forest/sm_env_forest_fern.glb",
	"res://assets/models/environment/forest/sm_env_forest_grass_clump.glb",
	"res://assets/models/environment/forest/sm_env_forest_wildflower.glb",
	"res://assets/models/environment/forest/sm_env_forest_mushroom.glb",
	"res://assets/models/environment/forest/sm_env_forest_fallen_log.glb",
	"res://assets/models/environment/forest/sm_env_forest_rock.glb",
	"res://assets/models/environment/forest/sm_env_forest_bramble_thicket.glb",
	"res://assets/models/environment/forest/sm_env_forest_tall_fern_cluster.glb",
	"res://assets/models/environment/forest/sm_env_forest_mossy_stump.glb",
	"res://assets/models/environment/forest/sm_env_forest_mossy_rock_cluster.glb",
	"res://assets/models/environment/forest/sm_env_forest_deadfall_branch.glb",
	"res://assets/models/environment/forest/sm_env_forest_tall_grass_clump.glb",
]

## Four irregular layers per side form a tight tree corridor, same as the
## old flat-route version -- just walked per-segment now via
## get_dressing_slots() so it follows a curve instead of assuming -Z.
func _dress_forest(segment: RouteSegment) -> void:
	var slots: Array[Transform3D] = segment.get_dressing_slots(TREE_ROW_SPACING)
	var forest: Node3D = segment.get_node_or_null(^"ForestDressing")
	if forest == null:
		forest = Node3D.new()
		forest.name = "ForestDressing"
		segment.add_child(forest)
	for row: int in range(slots.size()):
		for side: float in [-1.0, 1.0]:
			for layer: int in range(4):
				var index: int = _tree_index
				_tree_index += 1
				var tree := _instantiate_dressing(TREE_PATHS[index % TREE_PATHS.size()])
				if tree == null:
					continue
				var lateral: float = 8.0 + float(layer) * 5.1 + float((index * 7) % 5) * 0.45
				var offset := Vector3(side * lateral, _ground_height_at(side * lateral), float((index * 11) % 7) * -0.24)
				tree.transform = slots[row] * Transform3D(Basis(Vector3.UP, deg_to_rad(float((index * 37) % 360))), offset)
				var tree_scale: float = 0.82 + float((index * 17) % 54) / 100.0
				tree.scale = Vector3.ONE * tree_scale
				forest.add_child(tree)
	var plant_slots: Array[Transform3D] = segment.get_dressing_slots(PLANT_SPACING)
	for slot_index: int in range(plant_slots.size()):
		var index: int = _plant_index
		_plant_index += 1
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var plant := _instantiate_dressing(GROUND_PLANT_PATHS[index % GROUND_PLANT_PATHS.size()])
		if plant == null:
			continue
		var lateral: float = side * (6.7 + float((index * 11) % 25))
		var offset := Vector3(lateral, _ground_height_at(lateral), 0.0)
		plant.transform = plant_slots[slot_index] * Transform3D(Basis(Vector3.UP, deg_to_rad(float((index * 53) % 360))), offset)
		var plant_scale: float = 0.65 + float((index * 19) % 55) / 100.0
		plant.scale = Vector3.ONE * plant_scale
		forest.add_child(plant)


const STREET_PROP_PATHS: Array[String] = [
	"res://assets/models/environment/props/sm_env_prop_street_lamp.glb",
	"res://assets/models/environment/props/sm_env_prop_bench.glb",
	"res://assets/models/environment/props/sm_env_prop_mailbox.glb",
]
const PARKED_VEHICLE_PATHS: Array[String] = [
	"res://assets/models/vehicles/sm_vehicle_parked_hatchback.glb",
	"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb",
]

## Roadside dressing (docs/tareas-nacho.md #26, #29): street furniture every
## ~14m and a parked vehicle roughly every ~55m, same spacing philosophy as
## the old flat-route version, walked per-segment via get_dressing_slots().
func _dress_landmarks(segment: RouteSegment) -> void:
	var dressing: Node3D = segment.get_node_or_null(^"RoadsideDressing")
	if dressing == null:
		dressing = Node3D.new()
		dressing.name = "RoadsideDressing"
		segment.add_child(dressing)
	var furniture_slots: Array[Transform3D] = segment.get_dressing_slots(14.0)
	for slot_index: int in range(furniture_slots.size()):
		var index: int = _furniture_index
		_furniture_index += 1
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var prop := _instantiate_dressing(STREET_PROP_PATHS[index % STREET_PROP_PATHS.size()])
		if prop == null:
			continue
		var lateral: float = side * (9.0 + float((index * 13) % 4))
		var offset := Vector3(lateral, _ground_height_at(lateral), 0.0)
		prop.transform = furniture_slots[slot_index] * Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 * side + float((index * 23) % 20))), offset)
		dressing.add_child(prop)
	var vehicle_slots: Array[Transform3D] = segment.get_dressing_slots(55.0)
	for slot_index: int in range(vehicle_slots.size()):
		var index: int = _vehicle_index
		_vehicle_index += 1
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var vehicle := _instantiate_dressing(PARKED_VEHICLE_PATHS[index % PARKED_VEHICLE_PATHS.size()])
		if vehicle == null:
			continue
		var lateral: float = side * (12.5 + float((index * 9) % 3))
		var offset := Vector3(lateral, _ground_height_at(lateral), 0.0)
		vehicle.transform = vehicle_slots[slot_index] * Transform3D(Basis(Vector3.UP, deg_to_rad(90.0 * side)), offset)
		dressing.add_child(vehicle)
	# Hazard props (cones + a barrier) ride along on ConstructionZoneSegment
	# specifically -- that's the one segment type whose own narrative is
	# already "roadwork," instead of scattering them with no reason to be
	# wherever they land.
	if segment is ConstructionZoneSegment:
		var hazard_slots: Array[Transform3D] = segment.get_dressing_slots(2.2)
		for index: int in range(mini(4, hazard_slots.size())):
			var cone := _instantiate_dressing("res://assets/models/environment/props/sm_env_prop_traffic_cone.glb")
			if cone != null:
				cone.transform = hazard_slots[index] * Transform3D(Basis.IDENTITY, Vector3(6.4, 0.0, 0.0))
				dressing.add_child(cone)
		if not hazard_slots.is_empty():
			var barrier := _instantiate_dressing("res://assets/models/environment/props/sm_env_prop_road_barrier.glb")
			if barrier != null:
				barrier.transform = hazard_slots[0] * Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(6.4, 0.0, 0.0))
				dressing.add_child(barrier)


func _instantiate_dressing(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


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
	player.volume_db = -26.0
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


func _sign(node_name: String, caption: String, location: Vector3, accent: Color) -> void:
	var ground_y: float = _ground_height_at(location.x)
	_box(node_name + "Post", Vector3(0.16, 2.4, 0.16), location + Vector3(0.0, ground_y + 1.2, 0.0), CONCRETE, true)
	_box(node_name + "Board", Vector3(4.6, 1.4, 0.12), location + Vector3(0.0, ground_y + 2.65, 0.0), Color("263b3e"))
	_box(node_name + "Stripe", Vector3(4.6, 0.10, 0.13), location + Vector3(0.0, ground_y + 3.3, 0.0), accent)
	_label(node_name + "Text", caption, location + Vector3(0.0, ground_y + 2.65, 0.08), 0.0065, MARKING)


func _label(node_name: String, caption: String, location: Vector3, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = caption
	label.position = location
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = Color("1e3035")
	add_child(label)


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
