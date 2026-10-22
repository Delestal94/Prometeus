class_name ColdChain
extends RefCounted
## Cold products out of the fridge rot (expansion D-0616, "Modo Empresa").
##
## Pure data over the Inventory (D-0211). For each cold product (ProductDefinition.temperature ==
## &"cold") and each place it is stored, the chain counts the game minutes its units spent out of
## cold storage. Past CompanyTuning.COLD_SPOIL_MINUTES the units there rot: they leave the stock
## (Inventory.discard) and the orders that counted on them lose that reservation. In a fridge
## (a shelf whose id is in `cold_shelves`) the clock stops; it does not reset, so taking milk out
## and putting it back doesn't make it fresh. A box in transit is ColdPack's business, not this.
##
## The host owns one instance and calls advance() as the day clock runs. Stock changes that
## carry units between places go through move() or receive() so the clock travels with them:
## when units join others the clock is the average weighted by units. A place with no units
## has no clock.

## product id -> { location -> game minutes out of cold storage }
var _warm: Dictionary = {}


## True when `location` is a slot of a shelf listed in `cold_shelves` (shelf id -> true).
static func is_cold_location(location: StringName, cold_shelves: Dictionary) -> bool:
	var text: String = String(location)
	if not text.begins_with("shelf:"):
		return false
	var cut: int = text.rfind("_")
	if cut <= 6:
		return false
	return cold_shelves.has(StringName(text.substr(6, cut - 6)))


static func is_cold_product(product: StringName, products: Dictionary) -> bool:
	var def: ProductDefinition = products.get(product) as ProductDefinition
	return def != null and def.temperature == ColdPack.COLD


## Minutes the units of this product in this place have spent out of cold storage.
func warm_minutes(product: StringName, location: StringName) -> float:
	return float((_warm.get(product, {}) as Dictionary).get(location, 0.0))


## Minutes left before the units rot (they only count down out of a fridge).
func minutes_left(product: StringName, location: StringName) -> float:
	return maxf(CompanyTuning.COLD_SPOIL_MINUTES - warm_minutes(product, location), 0.0)


## Supplier units arriving fresh in a place. Same as Inventory.receive plus the clock.
func receive(inventory: Inventory, product: StringName, qty: int, location: StringName) -> bool:
	return _carry(inventory, product, qty, &"", location, 0.0)


## Moves units between places keeping their clock. Same as Inventory.move plus the clock.
func move(
	inventory: Inventory, product: StringName, qty: int, from: StringName, to: StringName
) -> bool:
	if from == &"" or from == to:
		return false
	return _carry(inventory, product, qty, from, to, warm_minutes(product, from))


## Lets `minutes` of game time go by. Every cold product stored outside a fridge gets older;
## the units whose clock passed the limit rot. Returns what rotted, one entry per product and
## place: { "product", "location", "qty", "lost": { order id -> units } }.
func advance(
	inventory: Inventory, products: Dictionary, cold_shelves: Dictionary, minutes: float
) -> Array[Dictionary]:
	var rotten: Array[Dictionary] = []
	if minutes <= 0.0:
		return rotten
	for product: StringName in _tracked(inventory, products):
		var places: Dictionary = inventory.locations_of(product)
		var clocks: Dictionary = _warm.get(product, {})
		for location: StringName in places.keys():
			if is_cold_location(location, cold_shelves):
				continue
			var age: float = float(clocks.get(location, 0.0)) + minutes
			if age < CompanyTuning.COLD_SPOIL_MINUTES:
				clocks[location] = age
				continue
			var qty: int = int(places[location])
			var lost: Variant = inventory.discard(product, qty, location)
			clocks.erase(location)
			if lost is Dictionary:
				rotten.append(
					{"product": product, "location": location, "qty": qty, "lost": lost}
				)
		_warm[product] = clocks
	_prune(inventory)
	return rotten


func to_dict() -> Dictionary:
	return {"warm": _warm.duplicate(true)}


## Rebuilds from to_dict() (also after a JSON round trip). Bad entries are dropped.
func from_dict(data: Dictionary) -> void:
	_warm.clear()
	var warm: Dictionary = data.get("warm", {})
	for product: Variant in warm:
		var clocks: Dictionary = {}
		for location: Variant in warm[product]:
			var minutes: float = float(warm[product][location])
			if minutes > 0.0 and minutes < CompanyTuning.COLD_SPOIL_MINUTES:
				clocks[StringName(location)] = minutes
		if not clocks.is_empty():
			_warm[StringName(product)] = clocks


func _carry(
	inventory: Inventory,
	product: StringName,
	qty: int,
	from: StringName,
	to: StringName,
	incoming_minutes: float
) -> bool:
	var before: int = inventory.count(product, to)
	var at_dest: float = warm_minutes(product, to)
	var ok: bool
	if from == &"":
		ok = inventory.receive(product, qty, to)
	else:
		ok = inventory.move(product, qty, from, to)
	if not ok:
		return false
	var merged: float = (at_dest * before + incoming_minutes * qty) / float(before + qty)
	var clocks: Dictionary = _warm.get(product, {})
	if merged > 0.0:
		clocks[to] = merged
		_warm[product] = clocks
	_prune(inventory)
	return true


func _tracked(inventory: Inventory, products: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for product: StringName in products:
		if is_cold_product(product, products) and inventory.count(product) > 0:
			ids.append(product)
	return ids


## Forgets the clock of a place that no longer holds units.
func _prune(inventory: Inventory) -> void:
	for product: StringName in _warm.keys():
		var clocks: Dictionary = _warm[product]
		for location: StringName in clocks.keys():
			if inventory.count(product, location) <= 0:
				clocks.erase(location)
		if clocks.is_empty():
			_warm.erase(product)
