extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_default_layout.gd
##
## The shed a new company starts with (expansion D-0911 "layout por defecto que ya funciona sin tocar
## nada" and D-0620 "dársena, recepción, racks, armado, despacho"; DefaultShed, CompanyShed,
## data/shed/default_shed.tres):
## - the data is sound (DefaultShed.problems(): every piece fits through the same BuildPlacement the
##   build mode uses, every station can be walked to, the shelf slots and products exist) and applying
##   it twice gives the same layout and stock (no roll, no order of a Dictionary);
## - a new company opens the Modo Empresa root already furnished: at least one packing table, shelves
##   holding the starting stock, pallets waiting in reception (from the supplier calendar) and a
##   dispatch zone, nothing paid (money and wallet history untouched);
## - nothing overlaps, nothing is outside the floor or on the dock and the exit (D-0906), WalkReachability
##   says every piece is reachable and the dock reaches the exit (D-0907), and the player spawns on
##   the dock floor clear of every piece and pallet;
## - the shelves are the shed shelf's model (D-1811, sm_env_shed_shelf: 2 x 2 x 1 m, centred, front on
##   +Z), the crates stand on its real decks and the labels in front of its rails;
## - what is drawn follows the state: a station per table, a label with units per labeled slot that
##   follows the Inventory, a pallet node per pallet:<id>, and a client that only has the snapshot's
##   layout and stock draws the same pieces;
## - the build mode can move a default piece (BuildPlacement.move_piece) and the shed redraws it there,
##   keeping its station and its stock (the piece keeps its uid);
## - a company that already has a layout, a wallet history or stock is left as it is (needs_default());
## - the delivery practice card ("Cómo cuidar la carga", ends "subite a manejar") is not shown to the
##   company's players: there is no vehicle in the shed (the delivery's is test_modal_layers').

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_default_layout"
## The ambient products of the catalog: every one starts on a shelf (the cold ones wait in the pallets).
const SHELVED: Array[StringName] = [&"porcelain_vase", &"antique_lamp", &"glass_tower", &"sourdough",
	&"hen", &"puppy", &"raccoon_cage", &"fireworks_crate"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data: DefaultShed = DefaultShed.load_default()
	_expect(data != null, "data/shed/default_shed.tres loads as a DefaultShed")
	if data == null:
		quit(1)
		return
	_check_data(data)
	await _check_world(data)
	if _failures == 0:
		print("PASS: the default shed is furnished, reachable, free and drawn from the state")
	quit(_failures)


func _check_data(data: DefaultShed) -> void:
	var problems: Array[String] = data.problems()
	_expect(problems.is_empty(), "The default data is sound (%s)" % ", ".join(problems))
	var first := DefaultShed.ScratchState.new()
	var second := DefaultShed.ScratchState.new()
	_expect(DefaultShed.needs_default(first, data), "A fresh company needs the default")
	var report: Dictionary = data.apply_to(first)
	data.apply_to(second)
	_expect((report["refused"] as Array).is_empty() and int(report["placed"]) == data.pieces.size(),
		"Every piece of the data goes in (%s)" % [report])
	_expect(first.layout == second.layout and first.inventory == second.inventory,
		"Applying it twice gives the same layout and stock")
	_expect(not DefaultShed.needs_default(first, data), "...and then the company no longer needs it")
	var sold := DefaultShed.ScratchState.new()
	sold.ledger.append({"amount": 1})
	_expect(not DefaultShed.needs_default(sold, data), "A company with a wallet history is left as it is")
	var played := DefaultShed.ScratchState.new()
	played.layout.append({"id": "shelf", "x": 0, "z": 0, "turns": 0})
	_expect(not DefaultShed.needs_default(played, data), "A company with a layout is left as it is")
	var grown := DefaultShed.ScratchState.new()
	grown.warehouse_stage = 1
	_expect(not DefaultShed.needs_default(grown, data), "A company in another stage is left as it is")
	var roles: Dictionary = {}
	for piece: Dictionary in first.layout:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece["id"])))
		roles[def.role] = int(roles.get(def.role, 0)) + 1
	_expect(int(roles.get(&"assembly", 0)) >= 1 and int(roles.get(&"storage", 0)) >= 1
		and int(roles.get(&"dispatch", 0)) >= 1, "It has a packing table, a shelf and a dispatch zone (%s)" % [roles])


func _check_world(data: DefaultShed) -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var layout: Array = state.get(&"layout")
	var stock: Inventory = state.call(&"stock")
	var stage: int = int(state.get(&"warehouse_stage"))
	var grid: Vector2i = WarehouseStages.grid_size_for(stage)

	# A new company opens furnished, and it cost nothing.
	_expect(layout.size() == data.pieces.size(), "The new company's layout is the default (%d pieces)" % layout.size())
	_expect(int(state.get(&"money")) == CompanyTuning.STARTING_MONEY and (state.get(&"ledger") as Array).is_empty(),
		"Furnishing it moved no money and wrote nothing in the wallet history")
	for product: StringName in SHELVED:
		_expect(stock.count(product) > 0, "%s starts on a shelf (%d units)" % [product, stock.count(product)])
	var pallets: Array[Dictionary] = CompanyShed.pallets_in(stock)
	_expect(not pallets.is_empty(), "A starter pallet waits in reception (%d)" % pallets.size())
	for entry: Dictionary in pallets:
		_expect(str(entry["id"]).begins_with("d%d_" % CompanyTuning.STARTING_DAY),
			"The pallet %s comes from the day-1 supplier truck" % entry["id"])
	_expect(level.net.inventory.to_dict() == stock.to_dict(),
		"CompanyNet starts from that stock (the host's snapshot carries it)")

	# Layout rules: inside, off the fixed areas, apart, reachable, clear spawn.
	var fixed: Array[Rect2i] = WarehouseStages.fixed_rects(stage)
	var rects: Array[Rect2i] = []
	for index: int in layout.size():
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(layout[index]["id"])))
		var rect := Rect2i(Vector2i(int(layout[index]["x"]), int(layout[index]["z"])),
			def.footprint_for(int(layout[index]["turns"])))
		rects.append(rect)
		_expect(Rect2i(Vector2i.ZERO, grid).encloses(rect),
			"%s is inside the floor" % DefaultShed.piece_uid(layout, index))
		for area: Rect2i in fixed:
			_expect(not area.intersects(rect), "%s is off the dock and the exit" % DefaultShed.piece_uid(layout, index))
		for other: int in range(index):
			_expect(not rects[other].intersects(rect), "%s and %s do not overlap"
				% [DefaultShed.piece_uid(layout, index), DefaultShed.piece_uid(layout, other)])
	_expect(WalkReachability.unreachable_pieces(grid, layout, fixed).is_empty(), "Every piece can be walked to")
	_expect(WalkReachability.entries_connected(grid, layout, fixed), "The dock reaches the exit")

	var shed: CompanyShed = level.shed
	_expect(shed != null and shed.pieces.size() == layout.size(), "The shed draws every piece of the layout")
	var tables: int = 0
	var shelf_labels: int = 0
	for piece: Dictionary in shed.pieces:
		if piece["id"] == &"assembly_table":
			tables += 1
			_expect(shed.stations.get(piece["uid"]) is PackingStation, "%s has its PackingStation" % piece["uid"])
	_expect(tables >= 1, "There is a packing table (%d)" % tables)
	_check_shelf_model(shed)
	var labels: Array[Node] = shed.find_children("Label_*", "Label3D", true, false)
	for label: Node in labels:
		shelf_labels += 1
		var shown: String = (label as Label3D).text.replace("\n", " ")
		_expect(shown.contains("×"), "A shelf label carries its units (%s)" % shown)
	_expect(shelf_labels == data.shelf_stock.size(), "One label per labeled slot (%d)" % shelf_labels)
	_expect(shed.get_node(^"Pallets").get_child_count() == pallets.size(), "One pallet node per pallet")
	for node: Node in shed.get_node(^"Pallets").get_children():
		var spot: Vector2 = shed.local_to_cell((node as Node3D).position)
		var spot_cell := Vector2i(floori(spot.x), floori(spot.y))
		for area: Rect2i in fixed:
			_expect(not area.has_point(spot_cell), "%s is not on the dock or the exit" % node.name)
		_expect(shed.piece_at(spot_cell) == &"", "%s stands clear of every piece" % node.name)
	var player: Node3D = level.player
	var spawn_cell: Vector2 = shed.local_to_cell(CompanyRoot.SPAWN)
	var spawn_cell_i := Vector2i(floori(spawn_cell.x), floori(spawn_cell.y))
	_expect(WarehouseStages.dock_rect(stage).has_point(spawn_cell_i) and shed.piece_at(spawn_cell_i) == &"",
		"The player spawns on the dock floor, clear of every piece (cell %s)" % spawn_cell_i)
	_expect(player != null and player.is_in_group(CompanyRoot.CREW_GROUP),
		"The company's player is in %s" % CompanyRoot.CREW_GROUP)
	var care: Node = player.get_node_or_null(^"CargoCare")
	_expect(care != null and care.get(&"practice") == null,
		"The delivery practice card (\"subite a manejar\") is not shown in the company's shed")

	# The labels follow the stock.
	var shelf_uid: StringName = &"shelf_1"
	var slot: Dictionary = data.shelf_stock[0]
	var where: StringName = DefaultShed.shelf_location(StringName(str(slot["shelf"])), int(slot["slot"]))
	var product := StringName(str(slot["product"]))
	var taken: Inventory = level.net.inventory
	var label: Label3D = shed.get_node("Furniture/Shelf_%s/Label_%d" % [slot["shelf"], int(slot["slot"])]) as Label3D
	_expect(taken.count(product, where) == int(slot["qty"]) and label.text.ends_with("×%d" % int(slot["qty"])),
		"The label of %s shows %d units (%s)" % [where, int(slot["qty"]), label.text.replace("\n", " ")])
	taken.consume(product, 2, where)
	shed.refresh_stock(taken)
	_expect(label.text.ends_with("×%d" % (int(slot["qty"]) - 2)),
		"...and follows the stock down (%s)" % label.text.replace("\n", " "))
	taken.consume(product, int(slot["qty"]) - 2, where)
	shed.refresh_stock(taken)
	_expect(label.text.ends_with("×0"), "...to zero (%s)" % label.text.replace("\n", " "))

	# A client with only the snapshot's layout and stock draws the same pieces.
	var mirror := CompanyShed.new()
	root.add_child(mirror)
	var copy := DefaultShed.ScratchState.new()
	var snapshot: Dictionary = state.call(&"to_dict")
	copy.layout.assign((snapshot["layout"] as Array).duplicate(true))
	copy.warehouse_stage = int(snapshot["warehouse_stage"])
	mirror.rebuild(copy, taken)
	_expect(_summary(mirror.pieces) == _summary(shed.pieces),
		"A peer holding the snapshot's layout draws the same pieces")
	mirror.queue_free()

	# The build mode can move a piece: it keeps its uid, station and stock.
	var table_index: int = _index_of(layout, &"table_2")
	var station: Object = shed.stations.get(&"table_2")
	var checker: BuildPlacement = data.placement()
	var moved: Dictionary = checker.move_piece(state, table_index, 11, 6)
	_expect(bool(moved["ok"]), "The build mode moves table_2 to a free cell (%s)" % moved["reason"])
	shed.rebuild(state, taken)
	_expect(shed.piece_at(Vector2i(11, 6)) == &"table_2" and shed.piece_at(Vector2i(11, 4)) == &"",
		"The shed draws it at its new place")
	_expect(shed.stations.get(&"table_2") == station, "...with the same station state")
	var blocked: Dictionary = checker.move_piece(state, table_index, 5, 0)
	_expect(not bool(blocked["ok"]) and blocked["reason"] == BuildPlacement.REASON_FIXED,
		"The build mode refuses to put it on the exit (%s)" % blocked["reason"])
	_expect(shelf_uid == DefaultShed.piece_uid(state.get(&"layout"), _index_of(state.get(&"layout"), shelf_uid)),
		"A piece keeps its uid when others move")

	level.queue_free()
	await process_frame
	state.call(&"reset")
	_clean()


## The shelf is the model of the shed (D-1811), not boxes: it is imported, 2 m wide, 2 m high and 1 m deep
## (X -1..1, Y 0..2, Z -0.5..0.5), the batch of the furniture holds its geometry over the shelf's
## footprint, and the crates rest on the decks and the labels stand in front of the rails.
func _check_shelf_model(shed: CompanyShed) -> void:
	var path: String = DepotKit.depot_model(CompanyShed.MODEL_SHELF)
	_expect(ResourceLoader.exists(path), "The shed shelf model is imported (%s)" % path)
	if not ResourceLoader.exists(path):
		return
	var bounds: AABB = DepotKit.merged_mesh(path).get_aabb()
	_expect(bounds.size.distance_to(Vector3(2.0, 2.0, 1.0)) < 0.01 and absf(bounds.position.y) < 0.01
		and absf(bounds.get_center().x) < 0.01 and absf(bounds.get_center().z) < 0.01,
		"...sized 2 x 2 x 1 m, base centre on the floor (%s)" % bounds)
	var shelves: int = 0
	for piece: Dictionary in shed.pieces:
		if piece["id"] != &"shelf":
			continue
		shelves += 1
		var node := shed.get_node("Furniture/Shelf_%s" % piece["uid"]) as Node3D
		var rect: Rect2i = piece["rect"]
		var middle: Vector3 = shed.cell_to_local(Vector2(rect.position) + Vector2(rect.size) * 0.5)
		_expect(node.position.is_equal_approx(middle), "%s stands on the middle of its footprint" % piece["uid"])
		var drawn := false
		for batch: Node in shed.get_node(^"Furniture").get_children():
			if batch is MeshInstance3D and (batch as MeshInstance3D).get_aabb().encloses(
					node.transform * AABB(Vector3(-0.9, 0.0, -0.4), Vector3(1.8, 1.9, 0.8))):
				drawn = true
		_expect(drawn, "%s is drawn as geometry over its footprint, 1.9 m high" % piece["uid"])
	_expect(shelves >= 1, "There is a shelf to check (%d)" % shelves)
	for crate: Node in shed.find_children("Crate_*", "MeshInstance3D", true, false):
		var level: int = floori(int(String(crate.name).trim_prefix("Crate_")) / float(CompanyShed.SHELF_COLUMNS))
		var crate_y: float = (crate as Node3D).position.y
		_expect(is_equal_approx(crate_y - CompanyShed.CRATE_SIZE.y * 0.5, CompanyShed.SHELF_DECKS[level]),
			"%s rests on the top of its deck (%.3f)" % [crate.name, crate_y])
	for label: Node in shed.find_children("Label_*", "Label3D", true, false):
		var label_z: float = (label as Node3D).position.z
		_expect(label_z > 0.5, "%s stands in front of the rail (z %.2f)" % [label.name, label_z])


func _summary(pieces: Array[Dictionary]) -> Array:
	var rows: Array = []
	for piece: Dictionary in pieces:
		rows.append([piece["uid"], piece["id"], piece["rect"]])
	return rows


func _index_of(layout: Array, uid: StringName) -> int:
	for index: int in layout.size():
		if DefaultShed.piece_uid(layout, index) == uid:
			return index
	return -1


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
