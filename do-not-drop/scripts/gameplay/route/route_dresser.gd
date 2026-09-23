extends RefCounted
class_name RouteDresser
## Decides what stands where along a built route -- the equivalent of
## Minecraft's feature placement: each kind of object has a rule saying
## where across the road it may go, how often, in which kind of place, and
## what it needs around it. Every candidate spot is then checked the same
## way before anything is spawned:
##
##   1. far enough from the asphalt (terrain.nearest() to the road centreline
##      minus the object's own footprint radius),
##   2. not inside a cleared zone (a house and its yard, the farm's barn),
##   3. not overlapping anything solid already placed (occupancy grid),
##   4. not on a slope steeper than the object tolerates,
##   5. not too close to another of its own kind, when that matters
##      (two windmills side by side, three bus stops in a row).
##
## A spot that fails is simply skipped -- nothing gets nudged into a place
## it wasn't meant to be. Explicit features (warning signs, guardrails, the
## roadworks crew's stuff, house yards) go first and claim their space;
## then the rules run in priority order: landmarks, parked cars, village
## furniture, farm props, trees, and finally ground plants, which fill
## whatever is left.
##
## Zones make the road read as a journey instead of one repeated strip:
##   VILLAGE     within VILLAGE_RADIUS of a delivery house: lamps, benches,
##               hydrants, bus stops, parked cars, a thinner tree line.
##   COUNTRYSIDE open stretches picked by low-frequency noise along the road:
##               hay bales, crates, windmills and water towers, scattered trees.
##   FOREST      everything else: the dense tree corridor.
##
## Deterministic: every draw comes from an RNG seeded by the route's session
## seed plus the segment and rule index, so every peer dresses the same
## world, and changing one rule doesn't reshuffle all the others.

enum Zone { FOREST, COUNTRYSIDE, VILLAGE }
enum Facing { ROAD, RANDOM }

const ZONE_NAMES: Dictionary = {Zone.FOREST: "forest", Zone.COUNTRYSIDE: "countryside", Zone.VILLAGE: "village"}
const VILLAGE_RADIUS: float = 110.0
## Noise over distance-along-road, one cycle every few hundred metres; above
## the threshold the forest opens up into countryside.
const COUNTRYSIDE_NOISE_FREQUENCY: float = 0.004
const COUNTRYSIDE_THRESHOLD: float = 0.12
const GRID_CELL: float = 8.0
const MAX_FOOTPRINT: float = 8.0
## Terrain.nearest() returns 4x its HALO when a point has no road tile
## nearby at all -- i.e. there's no ground there to stand on.
const NO_TERRAIN_DISTANCE: float = 250.0

const PROPS: String = "res://assets/models/environment/props/"
const FOREST: String = "res://assets/models/environment/forest/"
const SIGN_DIR: String = "res://assets/models/environment/signs/"
## Which warning goes up in front of which hazard. Straight roads get none:
## a sign that means "nothing ahead" teaches players to ignore signs.
const HAZARD_SIGNS: Dictionary = {
	"CurveSegment": "sm_env_sign_curve.glb",
	"SCurveSegment": "sm_env_sign_curve.glb",
	"SpeedBumpSegment": "sm_env_sign_speed_bump.glb",
	"NarrowBridgeSegment": "sm_env_sign_narrow_bridge.glb",
	"ChicaneSegment": "sm_env_sign_narrow_bridge.glb",
	"GravelSegment": "sm_env_sign_gravel.glb",
	"ConstructionZoneSegment": "sm_env_sign_roadworks.glb",
}
const DELIVERY_SIGN: String = SIGN_DIR + "sm_env_sign_delivery_ahead.glb"
const SIGN_LATERAL: float = 7.8
## The warning stands this far before the hazard's first metre.
const SIGN_LEAD: float = 6.0
const GUARDRAIL: String = PROPS + "sm_env_prop_guardrail.glb"
const WILDLIFE: String = "res://assets/models/environment/wildlife/"
const ANIMAL_BEHAVIOUR: Script = preload("res://scripts/presentation/wildlife_animal.gd")
const CROSSING_SIGN: String = SIGN_DIR + "sm_env_sign_animal_crossing.glb"
## Deer crossings: on a straight, never in a village, never near the start,
## and spaced out so one route has a couple at most -- a hazard you meet
## every thirty seconds stops being a surprise.
const CROSSING_CHANCE: float = 0.35
const CROSSING_MIN_SEGMENT: int = 4
const CROSSING_MIN_GAP: float = 260.0
const CROSSING_MAX: int = 2
## Before the deer (on the segment the truck is still on), like every
## other warning, but far enough out to brake from full speed.
const CROSSING_SIGN_LEAD: float = 30.0
const GUARDRAIL_LATERAL: float = 7.4
const WINDMILL_TURN_SECONDS: float = 14.0
## Ground contact (see _settle()). A model's "feet" are every vertex within
## CONTACT_BAND of its lowest point; of those, the outermost one per angular
## sector around the origin (plus the very lowest) is kept, so a tree's root
## tips, a log's two ends and a bench's four legs are all checked against the
## terrain right under them instead of under the object's centre. Kept thin:
## a parked car's sills sit ~0.3 m above its tyres, and counting them as feet
## sank the wheels into the ground.
const CONTACT_BAND: float = 0.08
const CONTACT_SECTORS: int = 8
## Once nothing floats, everything sinks a touch more so no hairline of sky
## shows under a foot where the terrain bends between samples: proportional
## to how far the feet spread, within these bounds (metres).
const SINK_RATIO: float = 0.05
const SINK_RANGE: Vector2 = Vector2(0.02, 0.1)
## Ground plants that lie on the ground rather than grow out of it, and so
## lean with the slope (a stump or a fern stays upright like a tree).
const LEAN_MODELS: Array[String] = [
	"sm_env_forest_fallen_log.glb", "sm_env_forest_deadfall_branch.glb",
	"sm_env_forest_rock.glb", "sm_env_forest_mossy_rock_cluster.glb",
]

static var _contact_cache: Dictionary = {}

var _route: Node3D
var _terrain: Node
var _seed: int
var _noise := FastNoiseLite.new()
var _houses: Array = []
var _clear_zones: Array[Vector3] = []
var _grid: Dictionary = {}
var _same_kind: Dictionary = {}
var _rules: Array[Dictionary] = []
var _packed: Dictionary = {}
## How many things each rule/feature actually placed, and why the rest were
## turned down ({id: {reason: count}}), for tests and tuning.
var placed_counts: Dictionary = {}
var rejected_counts: Dictionary = {}


func _init(route: Node3D, terrain: Node, seed_value: int) -> void:
	_route = route
	_terrain = terrain
	_seed = seed_value
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = COUNTRYSIDE_NOISE_FREQUENCY
	_rules = _build_rules()


## The rule table, highest priority first. Fields (any missing one takes the
## default in _rule()):
##   paths      models to pick from          lateral   (min, max) metres from the centreline
##   density    Zone -> chance per attempt   spacing   metres along the road between slots
##   attempts   tries per slot and side      sides     which sides of the road, or [] = alternate
##   radius     footprint (m)                clearance min road-centreline distance to the footprint edge
##   max_slope  rise/run across the footprint facing  ROAD (front toward the asphalt) or RANDOM
##   scale      (min, max) uniform scale     solid     others must keep out of its footprint
##   tilt       lean with the ground         min_same  keep this far from another of the same rule
##   group      node that holds it under the segment
func _build_rules() -> Array[Dictionary]:
	return [
		_rule({"id": &"landmark", "group": "LandmarkDressing",
			"paths": ["res://assets/models/environment/landmarks/sm_env_landmark_windmill.glb",
				"res://assets/models/environment/landmarks/sm_env_landmark_water_tower.glb"],
			"density": {Zone.COUNTRYSIDE: 0.35, Zone.FOREST: 0.08}, "spacing": 60.0,
			"lateral": Vector2(42.0, 56.0), "radius": 7.0, "clearance": 30.0, "max_slope": 0.6,
			"facing": Facing.ROAD, "min_same": 170.0}),
		_rule({"id": &"parked_vehicle",
			"paths": ["res://assets/models/vehicles/sm_vehicle_parked_hatchback.glb",
				"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb"],
			"density": {Zone.VILLAGE: 0.55, Zone.COUNTRYSIDE: 0.2, Zone.FOREST: 0.06}, "spacing": 40.0,
			"lateral": Vector2(12.0, 14.5), "radius": 2.4, "clearance": 9.5, "max_slope": 0.18,
			"facing": Facing.ROAD, "tilt": true, "min_same": 22.0}),
		_rule({"id": &"village_furniture",
			"paths": [PROPS + "sm_env_prop_street_lamp.glb", PROPS + "sm_env_prop_bench.glb",
				PROPS + "sm_env_prop_mailbox.glb", PROPS + "sm_env_prop_fire_hydrant.glb"],
			"density": {Zone.VILLAGE: 0.75}, "spacing": 14.0,
			"lateral": Vector2(8.6, 10.2), "radius": 0.7, "clearance": 7.2, "max_slope": 0.25,
			"facing": Facing.ROAD, "tilt": true}),
		_rule({"id": &"bus_stop", "paths": [PROPS + "sm_env_prop_bus_stop.glb"],
			"density": {Zone.VILLAGE: 0.5}, "spacing": 30.0, "sides": [1.0],
			"lateral": Vector2(9.4, 9.8), "radius": 1.9, "clearance": 7.2, "max_slope": 0.15,
			"facing": Facing.ROAD, "tilt": true, "min_same": 150.0}),
		_rule({"id": &"milestone", "paths": [PROPS + "sm_env_prop_milestone.glb"],
			"density": {Zone.FOREST: 1.0, Zone.COUNTRYSIDE: 1.0}, "spacing": 100.0, "sides": [1.0],
			"lateral": Vector2(8.0, 8.4), "radius": 0.4, "clearance": 7.3, "facing": Facing.ROAD,
			"tilt": true, "min_same": 90.0}),
		_rule({"id": &"farm_props",
			"paths": [PROPS + "sm_env_prop_hay_bale.glb", PROPS + "sm_env_prop_wooden_crate.glb",
				PROPS + "sm_env_prop_pallet.glb"],
			"density": {Zone.COUNTRYSIDE: 0.3}, "spacing": 12.0,
			"lateral": Vector2(11.0, 24.0), "radius": 1.0, "clearance": 9.0, "max_slope": 0.3,
			"tilt": true, "min_same": 4.0}),
		_rule({"id": &"tree", "group": "ForestDressing",
			"paths": [FOREST + "sm_env_forest_oak.glb", FOREST + "sm_env_forest_birch.glb",
				FOREST + "sm_env_forest_pine_tall.glb", FOREST + "sm_env_forest_maple.glb",
				FOREST + "sm_env_forest_pine_tall.glb", FOREST + "sm_env_forest_dead.glb",
				FOREST + "sm_env_forest_pine_sapling.glb"],
			"density": {Zone.FOREST: 0.95, Zone.VILLAGE: 0.3, Zone.COUNTRYSIDE: 0.16}, "spacing": 5.5,
			"attempts": 3, "lateral": Vector2(10.0, 30.0), "radius": 1.6, "clearance": 8.4,
			"max_slope": 0.7, "scale": Vector2(0.82, 1.36)}),
		# Wildlife: scenery that notices the truck (wildlife_animal.gd). Never
		# solid -- it runs off -- and never close enough to wander onto the road.
		_rule({"id": &"wildlife_deer", "group": "WildlifeDressing", "solid": false,
			"paths": [WILDLIFE + "sm_env_animal_stag_rigged.glb"], "behaviour": ANIMAL_BEHAVIOUR,
			"density": {Zone.FOREST: 0.07, Zone.COUNTRYSIDE: 0.12}, "spacing": 60.0,
			"lateral": Vector2(15.0, 28.0), "radius": 0.9, "clearance": 12.0, "max_slope": 0.5,
			"min_same": 70.0}),
		_rule({"id": &"wildlife_rabbit", "group": "WildlifeDressing", "solid": false,
			"paths": [WILDLIFE + "sm_env_animal_rabbit.glb"], "behaviour": ANIMAL_BEHAVIOUR,
			"density": {Zone.COUNTRYSIDE: 0.28, Zone.FOREST: 0.12, Zone.VILLAGE: 0.06}, "spacing": 22.0,
			"lateral": Vector2(8.5, 20.0), "radius": 0.2, "clearance": 7.8, "max_slope": 0.5,
			"min_same": 10.0}),
		_rule({"id": &"wildlife_frog", "group": "WildlifeDressing", "solid": false,
			"paths": [WILDLIFE + "sm_env_animal_frog.glb"], "behaviour": ANIMAL_BEHAVIOUR,
			"density": {Zone.FOREST: 0.14, Zone.COUNTRYSIDE: 0.08}, "spacing": 26.0,
			"lateral": Vector2(7.2, 14.0), "radius": 0.15, "clearance": 7.0, "max_slope": 0.6,
			"min_same": 10.0}),
		_rule({"id": &"wildlife_bird", "group": "WildlifeDressing", "solid": false,
			"paths": [WILDLIFE + "sm_env_animal_bird.glb"], "behaviour": ANIMAL_BEHAVIOUR,
			"density": {Zone.COUNTRYSIDE: 0.24, Zone.VILLAGE: 0.22, Zone.FOREST: 0.09}, "spacing": 18.0,
			"lateral": Vector2(7.5, 18.0), "radius": 0.15, "clearance": 7.2, "max_slope": 0.6,
			"min_same": 7.0}),
		_rule({"id": &"ground_plant", "group": "ForestDressing", "solid": false, "sides": [],
			"paths": [FOREST + "sm_env_forest_bush_round.glb", FOREST + "sm_env_forest_fern.glb",
				FOREST + "sm_env_forest_grass_clump.glb", FOREST + "sm_env_forest_wildflower.glb",
				FOREST + "sm_env_forest_mushroom.glb", FOREST + "sm_env_forest_fallen_log.glb",
				FOREST + "sm_env_forest_rock.glb", FOREST + "sm_env_forest_bramble_thicket.glb",
				FOREST + "sm_env_forest_tall_fern_cluster.glb", FOREST + "sm_env_forest_mossy_stump.glb",
				FOREST + "sm_env_forest_mossy_rock_cluster.glb", FOREST + "sm_env_forest_deadfall_branch.glb",
				FOREST + "sm_env_forest_tall_grass_clump.glb"],
			"density": {Zone.FOREST: 0.85, Zone.COUNTRYSIDE: 0.65, Zone.VILLAGE: 0.4}, "spacing": 0.9,
			"lateral": Vector2(6.7, 31.0), "radius": 0.35, "clearance": 6.3, "max_slope": 1.0,
			"scale": Vector2(0.65, 1.2)}),
	]


func _rule(fields: Dictionary) -> Dictionary:
	var rule: Dictionary = {
		"group": "RoadsideDressing", "density": {}, "spacing": 10.0, "attempts": 1,
		"sides": [-1.0, 1.0], "lateral": Vector2(9.0, 12.0), "radius": 0.5, "clearance": 7.0,
		"max_slope": 0.35, "facing": Facing.RANDOM, "scale": Vector2.ONE, "solid": true,
		"tilt": false, "min_same": 0.0,
	}
	rule.merge(fields, true)
	return rule


## Runs everything, in priority order. `segments` must already sit on the
## finished terrain; `houses` are DeliveryHouse nodes whose yards were laid
## out by route.gd and get validated here.
func dress(segments: Array, houses: Array, clear_zones: Array[Vector3]) -> void:
	_houses = houses
	_clear_zones = clear_zones
	# Yards first: their pieces live inside their own house's cleared zone,
	# so they skip that check -- then the house claims its footprint.
	for house: Node3D in houses:
		_settle_yard(house)
	for house: Node3D in houses:
		_occupy(_route.to_local(house.global_position), 5.0)
	# Signs claim their corner before any guardrail: a warning matters more
	# than one more metre of rail, and real rails have a gap at the post too.
	for index: int in range(segments.size()):
		_dress_signs(segments[index])
	for index: int in range(segments.size()):
		_dress_barriers(segments[index])
	_dress_crossings(segments)
	for rule_index: int in range(_rules.size()):
		for index: int in range(segments.size()):
			_apply_rule(segments[index], index, rule_index)


## The zone at a point on the road, `distance` metres from the start.
func zone_at(route_point: Vector3, distance: float) -> int:
	for house: Node3D in _houses:
		var h: Vector3 = _route.to_local(house.global_position)
		if Vector2(h.x - route_point.x, h.z - route_point.z).length() < VILLAGE_RADIUS:
			return Zone.VILLAGE
	if _noise.get_noise_1d(distance) > COUNTRYSIDE_THRESHOLD:
		return Zone.COUNTRYSIDE
	return Zone.FOREST


# --- Explicit features ------------------------------------------------------

func _dress_signs(segment: RouteSegment) -> void:
	var sign_file: String = HAZARD_SIGNS.get(segment.get_script().get_global_name(), "")
	if sign_file != "":
		# The curve arrow is modelled bending to the driver's right; mirror it
		# for a left-hander, reading the bend off where the segment actually
		# ends rather than trusting the sign convention of turn_deg.
		var mirror: bool = segment is CurveSegment and segment.exit_offset.x < 0.0
		_place_sign(segment, SIGN_DIR + sign_file, 1.0, SIGN_LEAD, mirror, &"hazard_sign")
	if segment.has_meta(&"delivery_sign_side"):
		# Inside the segment rather than ahead of it, so it never shares a
		# corner with a hazard sign.
		_place_sign(segment, DELIVERY_SIGN, float(segment.get_meta(&"delivery_sign_side")), -minf(12.0, segment.length * 0.4), false, &"delivery_sign")


## Deer crossings on some straights (see CROSSING_*).
func _dress_crossings(segments: Array) -> void:
	var placed: int = 0
	var last_distance: float = -INF
	var fallback: Array = []  # [segment, side] for every spot that qualified but lost the draw.
	for index: int in range(CROSSING_MIN_SEGMENT, segments.size()):
		var segment: RouteSegment = segments[index]
		if not segment is StraightSegment or segment.has_meta(&"delivery_sign_side") or placed >= CROSSING_MAX:
			continue
		var distance: float = float(segment.get_meta(&"route_distance", 0.0))
		if distance - last_distance < CROSSING_MIN_GAP:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, index, &"deer_crossing"])
		var roll: float = rng.randf()
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		if zone_at(segment.transform * Vector3(0.0, 0.0, -segment.length * 0.5), distance) == Zone.VILLAGE:
			continue
		if roll > CROSSING_CHANCE:
			fallback.append([segment, side])
			continue
		_place_crossing(segment, side)
		placed += 1
		last_distance = distance
	# Every route gets at least one: a mechanic you may never meet is one
	# nobody learns. The middle candidate keeps it away from both ends.
	if placed == 0 and not fallback.is_empty():
		var pick: Array = fallback[fallback.size() / 2]
		_place_crossing(pick[0], pick[1])


## The warning sign goes up through the same gate as every other sign, then
## the crossing itself, which keeps the deer's waiting spot clear of trees.
func _place_crossing(segment: RouteSegment, side: float) -> void:
	var middle := Vector3(0.0, 0.0, -segment.length * 0.5)
	_place_sign(segment, CROSSING_SIGN, 1.0, CROSSING_SIGN_LEAD, false, &"crossing_sign")
	var crossing := WildlifeCrossing.new()
	crossing.name = "DeerCrossing"
	crossing.side = side
	crossing.position = middle
	segment.add_child(crossing)
	_occupy(segment.transform * Vector3(side * WildlifeCrossing.WAIT_LATERAL, 0.0, middle.z), 1.5)
	_count(&"deer_crossing")


func _dress_barriers(segment: RouteSegment) -> void:
	if segment is CurveSegment:
		_place_guardrails(segment)
	if segment is ConstructionZoneSegment:
		_place_roadworks(segment)


## Signs are authored facing -Z; half a turn makes them face the driver
## coming up the road (who travels toward -Z). `distance` is along the
## segment's real path (negative = into it, positive = before it), read off
## its dressing slots so a sign inside a curve follows the bend instead of
## standing where a straight road would have been. If the ideal spot is
## taken or too tight, it steps further out before giving up.
func _place_sign(segment: RouteSegment, path: String, side: float, distance: float, mirror: bool, id: StringName) -> void:
	var slot: Transform3D = Transform3D.IDENTITY
	var along: float = distance
	if distance < 0.0:
		var slots: Array[Transform3D] = segment.get_dressing_slots(2.0)
		var index: int = clampi(roundi(-distance / 2.0), 0, slots.size() - 1)
		slot = slots[index]
		along = 0.0
	var basis := Basis(Vector3.UP, PI)
	if mirror:
		basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	for lateral: float in [SIGN_LATERAL, SIGN_LATERAL + 0.9, SIGN_LATERAL + 1.9]:
		var xform: Transform3D = slot * Transform3D(basis, Vector3(side * lateral, 0.0, along))
		if _try_place(segment, "RoadsideDressing", path, xform,
				{"id": id, "radius": 0.5, "clearance": 6.8, "max_slope": 1.0, "solid": true, "tilt": true}) != null:
			return


## Along the outside of every real bend -- the side a van that takes it too
## fast leaves the road on. Authored along X with the reflector on -Z; a
## quarter turn lays it along the road, reflector toward the asphalt.
func _place_guardrails(segment: RouteSegment) -> void:
	var outer: float = -signf(segment.exit_offset.x)
	if outer == 0.0:
		return
	for slot: Transform3D in segment.get_dressing_slots(4.0):
		var xform: Transform3D = slot * Transform3D(Basis(Vector3.UP, outer * PI * 0.5), Vector3(outer * GUARDRAIL_LATERAL, 0.0, -2.0))
		_try_place(segment, "RoadsideDressing", GUARDRAIL, xform,
			{"id": &"guardrail", "radius": 0.3, "footprint": 1.8, "clearance": 6.6, "max_slope": 1.0, "solid": true, "tilt": true})


## Cones and the barrier stand right at the edge of the closed lane (that's
## the point of them); the crew's pallet and crate wait behind it.
func _place_roadworks(segment: RouteSegment) -> void:
	var slots: Array[Transform3D] = segment.get_dressing_slots(2.2)
	var edge: Dictionary = {"id": &"roadworks", "radius": 0.3, "clearance": 5.8, "max_slope": 1.0, "solid": true}
	# The barrier goes first and claims its whole 2.2 m board (feet at
	# +-0.85), so the cones -- which used to share its spot -- line up behind
	# it instead of standing inside its legs.
	if not slots.is_empty():
		var barrier: Dictionary = edge.duplicate()
		barrier["footprint"] = 1.2
		_try_place(segment, "RoadsideDressing", PROPS + "sm_env_prop_road_barrier.glb", slots[0] * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(6.4, 0.0, -1.2)), barrier)
	for index: int in range(mini(4, slots.size() - 2)):
		_try_place(segment, "RoadsideDressing", PROPS + "sm_env_prop_traffic_cone.glb", slots[index + 2] * Transform3D(Basis.IDENTITY, Vector3(6.4, 0.0, 0.0)), edge)
	var mid: float = -segment.length * 0.5
	var crew: Dictionary = {"id": &"roadworks", "radius": 0.8, "clearance": 7.0, "max_slope": 0.4, "solid": true, "tilt": true}
	_try_place(segment, "RoadsideDressing", PROPS + "sm_env_prop_pallet.glb", Transform3D(Basis(Vector3.UP, 0.2), Vector3(8.4, 0.0, mid + 1.6)), crew)
	_try_place(segment, "RoadsideDressing", PROPS + "sm_env_prop_wooden_crate.glb", Transform3D(Basis(Vector3.UP, -0.15), Vector3(8.2, 0.0, mid - 0.8)), crew)


## Yard pieces were laid out by route.gd from the house's own bounds. The
## porch ones (meta on_porch) belong to the house and ride on its porch
## deck; everything else in the lot has to pass the same checks as any
## roadside prop, or it's dropped -- which is what kept a fence off the
## asphalt when a house was dealt a tight spot.
func _settle_yard(house: Node3D) -> void:
	var yard: Node = house.get_node_or_null(^"Yard")
	if yard == null:
		return
	var pieces: Array = yard.get_children()
	# Biggest first, so a barn keeps its spot and a fence panel gives way.
	pieces.sort_custom(func(a: Node, b: Node) -> bool: return float(a.get_meta(&"footprint", 0.0)) > float(b.get_meta(&"footprint", 0.0)))
	for piece: Node3D in pieces:
		if piece.get_meta(&"on_porch", false):
			_count(&"yard")
			continue
		var p: Vector3 = _route.to_local(piece.global_position)
		var radius: float = float(piece.get_meta(&"footprint", 0.8))
		if _misfit(p, radius, 7.2, 0.45, false, &"yard", 0.0) != &"":
			piece.free()
			continue
		_settle(piece, p)
		piece.set_meta(&"rule", &"yard")
		piece.set_meta(&"reach", radius)
		piece.set_meta(&"solid", true)
		_occupy(p, radius)
		_count(&"yard")


# --- Rules ------------------------------------------------------------------

func _apply_rule(segment: RouteSegment, segment_index: int, rule_index: int) -> void:
	var rule: Dictionary = _rules[rule_index]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, segment_index, rule_index])
	var start_distance: float = float(segment.get_meta(&"route_distance", 0.0))
	var slots: Array[Transform3D] = segment.get_dressing_slots(rule.spacing)
	var sides: Array = rule.sides
	for slot_index: int in range(slots.size()):
		var slot: Transform3D = slots[slot_index]
		var road_point: Vector3 = segment.transform * slot.origin
		var zone: int = zone_at(road_point, start_distance - slot.origin.z)
		var density: float = float(rule.density.get(zone, 0.0))
		if density <= 0.0:
			continue
		var slot_sides: Array = sides if not sides.is_empty() else [-1.0 if (segment_index + slot_index) % 2 == 0 else 1.0]
		for side: float in slot_sides:
			for _attempt: int in range(rule.attempts):
				# Draw everything up front so a rejected spot never shifts the
				# sequence for the next one.
				var roll: float = rng.randf()
				var lateral: float = rng.randf_range(rule.lateral.x, rule.lateral.y)
				var along: float = rng.randf_range(-rule.spacing * 0.45, rule.spacing * 0.45)
				var yaw_jitter: float = rng.randf_range(-0.25, 0.25)
				var random_yaw: float = rng.randf() * TAU
				var scale: float = rng.randf_range(rule.scale.x, rule.scale.y)
				var pick: int = rng.randi() % rule.paths.size()
				if roll > density:
					continue
				var yaw: float = side * PI * 0.5 + yaw_jitter if rule.facing == Facing.ROAD else random_yaw
				var xform := slot * Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(side * lateral, 0.0, along))
				var fields: Dictionary = rule.duplicate()
				fields["zone"] = zone
				fields["radius"] = rule.radius * scale
				_try_place(segment, rule.group, rule.paths[pick], xform, fields)


# --- Placement --------------------------------------------------------------

## The single gate every object goes through. `xform` is in the segment's
## space. Returns the spawned node, or null when the spot fails a check.
func _try_place(segment: RouteSegment, group_name: String, path: String, xform: Transform3D, fields: Dictionary) -> Node3D:
	var p: Vector3 = segment.transform * xform.origin
	var radius: float = float(fields.get("radius", 0.5))
	var solid: bool = bool(fields.get("solid", true))
	var id: StringName = StringName(fields.get("id", &""))
	var min_same: float = float(fields.get("min_same", 0.0))
	var footprint: float = float(fields.get("footprint", radius))
	if _misfit(p, radius, float(fields.get("clearance", 7.0)), float(fields.get("max_slope", 0.35)), true, id, min_same, footprint) != &"":
		return null
	var node := _instantiate(path)
	if node == null:
		return null
	if fields.has("behaviour"):
		# Before entering the tree, so the behaviour's _ready() runs.
		node.set_script(fields.behaviour)
	node.transform = xform
	_group(segment, group_name).add_child(node)
	_settle(node, p, bool(fields.get("tilt", false)) or path.get_file() in LEAN_MODELS)
	node.set_meta(&"rule", id)
	node.set_meta(&"reach", radius)
	node.set_meta(&"footprint", footprint)
	node.set_meta(&"solid", solid)
	if fields.has("zone"):
		node.set_meta(&"zone", ZONE_NAMES[fields.zone])
	if solid:
		_occupy(p, footprint)
	if min_same > 0.0:
		if not _same_kind.has(id):
			_same_kind[id] = []
		_same_kind[id].append(Vector2(p.x, p.z))
	var rotor: Node3D = node.find_child("WindmillRotor", true, false) as Node3D
	if rotor != null:
		# Blender's rotor axis (+Y) arrives as Godot's local Z.
		rotor.create_tween().set_loops().tween_property(rotor, "rotation:z", TAU, WINDMILL_TURN_SECONDS).from(0.0)
	_count(id)
	return node


## The five checks from the class comment, in cheapest-first order. Returns
## why a spot was turned down, or &"" when it fits (and records the reason).
## `in_world` = false is for a house's own yard, which sits inside that
## house's cleared zone by definition (it still can't overlap itself).
func _misfit(p: Vector3, radius: float, clearance: float, max_slope: float, in_world: bool, id: StringName, min_same: float, footprint: float = -1.0) -> StringName:
	# `radius` is how close the object itself comes to the road; `footprint`
	# is the ground it claims from others (a guardrail is thin across the
	# road but 4 m along it).
	var claim: float = footprint if footprint >= 0.0 else radius
	var reason: StringName = &""
	var road: float = _terrain.nearest(Vector2(p.x, p.z)).x
	if road >= NO_TERRAIN_DISTANCE:
		reason = &"no_terrain"
	elif road - radius < clearance:
		reason = &"road"
	elif in_world and _in_clear_zone(p, claim):
		reason = &"clear_zone"
	elif _overlaps(p, claim):
		reason = &"occupied"
	elif min_same > 0.0 and _near_same(p, id, min_same):
		reason = &"same_kind"
	elif _slope(p, maxf(radius, 0.5)) > max_slope:
		reason = &"slope"
	if reason != &"":
		if not rejected_counts.has(id):
			rejected_counts[id] = {}
		rejected_counts[id][reason] = int(rejected_counts[id].get(reason, 0)) + 1
	return reason


func _in_clear_zone(p: Vector3, radius: float) -> bool:
	for zone: Vector3 in _clear_zones:
		if Vector2(p.x - zone.x, p.z - zone.y).length() < zone.z + radius:
			return true
	return false


func _near_same(p: Vector3, id: StringName, distance: float) -> bool:
	for other: Vector2 in _same_kind.get(id, []):
		if other.distance_to(Vector2(p.x, p.z)) < distance:
			return true
	return false


func _slope(p: Vector3, reach: float) -> float:
	var dx: float = absf(_terrain.height_at(p + Vector3(reach, 0.0, 0.0)) - _terrain.height_at(p - Vector3(reach, 0.0, 0.0)))
	var dz: float = absf(_terrain.height_at(p + Vector3(0.0, 0.0, reach)) - _terrain.height_at(p - Vector3(0.0, 0.0, reach)))
	return maxf(dx, dz) / (2.0 * reach)


func _occupy(p: Vector3, radius: float) -> void:
	var key := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(Vector3(p.x, p.z, radius))


func _overlaps(p: Vector3, radius: float) -> bool:
	var reach: int = ceili((radius + MAX_FOOTPRINT) / GRID_CELL)
	var center := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
	for dx: int in range(-reach, reach + 1):
		for dz: int in range(-reach, reach + 1):
			for other: Vector3 in _grid.get(center + Vector2i(dx, dz), []):
				if Vector2(other.x - p.x, other.y - p.z).length() < other.z + radius:
					return true
	return false


## Puts `node` (already posed and parented) down at route-space `p`: leans it
## with the slope if asked, then lowers it until every contact point is at or
## under the terrain right below it, plus a small sink. Placing by the centre
## alone is what left a tree's downhill roots or a log's far end in the air.
func _settle(node: Node3D, p: Vector3, lean: bool = false) -> void:
	node.global_position = _route.to_global(p)
	var contacts: PackedVector3Array = contact_points(node)
	if lean:
		_lean_with_ground(node, p, contacts)
	var basis: Basis = _route.global_basis.inverse() * node.global_basis
	var y: float = INF
	var spread: float = 0.0
	for contact: Vector3 in contacts:
		var offset: Vector3 = basis * contact
		y = minf(y, _terrain.height_at(p + Vector3(offset.x, 0.0, offset.z)) - offset.y)
		spread = maxf(spread, Vector2(offset.x, offset.z).length())
	if y == INF:
		y = _terrain.height_at(p)
	p.y = y - clampf(spread * SINK_RATIO, SINK_RANGE.x, SINK_RANGE.y)
	node.global_position = _route.to_global(p)


## Tilts `node` to the ground plane across its own length and width: a 4 m
## log reads the slope between its two ends, not over the metre at its middle.
func _lean_with_ground(node: Node3D, p: Vector3, contacts: PackedVector3Array) -> void:
	var scale: Vector3 = node.basis.get_scale()
	var reach := Vector2(0.5, 0.5)
	for contact: Vector3 in contacts:
		reach = reach.max(Vector2(absf(contact.x) * scale.x, absf(contact.z) * scale.z))
	var right: Vector3 = node.global_basis.x.normalized()
	var forward: Vector3 = node.global_basis.z.normalized()
	var rise_x: float = _terrain.height_at(p + right * reach.x) - _terrain.height_at(p - right * reach.x)
	var rise_z: float = _terrain.height_at(p + forward * reach.y) - _terrain.height_at(p - forward * reach.y)
	node.rotate_object_local(Vector3.FORWARD, -atan(rise_x / (2.0 * reach.x)))
	node.rotate_object_local(Vector3.RIGHT, -atan(rise_z / (2.0 * reach.y)))


func _group(segment: Node3D, group_name: String) -> Node3D:
	var group: Node3D = segment.get_node_or_null(NodePath(group_name)) as Node3D
	if group == null:
		group = Node3D.new()
		group.name = group_name
		segment.add_child(group)
	return group


func _instantiate(path: String) -> Node3D:
	if not _packed.has(path):
		_packed[path] = load(path) as PackedScene
	var packed: PackedScene = _packed[path]
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	LowpolyMaterials.apply(node)
	return node


func _count(id: StringName) -> void:
	placed_counts[id] = int(placed_counts.get(id, 0)) + 1


## How far a model's visible base sits above (or below) its own origin, in
## the node's unscaled local space. Most props are exported with the base at
## y=0, but some (ferns, fallen logs, round bushes) are not, and would float
## or sink if placed by their origin.
static func base_offset(node: Node3D) -> float:
	var lowest: float = _lowest_mesh_y(node, node)
	return lowest if lowest != INF else 0.0


## How far the highest of `node`'s feet sits above the terrain right under it
## (negative = every foot is in the ground). For tests: after _settle() this
## is -sink, never above zero.
static func ground_gap(node: Node3D, route: Node3D, terrain: Node) -> float:
	var basis: Basis = route.global_basis.inverse() * node.global_basis
	var origin: Vector3 = route.to_local(node.global_position)
	var gap: float = -INF
	for contact: Vector3 in contact_points(node):
		var foot: Vector3 = origin + basis * contact
		gap = maxf(gap, foot.y - float(terrain.call(&"height_at", foot)))
	return gap


## The model's feet in its own (unscaled) space: see CONTACT_BAND. Cached per
## scene file, since every oak has the same roots.
static func contact_points(node: Node3D) -> PackedVector3Array:
	var key: String = node.scene_file_path
	if key != "" and _contact_cache.has(key):
		return _contact_cache[key]
	var vertices := PackedVector3Array()
	_collect_vertices(node, node, vertices)
	var contacts := PackedVector3Array()
	if vertices.is_empty():
		contacts.append(Vector3.ZERO)
	else:
		var lowest: Vector3 = vertices[0]
		for v: Vector3 in vertices:
			if v.y < lowest.y:
				lowest = v
		contacts.append(lowest)
		var outermost: Array = []
		outermost.resize(CONTACT_SECTORS)
		for v: Vector3 in vertices:
			if v.y > lowest.y + CONTACT_BAND:
				continue
			var sector: int = posmod(floori(atan2(v.z, v.x) / TAU * CONTACT_SECTORS), CONTACT_SECTORS)
			var best: Variant = outermost[sector]
			if best == null or Vector2(v.x, v.z).length_squared() > Vector2(best.x, best.z).length_squared():
				outermost[sector] = v
		for v: Variant in outermost:
			if v != null:
				contacts.append(v)
	if key != "":
		_contact_cache[key] = contacts
	return contacts


static func _collect_vertices(root_node: Node3D, node: Node, into: PackedVector3Array) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			var xform: Transform3D = root_node.global_transform.affine_inverse() * (child as Node3D).global_transform
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					into.append(xform * v)
		if child is Node3D:
			_collect_vertices(root_node, child, into)


static func _lowest_mesh_y(root_node: Node3D, node: Node) -> float:
	var lowest: float = INF
	for child: Node in node.get_children():
		if child is VisualInstance3D:
			var xform: Transform3D = root_node.global_transform.affine_inverse() * (child as Node3D).global_transform
			lowest = minf(lowest, (xform * (child as VisualInstance3D).get_aabb()).position.y)
		if child is Node3D:
			lowest = minf(lowest, _lowest_mesh_y(root_node, child))
	return lowest
