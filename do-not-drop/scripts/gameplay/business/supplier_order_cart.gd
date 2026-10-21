class_name SupplierOrderCart
extends RefCounted
## The supplier order being filled in on the board or the clipboard (expansion D-0603,
## "Modo Empresa").
##
## What the order screen reads and writes: lines product -> units, the total, how many
## pallets the truck will bring, and submit(), which checks the wallet and puts the order
## in the SupplierSchedule for the next day (arrival_day). Nothing is charged here: the
## bill is paid when each pallet is received (SupplierPurchase.receive, D-0503), so a
## truck that never gets unloaded costs nothing. Pure logic over objects passed in: no
## node, no autoload, no UI; the host applies a submitted order, clients only ask.

## Most units of one product in one order, so a stray key repeat cannot ask for thousands.
const MAX_LINE_QTY: int = 240

## Who sells; null means any catalog product is allowed.
var supplier: SupplierDefinition
## Product id -> ProductDefinition (the catalog); only these can be ordered.
var products: Dictionary = {}

## Product id (StringName) -> units.
var _lines: Dictionary = {}


## Adds qty units of a product. False, changing nothing, for an unknown product, one the
## supplier does not sell, qty < 1 or a line that would pass MAX_LINE_QTY.
func add(product: StringName, qty: int) -> bool:
	if qty < 1 or not _orderable(product):
		return false
	var total: int = qty(product) + qty
	if total > MAX_LINE_QTY:
		return false
	_lines[product] = total
	return true


## Sets the units of a product; 0 removes the line. Same refusals as add().
func set_qty(product: StringName, new_qty: int) -> bool:
	if new_qty == 0:
		return _lines.erase(product)
	if new_qty < 1 or new_qty > MAX_LINE_QTY or not _orderable(product):
		return false
	_lines[product] = new_qty
	return true


## Takes qty units off a product (the line goes away at zero or below). False when the
## product is not in the cart or qty < 1.
func remove(product: StringName, qty_off: int = 1) -> bool:
	if qty_off < 1 or not _lines.has(product):
		return false
	var left: int = qty(product) - qty_off
	if left <= 0:
		_lines.erase(product)
	else:
		_lines[product] = left
	return true


func clear() -> void:
	_lines.clear()


func is_empty() -> bool:
	return _lines.is_empty()


## Units of a product in the cart (0 when none).
func qty(product: StringName) -> int:
	return int(_lines.get(product, 0))


## The lines, products in id order: {product, qty, unit_price, cost}.
func lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = _lines.keys()
	# StringName < compares interned pointers, not text: sort by the string.
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		var n: int = qty(id)
		out.append(
			{
				"product": id,
				"qty": n,
				"unit_price": SupplierPurchase.cost(id, 1, products),
				"cost": SupplierPurchase.cost(id, n, products),
			}
		)
	return out


## What the whole order will cost once received.
func total() -> int:
	var sum: int = 0
	for line: Dictionary in lines():
		sum += int(line["cost"])
	return sum


## How many pallets the truck brings for this order (24 units per pallet at most).
func pallet_count() -> int:
	var count: int = 0
	for id: StringName in _lines:
		count += Pallet.plan(&"cart", id, qty(id)).size()
	return count


## True when the cart has lines and the wallet covers the total.
func can_submit(wallet: Object) -> bool:
	return not is_empty() and wallet != null and wallet.can_afford(total())


## Puts the order in the schedule for the day after order_day and empties the cart. False,
## changing nothing, when the cart is empty, the wallet does not cover it or the schedule
## refuses it.
func submit(wallet: Object, schedule: SupplierSchedule, order_day: int) -> bool:
	if schedule == null or not can_submit(wallet):
		return false
	var order: Array = []
	for line: Dictionary in lines():
		order.append({"product": line["product"], "qty": line["qty"]})
	if not schedule.place(order_day, order):
		return false
	clear()
	return true


## The cart as the order screen sends it to the host: [{product, qty}, ...].
func to_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: Dictionary in lines():
		out.append({"product": line["product"], "qty": line["qty"]})
	return out


func _orderable(product: StringName) -> bool:
	if not products.has(product):
		return false
	return supplier == null or supplier.sells(product)
