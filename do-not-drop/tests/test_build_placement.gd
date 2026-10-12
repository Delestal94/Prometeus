extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_placement.gd
##
## Placing a warehouse object with a green/red preview (expansion D-0902, BuildPlacement):
## - an object on free floor is green; outside the floor, over a fixed area or over a placed
##   piece is red with the reason (out_of_bounds, fixed_area, overlap);
## - rotation changes the footprint (a 2x1 table turned once covers 1x2);
## - touching edges is not a collision;
## - preview_color() is green or red;
## - place() buys and adds the entry only when green; a red place() changes nothing;
## - place() without enough money is refused with no_money and changes nothing;
## - free = true places owned-at-start objects without checking the wallet.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Place Co")
	state.money = 1000
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var shelf: PlaceableDefinition = PlaceableShop.definition(&"shelf")
	var grid := BuildPlacement.new(Vector2i(12, 8))
	grid.fixed_blocked.append(Rect2i(0, 0, 2, 2))

	var ok: Dictionary = grid.preview(state.layout, table, 5, 5)
	_expect(ok["ok"] and ok["reason"] == BuildPlacement.REASON_OK, "free floor is green")
	_expect(grid.preview_color(ok) == BuildPlacement.COLOR_OK, "green color")
	var out: Dictionary = grid.preview(state.layout, table, 11, 5)
	_expect(not out["ok"] and out["reason"] == BuildPlacement.REASON_OUT_OF_BOUNDS,
		"a 2x1 table at the last column sticks out")
	_expect(not grid.preview(state.layout, table, -1, 3)["ok"], "negative cell is out")
	var fixed: Dictionary = grid.preview(state.layout, table, 1, 1)
	_expect(not fixed["ok"] and fixed["reason"] == BuildPlacement.REASON_FIXED, "fixed area is red")
	_expect(grid.preview_color(fixed) == BuildPlacement.COLOR_BAD, "red color")
	_expect(grid.preview(state.layout, table, 2, 0)["ok"], "touching a fixed area is fine")
	_expect(not grid.preview(state.layout, null, 3, 3)["ok"], "no definition is red")

	var placed: Dictionary = grid.place(state, table, 5, 5)
	_expect(placed["ok"] and state.layout.size() == 1, "place() adds the piece")
	_expect(state.money == 1000 - table.price, "place() charges the price")
	var money_after: int = state.money
	var hit: Dictionary = grid.place(state, shelf, 6, 5)
	_expect(not hit["ok"] and hit["reason"] == BuildPlacement.REASON_OVERLAP, "overlap is red")
	_expect(state.layout.size() == 1 and state.money == money_after, "a red place() changes nothing")
	_expect(grid.preview(state.layout, shelf, 7, 5)["ok"], "touching a placed piece is fine")

	# A 2x1 table turned once covers 1 wide x 2 deep: (5,6) is free for the straight table
	# but taken once the other piece is turned over it.
	_expect(grid.preview(state.layout, table, 5, 6)["ok"], "row below the table is free")
	_expect(not grid.preview(state.layout, table, 5, 4, 1)["ok"], "turned table 1x2 reaches the other")
	_expect(grid.footprint_rect(table, 3, 3, 1).size == Vector2i(1, 2), "turn swaps the footprint")
	_expect(grid.preview(state.layout, table, 11, 0, 1)["ok"], "turned table fits at the edge")

	state.money = shelf.price - 1
	var poor: Dictionary = grid.place(state, shelf, 8, 1)
	_expect(not poor["ok"] and poor["reason"] == BuildPlacement.REASON_NO_MONEY, "no money is refused")
	_expect(state.layout.size() == 1 and state.money == shelf.price - 1, "refusal changes nothing")
	var free: Dictionary = grid.place(state, shelf, 8, 1, 0, true)
	_expect(free["ok"] and state.layout.size() == 2 and state.money == shelf.price - 1,
		"free = true skips the wallet")

	state.reset()
	if _failures == 0:
		print("PASS: placement is green or red by grid, buys only when green")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
