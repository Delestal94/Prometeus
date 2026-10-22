class_name SupplierAutoOrder
extends RefCounted
## The automatic supplier order of the day's close (expansion D-0151.3b, "Modo Empresa";
## docs/expansion-distritos/diseno/roles-tripulacion.md §6.2 row 3 and §6.3).
##
## When the day goes to CLOSING and nobody sent the order for tomorrow, the host sends the suggested one
## (SupplierOrderCart.suggested(): the units today's orders asked for less the stock, trimmed to leave the
## rent and the reserve in the wallet) and the day's summary tells it. It applies to every crew. Pure rule over
## the values passed in: no node, no autoload; SupplierAutoOrderHook is the host's wiring. Nothing is charged
## here: like any order, the bill is paid when each pallet is received (SupplierPurchase.receive).


## The lines to order for tomorrow, [{product, qty}] in product id order (SupplierOrderCart.to_array()), or []
## when there is nothing to do: a truck is already due tomorrow (someone sent the order), the day's orders
## were all covered by the stock, or the wallet does not reach past the rent and the reserve.
## `orders` are the day's Order dictionaries (todays_orders()), `stock` is product -> units (stock_units()),
## `products` the catalog (id -> ProductDefinition) and `supplier` who sells (null: any product).
static func lines(money: int, schedule: SupplierSchedule, orders: Array, stock: Dictionary, products: Dictionary,
		supplier: SupplierDefinition, day: int) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if schedule == null or day < 1 or schedule.has_delivery(SupplierSchedule.arrival_day(day)):
		return none
	var wanted: Dictionary = SupplierOrderCart.suggested(
		SupplierOrderCart.ordered_units(orders), stock, money, products, supplier)
	var cart := SupplierOrderCart.new()
	cart.supplier = supplier
	cart.products = products
	for id: StringName in wanted:
		cart.set_qty(id, int(wanted[id]))
	return cart.to_array()


## What the order screen's cart opens with (D-0151.3c, portapapeles.md §3): the suggested order less what is
## already ordered for tomorrow, product -> units. Units on tomorrow's truck count as stock and their cost comes
## off `money` before the trim, so ordering the suggested on top never asks for more than the rule would.
## Same values as lines(); {} when nothing is missing.
static func cart_preload(money: int, schedule: SupplierSchedule, orders: Array, stock: Dictionary, products: Dictionary,
		supplier: SupplierDefinition, day: int) -> Dictionary:
	var have: Dictionary = stock.duplicate()
	var budget: int = money
	if schedule != null:
		var already: Dictionary = schedule.ordered_for(SupplierSchedule.arrival_day(day))
		for id: Variant in already:
			have[id] = int(have.get(id, 0)) + int(already[id])
			budget -= SupplierPurchase.cost(StringName(id), int(already[id]), products)
	return SupplierOrderCart.suggested(SupplierOrderCart.ordered_units(orders), have, budget, products, supplier)


## Notes in `today_ids` the orders that come in today: an order_added adds its id, the day's OPENING clears them.
## Every CompanyNet event goes through here (SupplierAutoOrderHook on the host, SupplierBoard on every peer).
static func note_today(today_ids: Dictionary, kind: StringName, data: Dictionary) -> void:
	if kind == CompanyOrdersNet.ADDED:
		var order: Variant = data.get("order")
		if order is Dictionary:
			today_ids[StringName((order as Dictionary).get("id", &""))] = true
	elif kind == CompanyNet.DAY_PHASE and data.get("phase") == DayCycle.PHASE_NAMES[DayCycle.Phase.OPENING]:
		today_ids.clear()


## The day's orders out of the book's (OrderBook.to_dict()["orders"]): the ones whose id is a key of `today_ids`
## (the hook notes them as they come in: the book keeps the whole session and an Order has no day), open or
## closed, less the ones the customer cancelled: those asked for nothing.
static func todays_orders(book_orders: Array, today_ids: Dictionary) -> Array:
	var out: Array = []
	for order: Variant in book_orders:
		if not order is Dictionary or not today_ids.has(StringName((order as Dictionary).get("id", &""))):
			continue
		if StringName((order as Dictionary).get("state", &"")) != Order.STATE_CANCELLED:
			out.append(order)
	return out


## Units per product of `products` that `inventory` holds, anywhere (Inventory.count()).
static func stock_units(inventory: Inventory, products: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if inventory == null:
		return out
	for id: StringName in products:
		var units: int = inventory.count(id)
		if units > 0:
			out[id] = units
	return out


## Units in `lines` ([{product, qty}]).
static func units_of(order_lines: Array) -> int:
	var sum: int = 0
	for line: Variant in order_lines:
		sum += int((line as Dictionary).get("qty", 0))
	return sum
