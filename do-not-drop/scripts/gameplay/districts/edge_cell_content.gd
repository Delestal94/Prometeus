class_name EdgeCellContent
extends RefCounted
## What each world cell holds of the streets (expansion D-0304.1): the pieces
## EdgePieces lays along every RoadEdge, handed to the cell their start point lies in.
##
## Every piece is a RouteSegment that builds its own roadway, shoulders and
## markings, so a cell's street is those pieces placed in world space (a cell
## node sits at the origin). index() is pure data; build_cell() makes the nodes.
##
## With a CentroDecor (D-0314) the cell also holds what the gray Barrio Centro has
## around its streets: sidewalks, houses, traffic lights, lamps and benches, in a
## `Centro` child after the pieces.

## The Campo's animals and events (EdgeEvents, D-0315) are dealt the same way: each
## goes to the cell its point lies in (events_in()). build_cell() builds the nodes of
## the deer, the flock and the dog only with `spawn_events` on (off by default: they
## need a vehicle to run for, which the Campo's company trips bring with D-0315.b).

## What each event with a node claims of the ground: Vector2(lateral from the street, radius).
const EVENT_CLAIMS: Dictionary = {
	EdgeEvents.DEER: Vector2(WildlifeCrossing.WAIT_LATERAL, 1.5),
	EdgeEvents.FLOCK: Vector2(11.0, 7.0),
	EdgeEvents.DOG: Vector2(ChasingDog.HOME_LATERAL, 1.0),
}

var graph: RoadGraph
var cell_size: float
var session_seed: int
## Whether build_cell() also builds the nodes of the events it holds.
var spawn_events: bool = false
## What Centro holds besides its streets; null: the cells hold the streets only.
var decor: CentroDecor

## { Vector2i cell: Array[{ edge: StringName, piece: int }] }, built once.
var _by_cell: Dictionary = {}
var _plans: Dictionary = {}
## { Vector2i cell: Array[Dictionary] } (EdgeEvents.plan entries), built once.
var _events_by_cell: Dictionary = {}


func _init(
		road_graph: RoadGraph, size: float, world_seed: int = 0, with_events: bool = false,
		centro_decor: CentroDecor = null) -> void:
	graph = road_graph
	cell_size = size
	session_seed = world_seed
	spawn_events = with_events
	decor = centro_decor
	_index()
	_index_events()


## Cells that hold at least one piece, or something of the decor.
func cells() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for cell: Vector2i in _by_cell:
		found.append(cell)
	if decor != null:
		for cell: Vector2i in decor.cells():
			if not _by_cell.has(cell):
				found.append(cell)
	return found


## How many pieces the cell holds.
func piece_count(cell: Vector2i) -> int:
	return (_by_cell.get(cell, []) as Array).size()


## The events (EdgeEvents) whose point lies in the cell, ordered by street and distance.
func events_in(cell: Vector2i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	found.assign(_events_by_cell.get(cell, []))
	return found


## Cells that hold at least one event.
func event_cells() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for cell: Vector2i in _events_by_cell:
		found.append(cell)
	return found


## The ground the deer, the flock and the dog of the cell's events wait on (D-0315.b), as the
## circles RoutePlacement.occupy() takes: Vector3(x, z, radius) in world space, the same lateral
## and radius RouteWildlife claims on the route (the deer 1.5 m at WAIT_LATERAL, the flock 7 m at
## 11 m, the dog 1 m at HOME_LATERAL). Empty for the events that have no node (cargo, mud).
func event_claims(cell: Vector2i) -> Array[Vector3]:
	var claims: Array[Vector3] = []
	for event: Dictionary in events_in(cell):
		var claim: Vector2 = EVENT_CLAIMS.get(event.kind, Vector2.ZERO)
		if claim.y <= 0.0:
			continue
		var ground: Vector2 = event.position
		var lateral: Vector3 = Basis(Vector3.UP, event.yaw) * Vector3(float(event.side) * claim.x, 0.0, 0.0)
		claims.append(Vector3(ground.x + lateral.x, ground.y + lateral.z, claim.y))
	return claims


## Marks the cell's event claims on `placement`, before whatever dresses the cell places a prop, so
## none lands where the animal waits. Only the cell's own events: a flock near the cell's edge can
## reach into the next one, so the dresser of a cell should reserve its neighbours' too. Returns
## how many circles it took. Independent of `spawn_events` (the claim is the same with no node).
func reserve_events(placement: RoutePlacement, cell: Vector2i) -> int:
	var claims: Array[Vector3] = event_claims(cell)
	for claim: Vector3 in claims:
		placement.occupy(Vector3(claim.x, 0.0, claim.y), claim.z)
	return claims.size()


## The cell a ground point (x, z in a Vector3) lies in.
func cell_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.z / cell_size))


## The cell node: `Cell_<x>_<z>` with a RouteSegment per piece of the cell and, with a decor, the
## `Centro` node of what it holds.
func build_cell(cell: Vector2i) -> Node3D:
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [cell.x, cell.y]
	for entry: Dictionary in _by_cell.get(cell, []):
		var piece: Dictionary = (_plans[entry.edge] as Array[Dictionary])[entry.piece]
		var segment: RouteSegment = EdgePieces.build_piece(piece)
		segment.name = "%s_%d" % [entry.edge, entry.piece]
		node.add_child(segment)
	if decor != null:
		var around: Node3D = decor.build_cell(cell)
		if around != null:
			node.add_child(around)
	if spawn_events:
		for event: Dictionary in events_in(cell):
			var holder: Node3D = _event_node(event)
			if holder != null:
				node.add_child(holder)
	return node


func _index() -> void:
	for edge: RoadEdge in graph.edges:
		var pieces: Array[Dictionary] = EdgePieces.plan(graph, edge.id)
		_plans[edge.id] = pieces
		for i in pieces.size():
			var ground: Vector2 = pieces[i].position
			var cell := cell_of(Vector3(ground.x, 0.0, ground.y))
			if not _by_cell.has(cell):
				_by_cell[cell] = []
			(_by_cell[cell] as Array).append({"edge": edge.id, "piece": i})


func _index_events() -> void:
	var all: Dictionary = EdgeEvents.plan_all(graph, session_seed)
	for edge_id: StringName in all:
		for event: Dictionary in all[edge_id]:
			var ground: Vector2 = event.position
			var cell := cell_of(Vector3(ground.x, 0.0, ground.y))
			if not _events_by_cell.has(cell):
				_events_by_cell[cell] = []
			(_events_by_cell[cell] as Array).append(event)


## The node of an event that has one (the deer, the flock, the dog), placed on its
## street the way a RouteSegment would carry it: at the point, facing along the street.
## The cargo animals and the mud on the glass are run by the nodes that already do.
func _event_node(event: Dictionary) -> Node3D:
	var holder: Node3D
	match event.kind:
		EdgeEvents.DEER:
			var deer := WildlifeCrossing.new()
			deer.side = event.side
			deer.with_sign = true
			holder = deer
		EdgeEvents.FLOCK:
			var flock := FlockCrossing.new()
			flock.side = event.side
			flock.flock_seed = event.seed
			flock.with_sign = true
			holder = flock
		EdgeEvents.DOG:
			var dog := ChasingDog.new()
			dog.side = event.side
			holder = dog
		_:
			return null
	holder.name = "%s_%s_%d" % [event.kind, event.edge, roundi(float(event.along))]
	var ground: Vector2 = event.position
	holder.transform = Transform3D(Basis(Vector3.UP, event.yaw), Vector3(ground.x, 0.0, ground.y))
	return holder
