class_name GelCostumeCatalog
extends RefCounted
## Stable IDs and art direction for the twelve base costumes (S-311.71).
## Selection, unlocks and profile persistence intentionally belong to S-311.76.

const DEFAULT_ID: StringName = &"courier"

const COSTUMES: Array[Dictionary] = [
	{&"id": &"courier", &"signature": &"parcel_badge", &"primary": Color("f28c28"),
		&"secondary": Color("17324d"), &"hat_rule": &"compress"},
	{&"id": &"mail_carrier", &"signature": &"mail_satchel", &"primary": Color("2864a8"),
		&"secondary": Color("e9c46a"), &"hat_rule": &"compress"},
	{&"id": &"firefighter", &"signature": &"air_tank", &"primary": Color("d94b3d"),
		&"secondary": Color("f6c945"), &"hat_rule": &"hide"},
	{&"id": &"astronaut", &"signature": &"life_support", &"primary": Color("e9eef2"),
		&"secondary": Color("4d8dcc"), &"hat_rule": &"hide"},
	{&"id": &"pirate", &"signature": &"tricorn", &"primary": Color("7d2332"),
		&"secondary": Color("e5c07b"), &"hat_rule": &"hide"},
	{&"id": &"chef", &"signature": &"toque", &"primary": Color("f5f1e8"),
		&"secondary": Color("d13f45"), &"hat_rule": &"compress"},
	{&"id": &"dinosaur", &"signature": &"dino_tail", &"primary": Color("4fae62"),
		&"secondary": Color("f2c14e"), &"hat_rule": &"none"},
	{&"id": &"bee", &"signature": &"bee_wings", &"primary": Color("f3c623"),
		&"secondary": Color("2a2630"), &"hat_rule": &"none"},
	{&"id": &"mummy", &"signature": &"loose_wrap", &"primary": Color("ded5bd"),
		&"secondary": Color("847b68"), &"hat_rule": &"none"},
	{&"id": &"robot", &"signature": &"chest_light", &"primary": Color("7c8b95"),
		&"secondary": Color("55d6d0"), &"hat_rule": &"hide"},
	{&"id": &"superhero", &"signature": &"hero_cape", &"primary": Color("2764c7"),
		&"secondary": Color("e84855"), &"hat_rule": &"none"},
	{&"id": &"skeleton", &"signature": &"inner_ribs", &"primary": Color("f1e7c8"),
		&"secondary": Color("92dce5"), &"hat_rule": &"none"},
]


static func costume(requested_id: StringName) -> Dictionary:
	for definition: Dictionary in COSTUMES:
		if definition[&"id"] == requested_id:
			return definition
	return COSTUMES[0]


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Dictionary in COSTUMES:
		result.append(definition[&"id"])
	return result
