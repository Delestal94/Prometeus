class_name PlaceableShop
extends RefCounted
## Buying and selling warehouse objects with the company money (expansion D-0920).
##
## Static helpers over a CompanyState-shaped object passed in by the caller (no autoload is
## named here, lesson N-919). A placed piece is one entry of `state.layout`:
## {id, x, z, turns} (grid cell of its corner and quarter turns). Whether the cell is free
## is the build grid's job (D-0225, D-0902); this class only moves money and layout entries.
## Buying charges the full price; selling gives back PlaceableDefinition.refund() and
## removes the entry. Both go in the wallet ledger.

const REASON_BUY: StringName = &"placeable_buy"
const REASON_SELL: StringName = &"placeable_sell"
const DEFINITIONS_DIR: String = "res://data/placeables/"


## The definition with this id, or null when there is no such object.
static func definition(id: StringName) -> PlaceableDefinition:
	var path: String = "%s%s.tres" % [DEFINITIONS_DIR, id]
	if id == &"" or not ResourceLoader.exists(path):
		return null
	return load(path) as PlaceableDefinition


## Pays the price and adds the piece to the layout. Returns false, changing nothing, when the
## wallet does not cover it. Objects the company owns at start are added with free = true.
static func buy(state: Object, def: PlaceableDefinition, x: int, z: int, turns: int = 0,
		free: bool = false) -> bool:
	if def == null:
		return false
	if not free and not state.spend(def.price, REASON_BUY):
		return false
	state.layout.append({"id": str(def.id), "x": x, "z": z, "turns": posmod(turns, 4)})
	return true


## Sells the piece at `index` of the layout: removes it and pays the refund. Returns the money
## given back, or -1 when the index or the object is not valid (nothing changes then).
static func sell(state: Object, index: int) -> int:
	if index < 0 or index >= state.layout.size():
		return -1
	var def: PlaceableDefinition = definition(StringName(str(state.layout[index].get("id", ""))))
	if def == null:
		return -1
	state.layout.remove_at(index)
	var refund: int = def.refund()
	if refund > 0:
		state.earn(refund, REASON_SELL)
	return refund


## Money lost buying and selling the same piece back: price - refund.
static func round_trip_loss(def: PlaceableDefinition) -> int:
	return def.price - def.refund()
