class_name PalletJack
extends RefCounted
## Where each supplier pallet physically is, and the manual pallet jack that moves it (expansion D-0605).
##
## Pure data, no node, no autoload: a pallet is on the truck's bed, carried by the jack or standing on
## the shed floor at a point in meters, or on a rack slot (D-0606).
## The jack takes one pallet at a time. Units reach the Inventory
## (Pallet.receive) once, when a pallet from the bed is put down on the floor, so a pallet that never
## leaves the bed is never counted and leaves with the truck. The nodes that draw and drive it come
## with D-0605.b. Host authority: peers apply the same calls in the same order.

const AT_BED: StringName = &"bed"
const AT_JACK: StringName = &"jack"
const AT_FLOOR: StringName = &"floor"
## On a rack slot (D-0606): only the forklift reaches that high (PalletForklift).
const AT_RACK: StringName = &"rack"

## Pallet id -> {pallet (the Pallet dictionary), at (AT_*), pos (Vector2, only on the floor)}.
var places: Dictionary = {}
## Id of the pallet on the jack, &"" when it is empty.
var carrying: StringName = &""


## Puts the day's pallets on the truck bed. Invalid or repeated ids are skipped; returns how many went on.
func load_bed(pallets: Array[Dictionary]) -> int:
	var loaded: int = 0
	for pallet: Dictionary in pallets:
		var id := StringName(pallet.get("id", &""))
		if not Pallet.validate(pallet).is_empty() or places.has(id):
			continue
		places[id] = {"pallet": pallet, "at": AT_BED}
		loaded += 1
	return loaded


## Ids of the pallets in a given place, sorted.
func ids_at(at: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in places:
		if places[id]["at"] == at:
			found.append(id)
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


## Whether pick_up(id, holder) would work, changing nothing (the host checks a request with it).
func can_pick_up(id: StringName, holder: Vector2 = Vector2.ZERO) -> bool:
	if carrying != &"" or not places.has(id):
		return false
	var place: Dictionary = places[id]
	if place["at"] == AT_JACK:
		return false
	if place["at"] == AT_FLOOR or place["at"] == AT_RACK:
		return holder.distance_to(place["pos"]) <= CompanyTuning.PALLET_JACK_REACH_M
	return true


## Picks a pallet up from the bed or the floor. `holder` and `from_pos` (meters) are where the person
## and the jack stand: it has to be within PALLET_JACK_REACH_M of a floor pallet (the bed is reached
## from the dock, the caller checks that). False, changing nothing, if the jack is full, the pallet is
## unknown or already on the jack, or it is out of reach.
func pick_up(id: StringName, holder: Vector2 = Vector2.ZERO) -> bool:
	if not can_pick_up(id, holder):
		return false
	var place: Dictionary = places[id]
	place.erase("pos")
	place.erase("slot")
	place["at"] = AT_JACK
	carrying = id
	return true


## Whether put_down(pos, floor_rect, ...) would find the spot free, changing nothing.
func can_put_down(pos: Vector2, floor_rect: Rect2) -> bool:
	if carrying == &"" or not floor_rect.encloses(_footprint(pos)):
		return false
	for id: StringName in ids_at(AT_FLOOR):
		if _footprint(places[id]["pos"]).intersects(_footprint(pos)):
			return false
	return true


## Puts the carried pallet on the floor at `pos`, inside `floor_rect` (meters) and without overlapping
## another floor pallet. A pallet that came from the bed is received into `inventory` here, once.
## False, changing nothing, when the jack is empty or the spot is not free.
func put_down(pos: Vector2, floor_rect: Rect2, inventory: Inventory) -> bool:
	if not can_put_down(pos, floor_rect):
		return false
	var place: Dictionary = places[carrying]
	var pallet: Dictionary = place["pallet"]
	if inventory.contents_at(Pallet.location(carrying)).is_empty():
		if not Pallet.receive(inventory, pallet):
			return false
	place["at"] = AT_FLOOR
	place["pos"] = pos
	carrying = &""
	return true


## Puts the carried pallet on rack slot `slot`, whose front is at `pos` (meters), if no other pallet
## holds it. Like put_down, a pallet from the bed is received into `inventory` here, once. False,
## changing nothing, when the jack is empty or the slot is taken. Height and reach are PalletForklift's.
func put_on_rack(slot: StringName, pos: Vector2, inventory: Inventory) -> bool:
	if carrying == &"" or slot == &"" or rack_pallet(slot) != &"":
		return false
	var place: Dictionary = places[carrying]
	var pallet: Dictionary = place["pallet"]
	if inventory.contents_at(Pallet.location(carrying)).is_empty():
		if not Pallet.receive(inventory, pallet):
			return false
	place["at"] = AT_RACK
	place["pos"] = pos
	place["slot"] = slot
	carrying = &""
	return true


## Id of the pallet on rack slot `slot`, &"" when it is free.
func rack_pallet(slot: StringName) -> StringName:
	for id: StringName in ids_at(AT_RACK):
		if places[id]["slot"] == slot:
			return id
	return &""


## What still sits on the bed (the truck takes it away when it leaves).
func left_on_bed() -> Array[Dictionary]:
	var left: Array[Dictionary] = []
	for id: StringName in ids_at(AT_BED):
		left.append(places[id]["pallet"])
	return left


## Takes a pallet off the yard (opened and emptied: Pallet.is_depleted). Not while it is on the jack.
func remove(id: StringName) -> bool:
	if not places.has(id) or places[id]["at"] == AT_JACK:
		return false
	places.erase(id)
	return true


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in places:
		var place: Dictionary = places[id].duplicate()
		if place.has("pos"):
			place["pos"] = [place["pos"].x, place["pos"].y]
		if place.has("slot"):
			place["slot"] = String(place["slot"])
		out[String(id)] = place
	return {"places": out, "carrying": String(carrying)}


func from_dict(data: Dictionary) -> void:
	places.clear()
	var raw: Dictionary = data.get("places", {})
	for key: String in raw:
		var place: Dictionary = (raw[key] as Dictionary).duplicate()
		if place.has("pos"):
			var xy: Array = place["pos"]
			place["pos"] = Vector2(float(xy[0]), float(xy[1]))
		place["at"] = StringName(place["at"])
		if place.has("slot"):
			place["slot"] = StringName(place["slot"])
		places[StringName(key)] = place
	carrying = StringName(data.get("carrying", ""))


static func _footprint(pos: Vector2) -> Rect2:
	var size: Vector2 = CompanyTuning.PALLET_FOOTPRINT_M
	return Rect2(pos - size * 0.5, size)
