extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_shelf_picking.gd
##
## Picking from a shelf by hand (expansion D-0609, shelf_picking.gd, CompanyShed.station_for,
## CompanyNet.request_for):
## - station names round-trip (station_id / parse_station) and a bad name parses to {};
## - plan() takes what is in the slot up to CompanyTuning.HAND_MAX_UNITS, tops up the product already
##   in the hands, and refuses with hands_full, hands_busy (another product) or empty;
## - with empty hands the slot rotates over the filled ones after the last one picked, wrapping;
## - the shed resolves its shelf slots as stations (location, reach spot, accepts, capacity) and nothing
##   else; an unlabeled slot or an unknown shelf is no station;
## - end to end, solo: a use asks the host for units_take and taking 3 units lowers the slot's stock
##   by 3 and puts them in the hands, nothing created or lost; far from the shelf it is refused.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_names()
	_test_plan()
	await _test_end_to_end()
	if _failures == 0:
		print("PASS: picking from a shelf takes up to the hand limit and the stock goes down by as much")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _test_names() -> void:
	var id: StringName = ShelfPicking.station_id(&"shelf_1", 3)
	_expect(ShelfPicking.parse_station(id) == {"uid": &"shelf_1", "slot": 3}, "station name round trip (%s)" % id)
	_expect(ShelfPicking.parse_station(&"shelf_hen").is_empty(), "a name without a slot is no shelf station")
	_expect(ShelfPicking.parse_station(&"shelf_1_slotx").is_empty(), "a non-numeric slot is no shelf station")
	_expect(ShelfPicking.parse_station(&"_slot1").is_empty(), "no uid is no shelf station")


func _test_plan() -> void:
	var shelf: Shelf = Shelf.make(&"s1", 4)
	var inv := Inventory.new()
	var hands: StringName = CompanyNet.hands_location(7)
	shelf.set_label(inv, 0, &"hen")
	shelf.set_label(inv, 1, &"lamp")
	shelf.set_label(inv, 2, &"cake")
	inv.receive(&"hen", 10, shelf.location(0))
	inv.receive(&"lamp", 2, shelf.location(1))
	var plan: Dictionary = ShelfPicking.plan(&"s1", shelf, inv, hands)
	_expect(plan.get("product") == &"hen" and plan.get("qty") == CompanyTuning.HAND_MAX_UNITS
		and plan.get("slot") == 0, "Empty hands take the first filled slot, up to the limit (%s)" % [plan])
	plan = ShelfPicking.plan(&"s1", shelf, inv, hands, 0)
	_expect(plan.get("product") == &"lamp" and plan.get("qty") == 2 and plan.get("slot") == 1,
		"After slot 0 comes slot 1, taking only what is there (%s)" % [plan])
	plan = ShelfPicking.plan(&"s1", shelf, inv, hands, 1)
	_expect(plan.get("slot") == 0, "The cursor wraps around the empty slots (%s)" % [plan])
	inv.receive(&"hen", 3, hands)
	plan = ShelfPicking.plan(&"s1", shelf, inv, hands, 1)
	_expect(plan.get("product") == &"hen" and plan.get("qty") == 1,
		"Hands with 3 hens top up to the limit, whatever the cursor says (%s)" % [plan])
	inv.receive(&"hen", 1, hands)
	_expect(ShelfPicking.plan(&"s1", shelf, inv, hands).get("reason") == ShelfPicking.REASON_HANDS_FULL,
		"Full hands are refused with hands_full")
	inv.consume(&"hen", 4, hands)
	inv.receive(&"mug", 1, hands)
	_expect(ShelfPicking.plan(&"s1", shelf, inv, hands).get("reason") == ShelfPicking.REASON_HANDS_BUSY,
		"Hands holding a product the shelf does not label are busy")
	inv.consume(&"mug", 1, hands)
	inv.consume(&"hen", 10, shelf.location(0))
	inv.consume(&"lamp", 2, shelf.location(1))
	_expect(ShelfPicking.plan(&"s1", shelf, inv, hands).get("reason") == ShelfPicking.REASON_EMPTY,
		"A shelf with nothing on it is refused with empty")
	_expect(ShelfPicking.plan(&"s1", null, inv, hands).get("reason") == ShelfPicking.REASON_EMPTY,
		"No shelf is refused with empty")


func _test_end_to_end() -> void:
	var data: DefaultShed = DefaultShed.load_default()
	var state := DefaultShed.ScratchState.new()
	data.apply_to(state)
	var shed := CompanyShed.new()
	root.add_child(shed)
	shed.rebuild(state, state.stock())
	await process_frame
	var uid: StringName = &""
	var slot: int = -1
	for shelf_uid: StringName in shed.shelves:
		var found: Shelf = shed.shelves[shelf_uid]
		for i: int in found.slot_count():
			if found.label_of(i) != &"" and slot == -1:
				uid = shelf_uid
				slot = i
	_expect(slot != -1, "The default shed has a labeled shelf slot")
	if slot == -1:
		shed.free()
		return
	var shelf: Shelf = shed.shelves[uid]
	var product: StringName = shelf.label_of(slot)
	var id: StringName = ShelfPicking.station_id(uid, slot)
	var station: Dictionary = shed.station_for(id)
	_expect(station.get("location") == shelf.location(slot) and station.get("accepts") == product
		and station.get("capacity") == CompanyTuning.SHELF_SLOT_CAPACITY and station.get("spot") is Vector3,
		"The shed resolves a labeled slot as a station (%s)" % [station])
	_expect(shed.station_for(ShelfPicking.station_id(uid, shelf.slot_count() - 1)).is_empty()
		or shelf.label_of(shelf.slot_count() - 1) != &"", "A slot with no label is no station")
	_expect(shed.station_for(ShelfPicking.station_id(&"no_such_shelf", 0)).is_empty()
		and shed.station_for(&"dock").is_empty(), "An unknown shelf or a plain name is no station")

	var net := CompanyNet.new()
	net.name = "PickingNet"
	root.add_child(net)
	net.stations = shed.station_for
	var near: Vector3 = station["spot"]
	net.player_origin = func(_peer: int) -> Variant: return near
	var refusals: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		refusals.append([rid, reason]))
	net.inventory.receive(product, 4, shelf.location(slot))
	var hands: StringName = CompanyNet.hands_location(1)
	var plan: Dictionary = ShelfPicking.plan(uid, shelf, net.inventory, hands)
	_expect(plan.get("qty") == CompanyTuning.HAND_MAX_UNITS, "The plan takes the hand limit of 4 (%s)" % [plan])
	_expect(net.request_for(1, &"units_take", {"station": plan["station"], "product": product, "qty": 3}),
		"The host asks on behalf of the peer")
	_expect(net.inventory.count(product, shelf.location(slot)) == 1 and net.inventory.count(product, hands) == 3,
		"Taking 3 lowers the slot by 3 and fills the hands (slot %d, hands %d)"
		% [net.inventory.count(product, shelf.location(slot)), net.inventory.count(product, hands)])
	net.request_for(1, &"units_take", {"station": plan["station"], "product": product, "qty": 1})
	_expect(net.inventory.count(product, hands) == 4 and net.inventory.count(product, shelf.location(slot)) == 0
		and net.inventory.total_units() == 4, "A second use empties the slot into the hands, without creating units")
	net.request_for(1, &"units_take", {"station": plan["station"], "product": product, "qty": 1})
	_expect(refusals.size() == 1 and refusals[0][1] == CompanyNet.REASON_NOT_ENOUGH,
		"Taking from an empty slot is refused (%s)" % [refusals])
	net.inventory.receive(product, 1, shelf.location(slot))
	net.player_origin = func(_peer: int) -> Variant: return near + Vector3(40.0, 0.0, 0.0)
	net.request_for(1, &"units_take", {"station": plan["station"], "product": product, "qty": 1})
	_expect(refusals.size() == 2 and refusals[1][1] == CompanyNet.REASON_OUT_OF_REACH
		and net.inventory.count(product, shelf.location(slot)) == 1, "Far from the shelf it is refused (%s)" % [refusals])
	_expect(not net.request_for(99, &"units_take", {}), "A peer that is not in the session is ignored")
	net.free()
	shed.free()
