class_name SupplierDeparture
extends RefCounted
## What the supplier truck does when its wait is over (expansion D-0618, "Modo Empresa").
##
## At SupplierSchedule.departure_minute() the truck drives off and takes every pallet that
## is still on its bed. Pure data over the pallets of the day and the ids that were
## unloaded: no node, no clock, no autoload. Decision: no extra demurrage fee; the
## wallet only pays for what arrived (D-0503) and DeliveryNote (D-0614) records the
## shortfall, so a late unload costs the units left behind and nothing else.


## True once the truck of that day has driven off.
static func has_left(schedule: SupplierSchedule, day: int, minute: int) -> bool:
	return schedule.truck_state(day, minute) == SupplierSchedule.STATE_LEFT


## The pallets still on the bed: the day's pallets whose id is not in unloaded_ids.
static func left_on_bed(pallets: Array, unloaded_ids: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pallet: Variant in pallets:
		if not pallet is Dictionary:
			continue
		var p: Dictionary = pallet
		var id: Variant = p.get("id", &"")
		if (
			unloaded_ids.has(id)
			or unloaded_ids.has(str(id))
			or unloaded_ids.has(StringName(str(id)))
		):
			continue
		out.append(p)
	return out


## Units per product the truck takes away.
static func taken_units(pallets: Array, unloaded_ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in left_on_bed(pallets, unloaded_ids):
		var product := StringName(p.get("product", &""))
		var qty: int = int(p.get("qty", 0))
		if product != &"" and qty >= 1:
			out[product] = int(out.get(product, 0)) + qty
	return out


## Closes the day's delivery. Returns {left, taken, note_lines}: left is true when the truck
## has driven off at that minute; taken is what it carries away; note_lines is the
## DeliveryNote comparison of the order against what was unloaded. Before the departure
## minute nothing is taken and the delivery stays open (the schedule is not touched).
## After it the delivery is cleared from the schedule.
static func resolve(
	schedule: SupplierSchedule, day: int, minute: int, pallets: Array, unloaded_ids: Array
) -> Dictionary:
	var out: Dictionary = {"left": false, "taken": {}, "note_lines": []}
	if not has_left(schedule, day, minute):
		return out
	out["left"] = true
	out["taken"] = taken_units(pallets, unloaded_ids)
	out["note_lines"] = DeliveryNote.compare(
		schedule.ordered_for(day), DeliveryNote.received_units(pallets, unloaded_ids)
	)
	schedule.clear_day(day)
	return out
