class_name GelHairCatalog
extends RefCounted
## Stable IDs and colours for the gel hair library (S-311.62).
## Geometry is built separately so future profile/network code never persists a resource path.

const DEFAULT_HAIRSTYLE: StringName = &"bald"
const NONE: StringName = &"none"

const HAIRSTYLES: Array[Dictionary] = [
	{&"id": &"bald", &"color": Color("ffd166")},
	{&"id": &"quiff", &"color": Color("ef476f")},
	{&"id": &"curls", &"color": Color("7b61ff")},
	{&"id": &"pigtails", &"color": Color("ff70a6")},
	{&"id": &"mohawk", &"color": Color("06d6a0")},
	{&"id": &"afro", &"color": Color("6f4e37")},
	{&"id": &"fringe", &"color": Color("118ab2")},
	{&"id": &"braid", &"color": Color("9b5de5")},
	{&"id": &"bun", &"color": Color("f9844a")},
	{&"id": &"long", &"color": Color("43aa8b")},
]

const EYEBROWS: Array[StringName] = [
	&"soft", &"thick", &"angled", &"arched", &"split",
]
const MOUSTACHES: Array[StringName] = [
	&"pencil", &"handlebar", &"walrus", &"chevron", &"curled",
]


static func hairstyle(id: StringName) -> Dictionary:
	for definition: Dictionary in HAIRSTYLES:
		if definition[&"id"] == id:
			return definition
	return HAIRSTYLES[0]


static func valid_eyebrows(id: StringName) -> StringName:
	return id if id in EYEBROWS else NONE


static func valid_moustache(id: StringName) -> StringName:
	return id if id in MOUSTACHES else NONE
