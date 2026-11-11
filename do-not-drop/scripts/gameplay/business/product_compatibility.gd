class_name ProductCompatibility
extends RefCounted
## Products that cannot travel in the same box (expansion D-0726, "Modo Empresa").
##
## Static and stateless. Every product belongs to at most one group (DANGEROUS, FOOD, LIVE); two groups
## clash when they are in RULES. conflicts() lists the clashing group pairs a PackedBox holds, so the
## table can warn before taping and assembly quality can take points off (penalty()). Products in no
## group (glass, lamps) mix with everything. Ids are looked up by name, so the table is the one place
## to extend when the catalog grows.

const DANGEROUS: StringName = &"dangerous"
const FOOD: StringName = &"food"
const LIVE: StringName = &"live"

## Product id -> group.
const GROUP_OF: Dictionary = {
	&"fireworks_crate": DANGEROUS,
	&"milk_canister": FOOD,
	&"sourdough": FOOD,
	&"wedding_cake": FOOD,
	&"hen": LIVE,
	&"puppy": LIVE,
	&"raccoon_cage": LIVE,
}

## Clashing group pairs, each as [a, b].
const RULES: Array = [
	[DANGEROUS, FOOD],
	[DANGEROUS, LIVE],
]


## The group of a product id, or &"" when it mixes with everything.
static func group_of(product: StringName) -> StringName:
	return GROUP_OF.get(product, &"")


## True when the two product ids may not share a box.
static func clash(a: StringName, b: StringName) -> bool:
	var ga: StringName = group_of(a)
	var gb: StringName = group_of(b)
	if ga == &"" or gb == &"" or ga == gb:
		return false
	for rule: Array in RULES:
		if (rule[0] == ga and rule[1] == gb) or (rule[0] == gb and rule[1] == ga):
			return true
	return false


## The clashing group pairs the box holds, as [group_a, group_b] in RULES order. Empty when the box is
## safe or null.
static func conflicts(box: PackedBox) -> Array:
	var out: Array = []
	if box == null:
		return out
	var held: Array = box.contents().keys()
	for rule: Array in RULES:
		var has_a: bool = false
		var has_b: bool = false
		for id: StringName in held:
			var g: StringName = group_of(id)
			has_a = has_a or g == rule[0]
			has_b = has_b or g == rule[1]
		if has_a and has_b:
			out.append([rule[0], rule[1]])
	return out


## True when nothing in the box clashes.
static func is_safe(box: PackedBox) -> bool:
	return conflicts(box).is_empty()


## Assembly quality points to take off for the clashes in the box (0 when safe).
static func penalty(box: PackedBox) -> int:
	return conflicts(box).size() * CompanyTuning.INCOMPATIBLE_QUALITY_PENALTY
