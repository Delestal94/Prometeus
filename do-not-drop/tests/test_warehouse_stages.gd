extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_warehouse_stages.gd
##
## Shed stages (expansion D-0905, WarehouseStages):
## - four stages whose grid grows and whose prices go up; the first one is free;
## - expand() charges the price, moves to the next stage and keeps the placed pieces untouched;
## - it is refused (nothing changes) without money, at the last stage and above the unlocked stage;
## - apply_to() resizes BuildPlacement and BuildMode: a spot out of the small floor is green after;
## - the dock and the exit (D-0906) stay free at every stage: nothing can be placed on them, the
##   gate openings sit in the wall line, and a piece next to them is still green;
## - the walls of a stage surround its floor, and the stage survives a save round trip.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	state.new_company("Stage Co")
	_expect(WarehouseStages.stage_count() == 4, "four stages")
	_expect(state.warehouse_stage == 0 and WarehouseStages.price_for(0) == 0, "starts small and free")
	for i: int in range(1, 4):
		var bigger: Vector2i = WarehouseStages.grid_size_for(i)
		var smaller: Vector2i = WarehouseStages.grid_size_for(i - 1)
		_expect(bigger.x > smaller.x and bigger.y > smaller.y, "stage %d is bigger" % i)
		_expect(WarehouseStages.price_for(i) > WarehouseStages.price_for(i - 1), "stage %d costs more" % i)
	_expect(WarehouseStages.floor_size_m(0) == Vector2(12, 8), "small floor in meters")

	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var grid := BuildPlacement.new(WarehouseStages.grid_size_for(0))
	state.money = 5000
	grid.place(state, table, 3, 3)
	var layout_before: Array = state.layout.duplicate(true)
	_expect(not grid.preview(state.layout, table, 14, 10)["ok"], "outside the small floor is red")

	var broke: Dictionary = WarehouseStages.expand(state)
	_expect(broke["ok"] and state.warehouse_stage == 1, "expanding with money works")
	_expect(state.money == 5000 - table.price - WarehouseStages.price_for(1), "it charges the price")
	_expect(state.ledger_total(WarehouseStages.REASON_EXPAND) == -WarehouseStages.price_for(1),
		"the charge goes in the ledger")
	_expect(state.layout == layout_before, "placed pieces are untouched")
	WarehouseStages.apply_to(state.warehouse_stage, grid)
	_expect(grid.grid_size == Vector2i(18, 12), "the placement grid grew")
	_expect(grid.preview(state.layout, table, 14, 10)["ok"], "the same spot is green on the medium floor")

	var money: int = state.money
	var refused: Dictionary = WarehouseStages.expand(state)
	_expect(not refused["ok"] and refused["reason"] == WarehouseStages.REFUSAL_NO_MONEY, "no money is refused")
	_expect(state.warehouse_stage == 1 and state.money == money, "a refusal changes nothing")
	state.money = 100000
	var locked: Dictionary = WarehouseStages.expand(state, 1)
	_expect(locked["reason"] == WarehouseStages.REFUSAL_LOCKED and state.warehouse_stage == 1,
		"above the unlocked stage is refused")
	_expect(WarehouseStages.expand(state, 2)["ok"] and state.warehouse_stage == 2, "unlocked stage works")
	_expect(WarehouseStages.expand(state)["ok"] and state.warehouse_stage == 3, "last stage reached")
	var last: Dictionary = WarehouseStages.expand(state)
	_expect(not last["ok"] and last["reason"] == WarehouseStages.REFUSAL_MAX_STAGE
			and state.warehouse_stage == 3, "no stage after the last")

	var mode := BuildMode.new()
	var size: Vector2i = WarehouseStages.apply_to(3, grid, mode)
	_expect(size == Vector2i(32, 20) and mode.grid_size == size and grid.grid_size == size,
		"apply_to resizes mode and placement")
	var walls: Array[Rect2i] = WarehouseStages.wall_rects(3)
	_expect(walls.size() == 4, "four walls")
	for wall: Rect2i in walls:
		_expect(not wall.intersects(Rect2i(Vector2i.ZERO, size)), "a wall stays off the floor")

	_check_fixed_areas(grid, table)

	var saved: Dictionary = state.to_dict()
	state.reset()
	_expect(state.warehouse_stage == 0, "reset goes back to small")
	state.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_expect(state.warehouse_stage == 3, "the stage survives a JSON round trip")
	state.from_dict({"company_name": "x", "warehouse_stage": 99})
	_expect(state.warehouse_stage == 3, "a stage out of range is clamped")
	state.from_dict({"company_name": "x"})
	_expect(state.warehouse_stage == 0, "a save without stage starts small")
	state.reset()
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _check_fixed_areas(grid: BuildPlacement, table: PlaceableDefinition) -> void:
	for stage: int in WarehouseStages.stage_count():
		var size: Vector2i = WarehouseStages.grid_size_for(stage)
		var floor_rect := Rect2i(Vector2i.ZERO, size)
		var dock: Rect2i = WarehouseStages.dock_rect(stage)
		var door: Rect2i = WarehouseStages.exit_rect(stage)
		_expect(floor_rect.encloses(dock) and floor_rect.encloses(door), "stage %d areas are on the floor" % stage)
		_expect(not dock.intersects(door), "stage %d dock and exit do not overlap" % stage)
		_expect(dock.end.y == size.y, "stage %d dock touches the south wall" % stage)
		_expect(door.position.y == 0, "stage %d exit touches the north wall" % stage)
		var gates: Array[Rect2i] = WarehouseStages.gate_rects(stage)
		_expect(gates.size() == 2 and not gates[0].intersects(floor_rect) and not gates[1].intersects(floor_rect),
			"stage %d gates are in the wall line" % stage)
		_expect(gates[0].position.x == dock.position.x and gates[1].position.x == door.position.x,
			"stage %d gates line up with their areas" % stage)
		WarehouseStages.apply_to(stage, grid)
		_expect(grid.fixed_blocked.size() == 2, "stage %d apply_to sets the fixed areas" % stage)
		var on_dock: Dictionary = grid.preview([], table, dock.position.x, dock.position.y)
		_expect(not on_dock["ok"] and on_dock["reason"] == BuildPlacement.REASON_FIXED, "stage %d dock is red" % stage)
		var on_exit: Dictionary = grid.preview([], table, door.position.x, door.position.y)
		_expect(not on_exit["ok"] and on_exit["reason"] == BuildPlacement.REASON_FIXED, "stage %d exit is red" % stage)
		var beside: Dictionary = grid.preview([], table, dock.end.x, dock.position.y)
		_expect(beside["ok"], "stage %d next to the dock is green" % stage)
