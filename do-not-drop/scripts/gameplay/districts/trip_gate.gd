class_name TripGate
extends RefCounted
## The shed gate as a line on the ground (expansion D-0302).
##
## The gate is a plane across the yard: positions on the shed side are inside,
## the others outside. Feeding a vehicle's position each physics tick tells when
## it crossed outward (a trip starts) or inward (a trip ends). The gate is
## described by a point on its line and the outward direction, both flat on XZ,
## so the roller door node only has to hand over its transform. Pure math.
##
## With a yard (set_yard()), inside is a rectangle instead of a half-plane: the shed and the playon, from the gate's
## line back `back` metres and `half_width` to each side of the axis. Leaving it by any side is a departure and
## coming in by any side a return: a vehicle that leaves round the playon's side, where there is no fence, is as
## out as one that drives through the opening (the opening and its width are not looked at then).

signal departed(vehicle_id: StringName)
signal returned(vehicle_id: StringName)

const OUTSIDE: int = 1
const INSIDE: int = -1

var _origin := Vector2.ZERO
var _outward := Vector2(0.0, 1.0)
## Half width of the opening; crossings farther from the door axis do not count.
var _half_width: float = 6.0
var _side_of: Dictionary = {}
## The yard rectangle (set_yard()): metres from the line toward the inside, and to each side of the axis. 0: none.
var _yard_back: float = 0.0
var _yard_half_width: float = 0.0


func _init(origin: Vector3 = Vector3.ZERO, outward: Vector3 = Vector3.BACK, width: float = 12.0) -> void:
	_origin = Vector2(origin.x, origin.z)
	var flat := Vector2(outward.x, outward.z)
	_outward = flat.normalized() if flat.length() > 0.001 else Vector2(0.0, 1.0)
	_half_width = maxf(width, 0.1) * 0.5


## Inside is the rectangle from the gate's line `back` metres toward the shed and `half_width` metres to each side of
## the axis (a yard that has no side or back to speak of for a vehicle that can't be there anyway); outside is
## everything else. Crossings then count anywhere along its edge, not only through the opening.
func set_yard(back: float, half_width: float) -> void:
	_yard_back = maxf(back, 0.0)
	_yard_half_width = maxf(half_width, 0.0)


func has_yard() -> bool:
	return _yard_back > 0.0 and _yard_half_width > 0.0


## Signed distance of a position from the gate line: positive outside.
func distance(pos: Vector3) -> float:
	return (Vector2(pos.x, pos.z) - _origin).dot(_outward)


func side_of(pos: Vector3) -> int:
	var along: float = distance(pos)
	if has_yard():
		var lateral := Vector2(-_outward.y, _outward.x)
		var inside: bool = along <= 0.0 and along >= -_yard_back \
			and absf((Vector2(pos.x, pos.z) - _origin).dot(lateral)) <= _yard_half_width
		return INSIDE if inside else OUTSIDE
	return OUTSIDE if along > 0.0 else INSIDE


## Updates a vehicle position. Emits departed / returned when it crossed the
## line through the opening since the last call, and returns which one
## (&"departed", &"returned" or &"" when nothing happened). The first position
## seen only sets the side.
func track(vehicle_id: StringName, pos: Vector3) -> StringName:
	var side: int = side_of(pos)
	var before: int = _side_of.get(vehicle_id, 0)
	_side_of[vehicle_id] = side
	if before == 0 or before == side or (not has_yard() and not _in_opening(pos)):
		return &""
	if side == OUTSIDE:
		departed.emit(vehicle_id)
		return &"departed"
	returned.emit(vehicle_id)
	return &"returned"


## Whether track(vehicle_id, pos) would be a departure now, changing nothing: CompanyTrips asks before
## feeding a vehicle it may hold at the gate instead (D-0316.2).
func departs(vehicle_id: StringName, pos: Vector3) -> bool:
	return int(_side_of.get(vehicle_id, 0)) == INSIDE and side_of(pos) == OUTSIDE \
		and (has_yard() or _in_opening(pos))


func forget(vehicle_id: StringName) -> void:
	_side_of.erase(vehicle_id)


func _in_opening(pos: Vector3) -> bool:
	var lateral := Vector2(-_outward.y, _outward.x)
	return absf((Vector2(pos.x, pos.z) - _origin).dot(lateral)) <= _half_width
