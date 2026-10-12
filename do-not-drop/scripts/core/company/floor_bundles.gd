class_name FloorBundles
extends RefCounted
## Where each bundle of units on the company shed's floor lies (D-2006).
##
## A bundle is an Inventory location, floor:<n> (location()), made by one units_moved event
## that carries its `pos`: a units_drop, or what a peer that left had in its hands (CompanyNet).
## Every peer keeps one of these next to its Inventory, changed only by those events
## (apply_move()) and by the snapshot (its "floor" key: to_dict() on the host, positions_ok()
## and from_dict() on a client), so every peer agrees on where each bundle lies; one left empty
## is gone. Pure data, no node: the Inventory counts the units, this only knows positions. What
## draws the bundles (D-0611) reads it on CompanyNet.event_applied and company_state_restored.

const PREFIX: String = "floor:"
## Most bundles a snapshot may carry (rule 5). Each one is a drop or a peer that left, and an
## empty one is gone: a shed never gets near it.
const MAX_BUNDLES: int = 4096
## Longest bundle id a snapshot may carry: floor: and a number.
const MAX_ID_LENGTH: int = 32

## {floor:<n>: Vector3}
var _at: Dictionary = {}


## Inventory location of bundle `n`.
static func location(n: int) -> StringName:
	return StringName(PREFIX + str(n))


## True for a bundle's location (floor:<n>).
static func is_floor(where: StringName) -> bool:
	return String(where).begins_with(PREFIX)


## Bundle positions that came over the network (rule 5): a Dictionary of at most MAX_BUNDLES
## floor:<n> ids, as text up to MAX_ID_LENGTH, each to a finite Vector3.
static func positions_ok(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() > MAX_BUNDLES:
		return false
	var bundles: Dictionary = value
	for id: Variant in bundles:
		if typeof(id) != TYPE_STRING and typeof(id) != TYPE_STRING_NAME:
			return false
		if String(id).length() > MAX_ID_LENGTH or not String(id).begins_with(PREFIX):
			return false
		var pos: Variant = bundles[id]
		if not (pos is Vector3 and RpcGuard.finite_vec3(pos)):
			return false
	return true


## Where bundle `where` lies, null when no bundle there has a position (none, or one a loaded
## day put there without one: CompanyRoot.SAVED_HANDS_LOCATION).
func position_of(where: StringName) -> Variant:
	return _at.get(where)


## {floor:<n>: Vector3} of every bundle with a position, a copy (the snapshot's "floor").
func to_dict() -> Dictionary:
	return _at.duplicate()


## Puts `value` (checked with positions_ok()) in place of every position here.
func from_dict(value: Dictionary) -> void:
	_at.clear()
	for id: Variant in value:
		_at[StringName(id)] = value[id]


## A units_moved on `stock`, with the floor kept (the same on every peer, rule 6): a move into
## a bundle needs `pos`, a finite Vector3, and the bundle lies there from then on; a bundle the
## move leaves empty is gone. False, changing nothing, when the move doesn't fit.
func apply_move(stock: Inventory, product: StringName, qty: int, from: StringName,
		to: StringName, pos: Variant) -> bool:
	var into_floor: bool = is_floor(to)
	if into_floor and not (pos is Vector3 and RpcGuard.finite_vec3(pos)):
		return false
	if not stock.move(product, qty, from, to):
		return false
	if into_floor:
		_at[to] = pos
	if is_floor(from) and stock.contents_at(from).is_empty():
		_at.erase(from)
	return true


## The lowest floor:<n> that holds nothing in `stock` and has no position: where a new bundle
## goes. A loaded day's stock may hold bundles without a position (SAVED_HANDS_LOCATION): those
## are never reused.
func next_free(stock: Inventory) -> StringName:
	var n: int = 0
	while _at.has(location(n)) or not stock.contents_at(location(n)).is_empty():
		n += 1
	return location(n)
