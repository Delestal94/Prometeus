extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_root_graph.gd
##
## The street map in the company's world (expansion D-0314.a, CompanyRoot._add_cells() ->
## CompanyCells.use_graph(RoadGraph.load_default(), seed, false, shed_ground())):
## - once inside the tree the root has exactly one WorldCells, and it is fed by the road graph (its
##   content_for builds `Cell_<x>_<z>` with the streets' pieces, not an empty node);
## - the cells next to the shed hold the three main streets as RouteSegments with a `Road` roadway, and
##   Centro's first cell holds its `Centro` decor (sidewalks, houses);
## - the shed and the roadways live together: no roadway of any loaded cell overlaps the ground the shed
##   takes at its biggest stage (CompanyRoot.shed_ground()), the streets that leave the shed's middle
##   start where they leave that ground, and the shed's floor and the roadway are never the same plane
##   with the zone slab under them (slab top -0.1, shed floor and roadway top 0.0);
## - a far cell's flat block (impostor) sits under the zone slabs' top, not on their plane;
## - a peer whose only anchor is its own player (a client's) still gets the street cells and Centro around
##   it, and they unload when it leaves;
## - building the cells costs little (a budget per cell, headless software rendering, a wide margin).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_root_graph"
## Real milliseconds a cell may take to build (test_company_cells measures 5-15).
const CELL_BUDGET_MSEC: float = 50.0
## Top of a zone slab and of the shed floor and a roadway (m).
const SLAB_TOP: float = -0.1
const FLOOR_TOP: float = 0.0
const MAX_STEPS: int = 400

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var cells: CompanyCells = level.cells
	_check_one_streamer(level, cells)
	if cells != null and cells.content_for.is_valid():
		_settle(cells, 0.0)
		_check_streets_near_the_shed(cells)
		_check_no_roadway_in_the_shed(level, cells)
		_check_planes(level, cells)
		_check_impostor(cells)
		_check_budget(level)
		_check_player_only_anchor(cells)
	level.queue_free()
	await process_frame
	_clean()
	if _failures == 0:
		print("OK: the company root lays the street map")
	quit(_failures)


func _check_one_streamer(level: CompanyRoot, cells: CompanyCells) -> void:
	var found: int = 0
	for child: Node in level.get_children():
		if child is CompanyCells:
			found += 1
	_expect(found == 1 and cells != null and cells.name == &"WorldCells",
		"There is a single WorldCells (got %d)" % found)
	_expect(cells != null and cells.content_for.is_valid(), "The cells are fed by the road graph (content_for is set)")


## The streets that leave the shed, in the cells around it.
func _check_streets_near_the_shed(cells: CompanyCells) -> void:
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var node: Node3D = cells.cell_node(cell)
		_expect(node != null and node.name == "Cell_%d_%d" % [cell.x, cell.y],
			"Cell %s is loaded and named for it" % cell)
		if node == null:
			continue
		var roads: int = 0
		for piece: Node in node.get_children():
			if piece is RouteSegment and piece.get_node_or_null(^"Road") != null:
				roads += 1
		_expect(roads > 0, "Cell %s holds street pieces with a roadway (got %d)" % [cell, roads])
	var centro: Node3D = cells.cell_node(Vector2i(1, 0))
	_expect(centro != null and centro.get_node_or_null(^"Centro") != null, "Centro's first cell holds its Centro decor")


## No roadway of a loaded cell overlaps the shed's ground; the streets start at its edge.
func _check_no_roadway_in_the_shed(level: CompanyRoot, cells: CompanyCells) -> void:
	var clear: Rect2 = CompanyCells.shed_ground(level.shed)
	var floor_m: Vector2 = WarehouseStages.floor_size_m(WarehouseStages.stage_count() - 1)
	var around: bool = clear.size.x > floor_m.x and clear.size.y > floor_m.y and clear.get_center().length() < 0.01
	_expect(clear.has_area() and around,
		"The clear ground is the biggest shed with its walls, around the shed (got %s)" % clear)
	var checked: int = 0
	var starts: Dictionary = {}
	for cell: Vector2i in cells.loaded_cells():
		var node: Node3D = cells.cell_node(cell)
		if node == null:
			continue
		for piece: Node in node.get_children():
			var segment := piece as RouteSegment
			if segment == null:
				continue
			var road := segment.get_node_or_null(^"Road") as StaticBody3D
			if road == null:
				continue
			checked += 1
			var footprint: Rect2 = _road_footprint(segment, road)
			_expect(not footprint.intersects(clear),
				"%s/%s keeps off the shed's ground (roadway %s, shed %s)" % [node.name, piece.name, footprint, clear])
			if String(piece.name).ends_with("_0"):
				starts[String(piece.name).trim_suffix("_0")] = Vector2(segment.position.x, segment.position.z)
	_expect(checked > 10, "Many roadways were checked (got %d)" % checked)
	var east: Vector2 = starts.get("avenida_este_1", Vector2(-99.0, -99.0))
	_expect(absf(east.y) < 0.01 and east.x >= clear.end.x and east.x < clear.end.x + 2.0,
		"The Avenida Este starts where it leaves the shed's ground (got %s, edge %.1f)" % [east, clear.end.x])
	var west: Vector2 = starts.get("calle_oeste_1", Vector2(99.0, 99.0))
	_expect(absf(west.y) < 0.01 and west.x <= clear.position.x and west.x > clear.position.x - 2.0,
		"The Calle Oeste starts where it leaves the shed's ground (got %s, edge %.1f)" % [west, clear.position.x])
	var south: Vector2 = starts.get("camino_campo_1", Vector2(99.0, 99.0))
	_expect(absf(south.x) < 0.01 and south.y >= clear.end.y and south.y < clear.end.y + 2.0,
		"The Camino del Campo starts where it leaves the shed's ground (got %s, edge %.1f)" % [south, clear.end.y])


## The XZ rectangle a roadway box takes in the world (its four corners through the piece's transform).
func _road_footprint(segment: RouteSegment, road: StaticBody3D) -> Rect2:
	var size: Vector3 = _size_of(road)
	var rect := Rect2()
	var first: bool = true
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var local := road.position + Vector3(size.x * sx, 0.0, size.z * sz)
			var world: Vector3 = segment.transform * local
			var point := Vector2(world.x, world.z)
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return rect


## Zone slab, shed floor and roadway are three different heights: nothing is laid on another's plane.
func _check_planes(level: CompanyRoot, cells: CompanyCells) -> void:
	var slab := level.get_node_or_null(^"World/Zone_parque_industrial") as StaticBody3D
	_expect(slab != null and is_equal_approx(_top_of(slab), SLAB_TOP),
		"The industrial park's slab tops out at %.1f" % SLAB_TOP)
	var floor_body := level.shed.get_node_or_null(^"Shell/Floor") as StaticBody3D
	_expect(floor_body != null and is_equal_approx(_top_of(floor_body), FLOOR_TOP),
		"The shed floor tops out at %.1f" % FLOOR_TOP)
	var node: Node3D = cells.cell_node(Vector2i(0, 0))
	var road: StaticBody3D = null
	for piece: Node in node.get_children():
		if piece is RouteSegment:
			road = piece.get_node_or_null(^"Road") as StaticBody3D
			break
	_expect(road != null and is_equal_approx(road.position.y + (_size_of(road).y * 0.5), FLOOR_TOP),
		"A roadway tops out at %.1f (the slab's -0.1 is under it)" % FLOOR_TOP)
	var backup := level.get_node_or_null(^"World/GroundBackup") as StaticBody3D
	_expect(backup != null and _top_of(backup) < SLAB_TOP - 0.1, "The backup ground is under the zone slabs")


func _check_impostor(cells: CompanyCells) -> void:
	# A far anchor leaves cells near the shed unloaded but inside the impostor radius.
	cells.anchors = [Vector3(1500.0, 0.0, 0.0)]
	_settle(cells, 10.0)
	_expect(cells.impostor_count() > 0, "Cells near the anchor but not loaded get their flat block")
	var top: float = INF
	for child: Node in cells.get_children():
		if not String(child.name).begins_with("Cell_") and child.get_child_count() == 1 \
				and child.get_child(0) is MeshInstance3D:
			var block := child.get_child(0) as MeshInstance3D
			top = minf(top, (child as Node3D).position.y + block.position.y + (block.mesh as BoxMesh).size.y * 0.5)
	_expect(top < SLAB_TOP - 0.05, "A far cell's block tops out under the slabs' plane (got %.2f)" % top)
	_expect(top > CompanyGround.BACKUP_TOP_Y,
		"...and over the backup ground, so it shows where no zone is (got %.2f)" % top)


## What a cell costs to build, at the cell that has the most (Centro's first).
func _check_budget(level: CompanyRoot) -> void:
	var content: Callable = level.cells.content_for
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
		var start: int = Time.get_ticks_usec()
		var node := content.call(cell) as Node3D
		var msec: float = float(Time.get_ticks_usec() - start) / 1000.0
		node.free()
		_expect(msec < CELL_BUDGET_MSEC, "Building cell %s takes %.1f ms (under %.0f)" % [cell, msec, CELL_BUDGET_MSEC])


## A client only anchors its own player: the cells around it load, with Centro's decor, and go when it leaves.
func _check_player_only_anchor(cells: CompanyCells) -> void:
	cells.anchors = [Vector3(700.0, 1.0, 40.0)]
	_settle(cells, 20.0)
	var near: Vector2i = cells.grid.cell_of(cells.anchors[0])
	var node: Node3D = cells.cell_node(near)
	_expect(node != null and node.get_node_or_null(^"Centro") != null,
		"Around the player's cell %s Centro is laid" % near)
	var edge := Vector2i(4, 2)
	_expect(not cells.grid.is_pinned(edge) and cells.is_loaded(edge), "%s is loaded for the player only" % edge)
	cells.anchors = [Vector3(0.0, 1.0, 0.0)]
	_settle(cells, 40.0)
	_expect(not cells.is_loaded(edge), "Back at the shed the cells that were only near the player are gone")


## Steps the streamer on its own clock, starting `from_sec`, until it has nothing left to build.
func _settle(cells: CompanyCells, from_sec: float) -> void:
	var now: float = from_sec + Time.get_ticks_msec() / 1000.0
	var steps: int = 0
	cells.step(now)
	while cells.is_busy() and steps < MAX_STEPS:
		now += 0.3
		cells.step(now)
		steps += 1
	now += 0.3
	cells.step(now)
	while cells.is_busy() and steps < MAX_STEPS:
		now += 0.3
		cells.step(now)
		steps += 1
	_expect(steps < MAX_STEPS, "The cells settle (took %d steps)" % steps)


func _size_of(body: StaticBody3D) -> Vector3:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			return ((child as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO


func _top_of(body: StaticBody3D) -> float:
	return body.position.y + _size_of(body).y * 0.5


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
