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


static func skin(requested_id: StringName) -> Resource:
	for definition: Resource in SKINS:
		if definition.get(&"id") == requested_id:
			return definition
	return SKINS[0]


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Resource in SKINS:
		result.append(definition.get(&"id"))
	return result
