extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_walk_reachability.gd
##
## Walking paths in the warehouse (expansion D-0907, WalkReachability + BuildPlacement):
## - an empty floor and a few pieces leave every piece reachable and the dock joined to the exit;
## - a row of tables across the whole floor cuts the dock from the exit: the last one is red with
##   `blocks_path`, and one cell shorter it is green;
## - four fridges around a fifth one enclose it: the fourth neighbour is red;
## - a dispatch zone (painted on the floor, does not block walking) is never in the way;
## - unreachable_pieces() names the walled-off piece; moving it out reopens the way;
## - without entry areas nothing is checked; apply_to() sets them at every stage.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var fridge: PlaceableDefinition = PlaceableShop.definition(&"fridge")
	var zone: PlaceableDefinition = PlaceableShop.definition(&"dispatch_zone")
	var grid := BuildPlacement.new()
	WarehouseStages.apply_to(0, grid)
	var entries: Array[Rect2i] = grid.entry_areas
	_expect(entries.size() == 2, "apply_to sets the dock and the exit as entries")

	_expect(WalkReachability.is_walkable(grid.grid_size, [], entries), "empty floor is walkable")
	_expect(WalkReachability.reachable_cells(grid.grid_size, [], entries).size() == 96, "all 12x8 cells reached")

	# A wall of tables at z = 3 across the whole 12 columns.
	var wall: Array = []
	for i: int in 5:
		wall.append({"id": "assembly_table", "x": i * 2, "z": 3, "turns": 0})
	_expect(grid.preview(wall, table, 10, 3)["reason"] == BuildPlacement.REASON_BLOCKS_PATH,
		"the table that closes the row is red")
	_expect(not grid.preview(wall, table, 10, 3)["ok"], "blocks_path is not ok")
	_expect(grid.preview(wall, table, 10, 5)["ok"], "a table in another row leaves the gap")
	_expect(grid.preview(wall.slice(0, 4), table, 10, 3)["ok"], "one gap left is green")
	var closed: Array = wall.duplicate()
	closed.append({"id": "assembly_table", "x": 10, "z": 3, "turns": 0})
	_expect(not WalkReachability.entries_connected(grid.grid_size, closed, entries), "closed wall cuts dock from exit")
	_expect(WalkReachability.entries_connected(grid.grid_size, wall, entries), "five tables leave a gap")

	# The red preview also refuses to place and charges nothing.
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Walk Co")
	state.money = 5000
	state.layout = wall.duplicate(true)
	var money: int = state.money
	var refused: Dictionary = grid.place(state, table, 10, 3)
	_expect(not refused["ok"] and refused["reason"] == BuildPlacement.REASON_BLOCKS_PATH, "place() refuses it")
	_expect(state.layout.size() == 5 and state.money == money, "a refused place() changes nothing")
	state.reset()

	# Four fridges around a fifth enclose it.
	var ring: Array = [
		{"id": "fridge", "x": 2, "z": 2, "turns": 0},
		{"id": "fridge", "x": 1, "z": 2, "turns": 0},
		{"id": "fridge", "x": 3, "z": 2, "turns": 0},
		{"id": "fridge", "x": 2, "z": 1, "turns": 0},
	]
	_expect(grid.preview(ring.slice(0, 3), fridge, 2, 1)["ok"] == true, "three sides open is green")
	var shut: Dictionary = grid.preview(ring, fridge, 2, 3)
	_expect(not shut["ok"] and shut["reason"] == BuildPlacement.REASON_BLOCKS_PATH, "the fourth side is red")
	var enclosed: Array = ring.duplicate()
	enclosed.append({"id": "fridge", "x": 2, "z": 3, "turns": 0})
	var lost: Array[int] = WalkReachability.unreachable_pieces(grid.grid_size, enclosed, entries)
	_expect(lost == [0], "the middle fridge is the unreachable one: %s" % str(lost))
	var moved: Array = enclosed.duplicate(true)
	moved[1]["x"] = 8
	moved[1]["z"] = 5
	_expect(WalkReachability.unreachable_pieces(grid.grid_size, moved, entries).is_empty(),
		"moving a neighbour away reopens the way")

	# A dispatch zone across the corridor does not block walking.
	var with_zone: Array = wall.duplicate()
	with_zone.append({"id": "dispatch_zone", "x": 9, "z": 4, "turns": 0})
	_expect(WalkReachability.is_walkable(grid.grid_size, with_zone, entries), "a dispatch zone is walkable")
	_expect(grid.preview(wall.slice(0, 4), zone, 5, 3)["ok"], "a zone over the gap is green")

	# No entries, no check.
	var open := BuildPlacement.new()
	_expect(open.preview(wall, table, 10, 3)["ok"], "without entry areas nothing is checked")
	_expect(WalkReachability.unreachable_pieces(Vector2i(12, 8), ring, []).is_empty(), "no entries: no report")

	for stage: int in WarehouseStages.stage_count():
		WarehouseStages.apply_to(stage, grid)
		_expect(grid.entry_areas.size() == 2, "stage %d has two entries" % stage)
		_expect(WalkReachability.entries_connected(grid.grid_size, [], grid.entry_areas),
			"stage %d dock and exit are joined" % stage)

	if _failures == 0:
		print("PASS: pieces that wall off a station or the dock-exit path are red")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
