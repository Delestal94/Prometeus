extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_book.gd
##
## OrderBook (expansion D-0210, order_book.gd):
## - add() takes valid orders and refuses duplicates and malformed ones;
## - a whole order cycle OPEN -> PACKED -> OUT -> DELIVERED works and emits
##   order_added / order_changed;
## - expire() makes late the orders past their 4 h window, and a late delivery
##   pays 75 % while an on-time one pays in full;
## - open_orders() filters by zone and drops closed orders;
## - invalid moves (DELIVERED -> OPEN, packing a closed order) are refused;
## - to_dict()/from_dict() keep states, box and trip ids.

var _failures: int = 0
var _signals: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_add()
	_test_cycle()
	_test_expire_and_payout()
	_test_open_orders_by_zone()
	_test_invalid_transitions()
	_test_round_trip()
	quit(_failures)


func _products() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in [&"hen", &"sourdough"]:
		out[id] = load("res://data/products/%s.tres" % id)
	return out


func _order(id: StringName, zone: StringName = &"campo", created: int = 0) -> Dictionary:
	var items: Array = [{"product": &"hen", "qty": 1}, {"product": &"sourdough", "qty": 1}]
	return Order.make(id, "Doña Rosa", zone, &"%s_1" % zone, items, created, _products())


func _book() -> OrderBook:
	var book := OrderBook.new()
	_signals.clear()
	book.order_added.connect(func(id: StringName) -> void: _signals.append(["added", id]))
	book.order_changed.connect(
		func(id: StringName, state: StringName) -> void: _signals.append([id, state])
	)
	return book


func _test_add() -> void:
	var book := _book()
	_expect(book.add(_order(&"o1")), "a valid order is added")
	_expect(not book.add(_order(&"o1")), "a repeated id is refused")
	_expect(not book.add({"id": &"bad"}), "a malformed order is refused")
	_expect(book.size() == 1 and book.has(&"o1"), "only the valid order is in the book")
	_expect(_signals == [["added", &"o1"]], "adding emits order_added once")
	book.free()


func _test_cycle() -> void:
	var book := _book()
	book.add(_order(&"o1"))
	var pay: int = book.get_order(&"o1")["pay"]
	_expect(book.mark_packed(&"o1", &"box7"), "open -> packed")
	_expect(book.box_of(&"o1") == &"box7", "the order knows its box")
	_expect(book.mark_out(&"o1", &"trip1"), "packed -> out")
	_expect(book.mark_delivered(&"o1", 90, true, 100) == pay, "on-time delivery pays in full")
	_expect(book.state_of(&"o1") == Order.STATE_DELIVERED, "order is delivered")
	_expect(book.get_order(&"o1")["quality"] == 90, "quality is stored")
	_expect(
		(
			_signals.slice(1)
			== [
				[&"o1", Order.STATE_PACKED],
				[&"o1", Order.STATE_OUT],
				[&"o1", Order.STATE_DELIVERED]
			]
		),
		"each step emits order_changed"
	)
	book.free()


func _test_expire_and_payout() -> void:
	var book := _book()
	book.add(_order(&"o1", &"campo", 0))
	book.add(_order(&"o2", &"campo", 200))
	var due: int = book.get_order(&"o1")["due_min"]
	_expect(book.expire(due).is_empty(), "nothing is late at the due minute")
	var late: Array[StringName] = book.expire(due + 1)
	_expect(late == [&"o1"], "only the order past due becomes late")
	_expect(book.state_of(&"o2") == Order.STATE_OPEN, "the newer order stays open")
	_expect(book.expire(due + 2).is_empty(), "a late order is not reported twice")
	var pay: int = book.get_order(&"o1")["pay"]
	book.mark_packed(&"o1", &"b")
	book.mark_out(&"o1", &"t")
	_expect(book.mark_delivered(&"o1", 80, true) == roundi(pay * 0.75), "late delivery pays 75 %")
	book.free()


func _test_open_orders_by_zone() -> void:
	var book := _book()
	book.add(_order(&"o1", &"campo"))
	book.add(_order(&"o2", &"centro"))
	book.add(_order(&"o3", &"campo"))
	book.cancel(&"o3")
	_expect(book.open_orders().size() == 2, "cancelled orders are not open")
	var campo := book.open_orders(&"campo")
	_expect(campo.size() == 1 and campo[0]["id"] == &"o1", "open_orders filters by zone")
	book.free()


func _test_invalid_transitions() -> void:
	var book := _book()
	book.add(_order(&"o1"))
	_expect(not book.mark_out(&"o1", &"t"), "open cannot go straight out")
	_expect(book.mark_delivered(&"o1", 50, true) == -1, "open cannot be delivered")
	book.mark_packed(&"o1", &"b")
	book.mark_out(&"o1", &"t")
	book.mark_delivered(&"o1", 50, true, 10)
	_expect(not book.mark_packed(&"o1", &"b2"), "delivered cannot be packed again")
	_expect(not book.cancel(&"o1"), "delivered cannot be cancelled")
	_expect(not book.mark_failed(&"nope"), "an unknown id is refused")
	_expect(book.state_of(&"o1") == Order.STATE_DELIVERED, "refused moves keep the state")
	book.free()


func _test_round_trip() -> void:
	var book := _book()
	book.add(_order(&"o1"))
	book.add(_order(&"o2"))
	book.mark_packed(&"o1", &"box7")
	book.mark_out(&"o1", &"trip1")
	var copy := OrderBook.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	_expect(copy.size() == 2, "both orders survive a JSON round trip")
	_expect(copy.state_of(&"o1") == Order.STATE_OUT, "state survives")
	_expect(copy.box_of(&"o1") == &"box7", "box id survives")
	_expect(copy.get_order(&"o2") == book.get_order(&"o2"), "an untouched order is equal")
	book.free()
	copy.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
