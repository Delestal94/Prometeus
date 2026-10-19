class_name GelSkinCatalog
extends RefCounted
## Ordered base-skin catalog with stable IDs and a deterministic default (S-311.65).

const DEFAULT_ID: StringName = &"milk"
const SKINS: Array[Resource] = [
	preload("res://data/gel_skins/milk.tres"),
	preload("res://data/gel_skins/strawberry.tres"),
	preload("res://data/gel_skins/lime.tres"),
	preload("res://data/gel_skins/grape.tres"),
	preload("res://data/gel_skins/orange.tres"),
	preload("res://data/gel_skins/mint.tres"),
	preload("res://data/gel_skins/lemon.tres"),
	preload("res://data/gel_skins/blueberry.tres"),
	preload("res://data/gel_skins/cherry.tres"),
	preload("res://data/gel_skins/cola.tres"),
	preload("res://data/gel_skins/watermelon.tres"),
	preload("res://data/gel_skins/blackberry.tres"),
	preload("res://data/gel_skins/peach.tres"),
	preload("res://data/gel_skins/sky.tres"),
	preload("res://data/gel_skins/translucent_charcoal.tres"),
	preload("res://data/gel_skins/rainbow.tres"),
]
const INTERIOR_SKINS: Array[Resource] = [
	preload("res://data/gel_skins/layered_gummy.tres"),
	preload("res://data/gel_skins/vertical_gradient.tres"),
	preload("res://data/gel_skins/fruit_bits.tres"),
	preload("res://data/gel_skins/glitter.tres"),
	preload("res://data/gel_skins/big_bubbles.tres"),
]
const ANIMATED_SKINS: Array[Resource] = [
	preload("res://data/gel_skins/cycling_rainbow.tres"),
	preload("res://data/gel_skins/night_neon.tres"),
	preload("res://data/gel_skins/slow_lava.tres"),
	preload("res://data/gel_skins/holographic.tres"),
]


static func skin(requested_id: StringName) -> Resource:
	for definition: Resource in all_skins():
		if definition.get(&"id") == requested_id:
			return definition
	return SKINS[0]


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Resource in SKINS:
		result.append(definition.get(&"id"))
	return result


static func interior_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Resource in INTERIOR_SKINS:
		result.append(definition.get(&"id"))
	return result


static func animated_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Resource in ANIMATED_SKINS:
		result.append(definition.get(&"id"))
	return result


static func all_skins() -> Array[Resource]:
	var result: Array[Resource] = SKINS.duplicate()
	result.append_array(INTERIOR_SKINS)
	result.append_array(ANIMATED_SKINS)
	return result
