class_name PalletForklift
extends RefCounted
## The forklift a player drives to move supplier pallets, including up onto a rack (expansion D-0606).
##
## Pure state, no node: the height of the forks, and the rules for taking a pallet from the truck bed,
## the floor or a rack slot and leaving it on the floor or a rack slot. The pallets themselves live in
## a PalletJack ledger (the same one the manual jack uses, so a pallet can go from one to the other).
## The forks have to be at the level of the pallet (CompanyTuning.FORKLIFT_LEVEL_TOLERANCE_M) and the
## forklift within PALLET_JACK_REACH_M of it. The node that is driven and draws this is D-0606.b.
## Host authority: peers apply the same calls in the same order.

## Height of the forks above the floor, 0..CompanyTuning.FORKLIFT_MAX_LIFT_M.
var fork_height: float = 0.0


## Raises (positive `direction`) or lowers (negative) the forks for `delta` seconds; returns the new height.
func lift(direction: float, delta: float) -> float:
	var step: float = signf(direction) * CompanyTuning.FORKLIFT_LIFT_SPEED * maxf(delta, 0.0)
	fork_height = clampf(fork_height + step, 0.0, CompanyTuning.FORKLIFT_MAX_LIFT_M)
	return fork_height


## Sets the forks straight at `height` (a rack level), clamped to the mast.
func set_height(height: float) -> void:
	fork_height = clampf(height, 0.0, CompanyTuning.FORKLIFT_MAX_LIFT_M)


func at_level(height: float) -> bool:
	return absf(fork_height - height) <= CompanyTuning.FORKLIFT_LEVEL_TOLERANCE_M


## Takes pallet `id` off the bed (from the dock), the floor or a rack slot. `rack_levels` maps a slot id
## to its height in meters. False, changing nothing, when the forks are not at the pallet's level
## (the floor and the bed at 0), the forklift is out of reach or the ledger refuses.
func pick_up(jack: PalletJack, id: StringName, from_pos: Vector2, rack_levels: Dictionary = {}) -> bool:
	if not jack.places.has(id):
		return false
	var place: Dictionary = jack.places[id]
	var level: float = 0.0
	if place["at"] == PalletJack.AT_RACK:
		level = float(rack_levels.get(place["slot"], -1.0))
		if level < 0.0:
			return false
	if not at_level(level):
		return false
	return jack.pick_up(id, from_pos)


## Leaves the carried pallet on the floor. The forks have to be down.
func put_down(jack: PalletJack, pos: Vector2, floor_rect: Rect2, inventory: Inventory) -> bool:
	return at_level(0.0) and jack.put_down(pos, floor_rect, inventory)


## Leaves the carried pallet on rack slot `slot` (front at `slot_pos`, `level` meters up). The forks
## have to be at that level and the forklift within reach of the slot.
func put_on_rack(jack: PalletJack, slot: StringName, slot_pos: Vector2, level: float, from_pos: Vector2, inventory: Inventory) -> bool:
	if not at_level(level) or from_pos.distance_to(slot_pos) > CompanyTuning.PALLET_JACK_REACH_M:
		return false
	return jack.put_on_rack(slot, slot_pos, inventory)


func to_dict() -> Dictionary:
	return {"fork_height": fork_height}


func from_dict(data: Dictionary) -> void:
	set_height(float(data.get("fork_height", 0.0)))
