class_name DockQueue
extends RefCounted
## The rule of the dock when supplier trucks overlap (expansion D-0621.c.a, "Modo Empresa").
##
## The shed has CompanyTuning.SUPPLIER_DOCK_BAYS bays (one; D-0640 raises it) and every supplier has its own
## arrival and departure minute (SupplierDefinition), so two trucks of one day can want the same bay. The rule is a
## QUEUE, first come first served by arrival (a tie: the default supplier, SupplierIds.DEFAULT, then by id):
## - a truck that arrives with every bay taken waits outside and pulls in when one frees up
##   (start = max(arrival, the minute the bay frees));
## - it ALWAYS leaves at its own departure minute, so what it waited is taken off its stay;
## - when that leaves it no stay (start >= departure), or the part of the stay inside the visible day
##   (CompanyTuning.DAY_START_MIN..DAY_END_MIN) is empty, it does not fit: reason NO_ROOM / OUTSIDE_DAY, and it
##   takes no bay. A truck of the previous day's hours parked at the opening still counts (it holds the bay).
## The default supplier's truck is first on a tie but it is not privileged otherwise: it queues like the rest.
## Pure and deterministic: it depends only on the trucks' times, so every peer plans the same day with no RPC.
## No node, no clock, no autoload. Static only.

const REASON_NO_ROOM: StringName = &"no_room"
const REASON_OUTSIDE_DAY: StringName = &"outside_day"


## Plans `trucks` (Dictionaries {supplier: StringName, arrival: int, departure: int}, minutes of the day) over
## `bays` docks. Returns one Dictionary per well-formed truck, in queue order (a truck with no good supplier id
## is skipped):
## {supplier, bay, start, end, visible_start, visible_end, fits, reason}.
## - fits true: bay (0-based) is the dock it uses, start..end the stay (start is the arrival, or later when it
##   waited; end is the departure), visible_start..visible_end that stay cut to the visible day, reason &"".
## - fits false: bay is -1, start..end is the stay it would have had (start may be >= end), the visible bounds
##   are 0, and reason says why (REASON_NO_ROOM, REASON_OUTSIDE_DAY).
## `bays` below 1 is taken as 1.
static func plan(trucks: Array[Dictionary], bays: int = CompanyTuning.SUPPLIER_DOCK_BAYS) -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	for truck: Dictionary in trucks:
		if SupplierIds.ok(truck.get("supplier", &"")):
			queue.append(truck)
	queue.sort_custom(_comes_first)
	var free_at: Array[int] = []
	free_at.resize(maxi(bays, 1))
	free_at.fill(0)
	var out: Array[Dictionary] = []
	for truck: Dictionary in queue:
		var bay: int = 0
		for index: int in free_at.size():
			if free_at[index] < free_at[bay]:
				bay = index
		var arrival: int = int(truck.get("arrival", 0))
		var departure: int = int(truck.get("departure", 0))
		var start: int = maxi(arrival, free_at[bay])
		var entry: Dictionary = {
			"supplier": StringName(truck["supplier"]), "bay": -1, "start": start, "end": departure,
			"visible_start": 0, "visible_end": 0, "fits": false, "reason": REASON_NO_ROOM,
		}
		if start < departure:
			free_at[bay] = departure
			var shown_from: int = maxi(start, CompanyTuning.DAY_START_MIN)
			var shown_to: int = mini(departure, CompanyTuning.DAY_END_MIN)
			if shown_from < shown_to:
				entry["bay"] = bay
				entry["visible_start"] = shown_from
				entry["visible_end"] = shown_to
				entry["fits"] = true
				entry["reason"] = &""
			else:
				entry["reason"] = REASON_OUTSIDE_DAY
		out.append(entry)
	return out


## The trucks of `day` in `schedule` (SupplierSchedule.suppliers_on) as plan() takes them.
static func trucks_of(schedule: SupplierSchedule, day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if schedule == null:
		return out
	for supplier: StringName in schedule.suppliers_on(day):
		out.append({
			"supplier": supplier,
			"arrival": schedule.arrival_minute_of(supplier),
			"departure": schedule.departure_minute_of(supplier),
		})
	return out


## plan() of the trucks `schedule` has on `day`.
static func plan_day(
	schedule: SupplierSchedule, day: int, bays: int = CompanyTuning.SUPPLIER_DOCK_BAYS
) -> Array[Dictionary]:
	return plan(trucks_of(schedule, day), bays)


## The entry of `supplier` in a plan() result ({} when it is not there).
static func entry_of(planned: Array[Dictionary], supplier: StringName) -> Dictionary:
	for entry: Dictionary in planned:
		if entry["supplier"] == supplier:
			return entry
	return {}


## The suppliers of a plan() result whose truck fits, in queue order.
static func fitting(planned: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Dictionary in planned:
		if entry["fits"]:
			out.append(entry["supplier"])
	return out


static func _comes_first(a: Dictionary, b: Dictionary) -> bool:
	var arrival_a: int = int(a.get("arrival", 0))
	var arrival_b: int = int(b.get("arrival", 0))
	if arrival_a != arrival_b:
		return arrival_a < arrival_b
	var default_a: bool = StringName(a["supplier"]) == SupplierIds.DEFAULT
	var default_b: bool = StringName(b["supplier"]) == SupplierIds.DEFAULT
	if default_a != default_b:
		return default_a
	return String(a["supplier"]) < String(b["supplier"])
