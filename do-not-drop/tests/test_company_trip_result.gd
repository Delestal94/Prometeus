extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trip_result.gd
##
## Result of a trip at close (expansion D-0320, trip_result.gd). A trip with two orders of 2 hens
## (the hen price plus shipping) and a third that never arrives:
## - the intact delivery pays in full and its carrier earns TRIP_MERIT_INTACT;
## - the broken one loses its share (verdict from OrderPenalties) and earns no merit;
## - the undelivered one is FAILED, pays 0 and its whole base pay counts as penalty;
## - the totals add up, a trip still out has no summary, and applying twice pays merit once;
## - add_to_day() folds several trips into the day's summary.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node_or_null(^"CrewProgression")
	if crew == null or crew.get_script() == null:
		push_error("CrewProgression autoload missing")
		quit(1)
		return
	crew.reset_campaign(false)
	_test_mixed_trip(crew)
	_test_still_out()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _closed_trip(book: OrderBook, products: Dictionary) -> Trip:
	for i in 3:
		var id := StringName("o%d" % (i + 1))
		book.add(Order.make(id, "Ana", &"centro", StringName("h%d" % (i + 1)), [{"product": &"hen", "qty": 2}], 0, products))
		book.mark_packed(id, StringName("b%d" % (i + 1)))
	var ids: Array[StringName] = [&"o1", &"o2", &"o3"]
	var boxes: Array[StringName] = [&"b1", &"b2", &"b3"]
	return Trip.start(&"t1", &"van", ids, boxes, book, 60)


func _test_mixed_trip(crew: Node) -> void:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var book := OrderBook.new()
	var trip: Trip = _closed_trip(book, products)
	var base: int = int(book.get_order(&"o1")["pay"])
	_expect(trip.deliver(&"o1", book, 100, true, 100), "o1 delivered intact")
	_expect(trip.deliver(&"o2", book, 100, false, 100), "o2 delivered broken")
	trip.close(book, 150)
	var verdicts: Dictionary = {
		&"o2": {"pay": base / 2, "kinds": [OrderPenalties.KIND_BROKEN], "reputation": -5.0},
	}
	var carriers: Dictionary = {&"o1": 7, &"o2": 8, &"o3": 7}
	var result: Dictionary = TripResult.build(trip, book, verdicts, carriers)
	_expect(result["delivered"] == 2 and result["failed"] == 1, "2 delivered, 1 failed")
	_expect(result["intact"] == 1 and result["broken"] == 1, "one box intact, one broken")
	_expect(result["duration_min"] == 90, "the trip lasted 90 minutes")
	var lines: Array = result["orders"]
	_expect(lines[0]["pay"] == base and lines[0]["penalty"] == 0, "the intact one pays in full")
	_expect(lines[1]["box"] == TripResult.BOX_BROKEN and lines[1]["penalty"] == base - base / 2, "the broken one loses its share")
	_expect(lines[2]["outcome"] == TripResult.OUTCOME_FAILED and lines[2]["pay"] == 0, "the undelivered one pays 0")
	_expect(lines[2]["penalty"] == base and lines[2]["box"] == TripResult.BOX_UNDELIVERED, "its whole base pay is lost")
	_expect(result["pay_total"] == base + base / 2, "pay total adds up")
	_expect(result["penalty_total"] == (base - base / 2) + base, "penalty total adds up")
	_expect(is_equal_approx(float(result["reputation"]), -5.0), "reputation of the trip is the verdicts' sum")
	_expect(result["merit_by_peer"] == {7: CompanyTuning.TRIP_MERIT_INTACT}, "only the intact carrier earns merit")
	var before: int = int(crew.merit.get(7, 0))
	_expect(TripResult.apply(result, crew) == CompanyTuning.TRIP_MERIT_INTACT, "apply awards the merit")
	_expect(int(crew.merit.get(7, 0)) == before + CompanyTuning.TRIP_MERIT_INTACT, "peer 7 has the merit")
	_expect(int(crew.merit.get(8, 0)) == 0, "peer 8 (broken box) has none")
	_expect(TripResult.apply(result, crew) == 0, "applying twice pays nothing")
	var day: Dictionary = TripResult.add_to_day({"day": 1}, [result, result])
	_expect(day["trips"] == 2 and day["trip_deliveries"] == 4 and day["trip_failed"] == 2, "day counts both trips")
	_expect(day["trip_pay"] == 2 * result["pay_total"] and day["day"] == 1, "day pay sums and keeps its keys")
	_expect(TripResult.apply(result, null) == 0, "no crew, no merit")


func _test_still_out() -> void:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var book := OrderBook.new()
	var trip: Trip = _closed_trip(book, products)
	var result: Dictionary = TripResult.build(trip, book)
	_expect(result["orders"].is_empty() and result["delivered"] == 0, "a trip still out has no summary")
	_expect(TripResult.build(null, book)["trip_id"] == &"", "a null trip is an empty summary")
