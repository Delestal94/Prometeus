class_name EdgeEvents
extends RefCounted
## The animals and events of the road, planned per street of the graph instead of
## per generated segment (expansion D-0315). Only the Campo's streets get them: a
## loose surface (gravel, dirt) inside the `campo` zone.
##
## Pure data: plan() answers, from the graph and the session seed alone, the
## events of one street, each with its distance along the curve, so every peer
## (and the same seed on another day) deals the same ones. Nothing here repeats
## the rules of the route's own events: the chances, the seeded streams and the
## plans are RouteWildlife's, CargoAnimalPlan's and LowVisibilityPlan's. What
## changes is the unit they are dealt over: a piece (deer, flock, dog), a leg of
## the trip (the animals that go for the cargo; here, the Campo's streets in
## order) or a stretch of road (the mud on the glass; here, one draw per
## LOW_VISIBILITY_SPACING meters).
##
## An event: { kind, edge, along (m from the street's start), position (Vector2 on
## the ground), yaw (for a Basis(UP, yaw), facing along the street), side (-1/1),
## seed, animal, duration, length }. `animal`, `duration` and `length` are only
## filled by the kinds that use them. EdgeCellContent hands each event to the cell
## it lies in; the nodes of the deer, the flock and the dog are built from it there,
## and the other two kinds are read by the nodes that already run them
## (cargo_animals.gd, low_visibility_event.gd) once the company vehicle drives
## the Campo (D-0315.b).

const DEER: StringName = &"deer_crossing"
const FLOCK: StringName = &"flock_crossing"
const DOG: StringName = &"chasing_dog"
const CARGO_ANIMAL: StringName = &"cargo_animal"
const LOW_VISIBILITY: StringName = &"low_visibility"
const KINDS: Array[StringName] = [DEER, FLOCK, DOG, CARGO_ANIMAL, LOW_VISIBILITY]

## The zone whose streets carry them.
const FIELD_AREA: StringName = &"campo"
## The farm lanes, where a dog waits by a gate (the Campo has no village).
const DOG_STREET: StringName = &"chacras"
## A piece worth an event: a straight at least this long, and never the first
## one of a street (the junction, the gate).
const MIN_PIECE: float = 20.0
const FIRST_EVENT_PIECE: int = 1
## At most this many of each kind per street.
const MAX_PER_EDGE: int = 1
## The animals that go for the cargo meet the driver in the middle of a street:
## between these fractions of its length, by where in the leg's time window the
## plan puts them.
const CARGO_FROM: float = 0.25
const CARGO_TO: float = 0.75
## The mud on the glass: one draw per this many meters (LowVisibilityPlan.SPACING
## seconds at about 15 m/s), none at the very start or end of a street, and it
## lasts its duration at this speed (a street cuts it short).
const LOW_VISIBILITY_SPACING: float = 75.0
const LOW_VISIBILITY_SPEED: float = 12.0
const LOW_VISIBILITY_MARGIN: float = 30.0


## True for the streets that carry events: the Campo's loose-surface ones.
static func is_field(graph: RoadGraph, edge: RoadEdge) -> bool:
	return edge != null and edge.area == FIELD_AREA and graph.is_loose(edge)


## The ids of those streets, in the graph's order (the order of the cargo animals' legs).
static func field_edges(graph: RoadGraph) -> Array[StringName]:
	var found: Array[StringName] = []
	for edge: RoadEdge in graph.edges:
		if is_field(graph, edge):
			found.append(edge.id)
	return found


## The events of one street, ordered by `along`. Empty for a street outside the
## Campo or that is not in the graph.
static func plan(graph: RoadGraph, edge_id: StringName, world_seed: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var edge: RoadEdge = graph.edge_by_id(edge_id)
	if not is_field(graph, edge):
		return events
	var pieces: Array[Dictionary] = EdgePieces.plan(graph, edge_id)
	var taken: Dictionary = {}
	_add(events, _deer(graph, edge_id, pieces, world_seed, taken))
	_add(events, _flock(graph, edge_id, pieces, world_seed, taken))
	if edge.street == DOG_STREET:
		_add(events, _dog(graph, edge_id, pieces, world_seed, taken))
	_add(events, _cargo_animal(graph, edge_id, world_seed))
	_add(events, _low_visibility(graph, edge_id, world_seed))
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.along) < float(b.along))
	return events


## Every Campo street's events: { edge id: Array[Dictionary] } (streets with none are left out).
static func plan_all(graph: RoadGraph, world_seed: int) -> Dictionary:
	var all: Dictionary = {}
	for edge_id: StringName in field_edges(graph):
		var events: Array[Dictionary] = plan(graph, edge_id, world_seed)
		if not events.is_empty():
			all[edge_id] = events
	return all


## "kind@along" for every event, comma separated, to compare two plans in a test.
static func signature(events: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for event: Dictionary in events:
		parts.append("%s@%d" % [event.kind, roundi(float(event.along))])
	return ",".join(parts)


## A deer on a straight, maybe (RouteWildlife.CROSSING_CHANCE), at the middle of it.
static func _deer(graph: RoadGraph, edge_id: StringName, pieces: Array[Dictionary], world_seed: int,
		taken: Dictionary) -> Dictionary:
	for index: int in range(FIRST_EVENT_PIECE, pieces.size()):
		if not _fits(pieces[index], taken, index):
			continue
		var rng := _rng(world_seed, edge_id, index, DEER)
		var roll: float = rng.randf()
		var side: float = _side(rng)
		if roll > RouteWildlife.CROSSING_CHANCE:
			continue
		taken[index] = true
		return _event(graph, edge_id, DEER, _middle(pieces[index]), side)
	return {}


## One flock of sheep, maybe (RouteWildlife.FLOCK_CHANCE), on a straight no deer took.
static func _flock(graph: RoadGraph, edge_id: StringName, pieces: Array[Dictionary], world_seed: int,
		taken: Dictionary) -> Dictionary:
	for index: int in range(FIRST_EVENT_PIECE, pieces.size()):
		if not _fits(pieces[index], taken, index):
			continue
		var rng := _rng(world_seed, edge_id, index, FLOCK)
		var roll: float = rng.randf()
		var side: float = _side(rng)
		if roll > RouteWildlife.FLOCK_CHANCE:
			continue
		taken[index] = true
		var event: Dictionary = _event(graph, edge_id, FLOCK, _middle(pieces[index]), side)
		event.seed = hash([world_seed, edge_id, index, &"flock_members"])
		return event
	return {}


## A dog by the lane, maybe (RouteWildlife.DOG_CHANCE), on a straight or a curve.
static func _dog(graph: RoadGraph, edge_id: StringName, pieces: Array[Dictionary], world_seed: int,
		taken: Dictionary) -> Dictionary:
	for index: int in range(FIRST_EVENT_PIECE, pieces.size()):
		var piece: Dictionary = pieces[index]
		if taken.has(index) or not (piece.kind == &"straight" or piece.kind == &"curve"):
			continue
		var rng := _rng(world_seed, edge_id, index, DOG)
		var roll: float = rng.randf()
		var side: float = _side(rng)
		if roll > RouteWildlife.DOG_CHANCE:
			continue
		taken[index] = true
		return _event(graph, edge_id, DOG, float(piece.start), side)
	return {}


## The animal that goes for the cargo (CargoAnimalPlan.for_leg): the Campo's
## streets are the legs, in the graph's order (the first is quiet, none follows another).
static func _cargo_animal(graph: RoadGraph, edge_id: StringName, world_seed: int) -> Dictionary:
	var leg: int = field_edges(graph).find(edge_id)
	var planned: Dictionary = CargoAnimalPlan.for_leg(world_seed, leg)
	if planned.is_empty():
		return {}
	var window: float = CargoAnimalPlan.MAX_MOVING_SECONDS - CargoAnimalPlan.MIN_MOVING_SECONDS
	var share: float = (float(planned.moving_seconds) - CargoAnimalPlan.MIN_MOVING_SECONDS) / window
	var along: float = graph.edge_length(edge_id) * lerpf(CARGO_FROM, CARGO_TO, share)
	var event: Dictionary = _event(graph, edge_id, CARGO_ANIMAL, along, 1.0)
	event.animal = planned.kind
	return event


## The mud on the glass (LowVisibilityPlan.draw): the first draw that hits, one per street at most.
static func _low_visibility(graph: RoadGraph, edge_id: StringName, world_seed: int) -> Dictionary:
	var total: float = graph.edge_length(edge_id)
	var index: int = 1
	var at: float = LOW_VISIBILITY_SPACING
	while at <= total - LOW_VISIBILITY_MARGIN:
		var drawn: Dictionary = LowVisibilityPlan.draw(world_seed, hash(edge_id), index)
		if bool(drawn.hit):
			var event: Dictionary = _event(graph, edge_id, LOW_VISIBILITY, at, 1.0)
			event.duration = float(drawn.duration)
			event.length = minf(float(drawn.duration) * LOW_VISIBILITY_SPEED, total - at)
			return event
		index += 1
		at += LOW_VISIBILITY_SPACING
	return {}


static func _fits(piece: Dictionary, taken: Dictionary, index: int) -> bool:
	return piece.kind == &"straight" and float(piece.length) >= MIN_PIECE and not taken.has(index)


static func _middle(piece: Dictionary) -> float:
	return float(piece.start) + float(piece.length) * 0.5


static func _rng(world_seed: int, edge_id: StringName, index: int, key: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, edge_id, index, key])
	return rng


static func _side(rng: RandomNumberGenerator) -> float:
	return -1.0 if rng.randf() < 0.5 else 1.0


static func _event(graph: RoadGraph, edge_id: StringName, kind: StringName, along: float, side: float) -> Dictionary:
	var facing: Vector2 = graph.tangent_at(edge_id, along)
	return {
		"kind": kind, "edge": edge_id, "along": along, "position": graph.point_at(edge_id, along),
		"yaw": atan2(-facing.x, -facing.y), "side": side, "seed": 0, "animal": &"", "duration": 0.0,
		"length": 0.0,
	}


static func _add(events: Array[Dictionary], event: Dictionary) -> void:
	if not event.is_empty():
		events.append(event)
