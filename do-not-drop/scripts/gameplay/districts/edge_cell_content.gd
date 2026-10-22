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

var graph: RoadGraph
var cell_size: float
## What Centro holds besides its streets; null: the cells hold the streets only.
var decor: CentroDecor

## { Vector2i cell: Array[{ edge: StringName, piece: int }] }, built once.
var _by_cell: Dictionary = {}
var _plans: Dictionary = {}


func _init(road_graph: RoadGraph, size: float, centro_decor: CentroDecor = null) -> void:
	graph = road_graph
	cell_size = size
	decor = centro_decor
	_index()


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
