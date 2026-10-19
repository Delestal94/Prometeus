class_name DispatchZone
extends RefCounted
## The dispatch area of the shed (expansion D-0716, "Modo Empresa").
##
## A sealed box lying still inside the area is "dispatched": it waits there tied to its order for
## the next trip. If it leaves the area before the trip starts it is untied again. When the host
## loads a vehicle, load_into() hands every waiting box to CompanyTrips.stage_cargo() and the zone
## forgets them. Pure data over an OrderBook: the world adapter reads each box's position and
## calls update_box() every so often (host only, S3), and replicates the two results with
## `box_dispatched` / `box_undispatched` (red-autoridad row 17).

const RESULT_DISPATCHED: StringName = &"dispatched"
const RESULT_UNDISPATCHED: StringName = &"undispatched"
const RESULT_NONE: StringName = &""

## The floor of the area, in world coordinates.
var area: AABB = AABB()

## box id -> order id of the boxes waiting in the area.
var _waiting: Dictionary = {}
var _order_ids: Array[StringName] = []


func _init(zone_area: AABB = AABB()) -> void:
	area = zone_area


func contains(pos: Vector3) -> bool:
	return area.has_point(pos)


## Reports where a box is now. `sealed` is the box's tape, `at_rest` that it is not being carried
## or moving. A sealed box at rest inside the area whose order is PACKED in `book` becomes
## dispatched; a dispatched box that is no longer inside the area (or was picked up) is untied.
## Returns RESULT_DISPATCHED or RESULT_UNDISPATCHED when something changed, else RESULT_NONE.
func update_box(
	box_id: StringName,
	order_id: StringName,
	pos: Vector3,
	sealed: bool,
	at_rest: bool,
	book: OrderBook,
) -> StringName:
	if _waiting.has(box_id):
		if contains(pos):
			return RESULT_NONE
		_forget(box_id)
		return RESULT_UNDISPATCHED
	if not (sealed and at_rest and contains(pos)):
		return RESULT_NONE
	if book == null or book.state_of(order_id) != Order.STATE_PACKED:
		return RESULT_NONE
	if book.box_of(order_id) != box_id:
		return RESULT_NONE
	_waiting[box_id] = order_id
	_order_ids.append(box_id)
	return RESULT_DISPATCHED


func is_dispatched(box_id: StringName) -> bool:
	return _waiting.has(box_id)


func order_of(box_id: StringName) -> StringName:
	return _waiting.get(box_id, &"")


## Boxes waiting, oldest first.
func boxes() -> Array[StringName]:
	return _order_ids.duplicate()


## Orders of the boxes waiting, in the same order as boxes().
func orders() -> Array[StringName]:
	var out: Array[StringName] = []
	for box_id: StringName in _order_ids:
		out.append(_waiting[box_id])
	return out


## Hands the waiting boxes to the trip gate as the cargo of `vehicle_id` and empties the area.
## Returns how many boxes went; nothing is staged when none waits.
func load_into(trips: CompanyTrips, vehicle_id: StringName) -> int:
	if trips == null or _order_ids.is_empty():
		return 0
	var count: int = _order_ids.size()
	trips.stage_cargo(vehicle_id, orders(), boxes())
	_waiting.clear()
	_order_ids.clear()
	return count


func to_dict() -> Dictionary:
	return {"boxes": boxes(), "orders": orders()}


func from_dict(data: Dictionary) -> void:
	_waiting.clear()
	_order_ids.clear()
	var box_list: Array = data.get("boxes", [])
	var order_list: Array = data.get("orders", [])
	for i: int in mini(box_list.size(), order_list.size()):
		var box_id := StringName(box_list[i])
		if not _waiting.has(box_id):
			_waiting[box_id] = StringName(order_list[i])
			_order_ids.append(box_id)


func _forget(box_id: StringName) -> void:
	_waiting.erase(box_id)
	_order_ids.erase(box_id)
