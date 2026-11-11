class_name PickingCart
extends RefCounted
## A push cart that carries several products at once (expansion D-0610, "Modo Empresa").
##
## Pure over Inventory, no node, no autoload. The units of a cart live in the Inventory at
## &"cart:<id>"; this class only knows the id and answers what fits. It carries up to
## CompanyTuning.CART_MAX_UNITS units in total, products mixed, against HAND_MAX_UNITS of one product in
## the hands. Moving is all or nothing and goes only through Inventory.move, so a unit is never created
## or lost. plan_*() answers what a use would move, as the units_take-style request {product, qty, from,
## to}, or {reason}; load_from_hands() / unload_to_hands() apply it and answer how many units moved
## (0 when refused). The pushable node, its physics and the interaction come with D-0610.b. Host
## authority: peers apply the same calls in the same order.

const REASON_EMPTY: StringName = &"empty"
const REASON_FULL: StringName = &"full"
const REASON_HANDS_FULL: StringName = &"hands_full"
const REASON_HANDS_BUSY: StringName = &"hands_busy"
const REASON_NOT_ENOUGH: StringName = &"not_enough"

const LOCATION_PREFIX: String = "cart:"

## Id of the cart, &"" for one that does not exist (it carries nothing and refuses everything).
var id: StringName = &""


static func make(cart_id: StringName) -> PickingCart:
	var cart := PickingCart.new()
	cart.id = cart_id
	return cart


## The Inventory location of a cart.
static func location_of(cart_id: StringName) -> StringName:
	return StringName(LOCATION_PREFIX + String(cart_id))


## The cart id of a location_of() name, &"" when it is not one.
static func parse_location(location: StringName) -> StringName:
	var text: String = String(location)
	if not text.begins_with(LOCATION_PREFIX) or text.length() == LOCATION_PREFIX.length():
		return &""
	return StringName(text.substr(LOCATION_PREFIX.length()))


func is_valid() -> bool:
	return id != &""


func location() -> StringName:
	return location_of(id)


## Units on the cart, all products.
func count(inventory: Inventory) -> int:
	var total: int = 0
	for qty: int in contents(inventory).values():
		total += qty
	return total


## Units that still fit.
func free_space(inventory: Inventory) -> int:
	return maxi(CompanyTuning.CART_MAX_UNITS - count(inventory), 0)


## product -> qty on the cart.
func contents(inventory: Inventory) -> Dictionary:
	if not is_valid():
		return {}
	return inventory.contents_at(location())


## The products on the cart, sorted.
func products(inventory: Inventory) -> Array[StringName]:
	# Sorted as text: StringName's own order is by hash, not alphabetical.
	var names: Array[String] = []
	for product: StringName in contents(inventory):
		names.append(String(product))
	names.sort()
	var found: Array[StringName] = []
	for name: String in names:
		found.append(StringName(name))
	return found


## What putting hand units on the cart would move: {product, qty, from, to} or {reason}. `product` is
## &"" for the only one in the hands; `qty` is -1 for as many as fit (what the hands hold, up to the
## free space) or an exact number, which is refused (not_enough, full) when it does not fit.
func plan_load(inventory: Inventory, hands: StringName, product: StringName = &"",
		qty: int = -1) -> Dictionary:
	var held: Dictionary = inventory.contents_at(hands)
	if not is_valid() or held.is_empty():
		return {"reason": REASON_EMPTY}
	if product == &"":
		if held.size() > 1:
			return {"reason": REASON_HANDS_BUSY}
		product = held.keys()[0]
	var in_hands: int = int(held.get(product, 0))
	if in_hands <= 0 or qty == 0 or qty < -1:
		return {"reason": REASON_EMPTY if in_hands <= 0 else REASON_NOT_ENOUGH}
	var room: int = free_space(inventory)
	if room <= 0:
		return {"reason": REASON_FULL}
	if qty == -1:
		qty = mini(in_hands, room)
	elif qty > in_hands:
		return {"reason": REASON_NOT_ENOUGH}
	elif qty > room:
		return {"reason": REASON_FULL}
	return {"product": product, "qty": qty, "from": hands, "to": location()}


## What taking units off the cart into the hands would move: {product, qty, from, to} or {reason}.
## `product` is &"" for the one the hands already hold, or the first on the cart (sorted) when they
## are empty; `qty` is -1 for as many as the hands take (HAND_MAX_UNITS, one product) or an exact number.
func plan_unload(inventory: Inventory, hands: StringName, product: StringName = &"",
		qty: int = -1) -> Dictionary:
	var on_cart: Dictionary = contents(inventory)
	if on_cart.is_empty():
		return {"reason": REASON_EMPTY}
	var held: Dictionary = inventory.contents_at(hands)
	product = _unload_product(inventory, held, product)
	if product == &"":
		return {"reason": REASON_HANDS_BUSY}
	var held_units: int = int(held.get(product, 0))
	var available: int = int(on_cart.get(product, 0))
	if available <= 0 or qty == 0 or qty < -1:
		return {"reason": REASON_EMPTY if available <= 0 else REASON_NOT_ENOUGH}
	var room: int = CompanyTuning.HAND_MAX_UNITS - held_units
	if room <= 0:
		return {"reason": REASON_HANDS_FULL}
	if qty == -1:
		qty = mini(available, room)
	elif qty > available:
		return {"reason": REASON_NOT_ENOUGH}
	elif qty > room:
		return {"reason": REASON_HANDS_FULL}
	return {"product": product, "qty": qty, "from": location(), "to": hands}


## Puts hand units on the cart. Returns how many moved, 0 (nothing changed) when plan_load() refuses.
func load_from_hands(inventory: Inventory, hands: StringName, product: StringName = &"",
		qty: int = -1) -> int:
	return _apply(inventory, plan_load(inventory, hands, product, qty))


## Takes units off the cart into the hands. Returns how many moved, 0 (nothing changed) when
## plan_unload() refuses.
func unload_to_hands(inventory: Inventory, hands: StringName, product: StringName = &"",
		qty: int = -1) -> int:
	return _apply(inventory, plan_unload(inventory, hands, product, qty))


func to_dict() -> Dictionary:
	return {"id": String(id)}


## Rebuilds the cart from to_dict() (also after a JSON round trip). A missing or non-text id leaves an
## invalid cart instead of failing.
func from_dict(data: Dictionary) -> void:
	var raw: Variant = data.get("id", "")
	id = StringName(raw) if raw is String or raw is StringName else &""


## The product an unload would move, &"" when the hands are in the way: two products in them, or
## one that is not the one asked for or on the cart.
func _unload_product(inventory: Inventory, held: Dictionary, product: StringName) -> StringName:
	if held.size() > 1:
		return &""
	if held.is_empty():
		return product if product != &"" else products(inventory)[0]
	var in_hands: StringName = held.keys()[0]
	if (product != &"" and product != in_hands) or not contents(inventory).has(in_hands):
		return &""
	return in_hands


static func _apply(inventory: Inventory, plan: Dictionary) -> int:
	if plan.has("reason"):
		return 0
	var qty: int = plan["qty"]
	if not inventory.move(plan["product"], qty, plan["from"], plan["to"]):
		return 0
	return qty
