class_name OrderBook
extends Node
## Active customer orders of the company mode (expansion D-0210).
##
## Holds the order dictionaries built by Order (D-0802), moves them through
## their states and expires the ones past due. The host owns the one real
## book; clients mirror it through CompanyNet (D-2001), so every change goes
## through this API and never straight into a dictionary.
##
## Flow: OPEN -> PACKED -> OUT -> DELIVERED. An order past its due_min becomes
## LATE (still deliverable, paid with the late penalty). FAILED and CANCELLED
## are final, like DELIVERED.

signal order_added(id: StringName)
signal order_changed(id: StringName, state: StringName)

## States an order may move to from each state. DELIVERED, FAILED and CANCELLED
## are final.
const TRANSITIONS: Dictionary = {
	Order.STATE_OPEN:
	[Order.STATE_PACKED, Order.STATE_LATE, Order.STATE_FAILED, Order.STATE_CANCELLED],
	Order.STATE_PACKED:
	[Order.STATE_OUT, Order.STATE_LATE, Order.STATE_FAILED, Order.STATE_CANCELLED],
	Order.STATE_OUT: [Order.STATE_DELIVERED, Order.STATE_LATE, Order.STATE_FAILED],
	Order.STATE_LATE:
	[Order.STATE_PACKED, Order.STATE_OUT, Order.STATE_DELIVERED, Order.STATE_FAILED],
}

var _orders: Dictionary = {}
var _order_ids: Array[StringName] = []
var _now_min: int = 0


## Adds a valid order (state is forced to OPEN). False if it is malformed or
## its id is already in the book.
func add(order: Dictionary) -> bool:
	var clean: Dictionary = Order.normalize(order)
	if not Order.validate(clean).is_empty() or _orders.has(clean["id"]):
		return false
	clean["state"] = Order.STATE_OPEN
	_orders[clean["id"]] = clean
	_order_ids.append(clean["id"])
	order_added.emit(clean["id"])
	return true


func has(id: StringName) -> bool:
	return _orders.has(id)


func get_order(id: StringName) -> Dictionary:
	return _orders.get(id, {}).duplicate(true)


func size() -> int:
	return _order_ids.size()


func state_of(id: StringName) -> StringName:
	return _orders.get(id, {}).get("state", &"")


## The box that holds the order (set by mark_packed), empty if none.
func box_of(id: StringName) -> StringName:
	return StringName(_orders.get(id, {}).get("box_id", ""))


func mark_packed(id: StringName, box_id: StringName) -> bool:
	if not _move(id, Order.STATE_PACKED):
		return false
	_orders[id]["box_id"] = box_id
	return true


func mark_out(id: StringName, trip_id: StringName) -> bool:
	if not _move(id, Order.STATE_OUT):
		return false
	_orders[id]["trip_id"] = trip_id
	return true


## Closes the order and returns what it pays (late penalty included, now_min
## defaults to the last expire() time), or -1 if it cannot be delivered now.
func mark_delivered(id: StringName, quality: int, intact: bool, now_min: int = -1) -> int:
	if not _move(id, Order.STATE_DELIVERED):
		return -1
	var order: Dictionary = _orders[id]
	order["quality"] = clampi(quality, 0, 100)
	order["intact"] = intact
	var when: int = now_min if now_min >= 0 else _now_min
	order["paid"] = Order.payout(order, when)
	return order["paid"]


func mark_failed(id: StringName) -> bool:
	return _move(id, Order.STATE_FAILED)


func cancel(id: StringName) -> bool:
	return _move(id, Order.STATE_CANCELLED)


## Marks LATE every order that is not closed and is past its due_min at game
## minute now_min. Returns the ids that just became late.
func expire(now_min: int) -> Array[StringName]:
	_now_min = now_min
	var late: Array[StringName] = []
	for id: StringName in _order_ids:
		var order: Dictionary = _orders[id]
		if order["state"] == Order.STATE_LATE or not TRANSITIONS.has(order["state"]):
			continue
		if now_min > int(order["due_min"]) and _move(id, Order.STATE_LATE):
			late.append(id)
	return late


## Orders still to be delivered (not DELIVERED, FAILED or CANCELLED), oldest
## first; zone filters by district when given.
func open_orders(zone: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _order_ids:
		var order: Dictionary = _orders[id]
		if not TRANSITIONS.has(order["state"]):
			continue
		if zone == &"" or order["zone"] == zone:
			out.append(order.duplicate(true))
	return out


func to_dict() -> Dictionary:
	var list: Array[Dictionary] = []
	for id: StringName in _order_ids:
		list.append(_orders[id].duplicate(true))
	return {"orders": list, "now_min": _now_min}


func from_dict(data: Dictionary) -> void:
	_orders.clear()
	_order_ids.clear()
	_now_min = int(data.get("now_min", 0))
	for raw: Dictionary in data.get("orders", []):
		var order: Dictionary = Order.normalize(raw)
		for key: String in ["box_id", "trip_id"]:
			if raw.has(key):
				order[key] = StringName(raw[key])
		for key: String in ["quality", "paid"]:
			if raw.has(key):
				order[key] = int(raw[key])
		if raw.has("intact"):
			order["intact"] = bool(raw["intact"])
		if Order.validate(order).is_empty() and not _orders.has(order["id"]):
			_orders[order["id"]] = order
			_order_ids.append(order["id"])


func _move(id: StringName, to: StringName) -> bool:
	if not _orders.has(id):
		return false
	var order: Dictionary = _orders[id]
	var allowed: Array = TRANSITIONS.get(order["state"], [])
	if not to in allowed:
		return false
	order["state"] = to
	order_changed.emit(id, to)
	return true
