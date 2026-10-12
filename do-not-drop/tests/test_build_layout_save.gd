extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_layout_save.gd
##
## Saving the shed layout (expansion D-0909, BuildLayoutSave + CompanyState.from_dict):
## - a layout built with BuildPlacement survives to_dict -> JSON -> from_dict identical, with
##   integer fields (JSON gives floats) and the same pieces in the same order;
## - sanitize() drops what the build mode would refuse: unknown piece, out of the grid, over the
##   dock, overlapping an earlier piece, a missing or non-numeric position, entries that are not
##   dictionaries; the good pieces around them stay;
## - turns are folded to 0-3 and a missing turns means 0;
## - the saved stage decides the grid: a piece outside the small shed loads on the medium one;
## - a layout that is not an Array becomes empty.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_round_trip()
	_test_drops_invalid()
	_test_turns()
	_test_stage_decides_grid()
	_test_not_an_array()
	if _failures == 0:
		print("PASS: saved shed layouts load as the build mode would have made them")
	quit(_failures)


func _test_round_trip() -> void:
	var state: Node = _new_state()
	state.new_company("Layout SA")
	state.money = 5000
	var grid := BuildPlacement.new()
	WarehouseStages.apply_to(0, grid)
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var shelf: PlaceableDefinition = PlaceableShop.definition(&"shelf")
	_expect(bool(grid.place(state, table, 1, 2, 0)["ok"]), "table placed")
	_expect(bool(grid.place(state, shelf, 6, 3, 1)["ok"]), "shelf placed (turned)")
	var json: String = JSON.stringify(state.to_dict())
	var loaded: Node = _new_state()
	_expect(loaded.from_dict(JSON.parse_string(json)), "the save loads")
	_expect(loaded.layout.size() == 2, "both pieces come back")
	_expect(loaded.layout == state.layout, "same pieces in the same order, integer fields")
	_expect(loaded.layout[0]["x"] is int and loaded.layout[1]["turns"] is int,
		"coordinates and turns are ints after the JSON trip")
	state.free()
	loaded.free()


func _test_drops_invalid() -> void:
	var raw: Array = [
		{"id": "shelf", "x": 1.0, "z": 1.0, "turns": 0.0},
		{"id": "ghost_machine", "x": 3, "z": 3, "turns": 0},
		{"id": "shelf", "x": 11, "z": 1, "turns": 0},
		{"id": "assembly_table", "x": 4, "z": 6, "turns": 0},
		{"id": "fridge", "x": 1, "z": 1, "turns": 0},
		{"id": "fridge", "x": "left", "z": 4},
		{"id": "fridge", "z": 4},
		{"x": 2, "z": 2},
		"junk",
		7,
		{"id": "assembly_table", "x": 8, "z": 4, "turns": 0},
	]
	var kept: Array[Dictionary] = BuildLayoutSave.sanitize(raw, 0)
	_expect(kept.size() == 2, "only the two good pieces stay (got %d)" % kept.size())
	if kept.size() == 2:
		_expect(kept[0]["id"] == "shelf" and kept[0]["x"] == 1, "first good piece kept")
		_expect(kept[1]["id"] == "assembly_table" and kept[1]["x"] == 8, "last good piece kept")


func _test_turns() -> void:
	var kept: Array[Dictionary] = BuildLayoutSave.sanitize([
		{"id": "shelf", "x": 0, "z": 0, "turns": 5},
		{"id": "shelf", "x": 0, "z": 3},
		{"id": "shelf", "x": 4, "z": 3, "turns": -1},
	], 0)
	_expect(kept.size() == 3, "all three fit")
	if kept.size() == 3:
		_expect(kept[0]["turns"] == 1, "turns 5 folds to 1")
		_expect(kept[1]["turns"] == 0, "missing turns is 0")
		_expect(kept[2]["turns"] == 3, "turns -1 folds to 3")


func _test_stage_decides_grid() -> void:
	var far: Array = [{"id": "shelf", "x": 16, "z": 9, "turns": 0}]
	_expect(BuildLayoutSave.sanitize(far, 0).is_empty(), "outside the small shed: dropped")
	_expect(BuildLayoutSave.sanitize(far, 1).size() == 1, "inside the medium shed: kept")
	var state: Node = _new_state()
	state.from_dict({"warehouse_stage": 1, "layout": far})
	_expect(state.layout.size() == 1, "from_dict reads the stage before the layout")
	state.free()


func _test_not_an_array() -> void:
	_expect(BuildLayoutSave.sanitize(null, 0).is_empty(), "null layout is empty")
	_expect(BuildLayoutSave.sanitize({"id": "shelf"}, 0).is_empty(), "dictionary layout is empty")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)


func _new_state() -> Node:
	return load("res://scripts/core/company/company_state.gd").new()
