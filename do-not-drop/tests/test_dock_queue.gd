extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dock_queue.gd
##
## The rule of the supplier dock when trucks overlap (expansion D-0621.c.a, dock_queue.gd):
## - trucks that do not overlap pull in at their own arrival and stay until their own departure;
## - overlapping ones queue first come first served by arrival: with one bay the later waits outside
##   (start = the minute the bay frees) and still leaves on time; with two bays both pull in as they arrive;
## - a truck whose departure comes before a bay frees up is "no_room" and does not hold a bay; one whose
##   stay is wholly outside DAY_START_MIN..DAY_END_MIN is "outside_day"; one that straddles an edge is cut
##   (visible_start / visible_end) but fits;
## - a tie on arrival goes to the default supplier, then by id, whatever the order the list came in;
## - the five real suppliers of data/suppliers/ ordered for one day (SupplierSchedule + DockQueue.plan_day)
##   all fit in one bay, back to back, and nobody waits with two.

const CENTRAL: StringName = &"distribuidora_central"
const MERCADO: StringName = &"mercado_del_campo"
const FERIA: StringName = &"feria_de_antiguedades"
const PANADERIA: StringName = &"panaderia_mayorista"
const IMPORTADORA: StringName = &"importadora_express"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_bays_constant()
	_test_no_overlap()
	_test_queue_one_bay_and_two()
	_test_no_room()
	_test_outside_day()
	_test_tie()
	_test_bad_input()
	_test_real_suppliers()
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", label)


static func _truck(supplier: StringName, arrival: int, departure: int) -> Dictionary:
	return {"supplier": supplier, "arrival": arrival, "departure": departure}


func _test_bays_constant() -> void:
	_expect(CompanyTuning.SUPPLIER_DOCK_BAYS == 1, "the shed has one dock bay today (D-0640 raises it)")


func _test_no_overlap() -> void:
	var trucks: Array[Dictionary] = [_truck(&"b", 600, 660), _truck(&"a", 480, 540)]
	var planned: Array[Dictionary] = DockQueue.plan(trucks, 1)
	_expect(planned.size() == 2 and planned[0]["supplier"] == &"a" and planned[1]["supplier"] == &"b",
		"the plan goes in queue order (got %s)" % [planned])
	_expect(planned[0]["fits"] and planned[0]["bay"] == 0 and planned[0]["start"] == 480 and planned[0]["end"] == 540,
		"a truck with nobody in the way keeps its times (got %s)" % [planned[0]])
	_expect(planned[1]["fits"] and planned[1]["bay"] == 0 and planned[1]["start"] == 600 and planned[1]["end"] == 660
		and planned[1]["reason"] == &"", "so does the second (got %s)" % [planned[1]])
	var touching: Array[Dictionary] = DockQueue.plan([_truck(&"a", 480, 540), _truck(&"b", 540, 600)], 1)
	_expect(touching[1]["fits"] and touching[1]["start"] == 540, "one leaves as the next arrives: no wait")
	_expect(DockQueue.plan([] as Array[Dictionary], 1).is_empty(), "no trucks, no plan")


func _test_queue_one_bay_and_two() -> void:
	var trucks: Array[Dictionary] = [_truck(CENTRAL, 510, 690), _truck(MERCADO, 450, 570)]
	var one: Array[Dictionary] = DockQueue.plan(trucks, 1)
	_expect(one[0]["supplier"] == MERCADO and one[0]["start"] == 450 and one[0]["end"] == 570 and one[0]["bay"] == 0,
		"one bay: the first to arrive (mercado) pulls in on time (got %s)" % [one[0]])
	_expect(one[1]["supplier"] == CENTRAL and one[1]["fits"] and one[1]["start"] == 570 and one[1]["end"] == 690
		and one[1]["bay"] == 0,
		"one bay: central waits outside until 09:30 and still leaves at 11:30 (got %s)" % [one[1]])
	_expect(one[0]["visible_start"] == 480 and one[0]["visible_end"] == 570,
		"mercado's stay is cut to the opening of the day (got %s)" % [one[0]])
	var two: Array[Dictionary] = DockQueue.plan(trucks, 2)
	_expect(two[0]["fits"] and two[0]["bay"] == 0 and two[0]["start"] == 450, "two bays: mercado in bay 0")
	_expect(two[1]["fits"] and two[1]["bay"] == 1 and two[1]["start"] == 510 and two[1]["end"] == 690,
		"two bays: central pulls in at 08:30 in bay 1, nobody waits (got %s)" % [two[1]])
	var three: Array[Dictionary] = DockQueue.plan([
		_truck(&"a", 480, 600), _truck(&"b", 490, 600), _truck(&"c", 500, 650), _truck(&"d", 510, 700),
	], 2)
	_expect(three[2]["fits"] and three[2]["start"] == 600 and three[2]["bay"] == 0,
		"two bays, three trucks at once: the third waits for the first bay that frees (got %s)" % [three[2]])
	_expect(three[3]["fits"] and three[3]["start"] == 600 and three[3]["bay"] == 1,
		"and the fourth for the other (got %s)" % [three[3]])
	_expect(DockQueue.plan(trucks, 0)[1]["start"] == 570, "fewer than one bay is taken as one")


func _test_no_room() -> void:
	# A holds the bay until 700; B wants 500..600 and could only pull in at 700: it does not fit.
	var trucks: Array[Dictionary] = [_truck(&"a", 480, 700), _truck(&"b", 500, 600), _truck(&"c", 650, 720)]
	var planned: Array[Dictionary] = DockQueue.plan(trucks, 1)
	var b: Dictionary = DockQueue.entry_of(planned, &"b")
	_expect(not b["fits"] and b["reason"] == DockQueue.REASON_NO_ROOM and b["bay"] == -1,
		"a truck that would leave before a bay frees is no_room (got %s)" % [b])
	var c: Dictionary = DockQueue.entry_of(planned, &"c")
	_expect(c["fits"] and c["start"] == 700 and c["end"] == 720,
		"a no_room truck holds no bay: the next one gets it as soon as A leaves (got %s)" % [c])
	_expect(DockQueue.fitting(planned) == [&"a", &"c"],
		"fitting() lists who fits in queue order (got %s)" % [DockQueue.fitting(planned)])
	var exact: Array[Dictionary] = DockQueue.plan([_truck(&"a", 480, 600), _truck(&"b", 500, 600)], 1)
	_expect(not exact[1]["fits"] and exact[1]["reason"] == &"no_room",
		"leaving the minute the bay frees is still no_room")
	_expect(DockQueue.plan([_truck(&"z", 500, 500)], 1)[0]["reason"] == &"no_room", "a stay of no minutes is no_room")
	_expect(DockQueue.entry_of(planned, &"ghost").is_empty(), "entry_of() of a supplier that is not there is empty")


func _test_outside_day() -> void:
	var start: int = CompanyTuning.DAY_START_MIN
	var end: int = CompanyTuning.DAY_END_MIN
	var before: Dictionary = DockQueue.plan([_truck(&"a", 300, start)], 1)[0]
	_expect(not before["fits"] and before["reason"] == DockQueue.REASON_OUTSIDE_DAY,
		"gone by the time the day opens: outside_day (got %s)" % [before])
	var after: Dictionary = DockQueue.plan([_truck(&"a", end, end + 60)], 1)[0]
	_expect(not after["fits"] and after["reason"] == &"outside_day", "arrives as the day closes: outside_day")
	var opening: Dictionary = DockQueue.plan([_truck(&"a", start - 60, start + 20)], 1)[0]
	_expect(opening["fits"] and opening["start"] == start - 60 and opening["visible_start"] == start
		and opening["visible_end"] == start + 20,
		"already parked when the day opens: fits, cut at the opening (got %s)" % [opening])
	var closing: Dictionary = DockQueue.plan([_truck(&"a", end - 10, end + 120)], 1)[0]
	_expect(closing["fits"] and closing["visible_start"] == end - 10 and closing["visible_end"] == end,
		"still parked when the day closes: fits, cut at the closing (got %s)" % [closing])


func _test_tie() -> void:
	var forward: Array[Dictionary] = [_truck(&"b_two", 540, 600), _truck(CENTRAL, 540, 700), _truck(&"a_one", 540, 800)]
	var backward: Array[Dictionary] = [forward[2], forward[1], forward[0]]
	var first: Array[Dictionary] = DockQueue.plan(forward, 1)
	var second: Array[Dictionary] = DockQueue.plan(backward, 1)
	_expect(first == second, "the plan does not depend on the order the list came in")
	_expect(first[0]["supplier"] == CENTRAL and first[1]["supplier"] == &"a_one" and first[2]["supplier"] == &"b_two",
		"a tie: the default supplier first, then by id (got %s)" % [first])
	_expect(first[0]["start"] == 540 and first[1]["start"] == 700 and first[1]["fits"],
		"the default truck takes the bay, the other waits (got %s)" % [first[1]])
	_expect(not first[2]["fits"] and first[2]["reason"] == &"no_room", "and the last has no room (got %s)" % [first[2]])


func _test_bad_input() -> void:
	var junk: Array[Dictionary] = [
		{}, {"supplier": "Bad-Id", "arrival": 500, "departure": 600}, _truck(&"ok", 500, 600),
	]
	var planned: Array[Dictionary] = DockQueue.plan(junk, 1)
	_expect(planned.size() == 1 and planned[0]["supplier"] == &"ok",
		"trucks without a good supplier id are skipped (got %s)" % [planned])
	_expect(DockQueue.trucks_of(null, 5).is_empty(), "no calendar, no trucks")


func _test_real_suppliers() -> void:
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	_expect(catalog.errors.is_empty(), "the catalog loads (got %s)" % [catalog.errors])
	var schedule := SupplierSchedule.new()
	schedule.use_suppliers(catalog.all(CompanyCatalog.SUPPLIERS))
	for supplier: StringName in [CENTRAL, MERCADO, FERIA, PANADERIA, IMPORTADORA]:
		schedule.place(4, [{"product": &"milk_canister", "qty": 1}], supplier)
	_expect(DockQueue.trucks_of(schedule, 5).size() == 5, "five trucks booked for day 5")
	_expect(DockQueue.plan_day(schedule, 6).is_empty(), "a day with no truck has no plan")

	var planned: Array[Dictionary] = DockQueue.plan_day(schedule, 5)
	_expect(DockQueue.fitting(planned) == [PANADERIA, MERCADO, CENTRAL, FERIA, IMPORTADORA],
		"all five fit in one bay, in order of arrival (got %s)" % [planned])
	# [supplier, start, end]: each pulls in when the one before leaves.
	var expected: Array = [
		[PANADERIA, 7 * 60, 8 * 60 + 30], [MERCADO, 8 * 60 + 30, 9 * 60 + 30],
		[CENTRAL, 9 * 60 + 30, 11 * 60 + 30], [FERIA, 11 * 60 + 30, 14 * 60], [IMPORTADORA, 14 * 60, 15 * 60],
	]
	for index: int in mini(planned.size(), expected.size()):
		var row: Array = expected[index]
		var got: Dictionary = planned[index]
		_expect(got["supplier"] == row[0] and got["start"] == row[1] and got["end"] == row[2] and got["bay"] == 0,
			"%s stays %d..%d (got %s)" % [row[0], row[1], row[2], got])
	var bakery: Dictionary = DockQueue.entry_of(planned, PANADERIA)
	_expect(bakery["visible_start"] == CompanyTuning.DAY_START_MIN and bakery["visible_end"] == 8 * 60 + 30,
		"the bakery is seen from the opening of the day to 08:30 (got %s)" % [bakery])

	var two: Array[Dictionary] = DockQueue.plan_day(schedule, 5, 2)
	for entry: Dictionary in two:
		var supplier: StringName = entry["supplier"]
		_expect(entry["fits"] and entry["start"] == schedule.arrival_minute_of(supplier)
			and entry["end"] == schedule.departure_minute_of(supplier), "two bays: %s keeps its own times" % supplier)

	# The default truck keeps CompanyTuning's times whatever the queue does around it.
	var central: Dictionary = DockQueue.entry_of(planned, CENTRAL)
	_expect(central["end"] == SupplierSchedule.departure_minute(), "central always leaves at its own hour")

	# Without the bakery the others do not move earlier: mercado is first and keeps its own arrival.
	var others: Array[Dictionary] = []
	for truck: Dictionary in DockQueue.trucks_of(schedule, 5):
		if truck["supplier"] != PANADERIA:
			others.append(truck)
	var no_bakery: Array[Dictionary] = DockQueue.plan(others, 1)
	_expect(no_bakery[0]["supplier"] == MERCADO and no_bakery[0]["start"] == 7 * 60 + 30
		and no_bakery[1]["start"] == 9 * 60 + 30,
		"without the bakery: mercado 07:30, central still waits for it (got %s)" % [no_bakery])
	if _failures == 0:
		print("PASS: dock queue")
