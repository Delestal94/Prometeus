class_name Inventory
extends RefCounted
## Stock of the company by product and location (expansion D-0211).
##
## Pure data, no node and no autoload: the host owns the one instance (D-0202's
## CompanyState will hold it) and the clients only mirror it (D-0619). Units
## are never created or destroyed except by receive() (supplier delivery) and
## consume() (delivered or broken), so a move can never duplicate or lose one.
##
## Locations are plain StringNames: &"dock", &"shelf:<slot_id>", &"cart:<id>",
## &"box:<id>", &"hands:<peer>". The class does not interpret them.

signal stock_changed(product: StringName, location: StringName)

## product id -> { location -> qty (> 0) }
var _stock: Dictionary = {}
## order id -> { product id -> reserved qty (> 0) }
var _reserved: Dictionary = {}


## Supplier delivery: the only way units come in.
func receive(product: StringName, qty: int, location: StringName) -> bool:
	if product == &"" or location == &"" or qty <= 0:
		return false
	_add(product, location, qty)
	return true


## Delivered or broken units: the only way units go out. Without an order id it
## cannot dip into what other orders have reserved; with one, it also frees that
## much of the order's own reservation.
func consume(
	product: StringName, qty: int, location: StringName, order_id: StringName = &""
) -> bool:
	if qty <= 0 or count(product, location) < qty:
		return false
	if order_id == &"":
		if count(product) - qty < reserved_total(product):
			return false
	else:
		var held: Dictionary = _reserved.get(order_id, {})
		var own: int = held.get(product, 0)
		var other: int = reserved_total(product) - own
		if count(product) - qty < other:
			return false
		_shrink_reservation(order_id, product, mini(qty, own))
	_remove(product, location, qty)
	return true


## Moves units between locations. Fails, changing nothing, if the source holds
## fewer than qty.
func move(product: StringName, qty: int, from: StringName, to: StringName) -> bool:
	if qty <= 0 or to == &"" or from == to:
		return false
	if count(product, from) < qty:
		return false
	_remove(product, from, qty)
	_add(product, to, qty)
	return true


## Units of a product, in one location or (location == &"") everywhere.
func count(product: StringName, location: StringName = &"") -> int:
	var by_location: Dictionary = _stock.get(product, {})
	if location != &"":
		return by_location.get(location, 0)
	var total: int = 0
	for qty: int in by_location.values():
		total += qty
	return total


## Every unit of every product.
func total_units() -> int:
	var total: int = 0
	for product: StringName in _stock:
		total += count(product)
	return total


## product -> qty held in one location.
func contents_at(location: StringName) -> Dictionary:
	var result: Dictionary = {}
	for product: StringName in _stock:
		var qty: int = _stock[product].get(location, 0)
		if qty > 0:
			result[product] = qty
	return result


## Units not promised to any order.
func available(product: StringName) -> int:
	return count(product) - reserved_total(product)


func reserved_total(product: StringName) -> int:
	var total: int = 0
	for held: Dictionary in _reserved.values():
		total += held.get(product, 0)
	return total


## Promises units to an order so no other order can take them. Adds to what the
## order already holds. Fails, changing nothing, if not enough are available.
func reserve(product: StringName, qty: int, order_id: StringName) -> bool:
	if qty <= 0 or order_id == &"" or available(product) < qty:
		return false
	var held: Dictionary = _reserved.get(order_id, {})
	held[product] = held.get(product, 0) + qty
	_reserved[order_id] = held
	return true


## Drops every reservation of an order (cancelled or expired).
func release(order_id: StringName) -> void:
	_reserved.erase(order_id)


func reserved_by(order_id: StringName) -> Dictionary:
	return (_reserved.get(order_id, {}) as Dictionary).duplicate()


func to_dict() -> Dictionary:
	return {"stock": _stock.duplicate(true), "reserved": _reserved.duplicate(true)}


## Rebuilds the state from to_dict() (also after a JSON round trip, where ids
## come back as String and quantities as float). Invalid entries are dropped.
func from_dict(data: Dictionary) -> void:
	_stock.clear()
	_reserved.clear()
	var stock: Dictionary = data.get("stock", {})
	for product: Variant in stock:
		for location: Variant in stock[product]:
			var qty: int = int(stock[product][location])
			if qty > 0:
				_add(StringName(product), StringName(location), qty, false)
	var reserved: Dictionary = data.get("reserved", {})
	for order_id: Variant in reserved:
		for product: Variant in reserved[order_id]:
			var qty: int = int(reserved[order_id][product])
			if qty > 0:
				var held: Dictionary = _reserved.get(StringName(order_id), {})
				held[StringName(product)] = qty
				_reserved[StringName(order_id)] = held


func _add(product: StringName, location: StringName, qty: int, notify: bool = true) -> void:
	var by_location: Dictionary = _stock.get(product, {})
	by_location[location] = by_location.get(location, 0) + qty
	_stock[product] = by_location
	if notify:
		stock_changed.emit(product, location)


func _remove(product: StringName, location: StringName, qty: int) -> void:
	var by_location: Dictionary = _stock[product]
	var left: int = by_location[location] - qty
	if left > 0:
		by_location[location] = left
	else:
		by_location.erase(location)
		if by_location.is_empty():
			_stock.erase(product)
	stock_changed.emit(product, location)


func _shrink_reservation(order_id: StringName, product: StringName, qty: int) -> void:
	if qty <= 0 or not _reserved.has(order_id):
		return
	var held: Dictionary = _reserved[order_id]
	var left: int = held.get(product, 0) - qty
	if left > 0:
		held[product] = left
	else:
		held.erase(product)
		if held.is_empty():
			_reserved.erase(order_id)
