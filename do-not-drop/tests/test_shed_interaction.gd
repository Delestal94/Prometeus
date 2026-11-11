extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shed_interaction.gd
##
## Using the pieces of the company's shed (expansion D-0914 "interacción con objetos colocados igual
## que con los fijos"; ShedPiecePoint, CompanyShed):
## - every shelf and packing table of the layout has one use point, by its uid, on the interaction
##   layer with a shape, with the prompt of its role; a plain block has none; a dispatch zone has a
##   DispatchStation instead (D-0310.b, test_company_dispatch_station), not a use point;
## - a piece the crew places gets the same point as one of the default layout, and the point is the
##   same in kind (class, layer, shape, prompt) for placed and default alike;
## - the point stands on walkable floor in front of its piece, for the four turns: inside the floor,
##   off every piece's footprint, so the player can see it and reach it;
## - moving, turning or selling a piece moves or removes its point on the next draw (no point of a
##   sold piece stays, none is doubled);
## - using a point reports who used which piece (used / CompanyShed.piece_used with uid, role and
##   peer) and refuses nothing for a placed piece that the default one allows.

var _failures: int = 0
var _used: Array[Array] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data: DefaultShed = DefaultShed.load_default()
	var state := DefaultShed.ScratchState.new()
	data.apply_to(state)
	var shed := CompanyShed.new()
	root.add_child(shed)
	shed.piece_used.connect(func(uid: StringName, role: StringName, peer: int) -> void:
		_used.append([uid, role, peer]))
	shed.rebuild(state, state.stock())
	await process_frame

	_check_default(shed, state)
	await _check_placed(shed, state)
	_check_use(shed)
	shed.free()
	if _failures == 0:
		print("PASS: every workable piece, placed or default, has its use point in front of it")
	quit(_failures)


func _workable(layout: Array) -> int:
	var count: int = 0
	for piece: Dictionary in layout:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece["id"])))
		if def != null and ShedPiecePoint.PROMPT_KEYS.has(def.role):
			count += 1
	return count


func _check_default(shed: CompanyShed, state: DefaultShed.ScratchState) -> void:
	_expect(shed.use_points.size() == _workable(state.layout) and not shed.use_points.is_empty(),
		"One use point per workable piece of the default layout (%d)" % shed.use_points.size())
	for index: int in state.layout.size():
		var uid: StringName = DefaultShed.piece_uid(state.layout, index)
		if shed.dispatch_stations.has(uid):
			_expect(not shed.use_points.has(uid), "%s has a station, not a use point" % uid)
			continue
		var point := shed.use_points.get(uid) as ShedPiecePoint
		_expect(point != null, "%s has a use point" % uid)
		if point != null:
			_check_point(shed, point, state.layout, "default " + String(uid))


## The point is an Interactable on the interaction layer with a shape and a prompt, and it stands on the
## floor, off every piece, inside the shed.
func _check_point(shed: CompanyShed, point: ShedPiecePoint, layout: Array, label: String) -> void:
	_expect(point.collision_layer == Interactable.interaction_layer and point.get_child_count() == 1,
		"%s: on the interaction layer with its shape" % label)
	_expect(not point.get_prompt().is_empty() and point.get_prompt() != String(ShedPiecePoint.PROMPT_KEYS[point.role]),
		"%s: it has a translated prompt" % label)
	var cell := Vector2i(shed.local_to_cell(shed.to_local(point.global_position)).floor())
	_expect(Rect2i(Vector2i.ZERO, shed.grid).has_point(cell), "%s: its point is inside the floor (%s)" % [label, cell])
	for piece: Dictionary in shed.pieces:
		_expect(not (piece["rect"] as Rect2i).has_point(cell),
			"%s: its point is not inside %s" % [label, piece["uid"]])
	_expect(layout.size() > 0, "%s: layout read" % label)


func _check_placed(shed: CompanyShed, state: DefaultShed.ScratchState) -> void:
	var before: int = shed.use_points.size()
	# A shelf of the crew in each of the four turns, in free cells of the floor (stage 0 is 16 x 10 cells).
	for turns: int in 4:
		state.layout.append({"id": "shelf", "uid": "shelf_new_%d" % turns, "x": 3 + turns * 3, "z": 6, "turns": turns})
	shed.rebuild(state, state.stock())
	await process_frame
	_expect(shed.use_points.size() == before + 4 and shed.use_points.size() == _workable(state.layout),
		"Four placed shelves add four points (%d -> %d)" % [before, shed.use_points.size()])
	for turns: int in 4:
		var uid := StringName("shelf_new_%d" % turns)
		var point := shed.use_points.get(uid) as ShedPiecePoint
		_expect(point != null, "The placed %s has a use point" % uid)
		if point != null:
			_check_point(shed, point, state.layout, "placed " + String(uid))
	var default_point := shed.use_points[&"shelf_1"] as ShedPiecePoint
	var placed_point := shed.use_points[&"shelf_new_0"] as ShedPiecePoint
	_expect(default_point.get_prompt() == placed_point.get_prompt()
		and default_point.collision_layer == placed_point.collision_layer
		and ((default_point.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius
		== ((placed_point.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius,
		"A placed shelf's point is the same as a default shelf's")

	# Moving a piece moves its point; selling removes it, and nothing is doubled.
	var moved_from: Vector3 = placed_point.global_position
	state.layout[state.layout.size() - 4]["x"] = 1
	state.layout[state.layout.size() - 4]["z"] = 8
	state.layout.remove_at(state.layout.size() - 1)
	shed.rebuild(state, state.stock())
	await process_frame
	var moved := shed.use_points.get(&"shelf_new_0") as ShedPiecePoint
	_expect(moved != null and not moved.global_position.is_equal_approx(moved_from),
		"Moving a piece moves its point")
	_expect(not shed.use_points.has(&"shelf_new_3"), "Selling a piece removes its point")
	_expect(shed.use_points.size() == _workable(state.layout), "No point is doubled or left behind")
	var points: int = 0
	for child: Node in shed.get_children():
		if child is ShedPiecePoint:
			points += 1
	_expect(points == shed.use_points.size(), "The shed holds exactly its use points as children (%d)" % points)


func _check_use(shed: CompanyShed) -> void:
	var stand_in := Node3D.new()
	root.add_child(stand_in)
	stand_in.set_multiplayer_authority(7)
	for uid: StringName in [&"shelf_1", &"table_1", &"shelf_new_1"]:
		var point := shed.use_points.get(uid) as ShedPiecePoint
		if point == null:
			_expect(false, "%s exists to be used" % uid)
			continue
		_used.clear()
		point.interact(stand_in)
		_expect(_used.size() == 1 and _used[0][0] == uid and _used[0][1] == point.role and _used[0][2] == 7,
			"Using %s reports its uid, role and the peer (%s)" % [uid, _used])
	stand_in.free()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
