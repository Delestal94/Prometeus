class_name SupplierSchedule
extends RefCounted
## The supplier delivery calendar (expansion D-0602, "Modo Empresa").
##
## What is ordered on day N arrives on day N + 1 in the single supplier truck
## (CompanyTuning.SUPPLIER_ARRIVAL_MIN), which waits at the dock
## CompanyTuning.SUPPLIER_WAIT_MIN minutes. Pure data over day numbers and
## minutes of the day: no node, no clock, no autoload. The truck that drives
## in and parks is D-0601; the order screen is D-0603.
##
## Orders are kept as day -> {product: qty}; the pallets of a delivery are
## planned on demand with Pallet.plan(), so two orders of the same product
## on one day merge into fewer pallets.

const STATE_NONE: StringName = &"none"
const STATE_PENDING: StringName = &"pending"
const STATE_AT_DOCK: StringName = &"at_dock"
const STATE_LEFT: StringName = &"left"

## Arrival day -> {product id (String) -> units}.
var _deliveries: Dictionary = {}


## Day the truck brings what is ordered on order_day.
static func arrival_day(order_day: int) -> int:
	return order_day + 1


## Minute of the day the truck pulls into the dock.
static func arrival_minute() -> int:
	return CompanyTuning.SUPPLIER_ARRIVAL_MIN


## Minute of the day the truck leaves if it is still waiting.
static func departure_minute() -> int:
	return CompanyTuning.SUPPLIER_ARRIVAL_MIN + CompanyTuning.SUPPLIER_WAIT_MIN


## Adds an order placed on order_day. lines is an Array of {product, qty}.
## All or nothing: false, changing nothing, when order_day is negative, lines
## is empty or any line has an empty product or a non-positive qty.
func place(order_day: int, lines: Array) -> bool:
	if order_day < 0 or lines.is_empty():
		return false
	for line: Variant in lines:
		if not line is Dictionary:
			return false
		var d: Dictionary = line
		if StringName(d.get("product", &"")) == &"" or int(d.get("qty", 0)) < 1:
			return false
	var day: int = arrival_day(order_day)
	var wanted: Dictionary = _deliveries.get(day, {})
	for line: Dictionary in lines:
		var key: String = String(line["product"])
		wanted[key] = int(wanted.get(key, 0)) + int(line["qty"])
	_deliveries[day] = wanted
	return true


## True when a truck comes on that day.
func has_delivery(day: int) -> bool:
	return _deliveries.has(day)


## Units ordered per product for the truck of that day ({} when none).
func ordered_for(day: int) -> Dictionary:
	var out: Dictionary = {}
	var wanted: Dictionary = _deliveries.get(day, {})
	for key: String in wanted:
		out[StringName(key)] = int(wanted[key])
	return out


## The sealed pallets the truck of that day carries, products in id order.
## Pallet ids are "d<day>_<product>_<n>", unique across the calendar.
func pallets_for(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wanted: Dictionary = _deliveries.get(day, {})
	var keys: Array = wanted.keys()
	keys.sort()
	for key: String in keys:
		out.append_array(
			Pallet.plan(StringName("d%d_%s" % [day, key]), StringName(key), int(wanted[key]))
		)
	return out


## Days with a truck, ascending, from from_day on.
func upcoming_days(from_day: int) -> Array[int]:
	var out: Array[int] = []
	for day: int in _deliveries:
		if day >= from_day:
			out.append(day)
	out.sort()
	return out


## Where the truck of that day is at that minute: none (no truck that day),
## pending (not yet in), at_dock (in, waiting) or left (gone).
func truck_state(day: int, minute: int) -> StringName:
	if not _deliveries.has(day):
		return STATE_NONE
	if minute < arrival_minute():
		return STATE_PENDING
	if minute < departure_minute():
		return STATE_AT_DOCK
	return STATE_LEFT


## Drops the delivery of that day once it has been unloaded or has left.
func clear_day(day: int) -> void:
	_deliveries.erase(day)


## Drops every delivery of a day before `day` (they are past: D-0603.b.2 keeps the calendar short).
func forget_before(day: int) -> void:
	for past: int in _deliveries.keys():
		if past < day:
			_deliveries.erase(past)


## Puts `other`'s deliveries in place of these, a copy (a snapshot or a save lands in the calendar
## the truck already reads, D-0603.b.2).
func copy_from(other: SupplierSchedule) -> void:
	_deliveries = other._deliveries.duplicate(true) if other != null else {}


## How many days have a truck.
func day_count() -> int:
	return _deliveries.size()


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for day: int in _deliveries:
		out[str(day)] = (_deliveries[day] as Dictionary).duplicate()
	return {"deliveries": out}


## Tolerates malformed data: bad days, products or quantities are skipped.
static func from_dict(data: Dictionary) -> SupplierSchedule:
	var schedule := SupplierSchedule.new()
	var raw: Variant = data.get("deliveries", {})
	if not raw is Dictionary:
		return schedule
	var deliveries: Dictionary = raw
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
			schedule._deliveries[int(str(day_key))] = clean
	return schedule
