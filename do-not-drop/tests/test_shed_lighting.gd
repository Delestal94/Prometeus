extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_lighting.gd
##
## Lighting that follows the shed (expansion D-0913, ShedLighting and CompanyShed):
## - every stage has lamps and no dark floor cell, and the lamps grow with the stage;
## - no cell is reached by more omni lights than the renderer can use (SHED_MAX_LIGHTS_PER_POINT);
## - a packing table gets a task lamp over its middle, which follows it when it is moved or turned,
##   and other pieces (shelves, the dispatch zone) get none; junk layout entries are ignored;
## - the lamps are the same for the same stage and layout (no roll, no order of a Dictionary);
## - a grid with a gap in the ceiling grid is reported as dark cells (the check can fail);
## - CompanyShed hangs one OmniLight3D per lamp, under the 4 m walls, and redraws them with the layout
##   (move a table and its task lamp moves; the old lamps are freed, not stacked).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_check_stages()
	_check_task_lamps()
	_check_dark_detection()
	await _check_shed(state)
	if _failures == 0:
		print("PASS: the shed lamps leave no dark corner and follow the layout")
	quit(_failures)


func _check_stages() -> void:
	var previous: int = 0
	for stage: int in WarehouseStages.stage_count():
		var grid: Vector2i = WarehouseStages.grid_size_for(stage)
		var lamps: Array[Dictionary] = ShedLighting.ceiling_lamps(grid)
		_expect(lamps.size() >= previous and not lamps.is_empty(), "stage %d has %d lamps" % [stage, lamps.size()])
		previous = lamps.size()
		_expect(ShedLighting.dark_cells(grid, lamps).is_empty(), "stage %d has no dark cell" % stage)
		_expect(ShedLighting.max_overlap(grid, lamps) <= CompanyTuning.SHED_MAX_LIGHTS_PER_POINT,
			"stage %d keeps the lights per cell under the limit" % stage)
		_expect(ShedLighting.problems(grid, []).is_empty(), "stage %d has no problems (%s)"
			% [stage, ShedLighting.problems(grid, [])])
		for lamp: Dictionary in lamps:
			var at: Vector2 = lamp["at"]
			_expect(at.x > 0.0 and at.x < grid.x and at.y > 0.0 and at.y < grid.y, "stage %d lamp %s is over the floor" % [stage, at])
	_expect(ShedLighting.ceiling_lamps(WarehouseStages.grid_size_for(3)).size()
		> ShedLighting.ceiling_lamps(WarehouseStages.grid_size_for(0)).size(), "a bigger shed has more lamps")
	_expect(ShedLighting.ceiling_lamps(Vector2i(12, 8)).size() == 2, "the small shed has two lamps")
	_expect(ShedLighting.ceiling_lamps(Vector2i(12, 8)) == ShedLighting.ceiling_lamps(Vector2i(12, 8)),
		"the same floor gives the same lamps")


func _check_task_lamps() -> void:
	var layout: Array = [
		{"id": "assembly_table", "x": 10, "z": 2, "turns": 0},
		{"id": "shelf", "x": 0, "z": 1, "turns": 1},
		{"id": "dispatch_zone", "x": 7, "z": 0, "turns": 0},
		{"id": "nonsense", "x": 3, "z": 3, "turns": 0},
		"junk",
	]
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	var tasks: Array[Dictionary] = ShedLighting.task_lamps(layout)
	_expect(tasks.size() == 1, "only the packing table gets a task lamp (%d)" % tasks.size())
	if tasks.is_empty():
		return
	_expect(tasks[0]["at"] == Vector2(10, 2) + Vector2(table.footprint) * 0.5, "the task lamp is over the table's middle")
	_expect(tasks[0]["kind"] == ShedLighting.KIND_TASK, "it is a task lamp")
	layout[0] = {"id": "assembly_table", "x": 4, "z": 5, "turns": 1}
	var moved: Array[Dictionary] = ShedLighting.task_lamps(layout)
	_expect(moved[0]["at"] == Vector2(4, 5) + Vector2(table.footprint_for(1)) * 0.5, "moved and turned, the lamp follows")
	var all: Array[Dictionary] = ShedLighting.lamps_for(Vector2i(12, 8), layout)
	_expect(all.size() == ShedLighting.ceiling_lamps(Vector2i(12, 8)).size() + 1, "lamps_for adds the task lamp to the ceiling")
	_expect(ShedLighting.problems(Vector2i(12, 8), layout).is_empty(), "the small shed with a table has no problems")


func _check_dark_detection() -> void:
	var grid := Vector2i(24, 16)
	var lamps: Array[Dictionary] = ShedLighting.ceiling_lamps(grid)
	lamps.remove_at(0)
	_expect(not ShedLighting.dark_cells(grid, lamps).is_empty(), "a missing lamp leaves dark cells")
	_expect(ShedLighting.dark_cells(grid, lamps).has(Vector2i(0, 0)), "...the corner under it among them")
	var crowded: Array[Dictionary] = ShedLighting.ceiling_lamps(grid)
	for i: int in 10:
		crowded.append(ShedLighting.task_lamps([{"id": "assembly_table", "x": 12, "z": 8, "turns": 0}])[0])
	_expect(ShedLighting.max_overlap(grid, crowded) > CompanyTuning.SHED_MAX_LIGHTS_PER_POINT, "too many lamps are counted")


func _check_shed(state: Node) -> void:
	state.call(&"new_company", "Light Co")
	var first: Array[Dictionary] = [{"id": "assembly_table", "x": 7, "z": 2, "turns": 0},
		{"id": "shelf", "x": 0, "z": 1, "turns": 1}]
	state.set(&"layout", first)
	var shed := CompanyShed.new()
	root.add_child(shed)
	await process_frame
	var stock := Inventory.new()
	shed.rebuild(state, stock)
	var lights: Node3D = shed.get_node_or_null(^"Lights")
	_expect(lights != null, "the shed has a Lights node")
	if lights == null:
		shed.queue_free()
		return
	var expected: int = ShedLighting.lamps_for(shed.grid, state.get(&"layout")).size()
	_expect(lights.get_child_count() == expected, "one OmniLight3D per lamp (%d of %d)" % [lights.get_child_count(), expected])
	for child: Node in lights.get_children():
		_expect(child is OmniLight3D and (child as Node3D).position.y < CompanyShed.WALL_HEIGHT, "%s is a light under the walls" % child.name)
	var task_before: Vector3 = _task_position(lights)
	var table: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
	_expect(task_before.distance_to(shed.cell_to_local(Vector2(7, 2) + Vector2(table.footprint) * 0.5,
		CompanyTuning.SHED_LAMP_HEIGHT_M)) < 0.001, "the task lamp hangs over the table")
	var second: Array[Dictionary] = [{"id": "assembly_table", "x": 2, "z": 5, "turns": 0}]
	state.set(&"layout", second)
	shed.rebuild(state, stock)
	lights = shed.get_node(^"Lights")
	await process_frame
	var lamp_count: int = 0
	for child: Node in shed.get_children():
		if child.name.begins_with("Lights") and not child.is_queued_for_deletion():
			lamp_count += 1
	_expect(lamp_count == 1, "the old lights are freed, not stacked (%d)" % lamp_count)
	_expect(_task_position(lights).distance_to(task_before) > 1.0, "moving the table moved its lamp")
	shed.queue_free()


func _task_position(lights: Node3D) -> Vector3:
	for child: Node in lights.get_children():
		if child.name.begins_with("Task"):
			return (child as Node3D).position
	return Vector3(INF, INF, INF)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
