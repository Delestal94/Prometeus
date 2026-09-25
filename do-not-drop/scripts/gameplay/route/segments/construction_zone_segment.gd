extends RouteSegment
class_name ConstructionZoneSegment
## A construction barrier eats one side of the road for most of the
## segment's length, narrowing the drivable lane instead of forcing a full
## weave like ChicaneSegment -- a sustained one-sided squeeze rather than an
## alternating dodge.

const CONE := Color("d8752b")
const CONE_MODEL := "res://assets/models/environment/props/sm_env_prop_traffic_cone.glb"
const BARRIER_MODEL := "res://assets/models/environment/props/sm_env_prop_road_barrier.glb"
const BARRIER_COLLISION_HEIGHT: float = 1.6
const CONE_MASS: float = 4.0

var _barrier_length: float = 28.0


func _init() -> void:
	length = 40.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)

	var barrier_center_z: float = -length * 0.5
	# Collision stays a simple continuous wall; the repeated imported barriers
	# provide the readable feet, bevels and reflective faces. It stands taller
	# than the barriers (BARRIER_COLLISION_HEIGHT): at the barriers' own 0.9 m
	# a truck that clipped the first cone got thrown onto the wall and sat on
	# it with its front wheels in the air -- 0.9 m is more than the wheels
	# reach below the chassis, and nothing ever got it down again (N-803).
	var barrier_collision := _box("ConstructionBarrierCollision", Vector3(1.05, BARRIER_COLLISION_HEIGHT, _barrier_length), Vector3(2.5, BARRIER_COLLISION_HEIGHT * 0.5, barrier_center_z), CONCRETE, true)
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
		_cone(index, Vector3(1.65, 0.0, cone_z))
		cone_z -= 3.0
		index += 1


## A cone the truck bats aside, not a 0.65 m post: static, it was taller than
## the truck's ground clearance and a truck that clipped one could end up
## sitting on it (N-803). Moved onto the terrain as a whole (the "animated"
## meta, route_terrain.gd conform_geometry()), asleep until something hits it.
func _cone(index: int, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "ConstructionCone%d" % index
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1 | 2
	body.mass = CONE_MASS
	body.can_sleep = true
	body.set_meta(&"animated", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.42, 0.62, 0.42)
	shape.shape = box
	shape.position = Vector3(0.0, 0.34, 0.0)
	body.add_child(shape)
	var scene := load(CONE_MODEL) as PackedScene
	if scene != null:
		var model := scene.instantiate() as Node3D
		model.name = "Model"
		model.scale = Vector3.ONE * 0.92
		body.add_child(model)
	add_child(body)
	body.tree_entered.connect(func() -> void: body.sleeping = true, CONNECT_ONE_SHOT)
