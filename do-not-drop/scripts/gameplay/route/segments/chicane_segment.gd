extends RouteSegment
class_name ChicaneSegment
## Two offset concrete blocks force a left-then-right weave -- tests the
## Balance trap and general handling under lateral movement.
##
## The blocks are jersey barriers with a striped bollard at the end by the
## gap (N-133, assets/tools/build_route_pieces.py); what you hit is still the
## solid box _block() always made, BLOCK_COLLISION_HEIGHT tall.

const BARRIER_MODEL: String = "res://assets/models/environment/route/sm_env_route_chicane_barrier.glb"
const BLOCK_SIZE := Vector3(4.4, 0.8, 1.0)


func _init() -> void:
	length = 40.0


func _build() -> void:
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	# The model's bollard end (+X) points at the gap: the right block turns round.
	_barrier("ChicaneLeft", Vector3(-3.8, 0.0, -length * 0.35), 0.0)
	_barrier("ChicaneRight", Vector3(3.8, 0.0, -length * 0.65), PI)


func _barrier(node_name: String, base: Vector3, rotation_y: float) -> void:
	var solid: Node3D = _box(node_name, Vector3(BLOCK_SIZE.x, BLOCK_COLLISION_HEIGHT, BLOCK_SIZE.z),
			base + Vector3.UP * BLOCK_COLLISION_HEIGHT * 0.5, CONCRETE, true)
	_hide_box_visual(solid)
	_art(node_name + "Visual", BARRIER_MODEL, base, rotation_y)
