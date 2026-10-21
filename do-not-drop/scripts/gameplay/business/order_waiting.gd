class_name OrderWaiting
extends RefCounted
## Orders that cannot be assembled today for lack of stock (expansion D-0811).
##
## An order the shed cannot cover does not fail and is not hidden: it stays OPEN in the
## OrderBook (it still goes LATE and is abandoned on its own clock) and is marked here as
## waiting, with what it lacks. Pure functions over Inventory (D-0211) and the orders
## OrderBook.open_orders() returns (D-0210); no node, no autoload, no UI, so the host
## runs it on every stock or order change and the clients on their mirror.
##
## The free stock (StockAlert.free_units: everything but sealed boxes) is handed out to
## the pending orders earliest due first (then by id), so two orders for the last hen do
## not both look ready: the first one is, the second waits.


## { ready: Array[StringName], waiting: { order_id: { product: units_missing } } }.
## Orders that are not pending (packed, closed) appear in neither.
static func classify(inventory: Inventory, orders: Array) -> Dictionary:
	var pending: Array[Dictionary] = []
	for order: Dictionary in orders:
		if StockAlert.is_pending(order):
			pending.append(order)
	pending.sort_custom(_earlier)
	var left: Dictionary = {}
	var ready: Array[StringName] = []
	var waiting: Dictionary = {}
	for order: Dictionary in pending:
		var missing: Dictionary = {}
		var take: Dictionary = {}
		for item: Dictionary in order.get("items", []):
			var product: StringName = StringName(item.get("product", ""))
			var qty: int = int(item.get("qty", 0))
			if product == &"" or qty <= 0:
				continue
			if not left.has(product):
				left[product] = StockAlert.free_units(inventory, product)
			var have: int = maxi(int(left[product]) - int(take.get(product, 0)), 0)
			take[product] = int(take.get(product, 0)) + mini(qty, have)
			if qty > have:
				missing[product] = int(missing.get(product, 0)) + qty - have
		var id: StringName = StringName(order.get("id", ""))
		if missing.is_empty():
			ready.append(id)
			for product: StringName in take:
				left[product] = int(left[product]) - int(take[product])
		else:
			waiting[id] = missing
	return {"ready": ready, "waiting": waiting}


## True if the order can be assembled right now with the free stock, ignoring what the
## other orders would take.
static func can_cover(inventory: Inventory, order: Dictionary) -> bool:
	return missing_for(inventory, order).is_empty()


## product -> units the order lacks against the free stock (empty when it is covered).
static func missing_for(inventory: Inventory, order: Dictionary) -> Dictionary:
	var need: Dictionary = {}
	for item: Dictionary in order.get("items", []):
		var product: StringName = StringName(item.get("product", ""))
		if product != &"" and int(item.get("qty", 0)) > 0:
			need[product] = int(need.get(product, 0)) + int(item["qty"])
	var out: Dictionary = {}
	for product: StringName in need:
		var gap: int = int(need[product]) - StockAlert.free_units(inventory, product)
		if gap > 0:
			out[product] = gap
	return out


## Waiting orders that a supplier delivery (product -> units incoming) would unblock, ids
## only: the host can tell the crew the truck on its way is enough.
static func unblocked_by(
	inventory: Inventory, orders: Array, incoming: Dictionary
) -> Array[StringName]:
	var now: Dictionary = classify(inventory, orders)
	var plus := Inventory.new()
	plus.from_dict(inventory.to_dict())
	for product: StringName in incoming:
		if int(incoming[product]) > 0:
			plus.receive(product, int(incoming[product]), &"incoming")
	var later: Dictionary = classify(plus, orders)
	var out: Array[StringName] = []
	for id: StringName in later["ready"]:
		if now["waiting"].has(id):
			out.append(id)
	return out


static func _earlier(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("due_min", 0)) != int(b.get("due_min", 0)):
		return int(a.get("due_min", 0)) < int(b.get("due_min", 0))
	return String(a.get("id", "")) < String(b.get("id", ""))
