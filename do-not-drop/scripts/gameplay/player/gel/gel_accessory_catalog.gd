class_name GelAccessoryCatalog
extends RefCounted
## Stable IDs and attachment intent for the fifteen loose accessories (S-311.72).
## Unlocks and profile selection intentionally belong to S-311.76.

const DEFAULT_ID: StringName = &"cap"

const ACCESSORIES: Array[Dictionary] = [
	{&"id": &"cap", &"signature": &"cap_brim", &"anchor": &"head", &"bone": &"head",
		&"color": Color("e4572e"), &"accent": Color("f3a712"), &"hat_rule": &"compress"},
	{&"id": &"hard_hat", &"signature": &"helmet_ridge", &"anchor": &"head", &"bone": &"head",
		&"color": Color("f6c945"), &"accent": Color("30343f"), &"hat_rule": &"hide"},
	{&"id": &"glasses", &"signature": &"glasses_bridge", &"anchor": &"face", &"bone": &"head",
		&"color": Color("293241"), &"accent": Color("9bd7e5"), &"hat_rule": &"none"},
	{&"id": &"scarf", &"signature": &"scarf_tail", &"anchor": &"neck", &"bone": &"chest",
		&"color": Color("d1495b"), &"accent": Color("edae49"), &"hat_rule": &"none"},
	{&"id": &"backpack", &"signature": &"backpack_pocket", &"anchor": &"back", &"bone": &"chest",
		&"color": Color("3d5a80"), &"accent": Color("ee6c4d"), &"hat_rule": &"none"},
	{&"id": &"bow_tie", &"signature": &"bow_knot", &"anchor": &"neck", &"bone": &"chest",
		&"color": Color("9b5de5"), &"accent": Color("f15bb5"), &"hat_rule": &"none"},
	{&"id": &"crown", &"signature": &"crown_jewel", &"anchor": &"head", &"bone": &"head",
		&"color": Color("f4d35e"), &"accent": Color("ee4266"), &"hat_rule": &"compress"},
	{&"id": &"headphones", &"signature": &"headphone_band", &"anchor": &"head", &"bone": &"head",
		&"color": Color("343a40"), &"accent": Color("00b4d8"), &"hat_rule": &"compress"},
	{&"id": &"fake_moustache", &"signature": &"moustache_center", &"anchor": &"face", &"bone": &"head",
		&"color": Color("6f4e37"), &"accent": Color("3b2f2f"), &"hat_rule": &"none"},
	{&"id": &"party_hat", &"signature": &"party_pom", &"anchor": &"head", &"bone": &"head",
		&"color": Color("00bbf9"), &"accent": Color("fee440"), &"hat_rule": &"compress"},
	{&"id": &"snorkel", &"signature": &"snorkel_tip", &"anchor": &"face", &"bone": &"head",
		&"color": Color("00a896"), &"accent": Color("ff6b6b"), &"hat_rule": &"none"},
	{&"id": &"flower", &"signature": &"flower_center", &"anchor": &"head", &"bone": &"head",
		&"color": Color("ff70a6"), &"accent": Color("ffd166"), &"hat_rule": &"none"},
	{&"id": &"monocle", &"signature": &"monocle_lens", &"anchor": &"face", &"bone": &"head",
		&"color": Color("d4af37"), &"accent": Color("a8dadc"), &"hat_rule": &"none"},
	{&"id": &"wristwatch", &"signature": &"watch_face", &"anchor": &"wrist", &"bone": &"hand.L",
		&"color": Color("264653"), &"accent": Color("2a9d8f"), &"hat_rule": &"none"},
	{&"id": &"fairy_wings", &"signature": &"wing_core", &"anchor": &"back", &"bone": &"chest",
		&"color": Color("b8f2e6"), &"accent": Color("aed9e0"), &"hat_rule": &"none"},
]


static func accessory(requested_id: StringName) -> Dictionary:
	for definition: Dictionary in ACCESSORIES:
		if definition[&"id"] == requested_id:
			return definition
	return ACCESSORIES[0]


static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Dictionary in ACCESSORIES:
		result.append(definition[&"id"])
	return result
