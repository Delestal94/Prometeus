extends Camera3D
## Smooth, elevated rear view keeps both the cargo and upcoming obstacles visible.

@export var target_path: NodePath
@export var follow_distance: float = 9.5
@export var follow_height: float = 6.5
var target: Node3D
var initialized: bool = false


func _ready() -> void:
	target = get_node(target_path) as Node3D
	current = true
	fov = 65.0
	far = 400.0


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var rear: Vector3 = target.global_basis.z
	rear.y = 0.0
	rear = rear.normalized()
	var desired: Vector3 = target.global_position + rear * follow_distance + Vector3.UP * follow_height
	if not initialized:
		global_position = desired
		initialized = true
	else:
		global_position = global_position.lerp(desired, 1.0 - exp(-5.0 * delta))
	look_at(target.global_position - rear * 4.0 + Vector3.UP)
