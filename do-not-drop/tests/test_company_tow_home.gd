extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_tow_home.gd
##
## Tow home (expansion D-0307, trip_tow.gd, CompanyTuning.TOW_COST):
## - a STUCK (or BROKEN) vehicle on an open Trip is towed: the wallet drops TOW_COST with ledger reason
##   `tow`, the Trip closes, the orders not delivered are FAILED and the answer carries the cost,
##   the failed ids and the black screen seconds;
## - a delivered order stays DELIVERED and the products of a failed sound box go back to the dock;
## - a vehicle that still runs is refused (NOT_STUCK) and nothing is charged or closed;
## - a wallet that does not cover the tow is refused (NO_MONEY) and the Trip stays open;
## - no trip, or an already closed one, is refused (NO_TRIP) and a second tow never charges twice;
## - every key of the answers exists in strings_world.csv.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node_or_null(^"CompanyState")
	if state == null or state.get_script() == null:
		push_error("CompanyState autoload missing")
		quit(1)
		return
	_test_stuck_is_towed(state)
	_test_broken_and_inventory(state)
	_test_not_stuck_refused(state)
	_test_no_money_refused(state)
	_test_no_trip_and_double_tow(state)
	_test_keys_exist()
	state.reset()
	if _failures == 0:
		print("PASS: a stuck vehicle is towed home for TOW_COST and its trip closes; refusals change nothing")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


## Book with orders o1..oN packed in box b1..bN, and a Trip out with all of them.
func _setup(count: int) -> Array:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var book := OrderBook.new()
	var inv := Inventory.new()
	var ids: Array[StringName] = []
	var boxes: Array[StringName] = []
	for i in count:
		var id := StringName("o%d" % (i + 1))
		var box := StringName("b%d" % (i + 1))
		var house := StringName("h%d" % (i + 1))
		book.add(Order.make(id, "Ana", &"centro", house, [{"product": &"hen", "qty": 2}], 0, products))
		book.mark_packed(id, box)
		inv.receive(&"hen", 2, StringName("box:" + str(box)))
		ids.append(id)
		boxes.append(box)
	var trip: Trip = Trip.start(&"t1", &"van", ids, boxes, book, 600)
	return [book, inv, trip]


func _test_stuck_is_towed(state: Node) -> void:
	state.new_company("Tow Co")
	var s: Array = _setup(3)
	var book: OrderBook = s[0]
	var trip: Trip = s[2]
	trip.deliver(&"o1", book, 90, true, 620)
	var money: int = state.money
	_expect(CompanyTuning.TOW_COST == 50, "the tow costs 50")
	var r: Dictionary = TripTow.tow_home(trip, TripTow.VEHICLE_STUCK, state, book, 650)
	_expect(r["ok"] and r["key"] == TripTow.DONE, "a stuck vehicle is towed")
	_expect(r["cost"] == CompanyTuning.TOW_COST, "the answer carries the cost")
	_expect(r["black_screen_s"] == CompanyTuning.TOW_BLACK_SCREEN_SECONDS and r["black_screen_s"] == 3.0,
		"3 s of black screen")
	_expect(state.money == money - 50, "the wallet drops 50 (got %d from %d)" % [state.money, money])
	_expect(state.ledger_total(TripTow.LEDGER_REASON) == -50, "the ledger has the tow line")
	_expect(not trip.is_out() and trip.return_min == 650, "the trip is closed at the tow minute")
	_expect(r["failed_ids"] == [&"o2", &"o3"], "the undelivered orders failed")
	_expect(book.state_of(&"o1") == Order.STATE_DELIVERED, "o1 stays DELIVERED")
	_expect(book.state_of(&"o2") == Order.STATE_FAILED and book.state_of(&"o3") == Order.STATE_FAILED,
		"o2 and o3 are FAILED")


func _test_broken_and_inventory(state: Node) -> void:
	state.new_company()
	var s: Array = _setup(2)
	var book: OrderBook = s[0]
	var inv: Inventory = s[1]
	var trip: Trip = s[2]
	var broken: Array[StringName] = [&"b2"]
	var r: Dictionary = TripTow.tow_home(trip, TripTow.VEHICLE_BROKEN, state, book, 700, inv, broken)
	_expect(r["ok"], "a broken vehicle is towed too")
	_expect(inv.count(&"hen", Trip.RETURN_LOCATION) == 2, "the sound box's products went back to the dock")
	_expect(trip.lost_units == 2 and trip.returned_units == 2, "the broken box lost its products")


func _test_not_stuck_refused(state: Node) -> void:
	state.new_company()
	var s: Array = _setup(2)
	var book: OrderBook = s[0]
	var trip: Trip = s[2]
	var r: Dictionary = TripTow.tow_home(trip, TripTow.VEHICLE_OK, state, book, 650)
	_expect(not r["ok"] and r["key"] == TripTow.NOT_STUCK, "a vehicle that runs is refused")
	_expect(r["cost"] == 0 and r["failed_ids"].is_empty() and r["black_screen_s"] == 0.0, "a refusal takes nothing")
	_expect(state.money == CompanyTuning.STARTING_MONEY and state.ledger.is_empty(), "nothing charged")
	_expect(trip.is_out() and book.state_of(&"o1") == Order.STATE_OUT, "the trip stays open")


func _test_no_money_refused(state: Node) -> void:
	state.new_company()
	state.charge(state.money - (CompanyTuning.TOW_COST - 1), &"rent")  # 49 left
	_expect(state.money == CompanyTuning.TOW_COST - 1, "setup: 49 in the wallet")
	var s: Array = _setup(2)
	var book: OrderBook = s[0]
	var trip: Trip = s[2]
	var size: int = state.ledger.size()
	var r: Dictionary = TripTow.tow_home(trip, TripTow.VEHICLE_STUCK, state, book, 650)
	_expect(not r["ok"] and r["key"] == TripTow.NO_MONEY and r["args"] == [CompanyTuning.TOW_COST],
		"a wallet short by one is refused with the price")
	_expect(state.money == 49 and state.ledger.size() == size, "nothing charged")
	_expect(trip.is_out() and book.state_of(&"o1") == Order.STATE_OUT, "the trip stays open")
	state.earn(1, &"order_paid")
	_expect(TripTow.tow_home(trip, TripTow.VEHICLE_STUCK, state, book, 650)["ok"], "with exactly 50 it goes through")
	_expect(state.money == 0, "the wallet is emptied, not left in the red")
	_expect(TripTow.tow_home(trip, TripTow.VEHICLE_STUCK, null, book, 650)["key"] == TripTow.NO_TRIP,
		"a closed trip is no trip")


func _test_no_trip_and_double_tow(state: Node) -> void:
	state.new_company()
	var s: Array = _setup(1)
	var book: OrderBook = s[0]
	var trip: Trip = s[2]
	var r: Dictionary = TripTow.tow_home(null, TripTow.VEHICLE_STUCK, state, book, 650)
	_expect(not r["ok"] and r["key"] == TripTow.NO_TRIP, "no trip, no tow")
	_expect(TripTow.tow_home(trip, TripTow.VEHICLE_STUCK, state, book, 650)["ok"], "first tow goes through")
	var money: int = state.money
	r = TripTow.tow_home(trip, TripTow.VEHICLE_STUCK, state, book, 660)
	_expect(not r["ok"] and r["key"] == TripTow.NO_TRIP, "the closed trip cannot be towed again")
	_expect(state.money == money and trip.return_min == 650, "a second tow charges nothing and keeps the first close")
	var no_wallet: Array = _setup(1)
	r = TripTow.tow_home(no_wallet[2], TripTow.VEHICLE_STUCK, null, no_wallet[0], 650)
	_expect(not r["ok"] and r["key"] == TripTow.NO_MONEY and no_wallet[2].is_out(),
		"no wallet counts as no money")


func _test_keys_exist() -> void:
	var text: String = FileAccess.get_file_as_string("res://translations/strings_world.csv")
	for key: String in [TripTow.NO_TRIP, TripTow.NOT_STUCK, TripTow.NO_MONEY, TripTow.DONE]:
		_expect(text.contains("\n" + key + ","), "strings_world.csv has " + key)
