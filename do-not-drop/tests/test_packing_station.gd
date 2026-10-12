extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_packing_station.gd
##
## Packing table (expansion D-0701, packing_station.gd):
## - a table takes one box at a time and refuses unknown sizes;
## - products wait on the table up to STAGING_SLOTS and can be taken back;
## - put_in_box() moves a staged product into the box's grid, and refuses (changing
##   nothing) with no box, an unstaged product or a spot that does not fit;
## - three products fit in one box at PackedBox.first_fit() spots without overlapping, and the
##   box knows its content (D-0703);
## - an open box cannot be dispatched; seal() tapes it, charges the tape once and dispatch()
##   then hands the box over (D-0706);
## - label_for() sticks the order's label (street and number of its house) on the box, refuses
##   with no box or an order without a house, and relabeling the same order is free (D-0707);
## - take_box() frees the table; to_dict() survives a JSON round trip.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_box()
	_test_staging()
	_test_put_in_box()
	_test_three_products()
	_test_seal_and_dispatch()
	_test_label()
	_test_round_trip()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _product(id: StringName, cells: Vector3i) -> ProductDefinition:
	var p := ProductDefinition.new()
	p.id = id
	p.cells = cells
	return p


func _test_box() -> void:
	_expect(PackingStation.make(&"") == null, "empty id makes no table")
	var table: PackingStation = PackingStation.make(&"t1")
	_expect(not table.has_box(), "a new table is free")
	_expect(not table.start_box(&"XXL"), "unknown size is refused")
	_expect(table.start_box(&"M") and table.has_box(), "an M box opens on the table")
	_expect(not table.start_box(&"S"), "a second box does not fit on the table")
	_expect(table.box.box_size == &"M", "the first box stays")
	var taken: PackedBox = table.take_box()
	_expect(taken != null and not table.has_box(), "take_box() frees the table")
	_expect(table.take_box() == null, "nothing to take from a free table")


func _test_staging() -> void:
	var table: PackingStation = PackingStation.make(&"t1")
	_expect(not table.stage_product(&""), "empty product id is refused")
	for i: int in PackingStation.STAGING_SLOTS:
		_expect(table.stage_product(&"mug"), "slot %d takes a product" % i)
	_expect(not table.stage_product(&"mug"), "no room beyond STAGING_SLOTS")
	_expect(table.unstage_product(&"mug"), "a product comes back off the table")
	_expect(table.staged.size() == PackingStation.STAGING_SLOTS - 1, "one unit less on the table")
	_expect(not table.unstage_product(&"vase"), "a product that is not there stays out")


func _test_put_in_box() -> void:
	var table: PackingStation = PackingStation.make(&"t1")
	var mug: ProductDefinition = _product(&"mug", Vector3i(1, 1, 2))
	table.stage_product(&"mug")
	_expect(not table.put_in_box(mug, Vector3i.ZERO), "no box: nothing goes in")
	table.start_box(&"M")
	_expect(
		not table.put_in_box(_product(&"vase", Vector3i.ONE), Vector3i.ZERO),
		"unstaged product refused",
	)
	_expect(not table.put_in_box(mug, Vector3i(0, 0, 2)), "a spot that sticks out is refused")
	_expect(table.staged == [&"mug"] and table.box.items.is_empty(), "a refusal changes nothing")
	_expect(table.put_in_box(mug, Vector3i.ZERO), "the staged product goes in the box")
	_expect(table.staged.is_empty(), "it left the table")
	_expect(table.box.contents() == {&"mug": 1}, "the box knows its content")
	_expect(not table.put_in_box(mug, Vector3i.ZERO), "the same unit cannot go in twice")


func _test_three_products() -> void:
	var table: PackingStation = PackingStation.make(&"t1")
	table.start_box(&"M")
	var mug: ProductDefinition = _product(&"mug", Vector3i(1, 1, 2))
	var vase: ProductDefinition = _product(&"vase", Vector3i(2, 2, 1))
	var book: ProductDefinition = _product(&"book", Vector3i(2, 1, 1))
	for p: ProductDefinition in [mug, vase, book]:
		table.stage_product(p.id)
	var box: PackedBox = table.box
	for p: ProductDefinition in [mug, vase, book]:
		var spot: Vector3i = box.first_fit(p)
		_expect(spot != PackedBox.NO_SPOT, "%s has a spot" % p.id)
		_expect(table.put_in_box(p, spot), "%s goes in at its first fit" % p.id)
	_expect(table.staged.is_empty(), "the three left the table")
	_expect(
		box.contents() == {&"mug": 1, &"vase": 1, &"book": 1},
		"the box knows its three products",
	)
	_expect(box.first_fit(mug) != box.first_fit(book), "a taken spot is not offered again")
	var occupied: int = 0
	for item: Dictionary in box.items:
		var c: Vector3i = item["cells"]
		occupied += c.x * c.y * c.z
	_expect(occupied == 8 and box.grid.size() == 8, "cells taken match the products (no overlap)")
	_expect(
		box.first_fit(_product(&"wardrobe", Vector3i(4, 1, 1))) == PackedBox.NO_SPOT,
		"too big: no spot",
	)
	_expect(box.first_fit(null) == PackedBox.NO_SPOT, "null product: no spot")
	var full: PackedBox = PackedBox.new(&"M")
	full.fill_free_cells(full.total_cells())
	_expect(
		full.first_fit(_product(&"mug", Vector3i.ONE)) == PackedBox.NO_SPOT,
		"full box: no spot",
	)


func _test_seal_and_dispatch() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		_expect(false, "CompanyState autoload missing")
		return
	state.new_company("Tape Co")
	var money: int = state.money
	var station: PackingStation = PackingStation.make(&"t1")
	_expect(not station.seal(state), "no box to seal")
	_expect(station.dispatch() == null, "empty table dispatches nothing")
	station.start_box(&"S")
	_expect(not station.is_sealed(), "a fresh box is open")
	_expect(station.dispatch() == null, "open box is not dispatched")
	_expect(station.has_box(), "the open box stays on the table")
	_expect(station.seal(state), "seal tapes the box")
	_expect(station.is_sealed(), "box is sealed")
	_expect(state.money == money - CompanyTuning.TAPE_COST, "tape charged once")
	_expect(not station.seal(state), "second seal refused")
	_expect(state.money == money - CompanyTuning.TAPE_COST, "no second charge")
	var out: PackedBox = station.dispatch()
	_expect(out != null and out.taped, "sealed box is dispatched")
	_expect(not station.has_box(), "table is free after dispatch")
	state.reset()


func _test_label() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		_expect(false, "CompanyState autoload missing")
		return
	state.new_company("Label Co")
	var order: Dictionary = {"id": "o1", "customer": "Ana", "zone": "centro", "house_id": "centro_house_7"}
	var addr: Dictionary = OrderLabel.address(order)
	_expect(
		addr.get("number") == 7 and addr.get("street_key") == &"WORLD_STREET_CENTRO",
		"label shows street and number",
	)
	_expect(
		addr.get("order") == &"o1" and addr.get("customer") == "Ana",
		"label names the order and customer",
	)
	_expect(
		OrderLabel.address({"id": "o2", "zone": "campo", "house_id": "campo_house_12"}).get("number") == 12,
		"campo house 12",
	)
	_expect(
		(
			OrderLabel.address({"id": "o3", "zone": "isla", "house_id": "isla_house_3"}).get("street_key")
			== OrderLabel.FALLBACK_STREET_KEY
		),
		"unknown zone uses the fallback street",
	)
	_expect(
		OrderLabel.address({"id": "o4", "zone": "centro", "house_id": "kiosk"}).is_empty(),
		"no house number: no label",
	)
	_expect(
		OrderLabel.address({"zone": "centro", "house_id": "centro_house_1"}).is_empty(),
		"no order id: no label",
	)
	var table: PackingStation = PackingStation.make(&"t1")
	_expect(not table.label_for(order, state), "no box to label")
	table.start_box(&"S")
	_expect(
		not table.label_for({"id": "o4", "house_id": "kiosk"}, state),
		"order without a house is refused",
	)
	_expect(table.box.label_order_id == &"", "refused label leaves the box bare")
	var money: int = state.money
	_expect(table.label_for(order, state), "label sticks on the box")
	_expect(OrderLabel.matches(table.box, order), "box carries the label of the order")
	_expect(not OrderLabel.matches(table.box, {"id": "o2"}), "box does not match another order")
	_expect(state.money == money - CompanyTuning.LABEL_COST, "label charged at its tuning price")
	_expect(
		table.label_for(order, state) and state.money == money - CompanyTuning.LABEL_COST,
		"same order again is free",
	)
	_expect(
		table.label_for({"id": "o2", "house_id": "campo_house_2"}, state),
		"relabeling for another order works",
	)
	_expect(table.box.label_order_id == &"o2", "the newest label wins")
	state.reset()


func _test_round_trip() -> void:
	var table: PackingStation = PackingStation.make(&"t1")
	table.start_box(&"L")
	table.stage_product(&"mug")
	table.stage_product(&"vase")
	table.put_in_box(_product(&"mug", Vector3i.ONE), Vector3i.ZERO)
	var copy: PackingStation = PackingStation.from_dict(JSON.parse_string(JSON.stringify(table.to_dict())))
	_expect(copy.id == &"t1" and copy.staged == [&"vase"], "id and staged products survive JSON")
	_expect(copy.box != null and copy.box.box_size == &"L", "the box survives JSON")
	_expect(copy.box.contents() == {&"mug": 1}, "the box content survives JSON")
	_expect(PackingStation.from_dict({}) == null, "empty dict gives no table")
	_expect(not PackingStation.from_dict({"id": "t2"}).has_box(), "a table without box stays free")
