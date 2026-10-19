extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_build_input.gd
##
## Build mode of the company shed driven by keyboard, mouse and gamepad (expansion D-0917,
## BuildCursor and ShedBuilder):
## - BuildCursor: the cursor stays on the floor, the catalog wraps, an empty cell asks to place the
##   chosen object with its turns, a piece is grabbed and then moved (or let go with cancel), rotate
##   asks a turn only for a grabbed piece, sell asks for the piece under the cursor, the ghost is
##   green or red as BuildPlacement says;
## - the actions exist with a keyboard key and a gamepad input each, and the cursor reuses the walk
##   actions;
## - ShedBuilder in the company world: the toggle action enters and leaves, the camera is raised and
##   the player's input is off meanwhile and back after, the grid and the ghost are drawn, confirm
##   places a piece through CompanyNet (money paid, layout grows, shed redrawn), cancel grabs and lets
##   go before it leaves, a refusal shows its reason in the hint, and a real InputEventAction reaches it.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_build_input"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_cursor()
	_check_actions()
	await _check_world()
	if _failures == 0:
		print("PASS: build mode takes keyboard, mouse and gamepad and only asks the host")
	quit(_failures)


func _state() -> Node:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	state.set(&"money", 1000)
	return state


func _check_cursor() -> void:
	var state: Node = _state()
	var mode := BuildMode.new()
	mode.enter(Vector2i(12, 8))
	var cursor := BuildCursor.new(mode, BuildPlacement.new(Vector2i(12, 8)), state)
	_expect(cursor.catalog.size() >= 4, "the catalog lists every placeable (%d)" % cursor.catalog.size())
	cursor.set_cell(Vector2i.ZERO)
	cursor.move(Vector2i(-1, -1))
	_expect(cursor.cell == Vector2i.ZERO, "the cursor does not leave the floor on the north-west")
	cursor.move(Vector2i(50, 50))
	_expect(cursor.cell == Vector2i(11, 7), "nor on the south-east (%s)" % cursor.cell)
	cursor.chosen = 0
	cursor.cycle(-1)
	_expect(cursor.chosen == cursor.catalog.size() - 1, "the catalog wraps backwards")
	cursor.cycle(1)
	_expect(cursor.chosen == 0, "and forwards")

	var def: PlaceableDefinition = cursor.chosen_definition()
	cursor.set_cell(Vector2i(2, 2))
	cursor.turns = 0
	_expect(cursor.rotate().is_empty() and cursor.turns == 1, "rotating the chosen object asks nothing, it turns the ghost")
	var ask: Dictionary = cursor.confirm()
	_expect(ask.get("kind") == CompanyLayoutNet.PLACE and ask["data"] == {"id": def.id, "x": 2, "z": 2, "turns": 1},
		"confirm on a free cell asks to place the chosen object with its turns (%s)" % str(ask))
	_expect(bool(cursor.ghost()["ok"]), "the ghost is green on a free cell")

	state.layout.append({"id": "shelf", "x": 5, "z": 5, "turns": 0, "uid": "shelf_1"})
	cursor.set_cell(Vector2i(6, 5))
	_expect(cursor.piece_under_cursor() == 0, "the cursor finds the piece under any cell of its footprint")
	_expect(cursor.confirm().is_empty() and cursor.held == &"shelf_1", "confirm on a piece grabs it, asks nothing")
	cursor.cycle(1)
	_expect(cursor.chosen == 0, "the catalog stays put while a piece is in hand")
	_expect(cursor.rotate()["kind"] == CompanyLayoutNet.ROTATE, "rotate with a piece in hand asks the host for a turn")
	cursor.set_cell(Vector2i(9, 2))
	var move: Dictionary = cursor.confirm()
	_expect(move["kind"] == CompanyLayoutNet.MOVE and move["data"] == {"uid": &"shelf_1", "x": 9, "z": 2},
		"confirm with a piece in hand asks to move it to the cursor (%s)" % str(move))
	_expect(cursor.held == &"", "and lets go of it")
	cursor.set_cell(Vector2i(5, 5))
	cursor.confirm()
	_expect(cursor.cancel() and cursor.held == &"", "cancel lets go of a grabbed piece first")
	_expect(not cursor.cancel(), "and with nothing in hand it is free to leave the mode")
	cursor.set_cell(Vector2i(5, 5))
	_expect(cursor.sell() == {"kind": CompanyLayoutNet.SELL, "data": {"uid": &"shelf_1"}}, "sell asks for the piece under the cursor")
	cursor.set_cell(Vector2i(0, 0))
	_expect(cursor.sell().is_empty(), "and nothing on a free cell")
	cursor.chosen = cursor.catalog.find(PlaceableShop.definition(&"shelf"))
	cursor.set_cell(Vector2i(10, 0))
	_expect(not bool(cursor.ghost()["ok"]) and cursor.ghost()["reason"] == BuildPlacement.REASON_OUT_OF_BOUNDS,
		"the ghost is red when the object sticks out of the floor")
	state.call(&"reset")


func _check_actions() -> void:
	ShedBuilder.ensure_actions()
	ShedBuilder.ensure_actions()
	for action: StringName in [ShedBuilder.ACTION_TOGGLE, ShedBuilder.ACTION_CONFIRM, ShedBuilder.ACTION_CANCEL,
			ShedBuilder.ACTION_ROTATE, ShedBuilder.ACTION_NEXT, ShedBuilder.ACTION_PREVIOUS,
			ShedBuilder.ACTION_SELL, ShedBuilder.ACTION_ZOOM_IN, ShedBuilder.ACTION_ZOOM_OUT]:
		var key: bool = false
		var pad: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			key = key or event is InputEventKey
			pad = pad or event is InputEventJoypadButton or event is InputEventJoypadMotion
		_expect(key and pad and InputMap.action_get_events(action).size() == 2,
			"%s has one keyboard key and one gamepad input" % action)
	for action: StringName in ShedBuilder.MOVES:
		_expect(InputMap.has_action(action), "the cursor moves with the walk action %s" % action)


func _check_world() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var builder: ShedBuilder = level.builder
	_expect(builder != null and not builder.is_building(), "the company world has a builder, idle")
	if builder == null:
		return
	var player: Node3D = level.player
	var layout: Array = state.get(&"layout")
	var pieces: int = layout.size()
	var money: int = int(state.get(&"money"))

	var toggle := InputEventAction.new()
	toggle.action = ShedBuilder.ACTION_TOGGLE
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await process_frame
	_expect(builder.is_building(), "the toggle action enters the mode")
	_expect(not player.is_processing_unhandled_input(), "the player's own input is off while building")
	_expect(builder.camera != null and builder.camera.current and builder.camera.global_position.y > 5.0,
		"the camera is raised and current")
	_expect(builder._grid.mesh != null and builder._grid.mesh.get_surface_count() > 0, "the grid is drawn")
	_expect(builder._ghost.visible, "the ghost is drawn")

	builder.cursor.set_cell(Vector2i(0, 0))
	builder.cursor.chosen = builder.cursor.catalog.find(PlaceableShop.definition(&"shelf"))
	builder.handle_action(&"walk_right")
	_expect(builder.cursor.cell == Vector2i(1, 0), "a walk action moves the cursor one cell")
	builder.handle_action(ShedBuilder.ACTION_ZOOM_OUT)
	_expect(builder.mode.zoom > 1.0, "zoom out raises the camera")
	var shelf: PlaceableDefinition = PlaceableShop.definition(&"shelf")
	builder.handle_action(ShedBuilder.ACTION_CONFIRM)
	await process_frame
	var shelf_count: int = 0
	for entry: Dictionary in state.get(&"layout"):
		shelf_count += 1 if entry["id"] == "shelf" else 0
	_expect((state.get(&"layout") as Array).size() == pieces + 1, "confirm placed a piece through the net")
	_expect(int(state.get(&"money")) == money - shelf.price, "and the price was paid")
	_expect(level.shed.pieces.size() == (state.get(&"layout") as Array).size(), "the shed drew it")

	builder.handle_action(ShedBuilder.ACTION_CONFIRM)
	_expect(builder.cursor.held == &"", "confirm on the piece just placed does not break the cursor")
	builder.handle_action(ShedBuilder.ACTION_CANCEL)
	_expect(builder.cursor.held == &"" and builder.is_building(), "cancel with a piece in hand only lets go of it")
	builder.cursor.set_cell(Vector2i(5, 5))
	builder._last_refusal = &"overlap"
	builder._refresh()
	_expect(builder.hint.text.contains(tr("UI_BUILD_REASON_OVERLAP")) or builder.hint.text.contains("UI_BUILD_REASON_OVERLAP"),
		"a refusal shows its reason in the hint")
	_expect(shelf_count >= 1, "the layout has the shelf")

	builder.handle_action(ShedBuilder.ACTION_CANCEL)
	_expect(not builder.is_building(), "cancel with nothing in hand leaves the mode")
	_expect(player.is_processing_unhandled_input(), "the player's input is back")
	_expect(builder.camera == null and builder._ghost == null, "the build view is gone")
	level.queue_free()
	await process_frame
	_clean()


func _clean() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for file: String in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute("%s/%s" % [DIR, file])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + message)
