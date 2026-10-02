class_name AccessoryCatalog
extends RefCounted
## What the accessory shop sells (N-923): the four wearables of S-305, the slot
## each one goes in and its price in team money. Pure data and static lookups,
## no scene and no network: the depot and service-stop shops, the cosmetics
## panel and the saved campaign all read ids from here, and an id that is not
## in ACCESSORIES is never granted, equipped or loaded.
##
## One accessory per slot is worn at a time (AccessoryInventory.equip), so the
## cap and the hard hat compete for the head. Accessories are purely cosmetic:
## nothing here (or anywhere) changes how a delivery plays.
## Prices (decided 2026-10-02) are provisional until N-923.11 checks them
## against what a delivery pays: a cap is a taste, not a need, but the whole
## shelf (420) must not drain the supplies money of a campaign.

const SLOT_HEAD: StringName = &"head"
const SLOT_TORSO: StringName = &"torso"
const SLOT_BACK: StringName = &"back"
## The three places an accessory can be worn, in the order the UI lists them.
const SLOTS: Array[StringName] = [SLOT_HEAD, SLOT_TORSO, SLOT_BACK]
const SLOT_TITLES := {
	SLOT_HEAD: "UI_ACCESSORY_SLOT_HEAD",
	SLOT_TORSO: "UI_ACCESSORY_SLOT_TORSO",
	SLOT_BACK: "UI_ACCESSORY_SLOT_BACK",
}
const MODEL_DIR: String = "res://models/characters/accessories/"
## id -> {title (translation key), slot, price (team money), tags}. The model
## path is MODEL_DIR + id + ".glb" (art: N-923.9); ids are safe to persist and
## replicate because no peer ever supplies a path.
const ACCESSORIES := {
	&"cap": {"title": "UI_ACCESSORY_CAP", "slot": SLOT_HEAD, "price": 60, "tags": [&"casual"]},
	&"hi_vis_vest": {
		"title": "UI_ACCESSORY_HI_VIS_VEST", "slot": SLOT_TORSO, "price": 90, "tags": [&"work", &"reflective"],
	},
	&"hard_hat": {"title": "UI_ACCESSORY_HARD_HAT", "slot": SLOT_HEAD, "price": 120, "tags": [&"work"]},
	&"thermal_backpack": {
		"title": "UI_ACCESSORY_THERMAL_BACKPACK", "slot": SLOT_BACK, "price": 150, "tags": [&"work", &"delivery"],
	},
}


## Every accessory id, in catalogue order (the shelf order).
static func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in ACCESSORIES:
		result.append(id)
	return result


static func has(id: StringName) -> bool:
	return ACCESSORIES.has(id)


static func valid_slot(slot: StringName) -> bool:
	return SLOTS.has(slot)


## The slot of `id`, or &"" for an id that is not sold.
static func slot_of(id: StringName) -> StringName:
	return StringName(Dictionary(ACCESSORIES.get(id, {})).get("slot", &""))


## Price in team money; -1 for an unknown id, so it can never be bought as free.
static func price_of(id: StringName) -> int:
	if not ACCESSORIES.has(id):
		return -1
	return int(Dictionary(ACCESSORIES[id]).get("price", -1))


## Translation key of the name: the UI shows tr(title_key(id)).
static func title_key(id: StringName) -> String:
	return String(Dictionary(ACCESSORIES.get(id, {})).get("title", ""))


static func slot_title_key(slot: StringName) -> String:
	return String(SLOT_TITLES.get(slot, ""))


static func tags_of(id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for tag: Variant in Dictionary(ACCESSORIES.get(id, {})).get("tags", []):
		result.append(StringName(tag))
	return result


static func model_path(id: StringName) -> String:
	if not ACCESSORIES.has(id):
		return ""
	return MODEL_DIR + String(id) + ".glb"


## The ids that go in `slot`, in catalogue order.
static func ids_for_slot(slot: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in ACCESSORIES:
		if slot_of(id) == slot:
			result.append(id)
	return result
