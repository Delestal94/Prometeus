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
## then the rules run in priority order: landmarks, parked cars (and the
## competition's van), village furniture, farm props, the odd tractor, trees,
## and finally ground plants, which fill whatever is left.
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

const PROPS: String = "res://assets/models/environment/props/"
const FOREST: String = "res://assets/models/environment/forest/"
const WILDLIFE: String = "res://assets/models/environment/wildlife/"
const ANIMAL_BEHAVIOUR: Script = preload("res://scripts/presentation/wildlife_animal.gd")


var _route: Node3D
var _terrain: Node
var _seed: int
## Set by route.gd before dress(): whether this session's weather is rain,
## which is when storm debris lies on the road.
var raining: bool = false
var _noise := FastNoiseLite.new()
var _houses: Array = []
var _rules: Array[Dictionary] = []
## The placement gate, shared by the rules and every feature builder.
var _placement: RoutePlacement
var _signage: RouteSignage
var _wildlife: RouteWildlife
var _power_lines: RoutePowerLines

## Every town-limit sign put up, entries and exits, in road order (N-601).
var town_signs: Array[Node3D]:
	get:
		return _signage.town_signs
## Every roadside story put up (N-602), in road order.
var roadside_stories: Array[Node3D]:
	get:
		return _signage.roadside_stories
var power_poles: Array[Vector3]:
	get:
		return _power_lines.power_poles
## How many things each rule/feature actually placed, and why the rest were
## turned down ({id: {reason: count}}), for tests and tuning.
var placed_counts: Dictionary:
	get:
		return _placement.placed_counts
var rejected_counts: Dictionary:
	get:
		return _placement.rejected_counts


func _init(route: Node3D, terrain: Node, seed_value: int) -> void:
	_route = route
	_terrain = terrain
	_seed = seed_value
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = COUNTRYSIDE_NOISE_FREQUENCY
	_rules = _build_rules()
	_placement = RoutePlacement.new(route, terrain)
	_signage = RouteSignage.new(self, _placement, route, terrain, seed_value)
	_wildlife = RouteWildlife.new(self, _placement, _signage, route, terrain, seed_value)
	_power_lines = RoutePowerLines.new(self, _placement, route, terrain, seed_value)


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
##   contact_shadow  opacity of a soft dark patch under it (N-308.2)
##   order      when it runs (default: its index; see _rule_order())
##   yaw_offset extra turn (radians) for a model authored along another axis
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
				"res://assets/models/vehicles/sm_vehicle_parked_pickup.glb",
				"res://assets/models/vehicles/sm_vehicle_parked_sedan_refined.glb"],
			"density": {Zone.VILLAGE: 0.55, Zone.COUNTRYSIDE: 0.2, Zone.FOREST: 0.06}, "spacing": 40.0,
			"lateral": Vector2(12.0, 14.5), "radius": 2.4, "clearance": 9.5, "max_slope": 0.18,
			"facing": Facing.ROAD, "tilt": true, "min_same": 22.0, "contact_shadow": 0.55}),
		_rule({"id": &"village_furniture",
			"paths": [PROPS + "sm_env_prop_street_lamp_refined.glb", PROPS + "sm_env_prop_bench.glb",
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
		# The depot's other vehicles out on the road (N-306). Appended, so no
		# older rule's RNG stream moves; "order" slots them in before the trees.
		# A tractor now and then out in the fields, well back from the asphalt.
		_rule({"id": &"tractor", "order": 5.5,
			"paths": ["res://assets/models/vehicles/sm_vehicle_tractor.glb"],
			"density": {Zone.COUNTRYSIDE: 0.3}, "spacing": 70.0,
			"lateral": Vector2(17.0, 28.0), "radius": 2.2, "clearance": 15.0, "max_slope": 0.15,
			"tilt": true, "min_same": 320.0, "contact_shadow": 0.5}),
		# The competition's van, parked in a village like the other cars.
		_rule({"id": &"competitor_van", "order": 1.5,
			"paths": ["res://assets/models/vehicles/sm_vehicle_competitor_van.glb"],
			"density": {Zone.VILLAGE: 0.2}, "spacing": 60.0,
			"lateral": Vector2(12.4, 14.5), "radius": 2.7, "clearance": 9.5, "max_slope": 0.15,
			# Modelled lengthwise along Z, where the parked cars run along X.
			"facing": Facing.ROAD, "yaw_offset": PI * 0.5, "tilt": true, "min_same": 400.0,
			"contact_shadow": 0.55}),
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
func dress(segments: Array, houses: Array, clear_zones: Array[Vector3], sight_zones: Array[Vector3] = []) -> void:
	_houses = houses
	_placement.clear_zones = clear_zones
	_placement.sight_zones = sight_zones
	# Yards first: their pieces live inside their own house's cleared zone,
	# so they skip that check -- then the house claims its footprint.
	for house: Node3D in houses:
		_signage.settle_yard(house)
	for house: Node3D in houses:
		_placement.occupy(_route.to_local(house.global_position), 5.0)
	# Signs claim their corner before any guardrail: a warning matters more
	# than one more metre of rail, and real rails have a gap at the post too.
	for index: int in range(segments.size()):
		_signage.dress_signs(segments[index])
	_signage.dress_town_signs(segments)
	_signage.dress_roadside_stories(segments)
	for index: int in range(segments.size()):
		_signage.dress_barriers(segments[index])
	_wildlife.dress_crossings(segments)
	_wildlife.dress_flock(segments)
	_wildlife.dress_dog(segments)
	if raining:
		_wildlife.dress_storm_debris(segments)
	_power_lines.dress(segments)
	for rule_index: int in _rule_order():
		for index: int in range(segments.size()):
			_apply_rule(segments[index], index, rule_index)


## Rules run by "order" (their index unless they say otherwise), so a rule
## added at the end of the table can still claim its ground before the trees
## while every older rule keeps its index -- and with it its RNG stream
## (_apply_rule seeds by index): adding the tractor didn't move a single tree
## that it doesn't stand on.
func _rule_order() -> Array[int]:
	var order: Array[int] = []
	for rule_index: int in range(_rules.size()):
		order.append(rule_index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var oa: float = float(_rules[a].get("order", a))
		var ob: float = float(_rules[b].get("order", b))
		return oa < ob if oa != ob else a < b)
	return order


## The zone at a point on the road, `distance` metres from the start.
func zone_at(route_point: Vector3, distance: float) -> int:
	for house: Node3D in _houses:
		var h: Vector3 = _route.to_local(house.global_position)
		if Vector2(h.x - route_point.x, h.z - route_point.z).length() < VILLAGE_RADIUS:
			return Zone.VILLAGE
	if _noise.get_noise_1d(distance) > COUNTRYSIDE_THRESHOLD:
		return Zone.COUNTRYSIDE
	return Zone.FOREST


## Storm debris on its own (tests): dress() lays it only when it's raining.
func dress_storm_debris(segments: Array) -> void:
	_wildlife.dress_storm_debris(segments)


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
		var alternate: float = -1.0 if (segment_index + slot_index) % 2 == 0 else 1.0
		var slot_sides: Array = sides if not sides.is_empty() else [alternate]
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
				yaw += float(rule.get("yaw_offset", 0.0))
				var turn := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
				var xform := slot * Transform3D(turn, Vector3(side * lateral, 0.0, along))
				var fields: Dictionary = rule.duplicate()
				fields["zone"] = zone
				fields["radius"] = rule.radius * scale
				_placement.try_place(segment, rule.group, rule.paths[pick], xform, fields)
