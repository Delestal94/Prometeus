class_name CompanyCells
extends WorldCellStreamer
## The company map's cells (expansion D-0303): modules/world_cells with this
## game's numbers (CompanyTuning) and the cells that never unload.
##
## Pinned for good: the industrial park around the shed (cells -1..1) and the
## cells under the three main streets of diseno/mapa.md, so the shed and the
## streets are there before anyone drives. `pin_streets` pins them again from the
## road graph's real curves (RoadGraph, D-0304). A cell's content comes from
## `content_for` (the road graph's pieces, once the mesh per edge exists); until
## then a cell is an empty `Node3D` named `Cell_<x>_<z>` so the flow is testable.

## Waypoints of the main streets, from diseno/mapa.md (x, z in meters).
const MAIN_STREETS: Array = [
	[Vector2(0, 0), Vector2(256, 0), Vector2(1024, 0), Vector2(1792, 256)],
	[Vector2(0, 0), Vector2(0, 512), Vector2(0, 1024), Vector2(-640, 1536), Vector2(512, 1792)],
	[Vector2(0, 0), Vector2(-256, 0), Vector2(-768, 0), Vector2(-1024, -256)],
]
## Half-side of the pinned square around the shed, in cells.
const SHED_PIN_RADIUS: int = 1

## Callable(cell: Vector2i) -> Node3D, the content of a cell. Unset: empty cells.
var content_for: Callable


func _init() -> void:
	grid.cell_size = CompanyTuning.CELL_SIZE
	grid.load_radius = CompanyTuning.CELL_LOAD_RADIUS
	grid.unload_radius = CompanyTuning.CELL_UNLOAD_RADIUS
	grid.impostor_radius = CompanyTuning.CELL_IMPOSTOR_RADIUS
	slice_msec = CompanyTuning.CELL_SLICE_MSEC
	build_for = _build_cell
	pin_fixed_cells()


## Cells the shed and the main streets cross.
func pin_fixed_cells() -> void:
	for dx in range(-SHED_PIN_RADIUS, SHED_PIN_RADIUS + 1):
		for dz in range(-SHED_PIN_RADIUS, SHED_PIN_RADIUS + 1):
			grid.pin(Vector2i(dx, dz))
	for street: Array in MAIN_STREETS:
		for i in street.size() - 1:
			var from: Vector2 = street[i]
			var to: Vector2 = street[i + 1]
			var steps: int = maxi(1, ceili(from.distance_to(to) / (grid.cell_size * 0.5)))
			for s in steps + 1:
				var p := from.lerp(to, float(s) / float(steps))
				grid.pin(grid.cell_of(Vector3(p.x, 0.0, p.y)))


## Pins every cell the streets named `streets` (RoadEdge.street) cross, so they
## never unload. Returns how many cells were pinned.
func pin_streets(graph: RoadGraph, streets: Array[StringName] = RoadGraph.MAIN_STREETS) -> int:
	var count: int = 0
	for edge: RoadEdge in graph.edges:
		if not streets.has(edge.street):
			continue
		for cell: Vector2i in graph.cells_crossed(edge.id, grid.cell_size):
			if not grid.is_pinned(cell):
				count += 1
			grid.pin(cell)
	return count


func _build_cell(cell: Vector2i) -> Node3D:
	if content_for.is_valid():
		return content_for.call(cell) as Node3D
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [cell.x, cell.y]
	return node
