class_name GripZones
extends RefCounted
## The road surface's effect on a vehicle's wheels, shared by every segment
## that lowers grip (gravel, mud...). VehicleWheel3D.wheel_friction_slip is the
## only thing that moves real grip in this engine build, and two segments
## that each saved "the original" and restored it on leaving would, side by
## side (a truck is in both at the seam), save the OTHER one's lowered value
## and leave the truck slippery for the rest of the run.
##
## So the zones are registered on the vehicle itself: meta `grip_zones`
## {zone id: slip} and meta `grip_base` {wheel: slip from before the first
## zone}. The effective slip is the lowest of the active zones; the base is
## saved once, when the first zone is entered, and put back when the last one
## is left. Entering a zone twice never compounds (same id, same slot).

const ZONES_META: StringName = &"grip_zones"
const BASE_META: StringName = &"grip_base"


## `zone` (any object, usually the segment) lowers `vehicle`'s wheels to `slip`.
static func enter(vehicle: Node, zone: Object, slip: float) -> void:
	var zones: Dictionary = vehicle.get_meta(ZONES_META, {})
	if zones.is_empty():
		var base: Dictionary = {}
		for wheel: Node in vehicle.get_children():
			if wheel is VehicleWheel3D:
				base[wheel] = (wheel as VehicleWheel3D).wheel_friction_slip
		vehicle.set_meta(BASE_META, base)
	zones[zone.get_instance_id()] = slip
	vehicle.set_meta(ZONES_META, zones)
	_apply(vehicle, zones)


## `zone` no longer touches `vehicle`: its slot goes, and the grip is whatever
## the zones still active say, or the original when none is.
static func leave(vehicle: Node, zone: Object) -> void:
	if not is_instance_valid(vehicle):
		return
	var zones: Dictionary = vehicle.get_meta(ZONES_META, {})
	if not zones.has(zone.get_instance_id()):
		return
	zones.erase(zone.get_instance_id())
	if not zones.is_empty():
		vehicle.set_meta(ZONES_META, zones)
		_apply(vehicle, zones)
		return
	var base: Dictionary = vehicle.get_meta(BASE_META, {})
	for wheel: Variant in base.keys():
		if is_instance_valid(wheel):
			(wheel as VehicleWheel3D).wheel_friction_slip = base[wheel]
	vehicle.remove_meta(ZONES_META)
	vehicle.remove_meta(BASE_META)


static func is_in(vehicle: Node, zone: Object) -> bool:
	return (vehicle.get_meta(ZONES_META, {}) as Dictionary).has(zone.get_instance_id())


static func _apply(vehicle: Node, zones: Dictionary) -> void:
	var lowest: float = INF
	for slip: Variant in zones.values():
		lowest = minf(lowest, float(slip))
	var base: Dictionary = vehicle.get_meta(BASE_META, {})
	for wheel: Node in vehicle.get_children():
		if wheel is VehicleWheel3D:
			# A wheel that was not there at the start keeps the lowest too.
			var wanted: float = minf(lowest, float(base.get(wheel, INF)))
			(wheel as VehicleWheel3D).wheel_friction_slip = wanted
