extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_modifiers.gd
##
## The company's modifiers (expansion D-1919, diseno/dificultad.md §2-3, §6 points 1-3):
## - CompanyState.options: both off for a new company and after reset(); to_dict() / from_dict() keep them through
##   a JSON round trip; a save without the key loads both off; an unknown key or a value that is not a bool is
##   ignored; CompanySave.list_slots() lists each slot's options;
## - PackingStation.seal() with Armado asistido: a box with 3 free cells is sealed padded (fill_ratio 1.0, 3 cells
##   and the tape charged, the table's padding down by 3, the box marked assisted); money just for the tape seals
##   with no padding (assisted_cells 0); no tape on the table refuses and changes nothing; padding short on the
##   table pads only what there is;
## - PackedBox.assisted survives to_dict() / from_dict(); BoxToPackage.absorption gives the same padded box 0.6 by
##   hand and 0.75 assisted (ASSISTED_MIN_ABSORPTION);
## - the table over the network, solo host: with assisted_packing on, taping a box with free cells pads them in the
##   same event (box_sealed carries assisted and filled, the money and the package's absorption count them), and a
##   second copy of the tables applying the same events ends the same (wallet, padding on the table); with the
##   option off box_sealed pads nothing; a box_sealed with a bad filled (negative, text, more than the free cells)
##   is not applied by the copy.
## Pending (no system yet): the day-event draw with calm_days (D-0123) and the new-company and slot screens
## (D-0235 / D-1904).

const T := preload("res://scripts/core/company/company_table_net.gd")
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const DIR: String = "user://test_company_modifiers"
const SPOT := Vector3(0.0, 0.0, 1.0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_test_options()
	_test_slots()
	_test_station()
	_test_absorption()
	_test_table_net(true)
	_test_table_net(false)
	_clean()
	if _failures == 0:
		print("PASS: modifiers are saved, Armado asistido pads with the tape and cushions like the quick match")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _new_state(state_name: String) -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.name = state_name
	root.add_child(state)
	state.call(&"reset")
	return state


func _test_options() -> void:
	var state: Node = _new_state("Options")
	state.call(&"new_company", "Opciones SRL")
	var off: Dictionary = {"assisted_packing": false, "calm_days": false}
	_expect(state.get(&"options") == off, "a new company has both modifiers off (got %s)" % [state.get(&"options")])
	state.set(&"options", {"assisted_packing": true, "calm_days": false})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.call(&"to_dict")))
	var other: Node = _new_state("Loaded")
	_expect(other.call(&"from_dict", saved) and bool(other.call(&"option", "assisted_packing"))
		and not bool(other.call(&"option", "calm_days")), "the options survive a JSON round trip")
	saved.erase("options")
	_expect(other.call(&"from_dict", saved) and other.get(&"options") == off, "a save without options loads both off")
	saved["options"] = {"assisted_packing": "yes", "calm_days": 1, "turbo": true}
	_expect(other.call(&"from_dict", saved) and other.get(&"options") == off,
		"a value that is not a bool and an unknown key are ignored (got %s)" % [other.get(&"options")])
	saved["options"] = ["assisted_packing"]
	_expect(other.call(&"from_dict", saved) and other.get(&"options") == off, "options that are not a dictionary: off")
	other.call(&"reset")
	_expect(other.get(&"options") == off, "reset() turns them off")
	state.free()
	other.free()


func _test_slots() -> void:
	_clean()
	var state: Node = _new_state("Slots")
	state.call(&"new_company", "Calma SRL")
	state.set(&"options", {"assisted_packing": false, "calm_days": true})
	_expect(CompanySave.save(state, "calma", DIR), "a slot is saved")
	var slots: Array[Dictionary] = CompanySave.list_slots(DIR)
	_expect(slots.size() == 1 and slots[0].get("options") == {"assisted_packing": false, "calm_days": true},
		"list_slots() carries the slot's options (got %s)" % [slots])
	state.free()


func _box_with(free_cells: int) -> PackingStation:
	var station: PackingStation = PackingStation.make(&"t")
	station.start_box(&"S")
	var total: int = station.box.total_cells()
	station.box.fill_free_cells(total - free_cells)
	return station


func _test_station() -> void:
	var wallet: Node = _new_state("Wallet")
	wallet.call(&"new_company", "Mesa SRL")
	var station: PackingStation = _box_with(3)
	var fill_before: int = station.supplies.count(StationSupplies.FILL)
	var money: int = int(wallet.get(&"money"))
	var cells: int = station.assisted_cells(money)
	_expect(cells == 3, "3 free cells, padding and money: 3 to pad (got %d)" % cells)
	_expect(station.seal(wallet, cells), "the tape seals it")
	_expect(station.box.taped and station.box.assisted and is_equal_approx(station.box.fill_ratio(), 1.0),
		"...padded full and marked assisted")
	var cost: int = CompanyTuning.TAPE_COST + PackagingSupplies.fill_cost(3)
	_expect(int(wallet.get(&"money")) == money - cost, "...charging the 3 cells and the tape")
	_expect(station.supplies.count(StationSupplies.FILL) == fill_before - 3, "...from the table's padding")
	var tight: PackingStation = _box_with(3)
	wallet.set(&"money", CompanyTuning.TAPE_COST)
	_expect(tight.assisted_cells(int(wallet.get(&"money"))) == 0, "money just for the tape: nothing to pad")
	_expect(tight.seal(wallet, 0) and tight.box.taped and int(wallet.get(&"money")) == 0,
		"...and it seals without padding")
	var short: PackingStation = _box_with(3)
	short.supplies.take(StationSupplies.FILL, short.supplies.count(StationSupplies.FILL) - 1)
	_expect(short.assisted_cells(1000) == 1, "one unit of padding on the table: 1 cell")
	var bare: PackingStation = _box_with(3)
	bare.supplies.take(StationSupplies.TAPE, bare.supplies.count(StationSupplies.TAPE))
	wallet.set(&"money", 1000)
	var before: Dictionary = bare.box.to_dict()
	_expect(bare.assisted_cells(1000) == 0 and not bare.seal(wallet, 2) and bare.box.to_dict() == before
		and int(wallet.get(&"money")) == 1000, "no tape: false, nothing changes")
	wallet.free()


func _test_absorption() -> void:
	var by_hand: PackedBox = PackedBox.new(&"S")
	by_hand.fill_free_cells(by_hand.total_cells())
	var assisted: PackedBox = PackedBox.from_dict(by_hand.to_dict())
	assisted.assisted = true
	_expect(PackedBox.from_dict(assisted.to_dict()).assisted, "assisted survives to_dict / from_dict")
	_expect(not PackedBox.from_dict(by_hand.to_dict()).assisted, "...and a hand box stays a hand box")
	_expect(is_equal_approx(BoxToPackage.absorption(by_hand), CompanyTuning.ABSORPTION_FULL_PADDING),
		"padded by hand: 0.6 (got %.2f)" % BoxToPackage.absorption(by_hand))
	_expect(is_equal_approx(BoxToPackage.absorption(assisted), CompanyTuning.ASSISTED_MIN_ABSORPTION),
		"the same box assisted: 0.75 (got %.2f)" % BoxToPackage.absorption(assisted))


func _test_table_net(assisted: bool) -> void:
	var label: String = "assisted" if assisted else "off"
	var state: Node = _new_state("NetState")
	state.call(&"new_company", "Red SRL")
	state.set(&"options", {"assisted_packing": assisted, "calm_days": false})
	var net := CompanyNet.new()
	net.name = "ModNet"
	net.company = state
	root.add_child(net)
	net.inventory = Inventory.new()
	net.stations = func(id: StringName) -> Dictionary:
		return {"location": &"table:%s" % id, "spot": SPOT} if id == &"table_1" else {}
	net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	var heard: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void: heard.append([rid, reason]))
	var mirror_state: Node = _new_state("MirrorState")
	mirror_state.call(&"from_dict", state.call(&"to_dict"))
	var mirror := T.new()
	var mirror_stock := Inventory.new()
	mirror_stock.receive(&"hen", 1, CompanyNet.hands_location(1))
	var sealed: Array[Dictionary] = []
	var mirrored: Array[bool] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == T.SEALED:
			sealed.append(data)
		elif T.EVENT_KINDS.has(kind):
			mirrored.append(mirror.apply(mirror_state, mirror_stock, kind, data)))
	net.inventory.receive(&"hen", 1, CompanyNet.hands_location(1))
	var order: Dictionary = Order.make(&"o1", "Ana", &"centro", &"centro_house_12",
		[{"product": &"hen", "qty": 1}], 0, {})
	net.table.order_of = func(_table: StringName) -> Dictionary: return order
	mirror.order_of = net.table.order_of
	var steps: Array = [
		[T.START, {"station": &"table_1", "size": &"S"}],
		[T.PLACE, {"station": &"table_1", "cx": 0, "cy": 0, "cz": 0, "product": &"hen", "rot": 0}],
		[T.LABEL, {"station": &"table_1"}],
	]
	for step: Array in steps:
		_expect(_ask(net, heard, step[0], step[1]) == &"", "%s: %s goes through" % [label, step[0]])
	var open_box: PackedBox = net.table.call(&"_desk", &"table_1").box
	var free: int = open_box.total_cells() - open_box.grid.size()
	var money: int = int(state.get(&"money"))
	_expect(_ask(net, heard, T.TAPE, {"station": &"table_1"}) == &"" and sealed.size() == 1,
		"%s: the tape goes through" % label)
	if sealed.is_empty():
		_cleanup([net, state, mirror_state])
		return
	var data: Dictionary = sealed[0]
	var filled: int = free if assisted else 0
	_expect(data.get("assisted") == assisted and data.get("filled") == filled,
		"%s: box_sealed says assisted %s, filled %d (got %s, %s)" % [label, assisted, filled, data.get("assisted"),
			data.get("filled")])
	var cost: int = CompanyTuning.TAPE_COST + PackagingSupplies.fill_cost(filled)
	_expect(int(state.get(&"money")) == money - cost, "%s: the wallet paid %d" % [label, cost])
	var expected: float = CompanyTuning.ASSISTED_MIN_ABSORPTION if assisted else CompanyTuning.ABSORPTION_UNPADDED
	_expect(is_equal_approx(float(data.get("absorption")), expected) or not assisted,
		"%s: the package cushions %.2f (got %s)" % [label, expected, data.get("absorption")])
	if assisted:
		# A box_sealed whose `filled` does not fit is refused by the copy, its box still open.
		for bad: Variant in [-1, "3", free + 1]:
			var wrong: Dictionary = data.duplicate()
			wrong["filled"] = bad
			_expect(not mirror.apply(mirror_state, mirror_stock, T.SEALED, wrong) and mirror.has_box(&"table_1"),
				"a box_sealed with filled %s is not applied" % [bad])
	mirrored.append(mirror.apply(mirror_state, mirror_stock, T.SEALED, data))
	_expect(not mirrored.has(false) and int(mirror_state.get(&"money")) == int(state.get(&"money")),
		"%s: a copy applying the same events ends with the same wallet (%d vs %d)"
		% [label, int(mirror_state.get(&"money")), int(state.get(&"money"))])
	var host_fill: int = net.table.call(&"_desk", &"table_1").supplies.count(StationSupplies.FILL)
	var copy_fill: int = mirror.call(&"_desk", &"table_1").supplies.count(StationSupplies.FILL)
	_expect(host_fill == copy_fill, "%s: ...and the same padding left on the table (%d vs %d)"
		% [label, host_fill, copy_fill])
	_cleanup([net, state, mirror_state])


func _cleanup(nodes: Array) -> void:
	for node: Variant in nodes:
		if is_instance_valid(node):
			(node as Node).free()


func _ask(net: CompanyNet, heard: Array, kind: StringName, data: Dictionary) -> StringName:
	var rid: int = net.request(kind, data)
	for entry: Array in heard:
		if entry[0] == rid:
			return entry[1]
	return &""


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
