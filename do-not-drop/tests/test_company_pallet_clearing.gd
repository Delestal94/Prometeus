extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_pallet_clearing.gd
##
## The pallets that ran out leave the book, and the delivery note tells what really came (expansion D-0607.b:
## PalletJack.emptied_ids, CompanyPallets.cleared_event / clear_empties / CLEARED, CompanyNet, CompanySupplierLink):
## - emptied_ids() is what stands on the floor or a rack with no units left, sealed or not (units leave a sealed
##   pallet too), never a pallet of the bed, the one on the jack or one that still holds units;
## - jack_cleared takes them off the book on the host and on a second peer, stock untouched, and the same book
##   reaches a late joiner; data that does not fit (not a list, an unknown id, a pallet of the bed or the jack) is
##   refused changing nothing;
## - a hundred days of a truck that is fully unloaded and emptied, with the real events: every truck puts all its
##   pallets on its bed, the book never grows, the note stays even and the stock has every unit;
## - a full book: the truck brings what fits, and the note says the rest was missing, as the stock does;
## - the real company world (company_root.tscn, solo): a pallet on the floor whose units rot away leaves the book and
##   the shed's drawing within a game minute, and one with units stays.

const HEN: StringName = &"hen"
const DAY: int = 2
const UNITS_PER_DAY: int = 240
const LONG_DAYS: int = 100
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_pallet_clearing"
const ANYWHERE: Rect2 = Rect2(-500.0, -500.0, 1000.0, 1000.0)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_emptied_ids()
	_test_bad_data()
	_test_net()
	_test_long_run()
	_test_full_book()
	await _test_root()
	if _failures == 0:
		print("PASS: the pallets that ran out leave the book and the delivery note tells what really came")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


## A book with `count` hen pallets of 10 units, sealed, on the bed: p1, p2...
func _loaded(count: int) -> CompanyPallets:
	var pallets := CompanyPallets.new()
	var fresh: Array[Dictionary] = []
	for n: int in range(1, count + 1):
		fresh.append(Pallet.make(StringName("p%d" % n), HEN, 10))
	pallets.book.load_bed(fresh)
	return pallets


func _to_floor(pallets: CompanyPallets, id: StringName, stock: Inventory, x: float) -> void:
	pallets.book.pick_up(id)
	pallets.book.put_down(Vector2(x, 0.0), ANYWHERE, stock)


func _test_emptied_ids() -> void:
	var stock := Inventory.new()
	var pallets: CompanyPallets = _loaded(5)
	_to_floor(pallets, &"p1", stock, 0.0)
	_to_floor(pallets, &"p2", stock, 2.0)
	pallets.book.pick_up(&"p3")
	pallets.book.put_on_rack(&"rack_1", Vector2(9.0, 9.0), stock)
	pallets.book.pick_up(&"p4")
	pallets.book.put_down(Vector2(40.0, 40.0), ANYWHERE, stock)
	pallets.book.pick_up(&"p4", Vector2(40.0, 40.0))
	_expect(pallets.cleared_event(stock).is_empty(), "Nothing ran out: no event")
	# p1 still sealed: no game path opens a pallet before its units leave, so its state must not matter.
	stock.discard(HEN, 10, Pallet.location(&"p1"))
	stock.discard(HEN, 10, Pallet.location(&"p3"))
	stock.discard(HEN, 10, Pallet.location(&"p4"))
	var emptied: Array[StringName] = pallets.book.emptied_ids(stock)
	_expect(emptied.size() == 2 and emptied[0] == &"p1" and emptied[1] == &"p3",
		"The empty ones of the floor and the rack, not the jack's (got %s)" % [emptied])
	var event: Dictionary = pallets.cleared_event(stock)
	_expect(event == {"pallets": ["p1", "p3"]}, "The event lists them (got %s)" % [event])
	var units: int = stock.total_units()
	_expect(pallets.apply(stock, CompanyPallets.CLEARED, event), "jack_cleared applies")
	_expect(not pallets.book.places.has(&"p1") and not pallets.book.places.has(&"p3")
		and pallets.book.places.has(&"p2") and pallets.book.places.has(&"p4") and pallets.book.places.has(&"p5"),
		"Only they leave the book")
	_expect(stock.total_units() == units and pallets.book.rack_pallet(&"rack_1") == &"",
		"No units moved, the slot is free")
	_expect(not pallets.apply(stock, CompanyPallets.CLEARED, event), "A second time there is nothing to clear")
	# The jack lets go of p4: now it can go.
	pallets.book.put_down(Vector2(40.0, 40.0), ANYWHERE, stock)
	emptied = pallets.book.emptied_ids(stock)
	_expect(emptied.size() == 1 and emptied[0] == &"p4", "Set down, the empty pallet is cleared too")


func _test_bad_data() -> void:
	var stock := Inventory.new()
	var pallets: CompanyPallets = _loaded(3)
	_to_floor(pallets, &"p1", stock, 0.0)
	pallets.book.pick_up(&"p2")
	var keep: Dictionary = pallets.to_dict()
	var many: Array = []
	many.resize(CompanyPallets.MAX_PALLETS + 1)
	many.fill("p1")
	var bad: Array[Dictionary] = [
		{}, {"pallets": "p1"}, {"pallets": []}, {"pallets": many}, {"pallets": ["ghost"]}, {"pallets": [7]},
		{"pallets": ["bad id!"]}, {"pallets": ["p3"]}, {"pallets": ["p2"]}, {"pallets": ["p1", "p3"]},
	]
	for data: Dictionary in bad:
		_expect(not pallets.apply(stock, CompanyPallets.CLEARED, data) and pallets.to_dict() == keep,
			"Refused, nothing changed: %s" % [str(data).left(60)])


func _test_net() -> void:
	var state := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(state)
	var host := CompanyNet.new()
	host.company = state
	host.inventory = state.stock()
	root.add_child(host)
	var mirror := CompanyNet.new()
	mirror.company = state
	root.add_child(mirror)
	host.pallets = _loaded(2)
	_to_floor(host.pallets, &"p1", host.inventory, 0.0)
	_to_floor(host.pallets, &"p2", host.inventory, 2.0)
	mirror.inventory.from_dict(host.inventory.to_dict())
	mirror.pallets.put_snapshot(host.pallets.to_dict())
	host.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		mirror._receive(seq, kind, data))
	var cleared: Array[Dictionary] = []
	mirror.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == CompanyPallets.CLEARED:
			cleared.append(data))
	host.inventory.discard(HEN, 10, Pallet.location(&"p1"))
	mirror.inventory.discard(HEN, 10, Pallet.location(&"p1"))
	CompanyPallets.clear_empties(host.pallets, host.inventory, host.publish)
	_expect(cleared.size() == 1 and not host.pallets.book.places.has(&"p1"), "The host publishes jack_cleared")
	_expect(mirror.pallets.to_dict() == host.pallets.to_dict() and mirror.pallets.book.places.size() == 1,
		"The second peer holds the same book")
	CompanyPallets.clear_empties(host.pallets, host.inventory, host.publish)
	_expect(cleared.size() == 1, "With nothing left to clear, no event")
	var late := CompanyPallets.new()
	_expect(late.put_snapshot(host.pallets.to_dict()) and late.book.places.size() == 1,
		"A late joiner gets the same book")
	host.queue_free()
	mirror.queue_free()


## What the real events do with a truck that is unloaded and emptied every day.
func _test_long_run() -> void:
	var stock := Inventory.new()
	var pallets := CompanyPallets.new()
	var schedule := SupplierSchedule.new()
	var peak: int = 0
	var short_trucks: int = 0
	var after: int = SupplierSchedule.departure_minute()
	for day: int in range(2, LONG_DAYS + 2):
		schedule.forget_before(day)
		schedule.place(day - 1, [{"product": HEN, "qty": UNITS_PER_DAY}])
		var planned: Array[Dictionary] = schedule.pallets_for(day)
		var loading: Dictionary = pallets.loaded_event(day, planned, stock)
		var came: Array = loading.get("pallets", [])
		if came.size() != planned.size():
			short_trucks += 1
		if not loading.is_empty():
			pallets.apply(stock, CompanyPallets.LOADED, loading)
		peak = maxi(peak, pallets.book.places.size())
		for index: int in came.size():
			var id: StringName = StringName(came[index]["id"])
			pallets.apply(stock, CompanyPallets.PICKED, {"pallet": id})
			pallets.apply(stock, CompanyPallets.PLACED, {"pallet": id, "pos": Vector2(float(index) * 2.0, 0.0)})
			stock.move(HEN, int(came[index]["qty"]), Pallet.location(id), &"dock")
		var departure: Dictionary = pallets.departed_event(schedule, day, after, planned)
		pallets.apply(stock, CompanyPallets.DEPARTED, departure)
		CompanyPallets.clear_empties(pallets, stock, func(kind: StringName, data: Dictionary) -> void:
			pallets.apply(stock, kind, data))
	_expect(short_trucks == 0, "Every truck puts all its pallets on its bed (%d did not)" % short_trucks)
	_expect(peak == ceili(float(UNITS_PER_DAY) / CompanyTuning.PALLET_MAX_UNITS),
		"The book holds one day's pallets, however many days went by (peak %d)" % peak)
	_expect(pallets.book.places.is_empty() and pallets.note.days_with_shortfall().is_empty(),
		"Nothing is left in the book, and the note is even")
	_expect(stock.count(HEN, &"dock") == UNITS_PER_DAY * LONG_DAYS, "Every unit reached the stock (got %d)"
		% stock.count(HEN, &"dock"))


## A book with no room for the whole truck: the note says what the stock says.
func _test_full_book() -> void:
	var stock := Inventory.new()
	var room: int = 3
	var pallets: CompanyPallets = _loaded(CompanyPallets.MAX_PALLETS - room)
	for id: StringName in pallets.book.ids_at(PalletJack.AT_BED):
		pallets.book.places[id]["at"] = PalletJack.AT_FLOOR
		pallets.book.places[id]["pos"] = Vector2.ZERO
		stock.receive(HEN, 10, Pallet.location(id))
	var schedule := SupplierSchedule.new()
	schedule.place(DAY - 1, [{"product": HEN, "qty": UNITS_PER_DAY}])
	var planned: Array[Dictionary] = schedule.pallets_for(DAY)
	var loading: Dictionary = pallets.loaded_event(DAY, planned, stock)
	var came: Array = loading.get("pallets", [])
	_expect(came.size() == room and room < planned.size(),
		"Only what fits comes (%d of %d)" % [came.size(), planned.size()])
	pallets.apply(stock, CompanyPallets.LOADED, loading)
	var units: int = stock.total_units()
	var unloaded: int = 0
	for entry: Dictionary in came:
		pallets.apply(stock, CompanyPallets.PICKED, {"pallet": entry["id"]})
		var spot := Vector2(float(unloaded) * 2.0, 9.0)
		pallets.apply(stock, CompanyPallets.PLACED, {"pallet": entry["id"], "pos": spot})
		unloaded += int(entry["qty"])
	_expect(stock.total_units() == units + unloaded, "The stock rises by what came")
	var departure: Dictionary = pallets.departed_event(schedule, DAY, SupplierSchedule.departure_minute(), planned)
	var lines: Array = departure.get("lines", [])
	_expect(lines.size() == 1 and int(lines[0]["ordered"]) == UNITS_PER_DAY and int(lines[0]["received"]) == unloaded,
		"The note receives what came, not the pallets left off the bed (%s)" % [lines])
	pallets.apply(stock, CompanyPallets.DEPARTED, departure)
	_expect(int(pallets.note.missing_totals().get(HEN, 0)) == UNITS_PER_DAY - unloaded,
		"... and says the rest is missing (%s)" % [pallets.note.missing_totals()])
	# The next truck finds the room the emptied pallets left.
	stock.discard(HEN, 10, Pallet.location(&"p1"))
	CompanyPallets.clear_empties(pallets, stock, func(kind: StringName, data: Dictionary) -> void:
		pallets.apply(stock, kind, data))
	_expect(pallets.book.places.size() == CompanyPallets.MAX_PALLETS - 1, "A pallet that ran out makes room")


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var net: CompanyNet = level.net
	if net == null:
		_expect(false, "The company world has a net")
		return
	state.set(&"day", DAY)
	level.supplier_schedule.place(DAY - 1, [{"product": HEN, "qty": 48}])
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 3.0)
	await process_frame
	await process_frame
	var on_bed: Array[StringName] = net.pallets.book.ids_at(PalletJack.AT_BED)
	_expect(on_bed.size() == 2, "The truck came with its 2 pallets (got %d)" % on_bed.size())
	if on_bed.size() != 2:
		level.queue_free()
		return
	var spent: StringName = on_bed[0]
	var kept: StringName = on_bed[1]
	var floor_rect: Rect2 = Rect2(-50.0, -50.0, 100.0, 100.0)
	net.pallets.book.pick_up(spent)
	net.pallets.book.put_down(Vector2(1.0, 1.0), floor_rect, net.inventory)
	net.pallets.book.pick_up(kept)
	net.pallets.book.put_down(Vector2(4.0, 1.0), floor_rect, net.inventory)
	level.shed.yard.refresh(net.pallets)
	_expect(level.shed.yard.floor_nodes.has(spent), "The pallet is drawn on the floor")
	level.clock.start(float(SupplierSchedule.arrival_minute()) + 1.0)
	await process_frame
	await process_frame
	_expect(net.pallets.book.places.has(spent), "With its units it stays")
	net.inventory.discard(HEN, 24, Pallet.location(spent))
	level.clock.start(float(SupplierSchedule.arrival_minute()) + 2.0)
	await process_frame
	await process_frame
	_expect(not net.pallets.book.places.has(spent) and net.pallets.book.places.has(kept),
		"Its units gone, it leaves the book within a game minute, and the other one stays")
	_expect(not level.shed.yard.floor_nodes.has(spent) and level.shed.yard.floor_nodes.has(kept),
		"... and the shed's drawing")
	level.queue_free()
	await process_frame
	state.call(&"reset")
	_clean()


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
