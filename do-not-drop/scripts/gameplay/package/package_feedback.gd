extends Node
## A presentation-only child: changing color never changes simulation state.

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


func _on_package_state_changed(id: StringName, new_state: int) -> void:
	if id == _package_id:
		_set_state(new_state)


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
