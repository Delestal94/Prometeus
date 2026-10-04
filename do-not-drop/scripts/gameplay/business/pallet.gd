class_name Pallet
extends RefCounted
## A supplier pallet: up to MAX_UNITS units of one product (expansion D-0604).
##
## A pallet is a plain Dictionary (id, product, qty, state) so it can travel
## by network and live in a save. Its units sit in the Inventory under the
## location &"pallet:<id>" until the pallet is opened (D-0607). Pure data: no
## node, no autoload. The physical pallet object (mesh, truck bed) is built on
## top of this by D-0605 / D-0606.

const STATE_SEALED: StringName = &"sealed"
const STATE_OPEN: StringName = &"open"
const STATES: Array[StringName] = [STATE_SEALED, STATE_OPEN]
## Assumption of supuestos.md: a pallet holds up to 24 units of one product.
const MAX_UNITS: int = 24


## Builds a sealed pallet, or {} when product is empty or qty is out of 1..MAX_UNITS.
static func make(id: StringName, product: StringName, qty: int) -> Dictionary:
	if id == &"" or product == &"" or qty < 1 or qty > MAX_UNITS:
		return {}
	return {"id": id, "product": product, "qty": qty, "state": STATE_SEALED}


## Splits a supplier order into the fewest pallets (full ones first). Ids are
## "<prefix>_1", "<prefix>_2"... Empty when the order is not positive.
static func plan(prefix: StringName, product: StringName, qty: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var left: int = qty
	while left > 0 and product != &"":
		var n: int = mini(left, MAX_UNITS)
		out.append(make(StringName("%s_%d" % [prefix, out.size() + 1]), product, n))
		left -= n
	return out


## Inventory location of a pallet's units.
static func location(id: StringName) -> StringName:
	return StringName("pallet:%s" % id)


## Problems of a pallet dictionary (empty list = valid).
static func validate(pallet: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if StringName(pallet.get("id", &"")) == &"":
		problems.append("id is empty")
	if StringName(pallet.get("product", &"")) == &"":
		problems.append("product is empty")
	var qty: int = int(pallet.get("qty", 0))
	if qty < 1 or qty > MAX_UNITS:
		problems.append("qty %d is out of 1..%d" % [qty, MAX_UNITS])
	if not StringName(pallet.get("state", &"")) in STATES:
		problems.append("unknown state")
	return problems


## Puts a sealed pallet's units into the inventory (the supplier truck unloads
## it). False, changing nothing, if the pallet is invalid or already received.
static func receive(inventory: Inventory, pallet: Dictionary) -> bool:
	if not validate(pallet).is_empty():
		return false
	var at: StringName = location(StringName(pallet["id"]))
	if inventory.contents_at(at).size() > 0:
		return false
	return inventory.receive(StringName(pallet["product"]), int(pallet["qty"]), at)


## Units still on the pallet, according to the inventory.
static func units_left(inventory: Inventory, pallet: Dictionary) -> int:
	return inventory.count(
		StringName(pallet.get("product", &"")), location(StringName(pallet.get("id", &"")))
	)


## Opens a sealed pallet so its units can be taken (D-0607). The units stay at
## pallet:<id>; open() only flips the state, in place. False, changing nothing,
## if the pallet is invalid, already open or no longer holds its units.
static func open(inventory: Inventory, pallet: Dictionary) -> bool:
	if not validate(pallet).is_empty() or pallet["state"] != STATE_SEALED:
		return false
	if units_left(inventory, pallet) < 1:
		return false
	pallet["state"] = STATE_OPEN
	return true


## Takes qty units out of an open pallet into another location (a hand, a cart,
## a shelf slot). False, changing nothing, while the pallet is sealed or if it
## holds fewer than qty.
static func take(inventory: Inventory, pallet: Dictionary, qty: int, to: StringName) -> bool:
	if pallet.get("state") != STATE_OPEN:
		return false
	return inventory.move(
		StringName(pallet["product"]), qty, location(StringName(pallet["id"])), to
	)


## True once an open pallet has been emptied and can be removed from the yard.
static func is_depleted(inventory: Inventory, pallet: Dictionary) -> bool:
	return pallet.get("state") == STATE_OPEN and units_left(inventory, pallet) == 0


static func to_json(pallet: Dictionary) -> String:
	return JSON.stringify(pallet)


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var d: Dictionary = parsed
	var out: Dictionary = make(
		StringName(d.get("id", "")), StringName(d.get("product", "")), int(d.get("qty", 0))
	)
	if not out.is_empty() and StringName(d.get("state", "")) in STATES:
		out["state"] = StringName(d["state"])
	return out
