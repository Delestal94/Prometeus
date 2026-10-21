extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_trip_stops.gd
##
## Trip stops (expansion D-0305, trip.gd):
## - a Trip with orders for 3 houses has 3 stops, in load order, and orders of
##   the same house share a stop;
## - delivering 2 stops and coming back leaves 2 DELIVERED and 1 FAILED, and the
##   products of the failed order's sound box return to the Inventory;
## - next_stop() walks the pending houses and is empty when none is left;
## - a broken undelivered box loses its products instead of restocking them.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_three_houses()
	_test_broken_box_is_lost()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _setup(houses: Array[StringName]) -> Array:
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	var book := OrderBook.new()
	var inv := Inventory.new()
	var ids: Array[StringName] = []
	var boxes: Array[StringName] = []
	for i in houses.size():
		var id := StringName("o%d" % (i + 1))
		var box := StringName("b%d" % (i + 1))
		book.add(Order.make(id, "Ana", &"centro", houses[i], [{"product": &"hen", "qty": 2}], 0, products))
		book.mark_packed(id, box)
		inv.receive(&"hen", 2, StringName("box:" + str(box)))
		ids.append(id)
		boxes.append(box)
	return [book, inv, ids, boxes]


func _test_three_houses() -> void:
	var houses: Array[StringName] = [&"h1", &"h2", &"h3", &"h1"]
	var s: Array = _setup(houses)
	var book: OrderBook = s[0]
	var inv: Inventory = s[1]
	var trip := Trip.start(&"t1", &"van", s[2], s[3], book, 480)
	_expect(trip.stops.size() == 3, "3 houses make 3 stops")
	_expect(trip.stops[0]["order_ids"].size() == 2, "h1 holds its 2 orders")
	_expect(trip.next_stop() == &"h1", "first stop is h1")
	_expect(trip.deliver_stop(&"h1", book, 500).size() == 2, "h1 delivers both orders")
	_expect(trip.next_stop() == &"h2", "next stop is h2")
	_expect(trip.deliver_stop(&"h2", book, 510).size() == 1, "h2 delivers")
	_expect(trip.deliver_stop(&"nowhere", book, 510).is_empty(), "unknown house delivers nothing")
	_expect(trip.pending_stops() == [&"h3"], "only h3 is left")
	var failed: Array[StringName] = trip.close(book, 540, inv)
	_expect(failed == [&"o3"], "o3 fails on return")
	_expect(book.state_of(&"o1") == Order.STATE_DELIVERED, "o1 DELIVERED")
	_expect(book.state_of(&"o2") == Order.STATE_DELIVERED, "o2 DELIVERED")
	_expect(book.state_of(&"o3") == Order.STATE_FAILED, "o3 FAILED")
	_expect(inv.count(&"hen", Trip.RETURN_LOCATION) == 2, "sound box products are back in stock")
	_expect(trip.returned_units == 2 and trip.lost_units == 0, "units counted")
	_expect(trip.next_stop() == &"", "no stop after closing home")


func _test_broken_box_is_lost() -> void:
	var houses: Array[StringName] = [&"h1"]
	var s: Array = _setup(houses)
	var book: OrderBook = s[0]
	var inv: Inventory = s[1]
	var trip := Trip.start(&"t2", &"van", s[2], s[3], book, 480)
	var broken: Array[StringName] = [&"b1"]
	trip.close(book, 500, inv, broken)
	_expect(inv.count(&"hen", Trip.RETURN_LOCATION) == 0, "broken box is not restocked")
	_expect(trip.lost_units == 2 and inv.total_units() == 0, "broken box products are lost")
