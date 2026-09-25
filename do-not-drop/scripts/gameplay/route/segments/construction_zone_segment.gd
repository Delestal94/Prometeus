extends RouteSegment
class_name ConstructionZoneSegment
## A construction barrier eats one side of the road for most of the
## segment's length, narrowing the drivable lane instead of forcing a full
## weave like ChicaneSegment -- a sustained one-sided squeeze rather than an
## alternating dodge.
##
## Laid out like a real lane closure: a taper of cones leads from the road's
## edge in to the barrier line, the barriers stand board to board along it
## with their lamps lit, and a second taper leads back out. It used to be a
## line of barriers with gaps and a second line of cones in front at a
## different spacing, which read as props dropped at random (playtest
## 2026-09-25); and every cone was a solid post: clipping one stopped the
## truck dead, which is what the cones in the tapers are not -- they're
## knocked flying.

const CONE := Color("d8752b")
const CONE_MODEL := "res://assets/models/environment/props/sm_env_prop_traffic_cone.glb"
const BARRIER_MODEL := "res://assets/models/environment/props/sm_env_prop_road_barrier.glb"
const BARRIER_COLLISION_HEIGHT: float = 1.6
## The barrier's board is 2.2 m long (feet at +-0.85); a hand's width between two.
const BARRIER_PITCH: float = 2.3
const BARRIER_X: float = 2.5
## The road's edge on the closed side, where the tapers start and end.
const TAPER_EDGE_X: float = 5.4
const TAPER_LENGTH: float = 5.2
const TAPER_CONES: int = 4
const CONE_SCALE: float = 0.92
const CONE_MASS: float = 4.0
## The barrier's lamp, lit: amber, and bright enough to read at night.
const LAMP_GLOW := Color(1.0, 0.52, 0.1)

var _barrier_length: float = 28.0
var _cone_count: int = 0
var _lamp_material: StandardMaterial3D


func _init() -> void:
	length = 40.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)

	var barrier_center_z: float = -length * 0.5
	var start_z: float = barrier_center_z + _barrier_length * 0.5
	var end_z: float = barrier_center_z - _barrier_length * 0.5
	# Collision stays a simple continuous wall; the repeated imported barriers
	# provide the readable feet, bevels and reflective faces. It stands taller
	# than the barriers (BARRIER_COLLISION_HEIGHT): at the barriers' own 0.9 m
	# a truck that clipped the first cone got thrown onto the wall and sat on
	# it with its front wheels in the air -- 0.9 m is more than the wheels
	# reach below the chassis, and nothing ever got it down again (N-803).
	var barrier_collision := _box("ConstructionBarrierCollision", Vector3(1.05, BARRIER_COLLISION_HEIGHT, _barrier_length), Vector3(BARRIER_X, BARRIER_COLLISION_HEIGHT * 0.5, barrier_center_z), CONCRETE, true)
	_hide_box_visual(barrier_collision)
	var count: int = int(floor(_barrier_length / BARRIER_PITCH))
	var first_z: float = barrier_center_z + float(count - 1) * BARRIER_PITCH * 0.5
	for index: int in range(count):
		var barrier := _model("ConstructionBarrier%d" % index, BARRIER_MODEL, Vector3(BARRIER_X, 0.0, first_z - float(index) * BARRIER_PITCH), PI * 0.5)
		_light_lamp(barrier)

	# In from the edge, then back out to it.
	for step: int in range(TAPER_CONES):
		var k: float = float(step) / float(TAPER_CONES)
		_cone(Vector3(lerpf(TAPER_EDGE_X, BARRIER_X, k), 0.0, start_z + TAPER_LENGTH * (1.0 - k)))
	for step: int in range(1, TAPER_CONES + 1):
		var k: float = float(step) / float(TAPER_CONES)
		_cone(Vector3(lerpf(BARRIER_X, TAPER_EDGE_X, k), 0.0, end_z - TAPER_LENGTH * k * 0.75))


## A loose cone: a light body the truck knocks aside (and never pushes back
## on -- it collides with the truck's cargo shell, vehicle.gd SHELL_LAYER).
## Marked "animated" so the segment's mesh merge leaves its model alone.
func _cone(location: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "ConstructionCone%d" % _cone_count
	_cone_count += 1
	body.set_meta(&"animated", true)
	body.position = location
	body.collision_layer = 1
	body.collision_mask = 1 | 64
	body.mass = CONE_MASS
	body.can_sleep = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.62, 0.4) * CONE_SCALE
	shape.shape = box
	shape.position = Vector3.UP * (box.size.y * 0.5 + 0.01)
	body.add_child(shape)
	add_child(body)
	var model := (load(CONE_MODEL) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * CONE_SCALE
	body.add_child(model)
	body.tree_entered.connect(func() -> void: body.sleeping = true, CONNECT_ONE_SHOT)


## The barrier's amber lamp glows, so the closure reads at night too.
func _light_lamp(barrier: Node3D) -> void:
	if barrier == null:
		return
	for node: Node in barrier.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface)
			if source == null or source.resource_name != "lamp":
				continue
			if _lamp_material == null:
				_lamp_material = StandardMaterial3D.new()
				_lamp_material.albedo_color = LAMP_GLOW
				_lamp_material.emission_enabled = true
				_lamp_material.emission = LAMP_GLOW
				_lamp_material.emission_energy_multiplier = 0.6
			mesh.set_surface_override_material(surface, _lamp_material)
