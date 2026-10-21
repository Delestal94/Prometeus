class_name OrderBoard
extends RefCounted
## What the order board of the shed lists (expansion D-0804, "Modo Empresa"): every order of the
## OrderBook with its state, who it is for, what it holds, the time left and the pay.
##
## Static and stateless; the screen is OrderBoardPanel. rows() reads Order dictionaries (what
## OrderBook.to_dict()["orders"] holds) and returns plain dictionaries, so a client draws the same
## board from what the host mirrored. No node, no autoload, no tr(): texts are translation keys.
##
## Row keys: order (id), customer, address ({street_key, number}), state, state_key, mark,
## items [{product, name, qty}], requirements [key], minutes_left (negative once past due),
## late, pay, closed (delivered, failed or cancelled).

## State -> [translation key of its name, mark]. Every state has a mark besides its colour.
const STATE_INFO: Dictionary = {
	Order.STATE_LATE: ["UI_ORDER_BOARD_LATE", "!"],
	Order.STATE_OPEN: ["UI_ORDER_BOARD_OPEN", "○"],
	Order.STATE_PACKED: ["UI_ORDER_BOARD_PACKED", "◐"],
	Order.STATE_OUT: ["UI_ORDER_BOARD_OUT", "●"],
	Order.STATE_DELIVERED: ["UI_ORDER_BOARD_DELIVERED", "✓"],
	Order.STATE_FAILED: ["UI_ORDER_BOARD_FAILED", "✗"],
	Order.STATE_CANCELLED: ["UI_ORDER_BOARD_CANCELLED", "–"],
}

## Closed orders are the last rows, and only the most recent ones are listed.
const MAX_CLOSED: int = 3


## The board rows for `orders` at game minute `now_min`: the ones still to deliver first (late
## ones on top, then by the time left), then the last MAX_CLOSED closed ones, newest first.
## `products` maps product id -> ProductDefinition and only gives the names.
static func rows(orders: Array, now_min: int, products: Dictionary = {}) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	var closed: Array[Dictionary] = []
	for raw: Variant in orders:
		if not raw is Dictionary:
			continue
		var order: Dictionary = raw
		var state := StringName(str(order.get("state", "")))
		if not STATE_INFO.has(state):
			continue
		var row: Dictionary = _row(order, state, now_min, products)
		if row["closed"]:
			closed.append(row)
		else:
			active.append(row)
	active.sort_custom(_before)
	closed.reverse()
	return active + closed.slice(0, MAX_CLOSED)


## True if `a` goes above `b` on the board: late first, then the least time left.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	var a_late: bool = a["state"] == Order.STATE_LATE
	var b_late: bool = b["state"] == Order.STATE_LATE
	if a_late != b_late:
		return a_late
	if a["minutes_left"] != b["minutes_left"]:
		return a["minutes_left"] < b["minutes_left"]
	return String(a["order"]) < String(b["order"])


static func _row(order: Dictionary, state: StringName, now_min: int, products: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	for item: Dictionary in order.get("items", []):
		var id := StringName(str(item["product"]))
		items.append({"product": id, "name": OrderSheet.product_name(id, products), "qty": int(item["qty"])})
	var requirements: Array[String] = []
	for req: Variant in order.get("requirements", []):
		var key: String = String(OrderSheet.REQUIREMENT_KEYS.get(StringName(str(req)), ""))
		if key != "":
			requirements.append(key)
	var minutes_left: int = int(order.get("due_min", 0)) - now_min
	var info: Array = STATE_INFO[state]
	return {
		"order": StringName(str(order.get("id", ""))),
		"customer": str(order.get("customer", "")),
		"address": OrderLabel.address(order),
		"state": state,
		"state_key": info[0],
		"mark": info[1],
		"items": items,
		"requirements": requirements,
		"minutes_left": minutes_left,
		"late": state == Order.STATE_LATE or (minutes_left < 0 and not _is_closed(state)),
		"pay": int(order.get("pay", 0)),
		"closed": _is_closed(state),
	}


static func _is_closed(state: StringName) -> bool:
	return state in [Order.STATE_DELIVERED, Order.STATE_FAILED, Order.STATE_CANCELLED]
