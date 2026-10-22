class_name CompanyDayOrders
extends RefCounted
## The day's customer orders in the company world (expansion D-0813.1): what the host's CompanyRoot does
## with CompanyNet.orders (CompanyOrdersNet, D-0813). Static only, nothing kept (the catalogs are read
## again for each day: a static cache of Resources would outlive the tree at exit); names no autoload
## (the company comes in as an Object, the CompanyState node).
##
## - plan(): at each new day's OPENING the host plans the day with OrderGenerator: the company's day seed
##   (CompanyState.day_seed(CompanySeed.ORDERS), D-0246), the day, the crew, the zones open to the company
##   (open_zones()) and the catalogs of data/products/ and data/order_requirements/. The same company
##   seed, day, crew and money give the same orders, so an interrupted day loaded again brings the same
##   ones back from its opening.
## - poll(): on the host's business tick, after DayCycle.poll, the orders come in and go late at the
##   shed's minute (DayCycle.shed_minute(), which stands still while the shed is frozen, S4) while the day
##   is open (OPENING, OPERATING); none in CLOSING or SUMMARY, so a frozen shed costs the day the orders
##   it never got to.
## Telling each order to the presentation (EventBus.order_added) is every peer's CompanyRoot, from
## CompanyNet.event_applied.

## Host: the orders of `day` for a crew of `players`, planned on `net` (CompanyOrdersNet.plan_day()) from
## `company`'s day seed, the zones open to it and the catalogs. Returns how many are planned: 0 on a
## client or without a company.
static func plan(net: CompanyNet, company: Object, day: int, players: int) -> int:
	if net == null or not net.is_host() or company == null:
		return 0
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	var products: Dictionary = {}
	for id: StringName in catalog.ids(CompanyCatalog.PRODUCTS):
		products[id] = catalog.product(id)
	var day_seed: int = int(company.call(&"day_seed", CompanySeed.ORDERS, day))
	return net.orders.plan_day(day_seed, day, maxi(players, 1), open_zones(catalog.zones(), company), products,
		requirements(), company)


## Host: the orders that came in by the shed's minute, and the ones past due, go out (CompanyOrdersNet.poll())
## while `cycle`'s day is open. Returns how many events went out.
static func poll(net: CompanyNet, cycle: DayCycle) -> int:
	if net == null or cycle == null:
		return 0
	if cycle.phase() != DayCycle.Phase.OPENING and cycle.phase() != DayCycle.Phase.OPERATING:
		return 0
	return net.orders.poll(net, floori(cycle.shed_minute()))


## The zones of `zones` open to `company`: the ones no gate closes (ZoneDefinition.is_open_at_start()) and
## the ones whose every gate it opened (CompanyState.is_gate_open(), as --district= leaves them), in the
## same order. OrderGenerator leaves out the ones that take no deliveries.
static func open_zones(zones: Array[ZoneDefinition], company: Object) -> Array[ZoneDefinition]:
	var open: Array[ZoneDefinition] = []
	for zone: ZoneDefinition in zones:
		if zone == null:
			continue
		var reachable: bool = true
		for gate_id: StringName in zone.gates:
			reachable = reachable and company != null and bool(company.call(&"is_gate_open", gate_id))
		if reachable:
			open.append(zone)
	return open


## The order requirement catalog (CompanyOrdersNet.REQUIREMENTS_DIR), by id.
static func requirements() -> Dictionary:
	var found: Dictionary = {}
	for file: String in CompanyCatalog.tres_files(CompanyOrdersNet.REQUIREMENTS_DIR):
		var requirement := load(CompanyOrdersNet.REQUIREMENTS_DIR + file) as OrderRequirement
		if requirement != null:
			found[requirement.id] = requirement
	return found
