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

var id: StringName = &""
var vehicle_id: StringName = &""
var box_ids: Array[StringName] = []
var order_ids: Array[StringName] = []
var depart_min: int = -1
var return_min: int = -1
var state: StringName = STATE_OUT
var delivered_ids: Array[StringName] = []
var failed_ids: Array[StringName] = []


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
	return trip


func is_out() -> bool:
	return state == STATE_OUT


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
func close(book: OrderBook, now_min: int) -> Array[StringName]:
	if not is_out():
		return []
	state = STATE_CLOSED
	return_min = now_min
	for order_id: StringName in order_ids:
		if not order_id in delivered_ids and book.mark_failed(order_id):
			failed_ids.append(order_id)
	return failed_ids.duplicate()


## Game minutes spent outside, -1 while the trip is still out.
func duration_min() -> int:
	return -1 if is_out() else return_min - depart_min
