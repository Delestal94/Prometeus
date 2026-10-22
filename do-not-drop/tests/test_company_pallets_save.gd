extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_pallets_save.gd
##
## The supplier pallets, the pallet jack and the delivery note in the company's save (expansion D-0605.c:
## CompanyPallets.to_save / load_save, CompanyState.pallets, CompanyRoot):
## - to_save() survives a JSON round trip (whole numbers back as float, the jack's spot as [x, z]): the book
##   (bed, jack and floor with their spots), loaded_day, departed_day and the note come back the same;
## - a forklift that was moved and had a driver saves its spot as [x, z] and nobody driving, and loads back with
##   the book, departed_day and the spot intact (the forklift's Vector2 used to turn into text in the JSON and
##   the whole book was lost);
## - load_save() refuses what does not fit (not a dictionary, a spot that is not two numbers, a pallet on the
##   jack that the book does not carry) and changes nothing;
## - CompanyState keeps it through CompanySave's JSON; a broken `pallets` loads the company with an empty book,
##   and a save from before D-0605.c (no key) too;
## - a truck that already drove off that day brings nothing again (loaded_event after departed_day): an
##   interrupted day loaded back at its opening does not put the left pallets back on the bed;
## - the real company world (company_root.tscn, solo): a pallet put on the floor and the note of a short
##   delivery are saved with the interrupted day; a new world over that slot has the pallet on the floor at the
##   same spot, its units in the stock once, the note and the departed day; the snapshot's company part does
##   not carry the pallets (its `pallets` part does).

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const DIR: String = "user://test_company_pallets_save"
const DAY: int = 2
const SPOT: Vector2 = Vector2(3.5, -2.0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_round_trip()
	_test_refused()
	_test_moved_forklift()
	_test_state()
	_test_no_second_truck()
	await _test_root()
	if _failures == 0:
		print("PASS: the pallets, the jack and the delivery note go into the company save and come back")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


## A book with a pallet on the floor, one on the jack, one on the bed, the jack pushed and a short day in the note.
func _filled(stock: Inventory) -> CompanyPallets:
	var pallets := CompanyPallets.new()
	var planned: Array[Dictionary] = [
		Pallet.make(&"d2_1", &"hen", 12), Pallet.make(&"d2_2", &"hen", 6), Pallet.make(&"d2_3", &"antique_lamp", 4)]
	_expect(pallets.apply(stock, CompanyPallets.LOADED, {"day": DAY, "pallets": planned}), "Pallets load on the bed")
	_expect(pallets.apply(stock, CompanyPallets.PICKED, {"pallet": &"d2_1"}), "A pallet goes on the jack")
	_expect(pallets.apply(stock, CompanyPallets.PLACED, {"pallet": &"d2_1", "pos": SPOT}), "It stands on the floor")
	_expect(pallets.apply(stock, CompanyPallets.PICKED, {"pallet": &"d2_2"}), "A second one goes on the jack")
	_expect(pallets.apply(stock, CompanyPallets.MOVED, {"pos": Vector2(1.25, 4.0)}), "The jack is pushed")
	pallets.note.check(DAY, {&"hen": 30}, {&"hen": 18})
	pallets.departed_day = DAY - 1
	return pallets


func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _test_round_trip() -> void:
	var pallets: CompanyPallets = _filled(Inventory.new())
	var saved: Variant = _json(pallets.to_save())
	_expect(saved is Dictionary, "to_save() is plain JSON")
	var back := CompanyPallets.new()
	_expect(back.load_save(saved), "load_save() takes it back after JSON")
	_expect(JSON.stringify(back.to_save()) == JSON.stringify(pallets.to_save()),
		"Same book, days and note after the round trip")
	_expect(back.book.ids_at(PalletJack.AT_FLOOR) == [&"d2_1"] and back.book.carrying == &"d2_2"
		and back.book.ids_at(PalletJack.AT_BED) == [&"d2_3"], "Floor, jack and bed in their places")
	_expect(back.book.places[&"d2_1"]["pos"] == SPOT, "The floor pallet at its spot")
	_expect(back.jack_at is Vector2 and back.jack_at == Vector2(1.25, 4.0), "The jack where it was pushed")
	_expect(back.loaded_day == DAY and back.departed_day == DAY - 1, "loaded_day and departed_day kept")
	_expect(back.note.days_with_shortfall() == [DAY] and back.note.missing_totals().get(&"hen", 0) == 12,
		"The note keeps the short day (got %s)" % [back.note.missing_totals()])
	var fresh := CompanyPallets.new()
	_expect(fresh.load_save(_json(fresh.to_save())) and fresh.jack_at == null and fresh.book.places.is_empty(),
		"An empty book round-trips with the jack at home")


func _test_moved_forklift() -> void:
	var pallets: CompanyPallets = _filled(Inventory.new())
	var spot := Vector2(-2.5, 6.0)
	_expect(pallets.forklift.apply({"driver": 7, "at": spot, "yaw": 1.5, "dir": 0, "height": 0.0}, 0),
		"The forklift is driven somewhere")
	var saved: Variant = _json(pallets.to_save())
	_expect(saved is Dictionary and saved["forklift"]["at"] is Array and saved["forklift"]["driver"] == 0,
		"The forklift's spot goes as [x, z] and nobody drives it")
	var back := CompanyPallets.new()
	_expect(back.load_save(saved), "A save with the forklift moved loads")
	_expect(back.forklift.at is Vector2 and back.forklift.at == spot and back.forklift.driver == 0,
		"The forklift stands where it was, with no driver")
	_expect(back.book.carrying == &"d2_2" and back.departed_day == DAY - 1 and back.loaded_day == DAY,
		"The book and departed_day came back")


func _test_refused() -> void:
	var good: Dictionary = _json(_filled(Inventory.new()).to_save())
	var target: CompanyPallets = _filled(Inventory.new())
	var before: String = JSON.stringify(target.to_save())
	var spot: Dictionary = good.duplicate(true)
	spot["jack_at"] = "(1, 2)"
	var short: Dictionary = good.duplicate(true)
	short["jack_at"] = [1.0]
	var dropped: Dictionary = good.duplicate(true)
	dropped["book"]["carrying"] = ""
	var day: Dictionary = good.duplicate(true)
	day["loaded_day"] = "two"
	for bad: Variant in ["broken", [], spot, short, dropped, day]:
		_expect(not target.load_save(bad), "Refused: %s" % [str(bad).left(60)])
	_expect(JSON.stringify(target.to_save()) == before, "A refused save changes nothing")


func _test_state() -> void:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"new_company", "Pallets")
	state.set(&"pallets", _filled(Inventory.new()).to_save())
	_clean()
	_expect(CompanySave.save(state, "slot", DIR), "The company saves")
	var loaded: Node = (load(STATE_SCRIPT) as GDScript).new()
	_expect(CompanySave.load_into(loaded, "slot", DIR) == CompanySave.LoadResult.LOADED, "The company loads")
	var back := CompanyPallets.new()
	_expect(back.load_save(loaded.get(&"pallets")) and back.book.ids_at(PalletJack.AT_FLOOR) == [&"d2_1"]
		and back.note.days_with_shortfall() == [DAY], "CompanyState keeps the pallets through the save")
	var data: Dictionary = state.call(&"to_dict")
	data["pallets"] = {"book": "broken"}
	_expect(loaded.call(&"from_dict", data) and (loaded.get(&"pallets") as Dictionary).is_empty(),
		"A broken pallets part loads the company with an empty book")
	data.erase("pallets")
	_expect(loaded.call(&"from_dict", data) and (loaded.get(&"pallets") as Dictionary).is_empty(),
		"A save from before D-0605.c loads with an empty book")
	state.free()
	loaded.free()
	_clean()


func _test_no_second_truck() -> void:
	var pallets := CompanyPallets.new()
	var planned: Array[Dictionary] = [Pallet.make(&"d2_1", &"hen", 12)]
	_expect(not pallets.loaded_event(DAY, planned, Inventory.new()).is_empty(), "The day's truck loads its pallets")
	pallets.departed_day = DAY
	_expect(pallets.loaded_event(DAY, planned, Inventory.new()).is_empty(),
		"A truck that drove off that day brings nothing again")
	_expect(not pallets.loaded_event(DAY + 1, planned, Inventory.new()).is_empty(), "The next day's truck does")


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level: CompanyRoot = await _open()
	if level == null:
		return
	var net: CompanyNet = level.net
	var planned: Array = [{"id": "d2_1", "product": "hen", "qty": 12}, {"id": "d2_2", "product": "hen", "qty": 6}]
	_expect(net.publish(CompanyPallets.LOADED, {"day": DAY, "pallets": planned}), "The host loads the bed")
	# What a player's jack_pick and jack_put lead to (test_company_pallet_jack_world plays the requests).
	_expect(net.pallets.apply(net.inventory, CompanyPallets.PICKED, {"pallet": &"d2_1"}), "A pallet on the jack")
	_expect(net.pallets.apply(net.inventory, CompanyPallets.PLACED, {"pallet": &"d2_1", "pos": SPOT}),
		"and on the floor")
	_expect(net.publish(CompanyPallets.DEPARTED, {"day": DAY, "lines": [{"product": "hen", "ordered": 18,
		"received": 12}]}), "The truck drives off short")
	var units: int = net.inventory.count(&"hen", Pallet.location(&"d2_1"))
	_expect(units == 12, "The floor pallet's units are in the stock (got %d)" % units)
	_expect(not (net.snapshot()["company"] as Dictionary).has("pallets")
		and net.snapshot().has(CompanyPallets.SNAPSHOT_KEY), "The snapshot carries the pallets in its own part")
	_expect(level.save_interrupted_day(), "The interrupted day is saved")
	await _close(level, state)
	level = await _open()
	if level == null:
		return
	net = level.net
	_expect(net.pallets.book.ids_at(PalletJack.AT_FLOOR) == [&"d2_1"]
		and net.pallets.book.places[&"d2_1"]["pos"] == SPOT, "The loaded world has the pallet on the floor")
	_expect(net.pallets.book.ids_at(PalletJack.AT_BED).is_empty() and net.pallets.departed_day == DAY,
		"The truck stays gone, with nothing on its bed")
	_expect(net.pallets.note.days_with_shortfall() == [DAY], "The delivery note comes back")
	units = net.inventory.count(&"hen", Pallet.location(&"d2_1"))
	_expect(units == 12, "The pallet's units are in the stock once (got %d)" % units)
	await _close(level, state)
	_clean()


func _open() -> CompanyRoot:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	if level.net == null:
		_expect(false, "The company world has a net")
		level.queue_free()
		return null
	return level


func _close(level: CompanyRoot, state: Node) -> void:
	level.queue_free()
	await process_frame
	state.call(&"reset")


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
