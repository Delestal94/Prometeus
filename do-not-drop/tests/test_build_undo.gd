extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_undo.gd
##
## Undoing the last placement of a warehouse object (expansion D-0916, BuildPlacement):
## - undo_last_placement() removes the newest piece placed and gives the full price back;
## - it goes back one placement at a time, newest first, and -1 when nothing is left;
## - a piece moved or turned after placing is still found; one sold in between is skipped;
## - pieces that were never placed through place() (loaded layout) are not undoable.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Undo Co")
	state.money = 1000
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var shelf: PlaceableDefinition = PlaceableShop.definition(&"shelf")
	var grid := BuildPlacement.new(Vector2i(12, 8))
	state.layout.append({"id": "shelf", "x": 0, "z": 0, "turns": 0})
	_expect(grid.undo_last_placement(state) == -1 and not grid.can_undo(state),
		"nothing placed here, nothing to undo")
	_expect(state.layout.size() == 1, "a loaded piece stays")

	grid.place(state, table, 5, 5)
	grid.place(state, shelf, 8, 5)
	var money: int = state.money
	_expect(grid.can_undo(state), "can undo after placing")
	_expect(grid.undo_last_placement(state) == shelf.price, "undo returns the full price")
	_expect(state.money == money + shelf.price, "the wallet got the price back")
	_expect(state.layout.size() == 2, "the newest piece is gone")
	_expect(grid.preview(state.layout, shelf, 8, 5)["ok"], "its cells are free again")

	grid.move_piece(state, 1, 6, 2)
	grid.rotate_piece(state, 1)
	_expect(grid.undo_last_placement(state) == table.price, "a moved and turned piece is undone")
	_expect(state.layout.size() == 1, "only the loaded piece is left")
	_expect(grid.undo_last_placement(state) == -1, "the stack is empty")

	grid.place(state, table, 5, 5)
	grid.place(state, shelf, 8, 5)
	grid.sell_piece(state, 2)
	_expect(grid.undo_last_placement(state) == table.price, "a sold piece is skipped")

	print("test_build_undo: %s" % ("OK" if _failures == 0 else "FAIL"))
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
