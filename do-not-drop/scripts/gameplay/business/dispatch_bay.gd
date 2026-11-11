class_name DispatchBay
extends RefCounted
## Loads several vehicles from the dispatch zone at the same time (expansion D-0931).
##
## DispatchLoading serves one vehicle; with two or more standing in the loading bay each waiting
## box (oldest first) goes to the first vehicle, in the order given, that accepts it: its order
## passes DispatchRules for that vehicle and cargo_slots / cargo_kg still have room. A box no
## vehicle takes stays waiting with the reason of the first vehicle that passed the rules but was
## full, or else the rules' reason for the first vehicle. Pure logic over plain data.

const MAX_VEHICLES: int = 3


## `vehicles` is an Array of {"id": StringName, "def": VehicleDefinition} (at most MAX_VEHICLES
## count). Returns {"loads": {vehicle id -> Array[StringName] box ids}, "left": Array of
## {"box", "order", "key", "args"}}. Does not touch the zone.
static func plan(
	zone: DispatchZone,
	book: OrderBook,
	vehicles: Array,
	box_kg: Dictionary,
	zones: Dictionary,
	gates: Dictionary,
	owned: Dictionary,
	opened_gates: Array = []
) -> Dictionary:
	var loads: Dictionary = {}
	var used_kg: Dictionary = {}
	var bays: Array = vehicles.slice(0, MAX_VEHICLES)
	for entry: Dictionary in bays:
		loads[entry["id"]] = [] as Array[StringName]
		used_kg[entry["id"]] = 0.0
	var left: Array[Dictionary] = []
	for box_id: StringName in zone.boxes():
		var order_id: StringName = zone.order_of(box_id)
		var weight: float = float(box_kg.get(box_id, 0.0))
		var placed: bool = false
		var reason: Dictionary = {}
		for entry: Dictionary in bays:
			var vehicle: VehicleDefinition = entry["def"]
			var vid: StringName = entry["id"]
			var verdict: Dictionary = DispatchRules.check_order(
				book.get_order(order_id), vehicle, zones, gates, owned, opened_gates
			)
			if not verdict["ok"]:
				if reason.is_empty():
					reason = verdict
				continue
			var taken: Array = loads[vid]
			if taken.size() >= vehicle.cargo_slots:
				if not reason.has("full"):
					reason = {"key": DispatchLoading.NO_SLOTS, "args": [vehicle.cargo_slots], "full": true}
			elif used_kg[vid] + weight > vehicle.cargo_kg:
				if not reason.has("full"):
					reason = {"key": DispatchLoading.NO_WEIGHT, "args": [vehicle.cargo_kg], "full": true}
			else:
				taken.append(box_id)
				used_kg[vid] += weight
				placed = true
				break
		if not placed:
			var key: String = reason.get("key", DispatchLoading.NO_SLOTS)
			left.append(
				{"box": box_id, "order": order_id, "key": key, "args": reason.get("args", [])}
			)
	return {"loads": loads, "left": left}


## plan() and then the loads: each vehicle's boxes are staged on it in the trip gate and leave the
## zone; the rest keep waiting. Returns the plan's result.
static func load_bay(
	zone: DispatchZone,
	trips: CompanyTrips,
	book: OrderBook,
	vehicles: Array,
	box_kg: Dictionary,
	zones: Dictionary,
	gates: Dictionary,
	owned: Dictionary,
	opened_gates: Array = []
) -> Dictionary:
	var result: Dictionary = plan(zone, book, vehicles, box_kg, zones, gates, owned, opened_gates)
	var loads: Dictionary = result["loads"]
	for vid: StringName in loads:
		var chosen: Array[StringName] = []
		chosen.assign(loads[vid])
		zone.load_boxes(trips, vid, chosen)
	return result
