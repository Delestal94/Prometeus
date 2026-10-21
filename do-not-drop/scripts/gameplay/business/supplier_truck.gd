class_name SupplierTruck
extends RefCounted
## Where the supplier's truck is at a given minute (expansion D-0601, "Modo Empresa").
##
## Pure data over the SupplierSchedule and the shed's stage: no node, no clock, no autoload, no
## random roll. pose() is a function of (schedule, day, minute, stage), so every peer that reads
## the same game clock puts the truck in the same place without a single RPC. The nodes that draw
## it are SupplierTruckView.
##
## The drive, in the shed's local metres (X east, Z south, origin at the middle of the floor; the
## dock is the gap in the south wall, SupplierSchedule's at_dock is the truck parked in front of it):
##   DRIVING_IN   comes from the east along a lane south of the dock, heading west;
##                turns left in an arc (CompanyTuning.SUPPLIER_TRUCK_TURN_RADIUS_M) until it
##                points south on the dock's axis;
##   REVERSING    backs up north, straight, until its rear is SUPPLIER_TRUCK_REAR_GAP_M from the
##                floor edge, outside the wall: it never enters the shed or the dock's floor
##                cells (WarehouseStages.dock_rect), the pallets are carried from its bed (D-0605);
##   PARKED       from SupplierSchedule.arrival_minute() to departure_minute(), motionless;
##   DRIVING_OUT  pulls forward (south), turns left again and leaves to the east on its own lane,
##                twelve metres south of the one it came in by.
## It is parked exactly when the schedule says at_dock; it drives in during the SUPPLIER_DRIVE_IN_MIN
## game minutes before and out during the SUPPLIER_DRIVE_OUT_MIN after. Easing: it slows into the
## parking spot and speeds up from it.

enum Phase { ABSENT, DRIVING_IN, REVERSING, PARKED, DRIVING_OUT }


## {present, phase (Phase), position (Vector2: x, z of the truck's middle), heading (Vector2: unit
## vector its front points to), yaw (radians about Y that turns a model facing -Z to that heading)}.
## Absent when that day has no truck, before it starts driving in and once it is out.
static func pose(schedule: SupplierSchedule, day: int, minute: float, stage: int = 0) -> Dictionary:
	var geo: Dictionary = _geometry(stage)
	var drive_in: float = CompanyTuning.SUPPLIER_DRIVE_IN_MIN
	var drive_out: float = CompanyTuning.SUPPLIER_DRIVE_OUT_MIN
	match schedule.truck_state(day, floori(minute)):
		SupplierSchedule.STATE_PENDING:
			var u: float = (minute - (SupplierSchedule.arrival_minute() - drive_in)) / drive_in
			if u < 0.0:
				return _absent()
			return _entry_pose(geo, 1.0 - (1.0 - u) * (1.0 - u))
		SupplierSchedule.STATE_AT_DOCK:
			return _made(Phase.PARKED, geo["park"], Vector2(0.0, 1.0))
		SupplierSchedule.STATE_LEFT:
			var u: float = (minute - SupplierSchedule.departure_minute()) / drive_out
			if u >= 1.0:
				return _absent()
			return _exit_pose(geo, u * u)
	return _absent()


## The truck's four corners (x, z) when its middle is at `position` pointing to `heading`.
static func corners(position: Vector2, heading: Vector2) -> PackedVector2Array:
	var size: Vector3 = CompanyTuning.SUPPLIER_TRUCK_SIZE_M
	var forward: Vector2 = heading.normalized() * (size.z * 0.5)
	var side: Vector2 = Vector2(-heading.y, heading.x).normalized() * (size.x * 0.5)
	return PackedVector2Array([
		position + forward + side, position + forward - side,
		position - forward - side, position - forward + side,
	])


## The parking spot as a rect in metres (shed-local x, z): the truck's footprint when parked.
static func parked_rect(stage: int) -> Rect2:
	var size: Vector3 = CompanyTuning.SUPPLIER_TRUCK_SIZE_M
	var park: Vector2 = _geometry(stage)["park"]
	return Rect2(park - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))


## Where the dock's gap in the south wall is, as an x range in metres (x = from, y = to).
static func gate_span_x(stage: int) -> Vector2:
	var dock: Rect2i = WarehouseStages.dock_rect(stage)
	var grid: Vector2i = WarehouseStages.grid_size_for(stage)
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	return Vector2((dock.position.x - grid.x * 0.5) * metres, (dock.end.x - grid.x * 0.5) * metres)


# --- Path ---


## The fixed points of the drive for a stage: the dock's axis (x), the parked middle, the lane the
## truck comes in by and the one it leaves by (z), and the turn radius.
static func _geometry(stage: int) -> Dictionary:
	var floor_m: Vector2 = WarehouseStages.floor_size_m(stage)
	var span: Vector2 = gate_span_x(stage)
	var radius: float = CompanyTuning.SUPPLIER_TRUCK_TURN_RADIUS_M
	var reverse: float = CompanyTuning.SUPPLIER_TRUCK_REVERSE_M
	var axis: float = (span.x + span.y) * 0.5
	var park_z: float = floor_m.y * 0.5 + CompanyTuning.SUPPLIER_TRUCK_REAR_GAP_M \
		+ CompanyTuning.SUPPLIER_TRUCK_SIZE_M.z * 0.5
	return {
		"axis": axis, "radius": radius, "reverse": reverse,
		"approach": CompanyTuning.SUPPLIER_TRUCK_APPROACH_M,
		"park": Vector2(axis, park_z),
		"turn_z": park_z + reverse,
	}


## Length of the way in: straight run, quarter turn, straight back.
static func _entry_length(geo: Dictionary) -> float:
	return float(geo["approach"]) + float(geo["radius"]) * PI * 0.5 + float(geo["reverse"])


## The pose after `progress` (0..1) of the way in.
static func _entry_pose(geo: Dictionary, progress: float) -> Dictionary:
	var axis: float = geo["axis"]
	var radius: float = geo["radius"]
	var turn_z: float = geo["turn_z"]
	var approach: float = geo["approach"]
	var arc: float = radius * PI * 0.5
	var s: float = clampf(progress, 0.0, 1.0) * _entry_length(geo)
	var lane_z: float = turn_z - radius
	if s < approach:
		return _made(Phase.DRIVING_IN, Vector2(axis + radius + approach - s, lane_z), Vector2(-1.0, 0.0))
	s -= approach
	if s < arc:
		var phi: float = s / radius
		var centre := Vector2(axis + radius, turn_z)
		return _made(Phase.DRIVING_IN, centre + radius * Vector2(-sin(phi), -cos(phi)),
			Vector2(-cos(phi), sin(phi)))
	s -= arc
	var back: float = minf(s, float(geo["reverse"]))
	if back >= float(geo["reverse"]) - 0.000001:
		return _made(Phase.PARKED, geo["park"], Vector2(0.0, 1.0))
	return _made(Phase.REVERSING, Vector2(axis, turn_z - back), Vector2(0.0, 1.0))


## The pose after `progress` (0..1) of the way out: straight forward, quarter turn, straight run.
static func _exit_pose(geo: Dictionary, progress: float) -> Dictionary:
	var axis: float = geo["axis"]
	var radius: float = geo["radius"]
	var turn_z: float = geo["turn_z"]
	var arc: float = radius * PI * 0.5
	var s: float = clampf(progress, 0.0, 1.0) * _entry_length(geo)
	var park: Vector2 = geo["park"]
	if s < float(geo["reverse"]):
		return _made(Phase.DRIVING_OUT, park + Vector2(0.0, s), Vector2(0.0, 1.0))
	s -= float(geo["reverse"])
	if s < arc:
		var phi: float = s / radius
		var centre := Vector2(axis + radius, turn_z)
		return _made(Phase.DRIVING_OUT, centre + radius * Vector2(-cos(phi), sin(phi)),
			Vector2(sin(phi), cos(phi)))
	s -= arc
	return _made(Phase.DRIVING_OUT, Vector2(axis + radius + s, turn_z + radius), Vector2(1.0, 0.0))


static func _made(phase: Phase, position: Vector2, heading: Vector2) -> Dictionary:
	return {"present": true, "phase": phase, "position": position, "heading": heading,
		"yaw": atan2(-heading.x, -heading.y)}


static func _absent() -> Dictionary:
	return {"present": false, "phase": Phase.ABSENT, "position": Vector2.ZERO,
		"heading": Vector2(0.0, 1.0), "yaw": 0.0}
