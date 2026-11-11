class_name SupplierSchedule
extends RefCounted
## The supplier delivery calendar (expansion D-0602, "Modo Empresa"; a truck per supplier, D-0621.b).
##
## What is ordered on day N from a supplier arrives on day N + 1 in that supplier's truck, which pulls
## into the dock at its arrival minute and waits its minutes there (SupplierDefinition.arrival_min and
## wait_minutes, handed over with use_suppliers(); one never handed over keeps CompanyTuning's
## SUPPLIER_ARRIVAL_MIN and SUPPLIER_WAIT_MIN). Pure data over day numbers and minutes of the day: no
## node, no clock, no autoload. The truck that drives in and parks is D-0601; the order screen is D-0603.
##
## The calls take the supplier last, DEFAULT_SUPPLIER when left out: that is the truck the shed draws,
## loads and sends off (SupplierTruckView, CompanyPallets, SupplierDeparture, which name none), so they
## answer as before D-0621.b, at CompanyTuning's times. The trucks of the other suppliers are kept,
## replicated and saved the same way; bringing them to the dock is D-0621.c. Supplier and pallet ids:
## SupplierIds.
##
## Orders are kept as supplier -> day -> {product: qty}; the pallets of a delivery are
## planned on demand with Pallet.plan(), so two orders of the same product
## on one day merge into fewer pallets.

const STATE_NONE: StringName = &"none"
const STATE_PENDING: StringName = &"pending"
const STATE_AT_DOCK: StringName = &"at_dock"
const STATE_LEFT: StringName = &"left"
## The supplier of the calls that name none: the only one before D-0621.b. Its .tres repeats
## CompanyTuning's times (test_company_suppliers), and its truck always keeps those.
const DEFAULT_SUPPLIER: StringName = SupplierIds.DEFAULT

## Supplier id (String) -> {arrival day (int) -> {product id (String) -> units}}; a supplier with no
## truck has no entry.
var _trucks: Dictionary = {}
## Supplier id (StringName) -> Vector2i(arrival minute, wait minutes) from use_suppliers(). Not saved
## nor copied: every peer reads the same catalog.
var _times: Dictionary = {}


## Day the truck brings what is ordered on order_day.
static func arrival_day(order_day: int) -> int:
	return order_day + 1


## Minute of the day DEFAULT_SUPPLIER's truck pulls into the dock.
static func arrival_minute() -> int:
	return CompanyTuning.SUPPLIER_ARRIVAL_MIN


## Minute of the day DEFAULT_SUPPLIER's truck leaves if it is still waiting.
static func departure_minute() -> int:
	return CompanyTuning.SUPPLIER_ARRIVAL_MIN + CompanyTuning.SUPPLIER_WAIT_MIN


## The trucks' times of `suppliers` (SupplierDefinitions; anything else is skipped): set_times() for each.
func use_suppliers(suppliers: Array) -> void:
	for seller: Variant in suppliers:
		if seller is SupplierDefinition:
			set_times((seller as SupplierDefinition).id, seller.arrival_min, seller.wait_minutes)


## When `supplier`'s truck pulls in (a minute of the day, 0..1439) and how many minutes it waits (1 on).
## False, changing nothing, for an id the calendar does not take (SupplierIds.ok) or times out of range.
func set_times(supplier: StringName, arrival_min: int, wait_min: int) -> bool:
	if not SupplierIds.ok(supplier) or arrival_min < 0 or arrival_min >= 24 * 60 or wait_min < 1:
		return false
	_times[supplier] = Vector2i(arrival_min, wait_min)
	return true


## Minute of the day `supplier`'s truck pulls into the dock (DEFAULT_SUPPLIER's: arrival_minute()).
func arrival_minute_of(supplier: StringName) -> int:
	var times: Variant = _times.get(supplier)
	if supplier == DEFAULT_SUPPLIER or not times is Vector2i:
		return arrival_minute()
	return (times as Vector2i).x


## Minute of the day `supplier`'s truck leaves if it is still waiting (DEFAULT_SUPPLIER's: departure_minute()).
func departure_minute_of(supplier: StringName) -> int:
	var times: Variant = _times.get(supplier)
	if supplier == DEFAULT_SUPPLIER or not times is Vector2i:
		return departure_minute()
	return (times as Vector2i).x + (times as Vector2i).y


## Adds an order placed on order_day to `supplier`'s truck. lines is an Array of {product, qty}.
## All or nothing: false, changing nothing, when the supplier id is not one the calendar takes,
## order_day is negative, lines is empty or any line has an empty product or a non-positive qty.
func place(order_day: int, lines: Array, supplier: StringName = DEFAULT_SUPPLIER) -> bool:
	if not SupplierIds.ok(supplier) or order_day < 0 or lines.is_empty():
		return false
	for line: Variant in lines:
		if not line is Dictionary:
			return false
		var d: Dictionary = line
		if StringName(d.get("product", &"")) == &"" or int(d.get("qty", 0)) < 1:
			return false
	var days: Dictionary = _trucks.get(String(supplier), {})
	var day: int = arrival_day(order_day)
	var wanted: Dictionary = days.get(day, {})
	for line: Dictionary in lines:
		var key: String = String(line["product"])
		wanted[key] = int(wanted.get(key, 0)) + int(line["qty"])
	days[day] = wanted
	_trucks[String(supplier)] = days
	return true


## True when `supplier`'s truck comes on that day.
func has_delivery(day: int, supplier: StringName = DEFAULT_SUPPLIER) -> bool:
	return _days_of(supplier).has(day)


## Units ordered per product (StringName -> int) for `supplier`'s truck of that day ({} when none).
func ordered_for(day: int, supplier: StringName = DEFAULT_SUPPLIER) -> Dictionary:
	var out: Dictionary = {}
	var wanted: Dictionary = _days_of(supplier).get(day, {})
	for key: String in wanted:
		out[StringName(key)] = int(wanted[key])
	return out


## The sealed pallets `supplier`'s truck of that day carries, products in id order. Pallet ids are
## "d<day>_<product>_<n>" for DEFAULT_SUPPLIER's (as before D-0621.b) and "d<day>-<supplier>-<product>_<n>"
## for the others' (SupplierIds.pallet_prefix): unique across the calendar, and
## SupplierIds.pallet_supplier() reads the supplier back.
func pallets_for(day: int, supplier: StringName = DEFAULT_SUPPLIER) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wanted: Dictionary = _days_of(supplier).get(day, {})
	var keys: Array = wanted.keys()
	keys.sort()
	for key: String in keys:
		var prefix: StringName = SupplierIds.pallet_prefix(supplier, day, StringName(key))
		out.append_array(Pallet.plan(prefix, StringName(key), int(wanted[key])))
	return out


## Days with `supplier`'s truck, ascending, from from_day on.
func upcoming_days(from_day: int, supplier: StringName = DEFAULT_SUPPLIER) -> Array[int]:
	var out: Array[int] = []
	for day: int in _days_of(supplier):
		if day >= from_day:
			out.append(day)
	out.sort()
	return out


## The suppliers whose truck comes on that day, the earliest to pull in first (ties by id).
func suppliers_on(day: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for supplier: String in _trucks:
		if (_trucks[supplier] as Dictionary).has(day):
			out.append(StringName(supplier))
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		if arrival_minute_of(a) != arrival_minute_of(b):
			return arrival_minute_of(a) < arrival_minute_of(b)
		return String(a) < String(b))
	return out


## Where `supplier`'s truck of that day is at that minute: none (no truck that day), pending (not yet
## in), at_dock (in, waiting) or left (gone).
func truck_state(day: int, minute: int, supplier: StringName = DEFAULT_SUPPLIER) -> StringName:
	if not has_delivery(day, supplier):
		return STATE_NONE
	if minute < arrival_minute_of(supplier):
		return STATE_PENDING
	if minute < departure_minute_of(supplier):
		return STATE_AT_DOCK
	return STATE_LEFT


## Drops the delivery of `supplier`'s truck of that day once it has been unloaded or has left.
func clear_day(day: int, supplier: StringName = DEFAULT_SUPPLIER) -> void:
	var days: Dictionary = _days_of(supplier)
	days.erase(day)
	if days.is_empty():
		_trucks.erase(String(supplier))


## Drops every delivery of a day before `day`, of every supplier (they are past: D-0603.b.2 keeps the
## calendar short).
func forget_before(day: int) -> void:
	for supplier: String in _trucks.keys():
		for past: int in (_trucks[supplier] as Dictionary).keys():
			if past < day:
				clear_day(past, StringName(supplier))


## Puts `other`'s deliveries in place of these, a copy (a snapshot or a save lands in the calendar
## the truck already reads, D-0603.b.2). The trucks' times stay this calendar's.
func copy_from(other: SupplierSchedule) -> void:
	_trucks = other._trucks.duplicate(true) if other != null else {}


## How many trucks the calendar holds, a supplier's day each (with DEFAULT_SUPPLIER alone, the days
## with a truck).
func day_count() -> int:
	var count: int = 0
	for supplier: String in _trucks:
		count += (_trucks[supplier] as Dictionary).size()
	return count


## {deliveries: {"<day>": {product: units}}} for DEFAULT_SUPPLIER's truck (the form before D-0621.b) and,
## only when another supplier has a truck, suppliers: {"<supplier>": {"<day>": {product: units}}}.
func to_dict() -> Dictionary:
	var out: Dictionary = {"deliveries": _days_to_dict(_days_of(DEFAULT_SUPPLIER))}
	var others: Dictionary = {}
	for supplier: String in _trucks:
		if StringName(supplier) != DEFAULT_SUPPLIER:
			others[supplier] = _days_to_dict(_trucks[supplier])
	if not others.is_empty():
		out["suppliers"] = others
	return out


## Tolerates malformed data: bad suppliers, days, products or quantities are skipped. A calendar from
## before D-0621.b (only `deliveries`) loads as DEFAULT_SUPPLIER's truck.
static func from_dict(data: Dictionary) -> SupplierSchedule:
	var schedule := SupplierSchedule.new()
	schedule._read_days(DEFAULT_SUPPLIER, data.get("deliveries", {}))
	var others: Variant = data.get("suppliers", {})
	if others is Dictionary:
		for supplier: Variant in others:
			if SupplierIds.ok(supplier) and StringName(supplier) != DEFAULT_SUPPLIER:
				schedule._read_days(StringName(supplier), (others as Dictionary)[supplier])
	return schedule


## The days of `supplier`'s truck as stored (the same Dictionary, {} when it has none).
func _days_of(supplier: StringName) -> Dictionary:
	return _trucks.get(String(supplier), {})


static func _days_to_dict(days: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for day: int in days:
		out[str(day)] = (days[day] as Dictionary).duplicate()
	return out


## Puts the valid days of `raw` ({"<day>": {product: units}}) in `supplier`'s truck.
func _read_days(supplier: StringName, raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var deliveries: Dictionary = raw
	var days: Dictionary = {}
	for day_key: Variant in deliveries:
		var wanted: Variant = deliveries[day_key]
		if not str(day_key).is_valid_int() or not wanted is Dictionary:
			continue
		var clean: Dictionary = {}
		var products: Dictionary = wanted
		for product: Variant in products:
			var qty: int = int(products[product])
			if str(product) != "" and qty >= 1:
				clean[str(product)] = qty
		if not clean.is_empty() and int(str(day_key)) >= 1:
			days[int(str(day_key))] = clean
	if not days.is_empty():
		_trucks[String(supplier)] = days
