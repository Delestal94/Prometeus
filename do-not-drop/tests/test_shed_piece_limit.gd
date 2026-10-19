extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_piece_limit.gd
##
## Piece limit per shed stage (expansion D-0915, BuildPlacement and WarehouseStages):
## - every stage has a limit and a bigger stage never has a smaller one;
## - `apply_to` hands the limit to BuildPlacement; one piece over it is red with `piece_limit`;
## - moving, turning and selling are not stopped by the limit, and selling frees a slot;
## - a shed filled to its limit, drawn by CompanyShed, stays under the node and collider budget
##   (the measurement: `print` of the counts at each stage).

## What a full shed may cost, per stage: scene nodes and physics bodies under the CompanyShed.
const NODE_BUDGET: Array[int] = [300, 450, 650, 900]
const BODY_BUDGET: Array[int] = [40, 70, 110, 150]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_check_limits()
	_check_refusal(state)
	await _check_budget(state)
	if _failures == 0:
		print("PASS: every stage holds a limited number of pieces and a full shed fits the budget")
	quit(_failures)


func _check_limits() -> void:
	var previous: int = 0
	for stage: int in WarehouseStages.stage_count():
		var limit: int = WarehouseStages.max_pieces_for(stage)
		_expect(limit > previous, "stage %d holds more than the one before (%d)" % [stage, limit])
		previous = limit
		var grid := BuildPlacement.new()
		WarehouseStages.apply_to(stage, grid)
		_expect(grid.max_pieces == limit, "apply_to gives stage %d its limit" % stage)
	_expect(WarehouseStages.max_pieces_for(99) == WarehouseStages.max_pieces_for(3), "a stage past the end clamps")
	_expect(BuildPlacement.new().max_pieces == 0, "a bare BuildPlacement has no limit")


func _check_refusal(state: Node) -> void:
	state.call(&"new_company", "Limit Co")
	state.set(&"money", 100000)
	var grid := BuildPlacement.new(Vector2i(12, 8))
	grid.max_pieces = 3
	var fridge: PlaceableDefinition = PlaceableShop.definition(&"fridge")
	for i: int in 3:
		_expect(bool(grid.place(state, fridge, i * 2, 0)["ok"]), "piece %d fits under the limit" % i)
	var layout: Array = state.get(&"layout")
	var over: Dictionary = grid.place(state, fridge, 0, 4)
	_expect(not bool(over["ok"]) and over["reason"] == BuildPlacement.REASON_PIECE_LIMIT,
		"the fourth piece is red with piece_limit (%s)" % over["reason"])
	_expect(layout.size() == 3, "nothing was added or bought")
	_expect(grid.move_piece(state, 0, 0, 5)["ok"], "moving is not stopped by the limit")
	_expect(grid.rotate_piece(state, 1)["ok"], "turning is not stopped by the limit")
	_expect(grid.sell_piece(state, 2) >= 0, "selling works at the limit")
	_expect(bool(grid.place(state, fridge, 4, 4)["ok"]), "selling freed a slot")
	grid.max_pieces = 0
	_expect(bool(grid.place(state, fridge, 6, 4)["ok"]), "no limit: no refusal")


## Fills the stage with a mix of shelves, tables and fridges up to its limit, draws it and counts.
func _check_budget(state: Node) -> void:
	var defs: Array[PlaceableDefinition] = [PlaceableShop.definition(&"shelf"),
		PlaceableShop.definition(&"assembly_table"), PlaceableShop.definition(&"fridge"),
		PlaceableShop.definition(&"dispatch_zone")]
	for stage: int in WarehouseStages.stage_count():
		state.call(&"new_company", "Budget Co")
		state.set(&"money", 1000000)
		state.set(&"warehouse_stage", stage)
		var grid := BuildPlacement.new()
		WarehouseStages.apply_to(stage, grid)
		var size: Vector2i = grid.grid_size
		var kind: int = 0
		var limit: int = WarehouseStages.max_pieces_for(stage)
		for z: int in size.y:
			for x: int in size.x:
				if (state.get(&"layout") as Array).size() >= limit:
					break
				var result: Dictionary = grid.place(state, defs[kind % defs.size()], x, z, 0, true)
				kind += 1 if bool(result["ok"]) else 0
		var placed: int = (state.get(&"layout") as Array).size()
		_expect(placed == WarehouseStages.max_pieces_for(stage),
			"stage %d fills to its limit (%d of %d)" % [stage, placed, WarehouseStages.max_pieces_for(stage)])
		var shed := CompanyShed.new()
		root.add_child(shed)
		await process_frame
		shed.rebuild(state, Inventory.new())
		var nodes: int = _count(shed, false)
		var bodies: int = _count(shed, true)
		print("D-0915 stage %d: %d pieces, %d nodes, %d bodies" % [stage, placed, nodes, bodies])
		_expect(nodes <= NODE_BUDGET[stage], "stage %d nodes %d <= %d" % [stage, nodes, NODE_BUDGET[stage]])
		_expect(bodies <= BODY_BUDGET[stage], "stage %d bodies %d <= %d" % [stage, bodies, BODY_BUDGET[stage]])
		shed.queue_free()
		await process_frame


func _count(node: Node, bodies_only: bool) -> int:
	var total: int = 1 if (not bodies_only or node is CollisionObject3D) else 0
	for child: Node in node.get_children():
		total += _count(child, bodies_only)
	return total


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
