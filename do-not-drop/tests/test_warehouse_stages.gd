extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_warehouse_stages.gd
##
## Shed stages (expansion D-0905, WarehouseStages):
## - four stages whose grid grows and whose prices go up; the first one is free;
## - expand() charges the price, moves to the next stage and keeps the placed pieces untouched;
## - it is refused (nothing changes) without money, at the last stage and above the unlocked stage;
## - apply_to() resizes BuildPlacement and BuildMode: a spot out of the small floor is green after;
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
