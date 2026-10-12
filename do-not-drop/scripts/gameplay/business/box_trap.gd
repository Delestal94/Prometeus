class_name BoxTrap
extends RefCounted
## What a packed box does to its trip (expansion D-0710, "Modo Empresa").
##
## Static and stateless. The packing never changes which trap rides (BoxToPackage.ruling_product);
## it changes how hard it hits (docs/expansion-distritos/diseno/armado-y-trampas.md §5):
## intensity = 1 - quality / QUALITY_MAX, so a perfect box rides at the trap's lowest level and a
## ruined one at its highest. A box that is mostly air (BoxToPackage.is_loose) also carries a low
## Balance trap on top. The plan is data only: the package keeps a single trap behavior, the
## absorption it already scales impacts with, and reads the rest from its metadata.

const LEVEL_LOW: StringName = &"low"
const LEVEL_MID: StringName = &"mid"
const LEVEL_HIGH: StringName = &"high"
const LOOSE_TRAP_ID: StringName = &"balance"


## 0 for a perfect box, 1 for a worthless one.
static func intensity(quality: float) -> float:
	return clampf(1.0 - quality / CompanyTuning.QUALITY_MAX, 0.0, 1.0)


## low / mid / high, by CompanyTuning.TRAP_INTENSITY_MID and TRAP_INTENSITY_HIGH.
static func level(trap_intensity: float) -> StringName:
	if trap_intensity >= CompanyTuning.TRAP_INTENSITY_HIGH:
		return LEVEL_HIGH
	if trap_intensity >= CompanyTuning.TRAP_INTENSITY_MID:
		return LEVEL_MID
	return LEVEL_LOW


## {trap_id, quality, intensity, level, absorption, extra}. extra lists the traps added on top as
## {trap_id, intensity}. An empty dictionary if the box holds no known product.
static func plan(box: PackedBox, order: Dictionary, products: Dictionary = {}) -> Dictionary:
	var main: ProductDefinition = BoxToPackage.ruling_product(box, products)
	if main == null:
		return {}
	var quality: float = AssemblyQuality.score(box, order, products)
	var amount: float = intensity(quality)
	var extra: Array = []
	if BoxToPackage.is_loose(box) and main.trap_id != LOOSE_TRAP_ID:
		extra.append(
			{"trap_id": LOOSE_TRAP_ID, "intensity": CompanyTuning.TRAP_LOOSE_BOX_INTENSITY}
		)
	return {
		"trap_id": main.trap_id,
		"quality": quality,
		"intensity": amount,
		"level": level(amount),
		"absorption": BoxToPackage.absorption(box),
		"extra": extra,
	}
