extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_cells.gd
##
## The company map's cells (expansion D-0303, scripts/gameplay/districts/company_cells.gd):
## - CompanyCells takes its numbers from CompanyTuning (256 m cells, load 2, unload 3) and
##   pins the cells of the shed and of the three main streets before anyone moves;
## - driving a van from the shed to the first Centro house (1000 m east at 12 m/s) in 60 fps
##   steps never costs a step over 50 ms, keeps the 5 x 5 square around it loaded, and drops
##   the cells it leaves behind except the pinned ones;
## - coming back to the shed leaves exactly the pinned cells and the square around the shed,
##   no cell node outside the tree's children and no orphan node.

const FRAME_LIMIT_USEC: int = 50000

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cells := CompanyCells.new()
	root.add_child(cells)
	_expect(is_equal_approx(cells.grid.cell_size, CompanyTuning.CELL_SIZE), "Cells are CELL_SIZE wide")
	_expect(cells.grid.load_radius == 2 and cells.grid.unload_radius == 3, "Radius 2, unload 3")
	for z in range(-1, 2):
		for x in range(-1, 2):
			_expect(cells.grid.is_pinned(Vector2i(x, z)), "The shed's cell (%d, %d) is pinned" % [x, z])
	_expect(cells.grid.is_pinned(Vector2i(4, 0)), "The Avenida Este is pinned up to the port")
	_expect(cells.grid.is_pinned(Vector2i(0, 3)), "The Camino del Campo is pinned")
	_expect(cells.grid.is_pinned(Vector2i(-4, -1)), "The Calle Oeste is pinned")
	_expect(not cells.grid.is_pinned(Vector2i(0, -6)), "The mountains are not")

	var orphans_before := _orphans()
	var van := Vector3(0, 0, 0)
	cells.anchors = [van]
	var now := 0.0
	var worst := 0
	var fine := true
	var steps := int(1000.0 / 12.0 * 60.0)
	for i in steps:
		now += 1.0 / 60.0
		van.x += 12.0 / 60.0
		cells.anchors = [van]
		var t0 := Time.get_ticks_usec()
		cells.step(now)
		worst = maxi(worst, Time.get_ticks_usec() - t0)
		if i % 60 == 59:
			fine = fine and _square_loaded(cells, van, 1)
	_expect(worst < FRAME_LIMIT_USEC, "No step over 50 ms driving to Centro (worst %d us)" % worst)
	_expect(fine, "The cells around the van were loaded every second")
	_expect(cells.is_loaded(Vector2i(0, 0)), "The shed's cell is still there (pinned)")
	_expect(not cells.is_loaded(Vector2i(-2, 2)), "A cell the van left behind is gone")

	# Back to the shed.
	for i in steps:
		now += 1.0 / 60.0
		van.x -= 12.0 / 60.0
		cells.anchors = [van]
		cells.step(now)
	van = Vector3(10, 0, 10)
	cells.anchors = [van]
	cells.step(now + 1.0)
	cells.step(now + 2.0)
	for cell: Vector2i in cells.loaded_cells():
		if cells.grid.distance_to_anchors(cell, cells.anchors) > 3 and not cells.grid.is_pinned(cell):
			_expect(false, "Cell %s should be gone back at the shed" % [cell])
	var nodes := 0
	for child in cells.get_children():
		if child.name.begins_with("Cell_"):
			nodes += 1
	_expect(nodes == cells.loaded_cells().size(), "Every loaded cell is one node, nothing else stays")
	cells.queue_free()
	for i in 3:
		await process_frame
	_expect(_orphans() <= orphans_before, "No orphan node is left")
	if _failures == 0:
		print("PASS: the company cells follow the van to Centro and back without a long step or leftovers")
	quit(_failures)


func _square_loaded(cells: CompanyCells, pos: Vector3, radius: int) -> bool:
	var own := cells.grid.cell_of(pos)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if not cells.is_loaded(Vector2i(own.x + dx, own.y + dz)):
				return false
	return true


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
