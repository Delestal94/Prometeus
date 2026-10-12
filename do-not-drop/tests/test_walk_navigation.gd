extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_walk_navigation.gd
##
## Walking navigation of the warehouse (expansion D-0908, WalkNavigation + BuildPlacement):
## - an empty floor has a straight path between two cells and none to a cell outside it;
## - a piece placed on that straight path rebakes the grid: `version` goes up and the path now
##   goes around it (longer, never through a blocked cell) - "the employee dodges the new object";
## - moving, turning and selling the piece rebake too, and selling it restores the short path;
## - a refused placement does not rebake; a dispatch zone (walkable) never changes a path;
## - find_path_to_rect() walks up to a side of a station and to nothing when it is walled off;
## - the grid agrees with WalkReachability: a cell with a path is a reachable one.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var zone: PlaceableDefinition = PlaceableShop.definition(&"dispatch_zone")
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Nav Co")
	state.money = 5000

	var grid := BuildPlacement.new()
	WarehouseStages.apply_to(0, grid)
	var nav := WalkNavigation.new()
	grid.navigation = nav
	grid.rebake_navigation(state)
	var v0: int = nav.version
	var from := Vector2i(0, 3)
	var to := Vector2i(7, 3)

	var straight: Array[Vector2i] = nav.find_path(from, to)
	_expect(straight.size() == 8 and straight[0] == from and straight[-1] == to, "straight path: %s" % str(straight))
	_expect(nav.find_path(from, Vector2i(20, 3)).is_empty(), "no path to a cell outside the floor")
	_expect(not nav.is_walkable(Vector2i(-1, 0)), "outside is not walkable")

	# A table (2x1 or so) on the straight line: the path bends around it.
	var placed: Dictionary = grid.place(state, table, 3, 3)
	_expect(placed["ok"], "table placed: %s" % str(placed))
	_expect(nav.version == v0 + 1, "placing rebakes the navigation")
	var blocked: Dictionary = WalkReachability.blocked_cells(state.layout)
	_expect(not blocked.is_empty() and not nav.is_walkable(blocked.keys()[0]), "the table cells are solid")
	var around: Array[Vector2i] = nav.find_path(from, to)
	_expect(around.size() > straight.size(), "the path got longer: %d vs %d" % [around.size(), straight.size()])
	_expect(around.size() > 0 and around[0] == from and around[-1] == to, "still joins the same cells")
	for cell: Vector2i in around:
		_expect(not blocked.has(cell), "path does not cross the table at %s" % str(cell))

	# Turning and moving rebake; moving it off the line gives the short path back.
	var v1: int = nav.version
	grid.rotate_piece(state, 0)
	_expect(nav.version == v1 + 1, "turning rebakes")
	var moved: Dictionary = grid.move_piece(state, 0, 3, 6)
	_expect(moved["ok"] and nav.version == v1 + 2, "moving rebakes")
	_expect(nav.find_path(from, to).size() == straight.size(), "off the line the path is short again")
	grid.move_piece(state, 0, 3, 3)
	_expect(nav.find_path(from, to).size() > straight.size(), "back on the line it bends again")

	# A refused placement leaves the navigation alone.
	var v2: int = nav.version
	var refused: Dictionary = grid.place(state, table, 3, 3)
	_expect(not refused["ok"] and nav.version == v2, "an overlapping placement does not rebake")

	# A dispatch zone is walkable: the path does not change.
	var before_zone: int = nav.find_path(from, to).size()
	grid.place(state, zone, 5, 3)
	_expect(nav.find_path(from, to).size() == before_zone, "a dispatch zone does not change the path")

	# Walking up to a station.
	var rect := Rect2i(Vector2i(int(state.layout[0]["x"]), int(state.layout[0]["z"])),
			table.footprint_for(int(state.layout[0]["turns"])))
	var to_station: Array[Vector2i] = nav.find_path_to_rect(from, rect)
	_expect(not to_station.is_empty(), "there is a path up to the table")
	_expect(to_station.size() > 0 and not rect.has_point(to_station[-1]), "it ends beside the table, not on it")
	var reached: Dictionary = WalkReachability.reachable_cells(grid.grid_size, state.layout, grid.entry_areas)
	for cell: Vector2i in to_station:
		_expect(reached.has(cell) or cell == from, "path cell %s is reachable on the grid" % str(cell))

	# Selling restores the short path.
	var v3: int = nav.version
	grid.sell_piece(state, 0)
	_expect(nav.version == v3 + 1, "selling rebakes")
	_expect(nav.find_path(from, to).size() == straight.size(), "after selling the path is straight")
	_expect(grid.sell_piece(state, 99) < 0 and nav.version == v3 + 1, "a bad sale index does not rebake")

	state.reset()
	if _failures == 0:
		print("PASS: the walking grid is rebaked with the layout and paths go around new pieces")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
