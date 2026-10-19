class_name DispatchRules
extends RefCounted
## Which vehicle can go where (expansion D-0309).
##
## Pure rules over plain data, like GateRequirement: no autoloads, no UI. The
## dispatch board (D-0310) asks `check_order()` for each order and, when the answer
## is not ok, shows the reason instead of letting the box be loaded. The same rule
## applies to every gate that closes the order's zone:
## - water and altitude gates are crossed only by the vehicle that owns them
##   (boat, plane), however open the gate is;
## - any other gate (barrier, roadblock, gear) must be open or met;
## - the zone may also list the fleet keys that can deliver inside it.

const NEEDS_VEHICLE: String = "DISPATCH_NEEDS_VEHICLE"
const NEEDS_MILESTONE: String = "DISPATCH_NEEDS_MILESTONE"
const NEEDS_EQUIPMENT: String = "DISPATCH_NEEDS_EQUIPMENT"


## {"ok": bool, "key": translation key ("" when ok), "args": values to format it with}.
## `zones` maps zone id -> ZoneDefinition and `gates` gate id -> GateRequirement;
## `owned` is CompanyState.gate_owned() and `opened_gates` its opened_gates.
static func check(
	zone_id: StringName,
	vehicle: VehicleDefinition,
	zones: Dictionary,
	gates: Dictionary,
	owned: Dictionary,
	opened_gates: Array = []
) -> Dictionary:
	var zone: ZoneDefinition = zones.get(zone_id)
	if zone == null or vehicle == null:
		return _no(NEEDS_VEHICLE, [str(zone_id)])
	if not zone.vehicles.is_empty() and not zone.vehicles.has(vehicle.fleet_key):
		return _no(NEEDS_VEHICLE, [_join(zone.vehicles)])
	for gate_id: StringName in zone.gates:
		var gate: GateRequirement = gates.get(gate_id)
		if gate == null:
			continue
		var verdict: Dictionary = _check_gate(gate, vehicle, owned, opened_gates)
		if not verdict["ok"]:
			return verdict
	return {"ok": true, "key": "", "args": []}


## Same as check() for an order dictionary (Order.make(): its "zone" key).
static func check_order(
	order: Dictionary,
	vehicle: VehicleDefinition,
	zones: Dictionary,
	gates: Dictionary,
	owned: Dictionary,
	opened_gates: Array = []
) -> Dictionary:
	return check(StringName(order.get("zone", "")), vehicle, zones, gates, owned, opened_gates)


static func _check_gate(
	gate: GateRequirement, vehicle: VehicleDefinition, owned: Dictionary, opened_gates: Array
) -> Dictionary:
	var crossing: bool = not gate.has_collision()
	if crossing and gate.vehicle_key != &"" and vehicle.fleet_key != gate.vehicle_key:
		return _no(NEEDS_VEHICLE, [str(gate.vehicle_key)])
	if opened_gates.has(gate.id):
		return {"ok": true, "key": "", "args": []}
	var reason_args: Array = []
	var missing: String = gate.missing_key(owned, reason_args)
	if crossing:
		# Own the boat or the plane is not enough on its own: that was checked above.
		if missing == "WORLD_GATE_NEEDS_VEHICLE":
			missing = ""
	match missing:
		"":
			return {"ok": true, "key": "", "args": []}
		"WORLD_GATE_NEEDS_VEHICLE":
			return _no(NEEDS_VEHICLE, reason_args)
		"WORLD_GATE_NEEDS_EQUIPMENT":
			return _no(NEEDS_EQUIPMENT, reason_args)
	return _no(NEEDS_MILESTONE, reason_args)


static func _no(key: String, args: Array) -> Dictionary:
	return {"ok": false, "key": key, "args": args}


static func _join(ids: Array) -> String:
	var parts: PackedStringArray = []
	for id: Variant in ids:
		parts.append(str(id))
	return ", ".join(parts)
