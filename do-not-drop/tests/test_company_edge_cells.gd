extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_edge_cells.gd
##
## The streets inside the company map's cells (expansion D-0304.1,
## scripts/gameplay/districts/edge_cell_content.gd on data/world/road_graph.tres):
## - every piece of every street lands in exactly one cell: the one its start lies in;
## - a cell's node is named Cell_<x>_<z> and holds a RouteSegment per piece, in world space;
## - CompanyCells.use_graph() makes the streamer deliver those nodes and pins the main streets;
## - a cell with no street is an empty node.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var graph := RoadGraph.load_default()
	_expect(graph != null, "data/world/road_graph.tres loads")
	if graph == null:
		quit(1)
		return
	var cells := CompanyCells.new()
	root.add_child(cells)
	var content: EdgeCellContent = cells.use_graph(graph)
	var planned: int = 0
	for edge: RoadEdge in graph.edges:
		planned += EdgePieces.plan(graph, edge.id).size()
	var held: int = 0
	for cell: Vector2i in content.cells():
		held += content.piece_count(cell)
	_expect(planned > 0 and held == planned, "Every piece (%d) is in exactly one cell (%d)" % [planned, held])

	var street_cell := Vector2i(floori(256.0 / cells.grid.cell_size), 0)
	_expect(content.piece_count(street_cell) > 0, "The Avenida Este's first cell holds pieces")
	var node: Node3D = content.build_cell(street_cell)
	root.add_child(node)
	_expect(node.name == "Cell_%d_%d" % [street_cell.x, street_cell.y], "The cell node is named for its cell")
	_expect(node.get_child_count() == content.piece_count(street_cell), "One segment per piece")
	var inside := true
	for child in node.get_children():
		var at: Vector3 = (child as Node3D).position
		inside = inside and child is RouteSegment and content.cell_of(at) == street_cell
	_expect(inside, "Each piece is a RouteSegment that starts in its own cell")
	node.queue_free()

	var far: Node3D = cells.content_for.call(Vector2i(400, 400)) as Node3D
	_expect(far != null and far.get_child_count() == 0, "A cell with no street is empty")
	far.free()
	_expect(cells.grid.is_pinned(Vector2i(4, 0)), "The main streets stay pinned")
	cells.free()
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: ", message)
	else:
		_failures += 1
		printerr("  FAIL: ", message)
