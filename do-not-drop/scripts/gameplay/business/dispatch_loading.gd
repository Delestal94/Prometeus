class_name DispatchLoading
extends RefCounted
## Loads a vehicle from the dispatch zone (expansion D-0717).
##
## The zone (D-0716) knows which sealed boxes wait; this decides which of them fit the vehicle
## that is being loaded: oldest first, each box must pass DispatchRules (D-0309) for its order's
## zone, and the vehicle's cargo_slots and cargo_kg (VehicleDefinition) must still have room.
## What does not fit stays waiting in the zone, with the reason. Pure logic over plain data: the
## world adapter walks the loaded boxes onto the vehicle's mount points like today's depot load.

const NO_SLOTS: String = "WORLD_LOAD_NO_SLOTS"
const NO_WEIGHT: String = "WORLD_LOAD_NO_WEIGHT"


## Splits the zone's waiting boxes for `vehicle`. `box_kg` maps box id -> kg (BoxScale.real_kg);
## a box without an entry weighs 0. Returns {"load": Array[StringName] of box ids,
## "left": Array of {"box", "order", "key", "args"}}. Does not touch the zone.
static func plan(
	zone: DispatchZone,
	book: OrderBook,
	vehicle: VehicleDefinition,
	box_kg: Dictionary,
	zones: Dictionary,
	gates: Dictionary,
	owned: Dictionary,
	opened_gates: Array = []
) -> Dictionary:
	var to_load: Array[StringName] = []
	var left: Array[Dictionary] = []
	var kg: float = 0.0
	var boxes: Array[StringName] = zone.boxes()
	for box_id: StringName in boxes:
		var order_id: StringName = zone.order_of(box_id)
		var verdict: Dictionary = DispatchRules.check_order(
			book.get_order(order_id), vehicle, zones, gates, owned, opened_gates
		)
		if not verdict["ok"]:
			left.append(_left(box_id, order_id, verdict["key"], verdict["args"]))
			continue
		var weight: float = float(box_kg.get(box_id, 0.0))
		if to_load.size() >= vehicle.cargo_slots:
			left.append(_left(box_id, order_id, NO_SLOTS, [vehicle.cargo_slots]))
		elif kg + weight > vehicle.cargo_kg:
			left.append(_left(box_id, order_id, NO_WEIGHT, [vehicle.cargo_kg]))
		else:
			to_load.append(box_id)
			kg += weight
	return {"load": to_load, "left": left}


## plan() and then the load: the boxes that fit are staged on `vehicle_id` in the trip gate and
## leave the zone; the rest keep waiting. Returns the plan's result.
static func load_vehicle(
	zone: DispatchZone,
	trips: CompanyTrips,
	vehicle_id: StringName,
	book: OrderBook,
	vehicle: VehicleDefinition,
	box_kg: Dictionary,
	zones: Dictionary,
	gates: Dictionary,
	owned: Dictionary,
	opened_gates: Array = []
) -> Dictionary:
	var result: Dictionary = plan(zone, book, vehicle, box_kg, zones, gates, owned, opened_gates)
	var chosen: Array[StringName] = []
	chosen.assign(result["load"])
	zone.load_boxes(trips, vehicle_id, chosen)
	return result


static func _left(box_id: StringName, order_id: StringName, key: String, args: Array) -> Dictionary:
	return {"box": box_id, "order": order_id, "key": key, "args": args}
