class_name ColdPack
extends RefCounted
## Ice packs in a box and how long its cold products last (expansion D-0721, "Modo Empresa").
##
## Static and stateless. A box with a cold product (ProductDefinition.temperature == &"cold")
## stays cold CompanyTuning.COLD_BASE_MINUTES on its own and COLD_PER_ICE_MINUTES more per ice
## pack (PackedBox.ice_packs, up to ICE_PACKS_MAX). The trip compares that with its length in game
## minutes: past it the cold products are warm on arrival. The ice pack's price (ICE_PACK_COST) is
## charged by whoever calls add_ice(), like the rest of the packaging supplies.

const COLD: StringName = &"cold"


## True when any product in the box is cold. products maps id -> ProductDefinition; an id missing
## there counts as not cold.
static func has_cold(box: PackedBox, products: Dictionary = {}) -> bool:
	if box == null:
		return false
	for item: Dictionary in box.items:
		var def: ProductDefinition = products.get(item["product"]) as ProductDefinition
		if def != null and def.temperature == COLD:
			return true
	return false


## Puts one more ice pack in. False, changing nothing, with no box or the maximum already in.
static func add_ice(box: PackedBox) -> bool:
	if box == null or box.ice_packs >= CompanyTuning.ICE_PACKS_MAX:
		return false
	box.ice_packs += 1
	return true


## Game minutes the cold lasts in this box.
static func cold_minutes(box: PackedBox) -> float:
	if box == null:
		return 0.0
	return CompanyTuning.COLD_BASE_MINUTES + CompanyTuning.COLD_PER_ICE_MINUTES * box.ice_packs


## True when the cold products are still cold after `trip_minutes`. A box with nothing cold always
## holds.
static func holds(box: PackedBox, trip_minutes: float, products: Dictionary = {}) -> bool:
	if not has_cold(box, products):
		return true
	return trip_minutes <= cold_minutes(box)


## Ice packs the box needs for a trip of `trip_minutes` (0 when it needs none), capped at
## ICE_PACKS_MAX. The tutorial and the bots use it to suggest how many to put in.
static func ice_needed(trip_minutes: float) -> int:
	var extra: float = trip_minutes - CompanyTuning.COLD_BASE_MINUTES
	if extra <= 0.0:
		return 0
	return mini(ceili(extra / CompanyTuning.COLD_PER_ICE_MINUTES), CompanyTuning.ICE_PACKS_MAX)
