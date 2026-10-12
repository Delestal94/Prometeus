extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_edit.gd
##
## Rotating, moving and selling placed warehouse objects (expansion D-0903, BuildPlacement):
## - rotate_piece() turns a piece a quarter turn when the turned footprint fits, wrapping at 4;
## - a rotation that would leave the floor, hit a fixed area or hit another piece is refused and
##   the piece stays as it was;
## - move_piece() moves it to a free cell (its own old cells do not count as a collision);
## - a move out of the floor, over a fixed area or over another piece is refused, nothing changes;
## - rotating and moving cost nothing;
## - sell_piece() removes the piece and pays the partial refund; a bad index returns -1.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Edit Co")
	state.money = 1000
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var shelf: PlaceableDefinition = PlaceableShop.definition(&"shelf")
	var grid := BuildPlacement.new(Vector2i(12, 8))
	grid.fixed_blocked.append(Rect2i(0, 0, 2, 2))
	grid.place(state, table, 5, 5)   # index 0, 2x1
	grid.place(state, shelf, 8, 5)   # index 1, 2x1
	var money: int = state.money

	var turned: Dictionary = grid.rotate_piece(state, 0)
	_expect(turned["ok"] and state.layout[0]["turns"] == 1, "rotating on free floor works")
	_expect(turned["rect"].size == Vector2i(1, 2), "the turned footprint is 1x2")
	grid.rotate_piece(state, 0, 3)
	_expect(state.layout[0]["turns"] == 0, "turns wrap at four")
	_expect(state.money == money, "rotating is free")

	# Turned at the last column it is 1x2; turning it back to 2x1 would stick out.
	state.layout[0] = {"id": "assembly_table", "x": 11, "z": 3, "turns": 1}
	var out: Dictionary = grid.rotate_piece(state, 0)
	_expect(not out["ok"] and out["reason"] == BuildPlacement.REASON_OUT_OF_BOUNDS,
		"a rotation that leaves the floor is refused")
	_expect(state.layout[0]["turns"] == 1, "a refused rotation changes nothing")

	state.layout[0] = {"id": "assembly_table", "x": 5, "z": 5, "turns": 0}
	state.layout[1] = {"id": "shelf", "x": 5, "z": 4, "turns": 0}
	_expect(grid.preview(state.layout, table, 5, 5, 0, -1, 0)["ok"],
		"ignoring itself, the piece does not collide with its own cells")
	_expect(grid.rotate_piece(state, 0)["ok"], "the shelf one row above is not in the way")
	state.layout[1] = {"id": "shelf", "x": 5, "z": 6, "turns": 0}
	state.layout[0] = {"id": "assembly_table", "x": 5, "z": 5, "turns": 0}
	var blocked: Dictionary = grid.rotate_piece(state, 0)
	_expect(not blocked["ok"] and blocked["reason"] == BuildPlacement.REASON_OVERLAP,
		"a rotation over another piece is refused")
	_expect(state.layout[0]["turns"] == 0, "the piece keeps its rotation")

	var moved: Dictionary = grid.move_piece(state, 0, 6, 5)
	_expect(moved["ok"] and state.layout[0]["x"] == 6, "moving one cell right overlaps only itself")
	_expect(not grid.move_piece(state, 0, 11, 5)["ok"] and state.layout[0]["x"] == 6,
		"moving out of the floor is refused")
	var fixed: Dictionary = grid.move_piece(state, 0, 1, 1)
	_expect(not fixed["ok"] and fixed["reason"] == BuildPlacement.REASON_FIXED,
		"moving over a fixed area is refused")
	var over: Dictionary = grid.move_piece(state, 0, 5, 6)
	_expect(not over["ok"] and over["reason"] == BuildPlacement.REASON_OVERLAP,
		"moving over another piece is refused")
	_expect(state.layout[0]["z"] == 5 and state.money == money, "refusals and moves cost nothing")
	_expect(not grid.move_piece(state, 9, 3, 3)["ok"], "bad index on move")
	_expect(not grid.rotate_piece(state, -1)["ok"], "bad index on rotate")

	var refund: int = grid.sell_piece(state, 1)
	_expect(refund == shelf.refund() and state.layout.size() == 1, "selling removes the piece")
	_expect(state.money == money + refund, "selling pays the partial refund")
	_expect(refund < shelf.price, "the refund is partial")
	_expect(grid.sell_piece(state, 5) == -1 and state.layout.size() == 1, "bad index on sell")

	state.reset()
	if _failures == 0:
		print("PASS: placed pieces rotate, move and sell with the same checks as placing")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
