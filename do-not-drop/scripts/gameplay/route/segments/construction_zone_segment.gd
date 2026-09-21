extends RouteSegment
class_name ConstructionZoneSegment
## A construction barrier eats one side of the road for most of the
## segment's length, narrowing the drivable lane instead of forcing a full
## weave like ChicaneSegment -- a sustained one-sided squeeze rather than an
## alternating dodge.

const CONE := Color("d8752b")

var _barrier_length: float = 28.0


func _init() -> void:
	length = 40.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)

	var barrier_center_z: float = -length * 0.5
	_box("ConstructionBarrier", Vector3(5.0, 0.9, _barrier_length), Vector3(2.5, 0.45, barrier_center_z), CONCRETE, true)
	_box("ConstructionBarrierStripe", Vector3(5.04, 0.12, _barrier_length), Vector3(2.5, 0.92, barrier_center_z), WARNING)

	var barrier_start_z: float = barrier_center_z + _barrier_length * 0.5
	var barrier_end_z: float = barrier_center_z - _barrier_length * 0.5
	var cone_z: float = barrier_start_z - 1.5
	var index: int = 0
	while cone_z > barrier_end_z:
		_box("ConstructionCone" + str(index), Vector3(0.5, 0.7, 0.5), Vector3(-0.1, 0.35, cone_z), CONE, true)
		cone_z -= 3.0
		index += 1
