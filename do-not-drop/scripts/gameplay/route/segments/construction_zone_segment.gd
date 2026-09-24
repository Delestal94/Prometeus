extends RouteSegment
class_name ConstructionZoneSegment
## A construction barrier eats one side of the road for most of the
## segment's length, narrowing the drivable lane instead of forcing a full
## weave like ChicaneSegment -- a sustained one-sided squeeze rather than an
## alternating dodge.

const CONE := Color("d8752b")
const CONE_MODEL := "res://assets/models/environment/props/sm_env_prop_traffic_cone.glb"
const BARRIER_MODEL := "res://assets/models/environment/props/sm_env_prop_road_barrier.glb"

var _barrier_length: float = 28.0


func _init() -> void:
	length = 40.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)

	var barrier_center_z: float = -length * 0.5
	# Collision stays a simple continuous wall; the repeated imported barriers
	# provide the readable feet, bevels and reflective faces.
	var barrier_collision := _box("ConstructionBarrierCollision", Vector3(1.05, 0.9, _barrier_length), Vector3(2.5, 0.45, barrier_center_z), CONCRETE, true)
	_hide_box_visual(barrier_collision)
	var barrier_z: float = barrier_center_z + _barrier_length * 0.5 - 1.8
	var barrier_index := 0
	while barrier_z > barrier_center_z - _barrier_length * 0.5 + 1.0:
		_model("ConstructionBarrier%d" % barrier_index, BARRIER_MODEL, Vector3(2.5, 0.0, barrier_z), PI * 0.5)
		barrier_z -= 3.6
		barrier_index += 1

	var barrier_start_z: float = barrier_center_z + _barrier_length * 0.5
	var barrier_end_z: float = barrier_center_z - _barrier_length * 0.5
	var cone_z: float = barrier_start_z - 1.5
	var index: int = 0
	while cone_z > barrier_end_z:
		var cone_collision := _box("ConstructionConeCollision" + str(index), Vector3(0.42, 0.65, 0.42), Vector3(1.65, 0.325, cone_z), CONE, true)
		_hide_box_visual(cone_collision)
		_model("ConstructionCone" + str(index), CONE_MODEL, Vector3(1.65, 0.0, cone_z), 0.0, 0.92)
		cone_z -= 3.0
		index += 1
