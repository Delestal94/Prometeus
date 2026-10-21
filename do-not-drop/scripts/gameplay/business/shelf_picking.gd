class_name ShelfPicking
extends RefCounted
## Picking from a shelf by hand (expansion D-0609, "Modo Empresa"): what one use of a shelf asks for.
##
## Pure over Shelf and Inventory. A use takes from one slot into the player's hands: the slot comes from
## a cursor that rotates over the shelf's non-empty slots while the hands are empty, and stays on the
## product in the hands otherwise, so a second use tops the hands up to CompanyTuning.HAND_MAX_UNITS. The
## answer is the units_take request (station, product, qty); the host checks it again (CompanyNet) and is
## the one that moves the units. Nothing here changes the Inventory.

const REASON_EMPTY: StringName = &"empty"
const REASON_HANDS_FULL: StringName = &"hands_full"
const REASON_HANDS_BUSY: StringName = &"hands_busy"


## The station name of a slot, as CompanyNet's `stations` resolver knows it.
static func station_id(shelf_uid: StringName, slot: int) -> StringName:
	return StringName("%s_slot%d" % [shelf_uid, slot])


## {uid, slot} of a station_id() name, or {} when it is not one.
static func parse_station(id: StringName) -> Dictionary:
	var text: String = String(id)
	var cut: int = text.rfind("_slot")
	if cut <= 0:
		return {}
	var tail: String = text.substr(cut + 5)
	if not tail.is_valid_int():
		return {}
	return {"uid": StringName(text.substr(0, cut)), "slot": tail.to_int()}


## What a use asks for: {station, product, qty, slot} when it takes, or {reason} when it cannot.
## `hands` is the Inventory location of the player's hands; `after` the slot the last use took from
## (-1 for none): with empty hands the next non-empty slot after it is taken, wrapping around.
static func plan(shelf_uid: StringName, shelf: Shelf, inventory: Inventory, hands: StringName,
		after: int = -1) -> Dictionary:
	if shelf == null:
		return {"reason": REASON_EMPTY}
	var held: Dictionary = inventory.contents_at(hands)
	if held.size() > 1:
		return {"reason": REASON_HANDS_BUSY}
	var held_units: int = 0
	var slot: int = -1
	if held.size() == 1:
		var product: StringName = held.keys()[0]
		held_units = int(held[product])
		slot = shelf.find_slot(product)
		if slot == -1:
			return {"reason": REASON_HANDS_BUSY}
	else:
		slot = _next_filled(shelf, inventory, after)
	if slot == -1 or shelf.count(inventory, slot) <= 0:
		return {"reason": REASON_EMPTY}
	var room: int = CompanyTuning.HAND_MAX_UNITS - held_units
	if room <= 0:
		return {"reason": REASON_HANDS_FULL}
	return {
		"station": station_id(shelf_uid, slot), "product": shelf.label_of(slot),
		"qty": mini(room, shelf.count(inventory, slot)), "slot": slot,
	}


static func _next_filled(shelf: Shelf, inventory: Inventory, after: int) -> int:
	var size: int = shelf.slot_count()
	for step: int in range(1, size + 1):
		var slot: int = posmod(after + step, size)
		if shelf.count(inventory, slot) > 0:
			return slot
	return -1
