extends Area3D
class_name AcousticZone
## A volume with its own acoustics (tareas de Nacho N-402): TunnelSegment puts
## one along its bore. AcousticSpace asks every node of the "acoustic_space"
## group whether it covers the listener's camera, and switches on the reverb
## for `acoustic_space` while one does. The box is `size`, centred on this
## node; it isn't monitored (no physics cost): the question is a point test.

@export var size: Vector3 = Vector3.ONE
@export var acoustic_space: StringName = &"tunnel"


func _ready() -> void:
	add_to_group(&"acoustic_space")
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)


func covers(world_point: Vector3) -> bool:
	var local: Vector3 = to_local(world_point)
	return absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5 and absf(local.z) <= size.z * 0.5
