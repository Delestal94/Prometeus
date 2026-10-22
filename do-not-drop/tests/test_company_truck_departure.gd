extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_truck_departure.gd
##
## The supplier truck driving off with what was left on its bed, and the delivery note (expansion D-0618.b and
## D-0614.b: CompanyPallets.departed_event / DEPARTED / note, CompanyNet, CompanyRoot._send_truck_off):
## - departed_event() is empty before the departure minute and without a delivery; after it, it lists every ordered
##   product with what was unloaded (the pallets that are not on the bed) and leaves the calendar as it was;
## - jack_departed on the host takes the pallets of the bed off the book (the ones on the floor stay), records the
##   day's shortfall in the note, and a second peer fed the same events holds the same book and note; the day
##   leaves a calendar only when the event is applied, so a refused publish asks again;
## - an even delivery leaves no record; a late joiner gets the note from the snapshot part;
## - bad data (a day below 1, a line with a negative count, too many lines, a product that is not an id) is refused
##   changing nothing;
## - the real company world (company_root.tscn, solo): on day 2 the truck drives off at its departure minute, once,
##   its pallets leave the bed and its drawing, the note says what was missing, and the calendar loses the day.
## Not covered: the note on screen (a UI task) and the save of the book (D-0605.c).

const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const DAY: int = 2
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_truck_departure"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_event()
	_test_net()
	await _test_root()
	if _failures == 0:
		print("PASS: the truck drives off with what stayed on its bed and the delivery note keeps the shortfall")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


func _schedule() -> SupplierSchedule:
	var schedule := SupplierSchedule.new()
	schedule.place(DAY - 1, [{"product": HEN, "qty": 30}, {"product": LAMP, "qty": 10}])
	return schedule


func _test_event() -> void:
	var schedule: SupplierSchedule = _schedule()
	var pallets := CompanyPallets.new()
	var planned: Array[Dictionary] = schedule.pallets_for(DAY)
	pallets.book.load_bed(planned)
	var before: Dictionary = schedule.to_dict()
	_expect(pallets.departed_event(schedule, DAY, SupplierSchedule.departure_minute() - 1, planned).is_empty(),
		"The truck still waiting: no departure")
	_expect(pallets.departed_event(schedule, DAY + 1, SupplierSchedule.departure_minute(), planned).is_empty(),
		"A day without a delivery: no departure")
	var event: Dictionary = pallets.departed_event(schedule, DAY, SupplierSchedule.departure_minute(), planned)
	_expect(int(event.get("day", 0)) == DAY and (event.get("lines", []) as Array).size() == 2,
		"At the departure minute: a line per product (%s)" % [event])
	var received: int = 0
	for line: Dictionary in event.get("lines", []):
		received += int(line["received"])
	_expect(received == 0 and schedule.to_dict() == before,
		"Nothing unloaded: all of it is short, and the calendar is untouched")
	# One hen pallet taken off the bed and put on the floor counts as unloaded.
	var unloaded: StringName = planned[1]["id"]
	pallets.book.places[unloaded]["at"] = PalletJack.AT_FLOOR
	var partial: Dictionary = pallets.departed_event(schedule, DAY, SupplierSchedule.departure_minute(), planned)
	var hens: int = 0
	for line: Dictionary in partial.get("lines", []):
		if line["product"] == String(HEN):
			hens = int(line["received"])
	_expect(hens == int(planned[1]["qty"]), "A pallet off the bed counts as received (%d hens)" % hens)


func _test_net() -> void:
	var state := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(state)
	var host := CompanyNet.new()
	host.company = state
	host.inventory = state.stock()
	root.add_child(host)
	var mirror := CompanyNet.new()
	mirror.company = state
	mirror.inventory.from_dict(host.inventory.to_dict())
	root.add_child(mirror)
	host.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		mirror._receive(seq, kind, data))
	var schedule: SupplierSchedule = _schedule()
	var planned: Array[Dictionary] = schedule.pallets_for(DAY)
	_expect(host.publish(CompanyPallets.LOADED, host.pallets.loaded_event(DAY, planned, host.inventory)),
		"The truck's pallets are loaded")
	# One hen pallet goes down to the floor through the book (the units enter the stock once).
	var first: StringName = &"d2_hen_1"
	host.pallets.book.pick_up(first)
	host.pallets.book.put_down(Vector2(2.0, 2.0), Rect2(-50.0, -50.0, 100.0, 100.0), host.inventory)
	mirror.pallets.put_snapshot(host.pallets.to_dict())
	var departure: Dictionary = host.pallets.departed_event(schedule, DAY, SupplierSchedule.departure_minute(), planned)
	_expect(host.publish(CompanyPallets.DEPARTED, departure), "The host publishes jack_departed")
	for peer: CompanyNet in [host, mirror]:
		_expect(peer.pallets.book.ids_at(PalletJack.AT_BED).is_empty() and peer.pallets.book.places.has(first),
			"The bed is empty and the floor pallet stays")
		_expect(peer.pallets.departed_day == DAY and peer.pallets.note.days_with_shortfall() == [DAY],
			"The note has the day's shortfall")
		_expect(int(peer.pallets.note.missing_totals().get(HEN, 0)) == 30 - int(planned[1]["qty"])
			and int(peer.pallets.note.missing_totals().get(LAMP, 0)) == 10,
			"... of what stayed on the bed (%s)" % [peer.pallets.note.missing_totals()])
	_expect(mirror.pallets.to_dict() == host.pallets.to_dict(), "The second peer holds the same book and note")
	var late := CompanyPallets.new()
	_expect(late.put_snapshot(host.pallets.to_dict()) and late.note.to_dict() == host.pallets.note.to_dict(),
		"A late joiner gets the note from the snapshot part")
	_expect(late.put_snapshot({"book": host.pallets.book.to_dict(), "jack_at": null, "loaded_day": DAY}),
		"... and a snapshot without the new keys still fits (an older host)")
	_expect(not late.put_snapshot({"book": host.pallets.book.to_dict(), "jack_at": null, "loaded_day": DAY,
		"departed_day": "x", "note": {}}), "... a day that is not a number does not")
	# An even delivery keeps no record.
	var even := CompanyPallets.new()
	var even_line: Dictionary = {"product": "hen", "ordered": 6, "received": 6}
	_expect(even.apply(null, CompanyPallets.DEPARTED, {"day": 3, "lines": [even_line]})
		and even.note.days_with_shortfall().is_empty() and even.note.discrepancies(3).is_empty(),
		"An even delivery leaves no record")
	# Bad data changes nothing.
	var good_line: Dictionary = {"product": "hen", "ordered": 6, "received": 0}
	var many: Array = []
	for index: int in CompanyPallets.MAX_NOTE_LINES + 1:
		many.append({"product": "p%d" % index, "ordered": 1, "received": 0})
	var bad: Array = [
		{"day": 0, "lines": [good_line]},
		{"day": 4, "lines": [{"product": "hen", "ordered": -1, "received": 0}]},
		{"day": 4, "lines": [{"product": "hen", "ordered": 1.5, "received": 0}]},
		{"day": 4, "lines": [{"product": "", "ordered": 1, "received": 0}]},
		{"day": 4, "lines": [{"product": "hen", "ordered": CompanyPallets.MAX_NOTE_UNITS + 1, "received": 0}]},
		{"day": 4, "lines": many},
		{"day": 4, "lines": [5]},
		{"day": 4},
	]
	var guard := CompanyPallets.new()
	guard.book.load_bed(planned)
	var untouched: Dictionary = guard.to_dict()
	for data: Dictionary in bad:
		_expect(not guard.apply(null, CompanyPallets.DEPARTED, data) and guard.to_dict() == untouched,
			"Refused, nothing changed: %s" % [str(data).left(60)])
	host.queue_free()
	mirror.queue_free()


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
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 8.0)
	await process_frame
	var departures: Array[Dictionary] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == CompanyPallets.DEPARTED:
			departures.append(data))
	level.clock.start(float(SupplierSchedule.arrival_minute()) - 3.0)
	await process_frame
	var on_bed: Array[StringName] = net.pallets.book.ids_at(PalletJack.AT_BED)
	_expect(not on_bed.is_empty() and level.supplier_schedule.has_delivery(DAY),
		"The truck came with pallets on its bed")
	level.clock.start(float(SupplierSchedule.departure_minute()) - 2.0)
	await process_frame
	_expect(departures.is_empty() and net.pallets.book.ids_at(PalletJack.AT_BED) == on_bed,
		"While it waits nothing leaves")
	level.clock.start(float(SupplierSchedule.departure_minute()) + 1.0)
	for _frame: int in 3:
		await process_frame
	_expect(departures.size() == 1 and net.pallets.book.ids_at(PalletJack.AT_BED).is_empty()
		and level.supplier_truck.bed_ids().is_empty(),
		"It drives off once and takes its pallets (%d events)" % departures.size())
	_expect(net.pallets.departed_day == DAY and net.pallets.note.days_with_shortfall() == [DAY]
		and not level.supplier_schedule.has_delivery(DAY),
		"The note says what was missing and the day left the calendar")
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
