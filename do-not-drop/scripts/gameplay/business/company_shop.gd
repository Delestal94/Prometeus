class_name CompanyShop
extends RefCounted
## The company's shop (expansion D-0511): what can be bought, whether the company may buy
## it now and the purchase itself. Pure functions over `data/shop/*.tres` and a company
## node (CompanyState): no nodes, no UI, no network. Who may spend (host or vote) is D-0518.
##
## `check` and `buy` answer with {ok, key, args} like DispatchRules: key is empty when ok,
## otherwise a WORLD_SHOP_* reason the UI translates.

const SHOP_DIR: String = "res://data/shop"
const REASON_SHOP: StringName = &"shop"

## Names of the shipped items, spelled out so the translation table's "no dead rows" scan
## (it reads scripts, not .tres) sees them. An item outside this table shows its own display_key.
const NAME_KEYS: Dictionary = {
	&"upgrade_1": "WORLD_SHOP_UPGRADE_1",
	&"label_reader": "WORLD_SHOP_LABEL_READER",
	&"conveyor": "WORLD_SHOP_CONVEYOR",
	&"packer": "WORLD_SHOP_PACKER",
	&"expansion_1": "WORLD_SHOP_EXPANSION_1",
	&"vehicle_van": "WORLD_SHOP_VEHICLE_VAN",
	&"vehicle_bike": "WORLD_SHOP_VEHICLE_BIKE",
	&"vehicle_cart": "WORLD_SHOP_VEHICLE_CART",
	&"vehicle_offroad": "WORLD_SHOP_VEHICLE_OFFROAD",
	&"vehicle_boat": "WORLD_SHOP_VEHICLE_BOAT",
	&"vehicle_plane": "WORLD_SHOP_VEHICLE_PLANE",
}

const NO_COMPANY: StringName = &"WORLD_SHOP_NO_COMPANY"
const UNKNOWN_ITEM: StringName = &"WORLD_SHOP_UNKNOWN_ITEM"
const ALREADY_OWNED: StringName = &"WORLD_SHOP_ALREADY_OWNED"
const NEEDS_ITEM: StringName = &"WORLD_SHOP_NEEDS_ITEM"
const WRONG_STAGE: StringName = &"WORLD_SHOP_WRONG_STAGE"
const CANNOT_AFFORD: StringName = &"WORLD_SHOP_CANNOT_AFFORD"


## Every enabled valid item of data/shop/, in file name order (the same on every peer).
static func items(dir: String = SHOP_DIR) -> Array[ShopItem]:
	var found: Array[ShopItem] = []
	var names: PackedStringArray = DirAccess.get_files_at(dir)
	names.sort()
	for file_name: String in names:
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var item: ShopItem = load(dir.path_join(clean)) as ShopItem
		if item != null and item.enabled and item.is_valid():
			found.append(item)
	return found


static func find(item_id: StringName, dir: String = SHOP_DIR) -> ShopItem:
	for item: ShopItem in items(dir):
		if item.id == item_id:
			return item
	return null


## Translation key of an item's name.
static func name_key(item: ShopItem) -> String:
	return String(NAME_KEYS.get(item.id, item.display_key))


## True when the company already has what the item grants (a vehicle can be bought again).
static func owns(company: Object, item: ShopItem) -> bool:
	match item.kind:
		&"machine":
			return (company.get("equipment") as Array).has(item.grant_key)
		&"expansion":
			return int(company.get("warehouse_stage")) >= item.stage
	return false


## Whether the company could buy `item` right now.
static func check(company: Object, item: ShopItem) -> Dictionary:
	if company == null or not company.has_method("can_afford"):
		return _no(NO_COMPANY)
	if item == null or not item.is_valid():
		return _no(UNKNOWN_ITEM)
	if owns(company, item):
		return _no(ALREADY_OWNED, [item.id])
	if item.kind == &"machine" and item.requires != &"":
		if not (company.get("equipment") as Array).has(item.requires):
			return _no(NEEDS_ITEM, [item.requires])
	if item.kind == &"expansion" and item.stage != int(company.get("warehouse_stage")) + 1:
		return _no(WRONG_STAGE, [item.stage])
	if not company.can_afford(item.price):
		return _no(CANNOT_AFFORD, [item.price, int(company.get("money"))])
	return {"ok": true, "key": &"", "args": []}


## Charges the price and grants the item. Returns the same dictionary as check();
## on a refusal nothing changes.
static func buy(company: Object, item: ShopItem) -> Dictionary:
	var verdict: Dictionary = check(company, item)
	if not verdict["ok"]:
		return verdict
	if not company.spend(item.price, REASON_SHOP):
		return _no(CANNOT_AFFORD, [item.price, int(company.get("money"))])
	match item.kind:
		&"vehicle":
			(company.get("fleet") as Array).append({"vehicle": item.grant_key})
		&"machine":
			(company.get("equipment") as Array).append(item.grant_key)
		&"expansion":
			company.set("warehouse_stage", item.stage)
	return verdict


static func _no(key: StringName, args: Array = []) -> Dictionary:
	return {"ok": false, "key": key, "args": args}
