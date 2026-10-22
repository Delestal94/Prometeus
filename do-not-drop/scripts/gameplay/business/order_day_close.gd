class_name OrderDayClose
extends RefCounted
## What becomes of the orders nobody delivered when the company day ends (expansion D-0851; rules 6 to 8 of
## docs/expansion-distritos/diseno/clientes.md).
##
## Pure functions over an OrderBook: no node, no autoload, no UI, and none of them changes the book
## except close_day(). The host decides with abandoned() and closing_plan(), publishes one order_closed
## event per id (CompanyOrdersNet) and every peer applies it with the book's own mark_failed() / cancel();
## close_day() is the same thing for a book with no network (a test, a tool). What a failed order costs
## is OrderPenalties.abandoned() (-3 reputation, pays 0); a cancelled one costs nothing.
##
## OrderBook is at gdlint's public-method limit, so this lives next to it instead of inside it.


## Ids of the orders the customer gives up on at game minute `now_min` (OrderBook.abandon() would fail them): late,
## not out on the road, and past their due_min by CompanyTuning.ORDER_ABANDON_MIN. `on_road` (Callable(id) -> bool,
## unset: none) names the ones a vehicle carries right now though the book doesn't say so yet; they are left alone.
## In book order.
static func abandoned(book: OrderBook, now_min: int, on_road: Callable = Callable()) -> Array[StringName]:
	var gone: Array[StringName] = []
	for order: Dictionary in book.open_orders():
		if order["state"] != Order.STATE_LATE or order.get("late_from", &"") == Order.STATE_OUT:
			continue
		if now_min <= int(order["due_min"]) + CompanyTuning.ORDER_ABANDON_MIN:
			continue
		if on_road.is_valid() and bool(on_road.call(order["id"])):
			continue
		gone.append(order["id"])
	return gone


## What the day's end does to every order still to be delivered at game minute `now_min`, without changing the
## book: {failed: ids, cancelled: ids}, each in book order. An order that is late (or that is past its due_min
## though nobody marked it yet) or out on the road fails; one still inside its window (open or packed) is
## cancelled for free, or fails too when the host closed the day early (`early`: guardado.md rule 2, closing
## early is no way to dodge a bad morning). Closed orders are in neither list.
static func closing_plan(book: OrderBook, now_min: int, early: bool) -> Dictionary:
	var failed: Array[StringName] = []
	var cancelled: Array[StringName] = []
	for order: Dictionary in book.open_orders():
		var state: StringName = order["state"]
		var gave_up: bool = state == Order.STATE_LATE or state == Order.STATE_OUT or now_min > int(order["due_min"])
		if early or gave_up:
			failed.append(order["id"])
		else:
			cancelled.append(order["id"])
	return {"failed": failed, "cancelled": cancelled}


## closing_plan() applied to `book` (mark_failed() / cancel()). Returns the plan.
static func close_day(book: OrderBook, now_min: int, early: bool) -> Dictionary:
	var plan: Dictionary = closing_plan(book, now_min, early)
	for id: StringName in plan["failed"]:
		book.mark_failed(id)
	for id: StringName in plan["cancelled"]:
		book.cancel(id)
	return plan
