class_name OrderGenerator
extends RefCounted
## Builds the day's customer orders from a seed (expansion D-0801, "Modo Empresa").
##
## When each order arrives comes from OrderRhythm (D-0803); here each one gets a
## zone, a house, a customer, 1 to 3 products and its requirements. Everything
## is drawn from one seeded generator, so the same seed, crew size and unlocked
## zones give the same orders on every peer. Pure functions: no node, no
## autoload, no UI. Catalogs come in as arguments (the caller loads data/).

## Chance that an order asks for one extra requirement beyond what its products imply.
const EXTRA_REQUIREMENT_CHANCE: float = 0.2
## Requirements that a customer may add on a whim (the product-driven ones are not random).
const EXTRA_REQUIREMENTS: Array[StringName] = [&"gift", &"urgent", &"no_bend"]
## A product ordered mostly in the order's zone is this many times likelier to be picked.
const HOME_ZONE_WEIGHT: int = 3
## Chance of asking two units of a product instead of one.
const DOUBLE_QTY_CHANCE: float = 0.15
## Houses per zone an order can name (house_id = "<zone>_house_<n>").
const HOUSES_PER_ZONE: int = 12
const CUSTOMER_NAMES: Array[String] = [
	"Marta", "Gustavo", "Lucía", "Bruno", "Elena", "Tomás", "Rosa", "Hugo",
	"Irene", "Julián", "Paula", "Ramiro", "Silvia", "Darío", "Nora", "Félix",
]


## The day's orders sorted by arrival. zones are the ZoneDefinitions open today
## (those that take no deliveries, shipping_fee 0, are skipped); products maps
## product id -> ProductDefinition; requirements maps id -> OrderRequirement.
## max_items caps the distinct products of an order (D-0812 lowers it early on).
static func generate_day(
	day_seed: int,
	day: int,
	players: int,
	zones: Array[ZoneDefinition],
	products: Dictionary,
	requirements: Dictionary,
	max_items: int = CompanyTuning.ORDER_ITEMS_MAX,
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var open_zones: Array[ZoneDefinition] = _delivery_zones(zones)
	var ids: Array[StringName] = _sorted_ids(products)
	if open_zones.is_empty() or ids.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = day_seed
	var minutes: Array[int] = OrderRhythm.arrival_minutes(day_seed, players)
	for index in minutes.size():
		var zone: ZoneDefinition = open_zones[rng.randi_range(0, open_zones.size() - 1)]
		var items: Array[Dictionary] = _pick_items(rng, zone.id, ids, products, max_items)
		var reqs: Array[StringName] = _pick_requirements(rng, items, products, requirements)
		var order_id := StringName("d%d_o%02d" % [day, index + 1])
		var order: Dictionary = Order.make(
			order_id,
			CUSTOMER_NAMES[rng.randi_range(0, CUSTOMER_NAMES.size() - 1)],
			zone.id,
			StringName("%s_house_%d" % [zone.id, rng.randi_range(1, HOUSES_PER_ZONE)]),
			items,
			minutes[index],
			products,
			reqs,
		)
		out.append(_apply_requirements(order, reqs, requirements))
	return out


static func _delivery_zones(zones: Array[ZoneDefinition]) -> Array[ZoneDefinition]:
	var out: Array[ZoneDefinition] = []
	for zone in zones:
		if zone != null and zone.shipping_fee > 0:
			out.append(zone)
	out.sort_custom(func(a: ZoneDefinition, b: ZoneDefinition) -> bool: return str(a.id) < str(b.id))
	return out


static func _sorted_ids(products: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in products:
		ids.append(StringName(key))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return ids


## 1 to max_items distinct products, those of the home zone weighted up.
static func _pick_items(
	rng: RandomNumberGenerator,
	zone_id: StringName,
	ids: Array[StringName],
	products: Dictionary,
	max_items: int,
) -> Array[Dictionary]:
	var wanted: int = rng.randi_range(
		CompanyTuning.ORDER_ITEMS_MIN, clampi(max_items, 1, CompanyTuning.ORDER_ITEMS_MAX)
	)
	wanted = mini(wanted, ids.size())
	var pool: Array[StringName] = ids.duplicate()
	var items: Array[Dictionary] = []
	for _i in wanted:
		var picked: StringName = _weighted_pick(rng, pool, zone_id, products)
		pool.erase(picked)
		var qty := 2 if rng.randf() < DOUBLE_QTY_CHANCE else 1
		items.append({"product": picked, "qty": qty})
	return items


static func _weighted_pick(
	rng: RandomNumberGenerator, pool: Array[StringName], zone_id: StringName, products: Dictionary
) -> StringName:
	var total := 0
	for id in pool:
		total += _weight(products[id], zone_id)
	var pick := rng.randi_range(0, total - 1)
	for id in pool:
		pick -= _weight(products[id], zone_id)
		if pick < 0:
			return id
	return pool[pool.size() - 1]


static func _weight(def: ProductDefinition, zone_id: StringName) -> int:
	return HOME_ZONE_WEIGHT if zone_id in def.districts else 1


## What the products imply (fragile, cold) plus, sometimes, one whim. Only ids
## that exist in the catalog are used.
static func _pick_requirements(
	rng: RandomNumberGenerator,
	items: Array[Dictionary],
	products: Dictionary,
	catalog: Dictionary,
) -> Array[StringName]:
	var out: Array[StringName] = []
	for item in items:
		var def: ProductDefinition = products[item["product"]]
		if def.fragile:
			_add_requirement(out, &"fragile", catalog)
		if def.temperature == &"cold":
			_add_requirement(out, &"cold", catalog)
	if rng.randf() < EXTRA_REQUIREMENT_CHANCE:
		_add_requirement(out, EXTRA_REQUIREMENTS[rng.randi_range(0, EXTRA_REQUIREMENTS.size() - 1)], catalog)
	return out


static func _add_requirement(out: Array[StringName], id: StringName, catalog: Dictionary) -> void:
	if catalog.has(id) and not id in out:
		out.append(id)


## Shrinks the window to the tightest requirement and adds every bonus to the pay.
static func _apply_requirements(order: Dictionary, reqs: Array[StringName], catalog: Dictionary) -> Dictionary:
	var window := CompanyTuning.ORDER_WINDOW_MIN
	var pay: int = int(order["pay"])
	for id in reqs:
		var req: OrderRequirement = catalog[id]
		window = mini(window, req.window_min(CompanyTuning.ORDER_WINDOW_MIN))
		pay = req.paid(pay)
	order["due_min"] = int(order["created_min"]) + window
	order["pay"] = pay
	return order
