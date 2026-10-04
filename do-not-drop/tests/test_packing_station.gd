extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_packing_station.gd
##
## Packing table (expansion D-0701, packing_station.gd):
## - a table takes one box at a time and refuses unknown sizes;
## - products wait on the table up to STAGING_SLOTS and can be taken back;
## - put_in_box() moves a staged product into the box's grid, and refuses (changing
##   nothing) with no box, an unstaged product or a spot that does not fit;
## - take_box() frees the table; to_dict() survives a JSON round trip.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_box()
	_test_staging()
	_test_put_in_box()
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
	_expect(not table.put_in_box(_product(&"vase", Vector3i.ONE), Vector3i.ZERO), "unstaged product refused")
	_expect(not table.put_in_box(mug, Vector3i(0, 0, 2)), "a spot that sticks out is refused")
	_expect(table.staged == [&"mug"] and table.box.items.is_empty(), "a refusal changes nothing")
	_expect(table.put_in_box(mug, Vector3i.ZERO), "the staged product goes in the box")
	_expect(table.staged.is_empty(), "it left the table")
	_expect(table.box.contents() == {&"mug": 1}, "the box knows its content")
	_expect(not table.put_in_box(mug, Vector3i.ZERO), "the same unit cannot go in twice")


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
