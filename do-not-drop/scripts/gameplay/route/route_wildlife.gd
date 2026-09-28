class_name RouteWildlife
extends RefCounted
## What crosses or lies on the road: deer crossings with their warning sign,
## a flock of birds in open country, a dog chasing the truck through a
## village, and -- only when it's raining -- branches and logs fallen onto
## the asphalt.

const CROSSING_SIGN: String = RouteSignage.SIGN_DIR + "sm_env_sign_animal_crossing.glb"
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
## Roadside hazards besides the deer (tareas de Nacho N-106), each drawn from
## its own seeded stream, so adding one never moves anything else:
## a flock of sheep in open country, a dog that chases the truck through a
## village, and -- only when it's raining -- branches and logs fallen onto
## one lane after the storm.
const FLOCK_CHANCE: float = 0.5
const FLOCK_MIN_DISTANCE: float = 200.0
const DOG_CHANCE: float = 0.7
const DEBRIS_MAX: int = 3
const DEBRIS_CHANCE: float = 0.45
const DEBRIS_MIN_DISTANCE: float = 150.0
const DEBRIS_MIN_GAP: float = 150.0
const DEBRIS_MODELS: Array[String] = [RouteDresser.FOREST + "sm_env_forest_fallen_log.glb",
		RouteDresser.FOREST + "sm_env_forest_deadfall_branch.glb"]
## Fallen across this much of the road from its own edge at most: the other
## lane always stays clear to drive round it.
const DEBRIS_REACH: float = 5.0
## The asphalt's half width (12 m road).
const ROAD_HALF_WIDTH_FOR_DEBRIS: float = 6.0


var _dresser: RouteDresser
var _placement: RoutePlacement
var _route: Node3D
var _terrain: Node
var _seed: int
var _signage: RouteSignage


func _init(dresser: RouteDresser, placement: RoutePlacement, signage: RouteSignage, route: Node3D, terrain: Node,
		seed_value: int) -> void:
	_dresser = dresser
	_placement = placement
	_signage = signage
	_route = route
	_terrain = terrain
	_seed = seed_value


## Deer crossings on some straights (see CROSSING_*).
func dress_crossings(segments: Array) -> void:
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
		if _dresser.zone_at(segment.transform * Vector3(0.0, 0.0, -segment.length * 0.5),
				distance) == RouteDresser.Zone.VILLAGE:
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
	_signage.place_sign(segment, CROSSING_SIGN, 1.0, CROSSING_SIGN_LEAD, false, &"crossing_sign")
	var crossing := WildlifeCrossing.new()
	crossing.name = "DeerCrossing"
	crossing.side = side
	crossing.position = middle
	segment.add_child(crossing)
	_placement.occupy(segment.transform * Vector3(side * WildlifeCrossing.WAIT_LATERAL, 0.0, middle.z), 1.5)
	_placement.count(&"deer_crossing")


## One flock of sheep, maybe, on a straight in open country: never on a
## segment that already has a deer crossing or a delivery warning.
func dress_flock(segments: Array) -> void:
	for index: int in range(CROSSING_MIN_SEGMENT, segments.size()):
		var segment: RouteSegment = segments[index]
		var taken: bool = segment.has_meta(&"delivery_sign_side") or segment.has_node(^"DeerCrossing")
		if not segment is StraightSegment or taken:
			continue
		var distance: float = float(segment.get_meta(&"route_distance", 0.0))
		var middle := Vector3(0.0, 0.0, -segment.length * 0.5)
		if distance < FLOCK_MIN_DISTANCE or _dresser.zone_at(segment.transform * middle,
				distance) != RouteDresser.Zone.COUNTRYSIDE:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, index, &"flock"])
		var roll: float = rng.randf()
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		if roll > FLOCK_CHANCE:
			continue
		_signage.place_sign(segment, CROSSING_SIGN, 1.0, CROSSING_SIGN_LEAD, false, &"crossing_sign")
		var flock := FlockCrossing.new()
		flock.name = "FlockCrossing"
		flock.side = side
		flock.flock_seed = hash([_seed, index, &"flock_members"])
		flock.position = middle
		segment.add_child(flock)
		_placement.occupy(segment.transform * Vector3(side * 11.0, 0.0, middle.z), 7.0)
		_placement.count(&"flock_crossing")
		return


## One dog, maybe, by the road in a village.
func dress_dog(segments: Array) -> void:
	for index: int in range(CROSSING_MIN_SEGMENT, segments.size()):
		var segment: RouteSegment = segments[index]
		if not (segment is StraightSegment or segment is CurveSegment):
			continue
		var distance: float = float(segment.get_meta(&"route_distance", 0.0))
		if _dresser.zone_at(segment.transform * Vector3.ZERO, distance) != RouteDresser.Zone.VILLAGE:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, index, &"dog"])
		var roll: float = rng.randf()
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var home: Vector3 = segment.transform * Vector3(side * ChasingDog.HOME_LATERAL, 0.0, 0.0)
		if roll > DOG_CHANCE or _placement.overlaps(home, 1.0) or _placement.in_clear_zone(home, 1.0):
			continue
		var dog := ChasingDog.new()
		dog.name = "ChasingDog"
		dog.side = side
		segment.add_child(dog)
		_placement.occupy(home, 1.0)
		_placement.count(&"chasing_dog")
		return


## After the storm: a fallen log or branch lying across one lane of a few
## forest straights, solid, so the driver has to steer round it. It reaches
## in from its own road edge DEBRIS_REACH metres at most, leaving the other
## lane clear.
func dress_storm_debris(segments: Array) -> void:
	var placed: int = 0
	var last_distance: float = -INF
	for index: int in range(segments.size()):
		var segment: RouteSegment = segments[index]
		if placed >= DEBRIS_MAX:
			return
		if not segment is StraightSegment or segment.has_meta(&"delivery_sign_side"):
			continue
		var distance: float = float(segment.get_meta(&"route_distance", 0.0))
		var middle := Vector3(0.0, 0.0, -segment.length * 0.5)
		var too_soon: bool = distance < DEBRIS_MIN_DISTANCE or distance - last_distance < DEBRIS_MIN_GAP
		if too_soon or _dresser.zone_at(segment.transform * middle, distance) != RouteDresser.Zone.FOREST:
			continue
		if segment.has_node(^"DeerCrossing") or segment.has_node(^"FlockCrossing"):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, index, &"storm_debris"])
		var roll: float = rng.randf()
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var model: String = DEBRIS_MODELS[rng.randi() % DEBRIS_MODELS.size()]
		var angle: float = rng.randf_range(-0.35, 0.35)
		var along: float = rng.randf_range(-0.3, 0.3) * segment.length
		if roll > DEBRIS_CHANCE:
			continue
		if _place_debris(segment, model, side, middle + Vector3(0.0, 0.0, along), angle):
			placed += 1
			last_distance = distance


func _place_debris(segment: RouteSegment, path: String, side: float, at: Vector3, angle: float) -> bool:
	var piece: Node3D = _placement.instantiate(path)
	if piece == null:
		return false
	# Lying across the road (its long axis along X), turned a little.
	var bounds: AABB = RoutePlacement.mesh_bounds(piece)
	var length: float = bounds.size.x if bounds.size.x >= bounds.size.z else bounds.size.z
	var yaw: float = angle if bounds.size.x >= bounds.size.z else angle + PI * 0.5
	var reach: float = minf(length, DEBRIS_REACH)
	var lateral: float = side * (ROAD_HALF_WIDTH_FOR_DEBRIS - reach * 0.5)
	var holder := StaticBody3D.new()
	holder.name = "StormDebris"
	holder.collision_layer = 1
	holder.collision_mask = 0
	# Kept out of the geometry merge: it has a collider to go with it.
	holder.set_meta(&"animated", true)
	holder.set_meta(&"debris", true)
	holder.position = at + Vector3(lateral, 0.0, 0.0)
	holder.rotation.y = yaw
	segment.add_child(holder)
	holder.add_child(piece)
	var ground_y: float = _terrain.height_at(segment.transform * holder.position) - segment.transform.origin.y
	holder.position.y = ground_y - RoutePlacement.base_offset(piece)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(bounds.size.x, 0.2), maxf(bounds.size.y, 0.3), maxf(bounds.size.z, 0.2))
	shape.shape = box
	shape.position = bounds.get_center()
	holder.add_child(shape)
	_placement.count(&"storm_debris")
	return true
