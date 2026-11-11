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
## Houses per zone an order can name (house_id = "<zone>_house_<n>") in a zone with no house on the map.
const HOUSES_PER_ZONE: int = 12


## The day's orders sorted by arrival. zones are the ZoneDefinitions open today
## (those that take no deliveries, shipping_fee 0, are skipped); products maps
## product id -> ProductDefinition; requirements maps id -> OrderRequirement.
## max_items caps the distinct products of an order; 0 (the default) takes items_cap_for_day(day). company, when
## given (a node with money), sets how many orders the day opens with: a company in the red gets
## BANKRUPT_ORDER_SHARE of the usual count (Bankruptcy.orders_for_day, D-0510); null keeps the usual
## count. templates maps zone id -> OrderTemplateSet (D-0820.b): a zone with a set draws its products and
## requirements from one of its templates (the ones within max_items); a zone without one, or with no
## template that fits, draws them at random as before. houses (D-2016.2), when given, is the fixed map: an order of a
## zone with houses on it names one of them (the house a trip stops at); a zone without, or no map, keeps
## "<zone>_house_<n>". The host's seed and money are all it takes: every peer gets the same orders.
static func generate_day(
	day_seed: int,
	day: int,
	players: int,
	zones: Array[ZoneDefinition],
	products: Dictionary,
	requirements: Dictionary,
	max_items: int = 0,
	company: Object = null,
	templates: Dictionary = {},
	houses: HouseMap = null,
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var open_zones: Array[ZoneDefinition] = _delivery_zones(zones)
	var ids: Array[StringName] = _sorted_ids(products)
	if open_zones.is_empty() or ids.is_empty():
		return out
	if max_items <= 0:
		max_items = items_cap_for_day(day)
	var rng := RandomNumberGenerator.new()
	rng.seed = day_seed
	var count: int = Bankruptcy.orders_for_day(OrderRhythm.orders_for_day(players), company)
	var minutes: Array[int] = OrderRhythm.arrival_minutes(day_seed, players, count)
	for index in minutes.size():
		var zone: ZoneDefinition = open_zones[rng.randi_range(0, open_zones.size() - 1)]
		var template: OrderTemplate = _pick_template(rng, templates.get(zone.id), max_items)
		var items: Array[Dictionary] = []
		var reqs: Array[StringName] = []
		if template != null:
			items = template.items.duplicate(true)
			reqs = template.requirements.duplicate()
		else:
			items = _pick_items(rng, zone.id, ids, products, max_items)
			reqs = _pick_requirements(rng, items, products, requirements)
		var order_id := StringName("%so%02d" % [id_prefix(day), index + 1])
		var order: Dictionary = Order.make(
			order_id,
			CustomerNames.pick(rng),
			zone.id,
			_pick_house(rng, zone.id, houses, day_seed, index),
			items,
			minutes[index],
			products,
			reqs,
		)
		out.append(_apply_requirements(order, reqs, requirements))
	return out


## The house an order of `zone_id` names: one of the zone's houses on the map, else "<zone>_house_<n>". The day's
## generator draws <n> either way, and the map house comes from its own generator seeded with the day and the
## order's index, so the rest of the day's orders come out the same with or without a map.
static func _pick_house(
	rng: RandomNumberGenerator, zone_id: StringName, houses: HouseMap, day_seed: int, index: int
) -> StringName:
	var n: int = rng.randi_range(1, HOUSES_PER_ZONE)
	var spots: Array[HouseSpot] = []
	if houses != null:
		spots = houses.in_zone(zone_id)
	if spots.is_empty():
		return StringName("%s_house_%d" % [zone_id, n])
	var pick := RandomNumberGenerator.new()
	pick.seed = hash([day_seed, index])
	return spots[pick.randi_range(0, spots.size() - 1)].id


## How the ids of `day`'s orders start ("d<day>_"): an order carries no day of its own, so this is how
## one is told from another day's (is_of_day()).
static func id_prefix(day: int) -> String:
	return "d%d_" % day


## True when `order_id` is one of `day`'s orders (generate_day() named it).
static func is_of_day(order_id: Variant, day: int) -> bool:
	return String(order_id).begins_with(id_prefix(day))


## Most distinct products an order may ask for on this day (D-0812): 2 in the first
## CompanyTuning.ORDER_EARLY_DAYS days, ORDER_ITEMS_MAX afterwards.
static func items_cap_for_day(day: int) -> int:
	if day <= CompanyTuning.ORDER_EARLY_DAYS:
		return CompanyTuning.ORDER_ITEMS_EARLY_MAX
	return CompanyTuning.ORDER_ITEMS_MAX


## One template of the set with at most max_items distinct products, or null when there is no set or none fits.
static func _pick_template(rng: RandomNumberGenerator, set_res: Variant, max_items: int) -> OrderTemplate:
	var fitting: Array[OrderTemplate] = []
	if set_res is OrderTemplateSet:
		for template in (set_res as OrderTemplateSet).templates:
			if template.items.size() <= max_items:
				fitting.append(template)
	if fitting.is_empty():
		return null
	return fitting[rng.randi_range(0, fitting.size() - 1)]


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
	for id in reqs:
		var req: OrderRequirement = catalog[id]
		window = mini(window, req.window_min(CompanyTuning.ORDER_WINDOW_MIN))
	order["due_min"] = int(order["created_min"]) + window
	order["pay"] = OrderPricing.with_requirements(int(order["pay"]), reqs, catalog)
	return order
