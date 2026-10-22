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
## Top of a far cell's flat block (m): under the zone slabs' (-0.1, CompanyRoot) so it never fights them for
## the same plane, over the backup ground's (-0.5, CompanyGround) so it still shows where no zone is.
const IMPOSTOR_TOP_Y: float = -0.2
const IMPOSTOR_THICKNESS_M: float = 0.2

## Callable(cell: Vector2i) -> Node3D, the content of a cell. Unset: empty cells.
var content_for: Callable
## The content `use_graph` made: a Callable holds its object by id only, so a RefCounted that nobody keeps is freed
## and `content_for` goes dead (every cell would come out as an empty Node3D).
var _graph_content: EdgeCellContent


func _init() -> void:
	grid.cell_size = CompanyTuning.CELL_SIZE
	grid.load_radius = CompanyTuning.CELL_LOAD_RADIUS
	grid.unload_radius = CompanyTuning.CELL_UNLOAD_RADIUS
	grid.impostor_radius = CompanyTuning.CELL_IMPOSTOR_RADIUS
	slice_msec = CompanyTuning.CELL_SLICE_MSEC
	build_for = _build_cell
	impostor_for = _impostor
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


## Fills the cells with the graph's streets (EdgeCellContent, D-0304.1) and pins
## the gray Barrio Centro around them (CentroDecor, D-0314) and pins
## the main streets. Returns the content, for tests and for callers that want it.
## `world_seed` deals the Campo's animals and events (EdgeEvents, D-0315); their
## nodes are built only with `spawn_events`. `keep_clear` is a ground rectangle no roadway is laid
## inside (the shed's: the streets that start at its middle start at its edge, D-0314.a).
func use_graph(graph: RoadGraph, world_seed: int = 0, spawn_events: bool = false,
		keep_clear: Rect2 = Rect2()) -> EdgeCellContent:
	var decor := CentroDecor.new(graph, HouseMap.load_default(), grid.cell_size)
	var content := EdgeCellContent.new(graph, grid.cell_size, world_seed, spawn_events, decor, keep_clear)
	_graph_content = content
	content_for = content.build_cell
	pin_streets(graph)
	return content


func _build_cell(cell: Vector2i) -> Node3D:
	if content_for.is_valid():
		return content_for.call(cell) as Node3D
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [cell.x, cell.y]
	return node


## A far cell's block: the streamer's flat block, lowered so its top is IMPOSTOR_TOP_Y (the streamer puts a node
## 0.6 m under the cell's centre, and the default block's top was the zone slabs' own plane).
func _impostor(_cell: Vector2i) -> Node3D:
	var block := _default_impostor() as MeshInstance3D
	(block.mesh as BoxMesh).size = Vector3(grid.cell_size * 0.98, IMPOSTOR_THICKNESS_M, grid.cell_size * 0.98)
	block.position.y = IMPOSTOR_TOP_Y + 0.6 - IMPOSTOR_THICKNESS_M * 0.5
	var holder := Node3D.new()
	holder.name = "Impostor"
	holder.add_child(block)
	return holder


## The seed of the world a peer joined (NetworkManager.world_seed, the host's, which a client has before the level
## loads); 0 when the session has none (solo before a roll, a test). Only the Campo's events read it.
static func seed_of(session: Object) -> int:
	var value: Variant = session.get(&"world_seed") if session != null else null
	return int(value) if value is int else 0


## The ground (XZ, metres) the shed takes at its biggest stage, with its walls: no roadway is laid inside it (the
## shed is rebuilt bigger as the company upgrades it, and the cells are built once). Empty without a shed.
static func shed_ground(at_shed: Node3D) -> Rect2:
	if at_shed == null:
		return Rect2()
	var floor_m: Vector2 = WarehouseStages.floor_size_m(WarehouseStages.stage_count() - 1)
	var size: Vector2 = floor_m + Vector2.ONE * 2.0 * CompanyShed.WALL_THICKNESS
	var middle := Vector2(at_shed.position.x, at_shed.position.z)
	return Rect2(middle - size * 0.5, size)
