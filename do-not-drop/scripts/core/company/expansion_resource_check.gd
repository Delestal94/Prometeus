class_name ExpansionResourceCheck
extends RefCounted
## Transversal validator of the expansion's .tres under data/ (expansion D-0245, "Modo Empresa").
##
## Reads every folder the company registries use (CompanyCatalog) plus the ones the catalog
## does not read (placeables, order_requirements, shop, shed, traps) and returns one readable
## text per problem, empty when everything is sound. It checks: ids that repeat, are missing or
## differ from the file name; files that do not load or are the wrong class; references between
## files (supplier -> products, product -> zones and trap, zone -> gates, gate and vehicle ->
## fleet keys and traps, shop item -> fleet key); exported scenes and resources that are set and
## exist; and numeric ranges. Each text starts with "<folder>/<file>: ". It reuses the validity
## the classes already have (ShopItem.is_valid, VehicleDefinition.is_valid, DefaultShed.problems)
## instead of repeating it. Pure: no node, no autoload, nothing drawn or played.
##
## Not checked on purpose, because the data does not satisfy it today and the code gives no
## registry for it: ZoneDefinition.vehicles (bike, pallet_jack and forklift are not in the fleet
## yet), ZoneDefinition.hazards and mood_profiles, GateRequirement.milestone and equipment, and
## the ShopItem machine keys (the equipment has no registry).

const SHOP: StringName = &"shop"
const PLACEABLES: StringName = &"placeables"
const ORDER_REQUIREMENTS: StringName = &"order_requirements"
const SHED: StringName = &"shed"
const TRAPS: StringName = &"traps"
## Folders the catalog does not read, checked here. Traps are only read to resolve references.
const EXTRA_KINDS: Array[StringName] = [PLACEABLES, ORDER_REQUIREMENTS, SHOP, SHED, TRAPS]
const TEMPERATURES: Array[StringName] = [&"ambient", &"cold", &"heat"]
const PLACEABLE_ROLES: Array[StringName] = [&"assembly", &"storage", &"dispatch"]
const GATE_KEYS: Array[StringName] = [&"", &"water", &"altitude"]
const DAY_MINUTES: int = 1440

## kind -> { id: Resource } of the folders in EXTRA_KINDS (first file wins, like the catalog).
var _extra: Dictionary = {}
var _catalog: CompanyCatalog
var _problems: Array[String] = []


## Every problem of data/ plus the same kind folders under each of `extra_roots`.
static func run(extra_roots: Array[String] = []) -> Array[String]:
	var check := ExpansionResourceCheck.new()
	check._run(extra_roots)
	return check._problems


func _run(extra_roots: Array[String]) -> void:
	var roots: Array[String] = [CompanyCatalog.DATA_ROOT]
	roots.append_array(extra_roots)
	_catalog = CompanyCatalog.load_all(extra_roots)
	_problems.append_array(_catalog.errors)
	for kind: StringName in EXTRA_KINDS:
		_extra[kind] = {}
		for root: String in roots:
			_read_extra(kind, root.path_join(String(kind)))
	_check_file_names()
	for res: Resource in _catalog.all(CompanyCatalog.PRODUCTS):
		_check_product(res)
	for res: Resource in _catalog.all(CompanyCatalog.ZONES):
		_check_zone(res)
	for res: Resource in _catalog.all(CompanyCatalog.VEHICLES):
		_check_vehicle(res)
	for res: Resource in _catalog.all(CompanyCatalog.GATES):
		_check_gate(res)
	for res: Resource in _catalog.all(CompanyCatalog.SUPPLIERS):
		_check_supplier(res)
	for res: Resource in _catalog.all(CompanyCatalog.BOXES):
		_check_box(res)
	for res: Resource in _extra_all(PLACEABLES):
		_check_placeable(res)
	for res: Resource in _extra_all(ORDER_REQUIREMENTS):
		_check_order_requirement(res)
	for res: Resource in _extra_all(SHOP):
		_check_shop_item(res)


# --- reading -------------------------------------------------------------------------------

## Loads the .tres of one folder. Shed files have no id: they are all kept, by path.
func _read_extra(kind: StringName, dir: String) -> void:
	var by_id: Dictionary = _extra[kind]
	for file: String in CompanyCatalog.tres_files(dir):
		var path: String = dir.path_join(file)
		var res: Resource = load(path)
		if res == null:
			_add(kind, path, "cannot load")
			continue
		if kind == SHED:
			if not res is DefaultShed:
				_add(kind, path, "is not a DefaultShed")
				continue
			for text: String in (res as DefaultShed).problems():
				_add(kind, path, text)
			by_id[path] = res
			continue
		var id: StringName = CompanyCatalog._id_of(res)
		if id == &"":
			_add(kind, path, "has no id")
			continue
		if by_id.has(id):
			_add(kind, path, "duplicate id '%s' (already in %s)" % [id, (by_id[id] as Resource).resource_path])
			continue
		by_id[id] = res


func _extra_all(kind: StringName) -> Array[Resource]:
	var found: Array[Resource] = []
	for res: Variant in (_extra[kind] as Dictionary).values():
		found.append(res as Resource)
	return found


## The documented rule "same id as the file name", for every folder with an id.
func _check_file_names() -> void:
	var all_resources: Array[Resource] = []
	for kind: StringName in CompanyCatalog.KINDS:
		all_resources.append_array(_catalog.all(kind))
	for kind: StringName in [PLACEABLES, ORDER_REQUIREMENTS, SHOP]:
		all_resources.append_array(_extra_all(kind))
	for res: Resource in all_resources:
		var id: StringName = CompanyCatalog._id_of(res)
		if String(id) != res.resource_path.get_file().get_basename():
			_add_res(res, "id '%s' differs from the file name" % id)


# --- per class -----------------------------------------------------------------------------

func _check_product(res: Resource) -> void:
	var product := res as ProductDefinition
	if product == null:
		_add_res(res, "is not a ProductDefinition")
		return
	_require_ref(res, "content")
	var xl: Vector3i = CompanyTuning.BOX_CELLS[&"XL"]
	_require(product.cells.x >= 1 and product.cells.y >= 1 and product.cells.z >= 1,
		res, "cells must be at least 1 on each axis (got %s)" % product.cells)
	_require(product.cells.x <= xl.x and product.cells.y <= xl.y and product.cells.z <= xl.z,
		res, "cells %s do not fit the XL box %s" % [product.cells, xl])
	_require(product.weight_kg > 0.0, res, "weight_kg must be above 0 (got %s)" % product.weight_kg)
	_require(TEMPERATURES.has(product.temperature), res,
		"temperature '%s' is not one of %s" % [product.temperature, TEMPERATURES])
	_require(product.buy_price >= 0, res, "buy_price must not be negative (got %d)" % product.buy_price)
	_require(product.sell_price >= 0, res, "sell_price must not be negative (got %d)" % product.sell_price)
	if product.trap_id != &"" and not (_extra[TRAPS] as Dictionary).has(product.trap_id):
		_add_res(res, "trap_id '%s' is not in data/traps/" % product.trap_id)
	for zone_id: StringName in product.districts:
		if not _catalog.has(CompanyCatalog.ZONES, zone_id):
			_add_res(res, "district '%s' is not a zone in data/zones/" % zone_id)


func _check_zone(res: Resource) -> void:
	var zone := res as ZoneDefinition
	if zone == null:
		_add_res(res, "is not a ZoneDefinition")
		return
	_require(zone.display_key != "", res, "display_key is empty")
	_require(zone.bounds.size.x > 0.0 and zone.bounds.size.y > 0.0, res,
		"bounds must have a size above 0 (got %s)" % zone.bounds)
	_require(zone.shipping_fee >= 0, res, "shipping_fee must not be negative (got %d)" % zone.shipping_fee)
	_require(zone.houses_per_trip.x >= 0 and zone.houses_per_trip.x <= zone.houses_per_trip.y, res,
		"houses_per_trip must be (min, max) with 0 <= min <= max (got %s)" % zone.houses_per_trip)
	_require(zone.base_reputation_gain >= 0.0, res,
		"base_reputation_gain must not be negative (got %s)" % zone.base_reputation_gain)
	for gate_id: StringName in zone.gates:
		if not _catalog.has(CompanyCatalog.GATES, gate_id):
			_add_res(res, "gate '%s' is not in data/gates/" % gate_id)


func _check_vehicle(res: Resource) -> void:
	var vehicle := res as VehicleDefinition
	if vehicle == null:
		_add_res(res, "is not a VehicleDefinition")
		return
	_require_ref(res, "scene")
	_require(vehicle.is_valid(), res, "is not a usable vehicle (id, scene, movement, seats, cargo, fleet_key)")
	_require(vehicle.seats >= 1, res, "seats must be at least 1 (got %d)" % vehicle.seats)
	_require(vehicle.cargo_slots >= 1, res, "cargo_slots must be at least 1 (got %d)" % vehicle.cargo_slots)
	_require(vehicle.cargo_kg > 0.0, res, "cargo_kg must be above 0 (got %s)" % vehicle.cargo_kg)
	_require(VehicleDefinition.MOVEMENTS.has(vehicle.movement), res,
		"movement '%s' is not one of %s" % [vehicle.movement, VehicleDefinition.MOVEMENTS])
	_require(GATE_KEYS.has(vehicle.gate_key), res,
		"gate_key '%s' is not one of %s" % [vehicle.gate_key, GATE_KEYS])
	_require(vehicle.price >= 0, res, "price must not be negative (got %d)" % vehicle.price)
	if vehicle.amplified_trap != &"" and not (_extra[TRAPS] as Dictionary).has(vehicle.amplified_trap):
		_add_res(res, "amplified_trap '%s' is not in data/traps/" % vehicle.amplified_trap)


func _check_gate(res: Resource) -> void:
	var gate := res as GateRequirement
	if gate == null:
		_add_res(res, "is not a GateRequirement")
		return
	_require(gate.kind >= 0 and gate.kind < GateRequirement.Kind.size(), res,
		"kind %d is not a GateRequirement.Kind" % gate.kind)
	_require(gate.cost >= 0, res, "cost must not be negative (got %d)" % gate.cost)
	if gate.vehicle_key != &"" and not _fleet_keys().has(gate.vehicle_key):
		_add_res(res, "vehicle_key '%s' is neither a fleet_key nor a vehicle of the shop (known: %s)"
			% [gate.vehicle_key, _fleet_keys()])
	for item: StringName in gate.equipment:
		_require(item != &"", res, "equipment lists an empty id")


func _check_supplier(res: Resource) -> void:
	var supplier := res as SupplierDefinition
	if supplier == null:
		_add_res(res, "is not a SupplierDefinition")
		return
	_require(not supplier.products.is_empty(), res, "sells no product")
	var seen: Dictionary = {}
	for product_id: StringName in supplier.products:
		if not _catalog.has(CompanyCatalog.PRODUCTS, product_id):
			_add_res(res, "product '%s' is not in data/products/" % product_id)
		if seen.has(product_id):
			_add_res(res, "product '%s' is listed twice" % product_id)
		seen[product_id] = true
	_require(supplier.price_factor > 0.0, res, "price_factor must be above 0 (got %s)" % supplier.price_factor)
	_require(supplier.arrival_min >= 0 and supplier.arrival_min < DAY_MINUTES, res,
		"arrival_min must be inside the day 0..%d (got %d)" % [DAY_MINUTES - 1, supplier.arrival_min])
	_require(supplier.wait_minutes >= 1, res, "wait_minutes must be at least 1 (got %d)" % supplier.wait_minutes)
	if supplier.truck_scene != null:
		_require_ref(res, "truck_scene")


func _check_box(res: Resource) -> void:
	var box := res as BoxDefinition
	if box == null:
		_add_res(res, "is not a BoxDefinition")
		return
	_require_ref(res, "model")
	_require(box.cells.x >= 1 and box.cells.y >= 1 and box.cells.z >= 1, res,
		"cells must be at least 1 on each axis (got %s)" % box.cells)
	_require(box.cost >= 0, res, "cost must not be negative (got %d)" % box.cost)


func _check_placeable(res: Resource) -> void:
	var def := res as PlaceableDefinition
	if def == null:
		_add_res(res, "is not a PlaceableDefinition")
		return
	_require(def.display_key != "", res, "display_key is empty")
	_require(def.footprint.x >= 1 and def.footprint.y >= 1, res,
		"footprint must be at least 1 on each axis (got %s)" % def.footprint)
	_require(def.height_m > 0.0, res, "height_m must be above 0 (got %s)" % def.height_m)
	_require(def.price >= 0, res, "price must not be negative (got %d)" % def.price)
	_require(PLACEABLE_ROLES.has(def.role), res,
		"role '%s' is not one of %s" % [def.role, PLACEABLE_ROLES])
	if def.role == &"storage":
		_require(def.slots >= 1, res, "a storage piece needs slots (got %d)" % def.slots)
	else:
		_require(def.slots == 0, res, "slots is 0 outside storage (got %d)" % def.slots)


func _check_order_requirement(res: Resource) -> void:
	var req := res as OrderRequirement
	if req == null:
		_add_res(res, "is not an OrderRequirement")
		return
	_require(req.display_key != "", res, "display_key is empty")
	_require(req.min_quality >= 0 and req.min_quality <= 100, res,
		"min_quality must be 0..100 (got %d)" % req.min_quality)
	_require(req.window_factor > 0.0 and req.window_factor <= 1.0, res,
		"window_factor must be above 0 and at most 1 (got %s)" % req.window_factor)
	_require(req.pay_bonus >= 0.0, res, "pay_bonus must not be negative (got %s)" % req.pay_bonus)
	for seal: StringName in req.required_seals:
		_require(seal != &"", res, "required_seals lists an empty id")


func _check_shop_item(res: Resource) -> void:
	var item := res as ShopItem
	if item == null:
		_add_res(res, "is not a ShopItem")
		return
	_require(item.is_valid(), res, "is not a valid shop item (id, display_key, price > 0, kind in %s, "
		% [ShopItem.KINDS] + "grant_key or stage)")
	_require(ShopItem.KINDS.has(item.kind), res, "kind '%s' is not one of %s" % [item.kind, ShopItem.KINDS])
	_require(item.price >= 0, res, "price must not be negative (got %d)" % item.price)
	if item.kind == &"vehicle" and item.grant_key != &"" and not _fleet_keys().has(item.grant_key):
		_add_res(res, "grant_key '%s' is not a known fleet key" % item.grant_key)


# --- helpers -------------------------------------------------------------------------------

## Fleet keys the data knows: those of data/vehicles/ plus the vehicles sold in the shop.
func _fleet_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for res: Resource in _catalog.all(CompanyCatalog.VEHICLES):
		var vehicle := res as VehicleDefinition
		if vehicle != null and vehicle.fleet_key != &"" and not keys.has(vehicle.fleet_key):
			keys.append(vehicle.fleet_key)
	for res: Resource in _extra_all(SHOP):
		var item := res as ShopItem
		if item != null and item.kind == &"vehicle" and item.grant_key != &"" \
				and not keys.has(item.grant_key):
			keys.append(item.grant_key)
	return keys


## The exported Resource/PackedScene `prop` must be set, and its file must exist
## (an embedded sub-resource has no path and passes).
func _require_ref(res: Resource, prop: StringName) -> void:
	var value: Resource = res.get(prop) as Resource
	if value == null:
		_add_res(res, "%s is not set" % prop)
	elif value.resource_path != "" and not ResourceLoader.exists(value.resource_path):
		_add_res(res, "%s points to a missing file %s" % [prop, value.resource_path])


func _require(condition: bool, res: Resource, message: String) -> void:
	if not condition:
		_add_res(res, message)


func _add_res(res: Resource, message: String) -> void:
	var path: String = res.resource_path
	_add(StringName(path.get_base_dir().get_file()), path, message)


func _add(kind: StringName, path: String, message: String) -> void:
	_problems.append("%s/%s: %s" % [kind, path.get_file(), message])
