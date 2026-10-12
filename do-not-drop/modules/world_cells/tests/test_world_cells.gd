extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/world_cells/tests/test_world_cells.gd
##
## The world_cells module on its own (docs/modulos.md):
## - WorldCellGrid: cell_of() floors (negative positions too); an anchor wants
##   the (2 * load_radius + 1)^2 cells around it, closest first; a cell is
##   dropped only past unload_radius (one step past load_radius keeps it);
##   pinned cells are always there; with three anchors walking around, every
##   step's loaded set is the union of their squares plus what the hysteresis
##   keeps, and no cell is ever loaded and unloaded within min_stay_sec.
## - WorldCellStreamer: builds the cells the grid asks for in slices (a frame
##   never instances more than the budget allows), unloads what is left behind
##   with no orphans, fills the near unloaded cells with impostors and clears
##   them when the cell loads, and loads a scene file on a thread.

const CELL_SCENE: String = "res://modules/world_cells/tests/cell_piece.tscn"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_grid_basics()
	_test_hysteresis_and_pins()
	_test_three_anchors()
	await _test_streamer()
	await _test_threaded_scene()
	if _failures == 0:
		print("PASS: the world cells load around the anchors, keep their hysteresis and free what they drop")
	quit(_failures)


func _test_grid_basics() -> void:
	var grid := WorldCellGrid.new()
	_expect(grid.cell_of(Vector3(0, 5, 0)) == Vector2i(0, 0), "The origin is cell (0, 0)")
	_expect(grid.cell_of(Vector3(255.9, 0, 256.0)) == Vector2i(0, 1), "Cells are 256 m")
	_expect(grid.cell_of(Vector3(-0.1, 0, -256.1)) == Vector2i(-1, -2), "Negative positions floor")
	_expect(grid.center_of(Vector2i(1, -1)).is_equal_approx(Vector3(384, 0, -128)),
		"The center of a cell is half a cell in")
	var anchors: Array[Vector3] = [Vector3(10, 0, 10)]
	var changes := grid.update(anchors, 0.0)
	_expect(changes["load"].size() == 25, "One anchor asks for the 5 x 5 cells around it")
	_expect(changes["load"][0] == Vector2i(0, 0), "Its own cell comes first")
	_expect(changes["unload"].is_empty(), "Nothing to unload at the start")
	_expect(grid.update(anchors, 1.0)["load"].is_empty(), "Asking again changes nothing")


func _test_hysteresis_and_pins() -> void:
	var grid := WorldCellGrid.new()
	var anchors: Array[Vector3] = [Vector3(10, 0, 10)]
	grid.update(anchors, 0.0)
	grid.pin(Vector2i(-2, -2))
	# One cell east: (-2, y) is 3 cells away, past load_radius but not past unload_radius.
	anchors[0] = Vector3(256 + 10, 0, 10)
	var changes := grid.update(anchors, 5.0)
	_expect(changes["unload"].is_empty(), "A cell just past the load radius stays (hysteresis)")
	_expect(grid.is_loaded(Vector2i(-2, 0)), "...and is still loaded")
	_expect(grid.is_loaded(Vector2i(3, 0)), "The new edge loaded")
	# Four cells away it goes, but the pinned one never does.
	anchors[0] = Vector3(256 * 4 + 10, 0, 10)
	changes = grid.update(anchors, 10.0)
	_expect(not grid.is_loaded(Vector2i(-2, 0)), "Beyond the unload radius it is dropped")
	_expect(grid.is_loaded(Vector2i(-2, -2)), "A pinned cell is never dropped")
	_expect(grid.update(anchors, 11.0)["unload"].is_empty(), "Nothing else to drop")
	grid.unpin(Vector2i(-2, -2))
	_expect(grid.update(anchors, 12.0)["unload"].has(Vector2i(-2, -2)), "Unpinned, it goes")
	# Teleporting back: the dropped cells wait out min_stay_sec before they load again.
	anchors[0] = Vector3(10, 0, 10)
	var back := grid.update(anchors, 12.2)
	_expect(not back["load"].has(Vector2i(-2, -2)), "A cell dropped 0.2 s ago does not load yet")
	back = grid.update(anchors, 13.5)
	_expect(back["load"].has(Vector2i(-2, -2)), "...and does once the second has passed")


func _test_three_anchors() -> void:
	var grid := WorldCellGrid.new()
	var anchors: Array[Vector3] = [Vector3(0, 0, 0), Vector3(1500, 0, 0), Vector3(-900, 0, 700)]
	var loaded_at: Dictionary = {}
	var dropped_at: Dictionary = {}
	var moved_ok := true
	var stay_ok := true
	var now := 0.0
	for step in 600:
		now += 0.1
		anchors[0].x += 12.0 * 0.1
		anchors[1].z += 9.0 * 0.1
		anchors[2].x += 4.0 * 0.1
		anchors[2].z -= 8.0 * 0.1
		var changes := grid.update(anchors, now)
		for cell: Vector2i in changes["load"]:
			if now - float(dropped_at.get(cell, -1.0e9)) < 1.0:
				stay_ok = false
			loaded_at[cell] = now
		for cell: Vector2i in changes["unload"]:
			if now - float(loaded_at.get(cell, -1.0e9)) < 1.0:
				stay_ok = false
			dropped_at[cell] = now
		for pos in anchors:
			var own := grid.cell_of(pos)
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if not grid.is_loaded(Vector2i(own.x + dx, own.y + dz)):
						moved_ok = false
		for cell in grid.loaded_cells():
			if grid.distance_to_anchors(cell, anchors) > grid.unload_radius \
					and now - float(loaded_at[cell]) >= 1.0:
				moved_ok = false
	_expect(moved_ok, "Every step has the 5 x 5 square of each anchor loaded and nothing far kept")
	_expect(stay_ok, "No cell is loaded and unloaded (or the reverse) within a second")
	_expect(not grid.is_loaded(Vector2i(10, 10)), "A far cell is not loaded")


func _test_streamer() -> void:
	var streamer := WorldCellStreamer.new()
	root.add_child(streamer)
	var built: Array[Vector2i] = []
	streamer.build_for = func(cell: Vector2i) -> Node3D:
		built.append(cell)
		var n := Node3D.new()
		n.name = "cell_%d_%d" % [cell.x, cell.y]
		return n
	streamer.slice_msec = 0.0
	streamer.anchors = [Vector3(10, 0, 10)]
	var now := 0.0
	streamer.step(now)
	_expect(streamer.loaded_cells().size() == 1, "A zero slice instances one cell per step")
	_expect(built[0] == Vector2i(0, 0), "...the closest one")
	_expect(streamer.is_busy(), "The rest waits for later frames")
	for i in 40:
		now += 0.01
		streamer.step(now)
	_expect(streamer.loaded_cells().size() == 25 and not streamer.is_busy(),
		"All 25 cells arrive over the next steps")
	_expect(streamer.get_child_count() >= 25, "They are children of the streamer")
	_expect(streamer.impostor_count() == 121 - 25, "The unloaded cells within 5 of the anchor have impostors")
	# Walk 4 cells east, past the 1 s minimum stay.
	streamer.slice_msec = 1000.0
	streamer.anchors = [Vector3(256 * 4 + 10, 0, 10)]
	now += 2.0
	streamer.step(now)
	_expect(not streamer.is_loaded(Vector2i(-2, 0)), "A cell left behind unloads")
	_expect(streamer.is_loaded(Vector2i(6, 0)), "The new edge is loaded")
	# Columns 1..6 stay: the old ones within 3 cells (1, 2) plus the new square (2..6).
	_expect(streamer.loaded_cells().size() == 30, "30 cells are loaded after the walk")
	_expect(streamer.impostor_count() == 121 - 30, "Impostors follow: a loaded cell never has one")
	var cell_count := 0
	for child in streamer.get_children():
		if child.name.begins_with("cell_"):
			cell_count += 1
	_expect(cell_count == 30, "Exactly the loaded cells are in the tree")
	_expect(streamer.longest_step_usec < 50000, "Instancing a cell takes far less than a frame")
	streamer.queue_free()
	await process_frame


func _test_threaded_scene() -> void:
	var streamer := WorldCellStreamer.new()
	root.add_child(streamer)
	streamer.grid.load_radius = 0
	streamer.grid.unload_radius = 0
	streamer.grid.impostor_radius = 0
	var made: Array[Node3D] = []
	streamer.path_for = func(cell: Vector2i) -> String:
		return CELL_SCENE if cell == Vector2i(0, 0) else ""
	streamer.cell_loaded.connect(func(_cell: Vector2i, node: Node3D) -> void:
		made.append(node))
	streamer.anchors = [Vector3(10, 0, 10)]
	var now := 0.0
	for i in 600:
		now += 0.01
		streamer.step(now)
		if not streamer.is_busy():
			break
		await process_frame
	_expect(made.size() == 1 and made[0] != null and made[0].name == "CellPiece",
		"A scene file loads on a thread and is instanced")
	streamer.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
