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


## The day's orders as the book keeps them (OrderBook.to_dict()["orders"]), open or closed, less the ones the
## customer cancelled: those asked for nothing.
static func todays_orders(book_orders: Array) -> Array:
	var out: Array = []
	for order: Variant in book_orders:
		if order is Dictionary and StringName((order as Dictionary).get("state", &"")) != Order.STATE_CANCELLED:
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
