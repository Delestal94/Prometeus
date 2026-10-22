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
##
## In the company world (ColdChainTick, D-0616.b) the stock is the one CompanyNet's events
## change, so the host does not discard by itself: age() only counts the minutes and says what
## is due, the host publishes each one as a units_spoiled event (CompanyColdNet) that every
## peer applies with Inventory.discard, and note_moved() carries the clock after an event
## that already moved the units. advance() is age() plus the discard, for a stock nobody
## else mirrors.
##
## Only places where units wait age (ages_at()): what is in a hand, a box on a table or a
## package is in somebody's work, and a box has ColdPack.

## Places whose units never age here: hands, the contents of a packing table, open boxes and
## sealed packages (CompanyNet.HANDS_PREFIX, CompanyTableNet's prefixes).
const UNAGED_PREFIXES: Array[String] = ["hands:", "table:", "box:", "package:"]

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


## False for a place whose units don't age (UNAGED_PREFIXES).
static func ages_at(location: StringName) -> bool:
	var text: String = String(location)
	for prefix: String in UNAGED_PREFIXES:
		if text.begins_with(prefix):
			return false
	return true


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


## Lets `minutes` of game time go by and discards what rotted. Returns what rotted, one entry per
## product and place: { "product", "location", "qty", "lost": { order id -> units } }.
func advance(
	inventory: Inventory, products: Dictionary, cold_shelves: Dictionary, minutes: float
) -> Array[Dictionary]:
	var rotten: Array[Dictionary] = []
	for due: Dictionary in age(inventory, products, cold_shelves, minutes):
		var lost: Variant = inventory.discard(due["product"], due["qty"], due["location"])
		if lost is Dictionary:
			rotten.append({"product": due["product"], "location": due["location"], "qty": due["qty"], "lost": lost})
	_prune(inventory)
	return rotten


## Lets `minutes` of game time go by without touching the stock: every cold product stored outside
## a fridge, where units wait (ages_at()), gets older. Returns where the clock reached the limit,
## one entry per product and place: { "product", "location", "qty" } (all the units there). The
## caller takes them out of the stock and then calls forget_empty(); until then they stay due,
## so a failed attempt is reported again by the next call.
func age(
	inventory: Inventory, products: Dictionary, cold_shelves: Dictionary, minutes: float
) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if minutes <= 0.0:
		return due
	for product: StringName in _tracked(inventory, products):
		var places: Dictionary = inventory.locations_of(product)
		var clocks: Dictionary = _warm.get(product, {})
		for location: StringName in places.keys():
			if not ages_at(location) or is_cold_location(location, cold_shelves):
				continue
			var minutes_out: float = float(clocks.get(location, 0.0)) + minutes
			clocks[location] = minutes_out
			if minutes_out >= CompanyTuning.COLD_SPOIL_MINUTES:
				due.append({"product": product, "location": location, "qty": int(places[location])})
		_warm[product] = clocks
	return due


## An event already moved `qty` units of `product` from `from` to `to` in `inventory` (the host
## saw it applied): the clock goes with them, as move() does, joining the ones at `to` by the
## average weighted by units.
func note_moved(
	inventory: Inventory, product: StringName, qty: int, from: StringName, to: StringName
) -> void:
	var after: int = inventory.count(product, to)
	if qty <= 0 or from == to or after < qty:
		return
	_merge(product, to, after - qty, qty, warm_minutes(product, from))
	_prune(inventory)


## Forgets the clock of every place that no longer holds units (after the due ones were taken out).
func forget_empty(inventory: Inventory) -> void:
	_prune(inventory)


func to_dict() -> Dictionary:
	return {"warm": _warm.duplicate(true)}


## Rebuilds from to_dict() (also after a JSON round trip). Bad entries are dropped.
func from_dict(data: Variant) -> void:
	_warm.clear()
	var warm: Variant = {}
	if data is Dictionary:
		warm = (data as Dictionary).get("warm", {})
	if not warm is Dictionary:
		return
	for product: Variant in warm:
		var places: Variant = (warm as Dictionary)[product]
		if not CompanyAsk.is_id(product) or not places is Dictionary:
			continue
		var clocks: Dictionary = {}
		for location: Variant in places:
			var minutes: Variant = (places as Dictionary)[location]
			if not CompanyAsk.is_id(location) or not (minutes is int or minutes is float):
				continue
			if float(minutes) > 0.0 and float(minutes) < CompanyTuning.COLD_SPOIL_MINUTES:
				clocks[StringName(location)] = float(minutes)
		if not clocks.is_empty():
			_warm[StringName(product)] = clocks


## True when some place has a clock running.
func is_ticking() -> bool:
	return not _warm.is_empty()


func _carry(
	inventory: Inventory,
	product: StringName,
	qty: int,
	from: StringName,
	to: StringName,
	incoming_minutes: float
) -> bool:
	var before: int = inventory.count(product, to)
	var ok: bool
	if from == &"":
		ok = inventory.receive(product, qty, to)
	else:
		ok = inventory.move(product, qty, from, to)
	if not ok:
		return false
	_merge(product, to, before, qty, incoming_minutes)
	_prune(inventory)
	return true


## `qty` units with `incoming_minutes` on their clock joined the `before` that were at `to`.
func _merge(product: StringName, to: StringName, before: int, qty: int, incoming_minutes: float) -> void:
	var merged: float = (warm_minutes(product, to) * before + incoming_minutes * qty) / float(before + qty)
	var clocks: Dictionary = _warm.get(product, {})
	if merged > 0.0:
		clocks[to] = merged
		_warm[product] = clocks
	else:
		clocks.erase(to)


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
