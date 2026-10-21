extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_box_link.gd
##
## OrderBoxLink, the order tied to its box (expansion D-0808, order_box_link.gd):
## - an open or late order links to a taped box that carries its label, and becomes PACKED;
## - it refuses an unknown order, one already packed, an untaped or unlabelled box, a label of
##   another order, and a box already linked to another order;
## - order_of_box() finds the order from the box;
## - release() (OrderBook.unpack) returns the order to OPEN, or LATE past its due time, frees the
##   box and lets it be linked again; an order that is not packed cannot be released.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_assign()
	_test_refusals()
	_test_release()
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _book() -> OrderBook:
	var book := OrderBook.new()
	var products: Dictionary = {&"hen": load("res://data/products/hen.tres")}
	for id: StringName in [&"o1", &"o2"]:
		book.add(
			Order.make(id, "Ana", &"centro", &"house_1", [{"product": &"hen", "qty": 1}], 0, products)
		)
	return book


func _box(order_id: StringName, taped: bool = true) -> PackedBox:
	var box := PackedBox.new(&"M")
	box.label_order_id = order_id
	box.taped = taped
	return box


func _test_assign() -> void:
	var book: OrderBook = _book()
	_expect(OrderBoxLink.assign(book, &"o1", &"b1", _box(&"o1")) == OrderBoxLink.OK, "taped labelled box links")
	_expect(book.state_of(&"o1") == Order.STATE_PACKED, "order is packed")
	_expect(book.box_of(&"o1") == &"b1", "order knows its box")
	_expect(OrderBoxLink.order_of_box(book, &"b1") == &"o1", "box finds its order")
	_expect(OrderBoxLink.order_of_box(book, &"nope") == &"", "unknown box has no order")
	book.expire(300)
	_expect(OrderBoxLink.assign(book, &"o2", &"b2", _box(&"o2")) == OrderBoxLink.OK, "late order links too")


func _test_refusals() -> void:
	var book: OrderBook = _book()
	_expect(
		OrderBoxLink.assign(book, &"zz", &"b1", _box(&"zz")) == OrderBoxLink.ERR_UNKNOWN_ORDER, "unknown order"
	)
	_expect(
		OrderBoxLink.assign(book, &"o1", &"b1", _box(&"o1", false)) == OrderBoxLink.ERR_NOT_TAPED,
		"untaped box"
	)
	_expect(
		OrderBoxLink.assign(book, &"o1", &"b1", null) == OrderBoxLink.ERR_NOT_TAPED, "no box"
	)
	_expect(
		OrderBoxLink.assign(book, &"o1", &"b1", _box(&"")) == OrderBoxLink.ERR_LABEL_MISMATCH,
		"no label"
	)
	_expect(
		OrderBoxLink.assign(book, &"o1", &"b1", _box(&"o2")) == OrderBoxLink.ERR_LABEL_MISMATCH,
		"label of another order"
	)
	_expect(book.state_of(&"o1") == Order.STATE_OPEN, "refusals change nothing")
	OrderBoxLink.assign(book, &"o1", &"b1", _box(&"o1"))
	_expect(
		OrderBoxLink.assign(book, &"o1", &"b9", _box(&"o1")) == OrderBoxLink.ERR_NOT_WAITING,
		"already packed order"
	)
	_expect(
		OrderBoxLink.assign(book, &"o2", &"b1", _box(&"o2")) == OrderBoxLink.ERR_BOX_TAKEN,
		"box already tied to another order"
	)


func _test_release() -> void:
	var book: OrderBook = _book()
	_expect(not OrderBoxLink.release(book, &"o1"), "open order cannot be released")
	OrderBoxLink.assign(book, &"o1", &"b1", _box(&"o1"))
	_expect(OrderBoxLink.release(book, &"o1"), "packed order releases")
	_expect(book.state_of(&"o1") == Order.STATE_OPEN, "back to open")
	_expect(book.box_of(&"o1") == &"", "box link cleared")
	_expect(OrderBoxLink.order_of_box(book, &"b1") == &"", "box is free")
	_expect(OrderBoxLink.assign(book, &"o1", &"b1", _box(&"o1")) == OrderBoxLink.OK, "relinks")
	book.expire(400)
	_expect(book.state_of(&"o1") == Order.STATE_PACKED, "packed does not turn late by itself")
	_expect(OrderBoxLink.release(book, &"o1"), "release past due")
	_expect(book.state_of(&"o1") == Order.STATE_LATE, "released past due is late")
