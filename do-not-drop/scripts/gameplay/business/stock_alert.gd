class_name StockAlert
extends RefCounted
## Low-stock warning for products that pending orders are waiting on (expansion D-0613).
##
## Pure functions over plain data: no node, no autoload, no UI. The caller passes
## Inventory (D-0211) and the orders OrderBook.open_orders() returns (D-0210), so the
## host can run it on every stock or order change and the clients on their mirror.
##
## Pending order = OPEN or LATE and not in a box yet. Its items still have to be found, so
## they are counted against the stock that is free to pick: every location but the sealed
## boxes (&"box:<id>", the units there already belong to a packed order).

const BOX_PREFIX: String = "box:"


## One entry per product the pending orders need more of than the free stock holds,
## most urgent first (earliest due_min, then product id):
## { product, needed, have, incoming, missing, due_min, covered }.
## incoming is product -> units already ordered from a supplier (optional): they shrink
## `missing`, and `covered` is true when they alone close the gap (a warning that the
## truck is on its way, not that nothing was ordered).
static func shortages(
	inventory: Inventory, orders: Array, incoming: Dictionary = {}
) -> Array[Dictionary]:
	var needed: Dictionary = {}
	var due: Dictionary = {}
	for order: Dictionary in orders:
		if not is_pending(order):
			continue
		var due_min: int = int(order.get("due_min", 0))
		for item: Dictionary in order.get("items", []):
			var product: StringName = StringName(item.get("product", ""))
			var qty: int = int(item.get("qty", 0))
			if product == &"" or qty <= 0:
				continue
			needed[product] = int(needed.get(product, 0)) + qty
			due[product] = mini(int(due.get(product, due_min)), due_min)
	var out: Array[Dictionary] = []
	for product: StringName in needed:
		var have: int = free_units(inventory, product)
		var coming: int = maxi(int(incoming.get(product, 0)), 0)
		var gap: int = int(needed[product]) - have
		if gap <= 0:
			continue
		(
			out
			. append(
				{
					"product": product,
					"needed": needed[product],
					"have": have,
					"incoming": coming,
					"missing": maxi(gap - coming, 0),
					"due_min": due[product],
					"covered": coming >= gap,
				}
			)
		)
	out.sort_custom(_more_urgent)
	return out


## An order that still has to be assembled.
static func is_pending(order: Dictionary) -> bool:
	var state: StringName = StringName(order.get("state", ""))
	if state != Order.STATE_OPEN and state != Order.STATE_LATE:
		return false
	return String(order.get("box_id", "")).is_empty()


## Units of a product outside the sealed boxes.
static func free_units(inventory: Inventory, product: StringName) -> int:
	var total: int = 0
	var locations: Dictionary = inventory.locations_of(product)
	for location: StringName in locations:
		if not String(location).begins_with(BOX_PREFIX):
			total += int(locations[location])
	return total


## Products in `current` that were not short in `previous` (both shortages() results): what to
## warn about now, so the same product does not nag on every stock change.
static func fresh(previous: Array, current: Array) -> Array[StringName]:
	var known: Dictionary = {}
	for entry: Dictionary in previous:
		known[entry["product"]] = true
	var out: Array[StringName] = []
	for entry: Dictionary in current:
		if not known.has(entry["product"]) and not bool(entry.get("covered", false)):
			out.append(entry["product"])
	return out


static func _more_urgent(a: Dictionary, b: Dictionary) -> bool:
	if a["due_min"] != b["due_min"]:
		return a["due_min"] < b["due_min"]
	return String(a["product"]) < String(b["product"])
