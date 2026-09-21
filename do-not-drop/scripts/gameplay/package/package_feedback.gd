extends Node
## A presentation-only child: changing color never changes simulation state.
##
## The confetti burst on ruin is deliberately loud (docs/requerimientos-tecnicos.md
## 3.4, "momentos clipeables") -- package_ruined is already relayed to every peer
## (see package.gd's _emit_event), so each client's own local burst fires in lockstep
## with everyone else's without this script needing to know or care about the network.

const CONFETTI_COLORS: Array[Color] = [Color("f47e6d"), Color("f4c562"), Color("83e2ba"), Color("6db3d6")]
const CONFETTI_COUNT: int = 28
const CONFETTI_LIFETIME: float = 1.1

@export var box_mesh_path: NodePath = ^"../Box"
@export var status_label_path: NodePath = ^"../Status"

var _material: StandardMaterial3D
var _package_id: StringName
var _label: Label3D


func _ready() -> void:
	_package_id = get_parent().get("package_id")
	var box: MeshInstance3D = get_node(box_mesh_path) as MeshInstance3D
	_material = StandardMaterial3D.new()
	_material.roughness = 0.95
	box.material_override = _material
	_label = get_node(status_label_path) as Label3D
	_set_state(0)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("package_state_changed", _on_package_state_changed)
		bus.connect("package_ruined", _on_package_ruined)


func _on_package_state_changed(id: StringName, new_state: int) -> void:
	if id == _package_id:
		_set_state(new_state)


func _on_package_ruined(id: StringName, _cause: String) -> void:
	if id == _package_id:
		_burst_confetti()


## A handful of tiny colored cubes flung outward and pulled down by gravity --
## no particle texture/material asset needed, matches the placeholder-box style
## everything else in the prototype already uses.
func _burst_confetti() -> void:
	var origin: Vector3 = (get_parent() as Node3D).global_position
	var particles := GPUParticles3D.new()
	particles.top_level = true
	particles.emitting = false
	particles.one_shot = true
	particles.amount = CONFETTI_COUNT
	particles.lifetime = CONFETTI_LIFETIME
	particles.explosiveness = 1.0
	particles.draw_pass_1 = BoxMesh.new()
	(particles.draw_pass_1 as BoxMesh).size = Vector3.ONE * 0.09

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 1.8
	process_material.initial_velocity_max = 4.2
	process_material.gravity = Vector3(0.0, -9.0, 0.0)
	process_material.color = CONFETTI_COLORS[randi() % CONFETTI_COLORS.size()]
	particles.process_material = process_material

	# current_scene is null in headless test trees that never loaded a scene --
	# falls back to the tree root so this still works there, not just in-game.
	var container: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	container.add_child(particles)
	particles.global_position = origin
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _set_state(new_state: int) -> void:
	match new_state:
		0:
			_material.albedo_color = Color("e8be77")
			_label.text = "FRÁGIL\n↑ ↑"
		1:
			_material.albedo_color = Color("ff883d")
			_label.text = "¡CUIDADO!\n↑ ↑"
		2:
			_material.albedo_color = Color("9a4547")
			_label.text = "ROTO\n× ×"
