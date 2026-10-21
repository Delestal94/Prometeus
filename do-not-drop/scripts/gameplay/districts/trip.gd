class_name Trip
extends RefCounted
## One trip out of the shed (expansion D-0302, "Modo Empresa").
##
## A trip starts when a vehicle carrying dispatched boxes crosses the shed gate
## outward and ends when it comes back inside the yard. It keeps who left, with
## which boxes and orders and when. Orders go OUT through the OrderBook at the
## start; at the end the ones not delivered are closed as FAILED. Pure data
## over an OrderBook: no node, no autoload, no UI.

const STATE_OUT: StringName = &"out"
const STATE_CLOSED: StringName = &"closed"
## Where the products of an undelivered, sound box go back to.
const RETURN_LOCATION: StringName = &"dock"

var id: StringName = &""
var vehicle_id: StringName = &""
var box_ids: Array[StringName] = []
var order_ids: Array[StringName] = []
var depart_min: int = -1
var return_min: int = -1
var state: StringName = STATE_OUT
var delivered_ids: Array[StringName] = []
var failed_ids: Array[StringName] = []
## One entry per house visited, in the order the orders were loaded:
## { "house_id": StringName, "order_ids": Array[StringName] } (D-0305).
var stops: Array[Dictionary] = []
## Units that came back to stock / were lost with a broken box when closing.
var returned_units: int = 0
var lost_units: int = 0


## Starts a trip and moves every PACKED order to OUT. Orders that cannot go out
## (not packed, unknown) are left out of the trip. Null if none can leave.
static func start(
	trip_id: StringName,
	vehicle: StringName,
	orders: Array[StringName],
	boxes: Array[StringName],
	book: OrderBook,
	now_min: int,
) -> Trip:
	var trip := Trip.new()
	trip.id = trip_id
	trip.vehicle_id = vehicle
	trip.depart_min = now_min
	trip.box_ids = boxes.duplicate()
	for order_id: StringName in orders:
		if book.mark_out(order_id, trip_id):
			trip.order_ids.append(order_id)
	if trip.order_ids.is_empty():
		return null
	trip._build_stops(book)
	return trip


func is_out() -> bool:
	return state == STATE_OUT


## Houses with at least one order still to deliver, in stop order (none once closed).
func pending_stops() -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_out():
		return out
	for stop: Dictionary in stops:
		for order_id: StringName in stop["order_ids"]:
			if not order_id in delivered_ids:
				out.append(stop["house_id"])
				break
	return out


## The next house to visit, empty when no stop is left (time to drive home).
func next_stop() -> StringName:
	var pending: Array[StringName] = pending_stops()
	return &"" if pending.is_empty() else pending[0]


## Delivers every pending order of one house. Returns the ids delivered
## (empty for an unknown house or a closed trip). `quality` and `intact` map
## order id -> value; a missing entry means quality 100 and intact.
func deliver_stop(
	house_id: StringName,
	book: OrderBook,
	now_min: int,
	quality: Dictionary = {},
	intact: Dictionary = {},
) -> Array[StringName]:
	var done: Array[StringName] = []
	if not is_out():
		return done
	for stop: Dictionary in stops:
		if stop["house_id"] != house_id:
			continue
		for order_id: StringName in stop["order_ids"]:
			if deliver(order_id, book, int(quality.get(order_id, 100)), bool(intact.get(order_id, true)), now_min):
				done.append(order_id)
	return done


## Records a delivery made during the trip. False if the order is not from this
## trip or was already settled.
func deliver(
	order_id: StringName, book: OrderBook, quality: int, intact: bool, now_min: int
) -> bool:
	if not is_out() or not order_id in order_ids or order_id in delivered_ids:
		return false
	if book.mark_delivered(order_id, quality, intact, now_min) < 0:
		return false
	delivered_ids.append(order_id)
	return true


## Closes the trip on return to the yard: every order of the trip that was not
## delivered becomes FAILED. Returns the failed ids. A closed trip does nothing.
## With an inventory, the products of a failed order come back from its box to
## `RETURN_LOCATION` when the box is sound; if the box is in `broken_boxes` they
## are lost (consumed).
func close(
	book: OrderBook,
	now_min: int,
	inventory: Inventory = null,
	broken_boxes: Array[StringName] = [],
) -> Array[StringName]:
	if not is_out():
		return []
	state = STATE_CLOSED
	return_min = now_min
	for order_id: StringName in order_ids:
		if not order_id in delivered_ids and book.mark_failed(order_id):
			failed_ids.append(order_id)
			if inventory != null:
				_restock(book, order_id, inventory, broken_boxes)
	return failed_ids.duplicate()


## Game minutes spent outside, -1 while the trip is still out.
func duration_min() -> int:
	return -1 if is_out() else return_min - depart_min


func _build_stops(book: OrderBook) -> void:
	for order_id: StringName in order_ids:
		var house: StringName = StringName(book.get_order(order_id).get("house_id", ""))
		var found: bool = false
		for stop: Dictionary in stops:
			if stop["house_id"] == house:
				stop["order_ids"].append(order_id)
				found = true
				break
		if not found:
			var ids: Array[StringName] = [order_id]
			stops.append({"house_id": house, "order_ids": ids})


func _restock(
	book: OrderBook, order_id: StringName, inventory: Inventory, broken_boxes: Array[StringName]
) -> void:
	var box: StringName = book.box_of(order_id)
	if box == &"":
		return
	var location := StringName("box:" + str(box))
	for item: Dictionary in book.get_order(order_id).get("items", []):
		var product: StringName = item["product"]
		var qty: int = mini(int(item["qty"]), inventory.count(product, location))
		if qty <= 0:
			continue
		if box in broken_boxes:
			if inventory.consume(product, qty, location, order_id):
				lost_units += qty
		elif inventory.move(product, qty, location, RETURN_LOCATION):
			returned_units += qty
