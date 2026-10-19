class_name GelHairAttachment
extends BoneAttachment3D
## Mounts one library hairstyle on the real head and applies head/hat fitting (S-311.64).

enum HatRule { NONE, COMPRESS, HIDE }

const Library := preload("res://scripts/gameplay/player/gel/gel_hair_library.gd")
const Springs := preload("res://scripts/gameplay/player/gel/gel_hair_springs.gd")
const Catalog := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const HEAD_SHAPE_X: float = 0.12
const HEAD_SHAPE_Y: float = -0.10
const HAT_COMPRESSION: float = 0.60
const HAT_DROP: float = 0.07

var style_id: StringName = &"bald"
var hat_rule: HatRule = HatRule.NONE

var _hair: Node3D
var _springs: Node
var _fitted_scale: Vector3 = Vector3.ONE


func setup(skeleton: Skeleton3D, requested_style: StringName, layers: int = 1) -> bool:
	if skeleton == null or skeleton.find_bone(&"head") < 0:
		return false
	name = "GelHair"
	bone_name = &"head"
	style_id = Catalog.hairstyle(requested_style)[&"id"]
	skeleton.add_child(self)
	_hair = Library.build_hairstyle(style_id)
	add_child(_hair)
	_set_layers(_hair, layers)
	_springs = Springs.new()
	_hair.add_child(_springs)
	_springs.setup(_hair)
	_apply_hat_rule()
	return true


func apply_proportions(proportions: Resource) -> void:
	if proportions == null or _hair == null:
		return
	var head_size: float = clampf(float(proportions.get(&"head_size")), 0.75, 1.25)
	var head_shape: float = clampf(float(proportions.get(&"head_shape")), -1.0, 1.0)
	_fitted_scale = Vector3(
		1.0 + head_shape * HEAD_SHAPE_X,
		1.0 + head_shape * HEAD_SHAPE_Y,
		1.0
	) * head_size
	_hair.set_meta(&"gel_head_base_scale", _fitted_scale / head_size)
	_apply_hat_rule()


func set_hat_rule(rule: HatRule) -> void:
	hat_rule = rule
	_apply_hat_rule()


func hair_root() -> Node3D:
	return _hair


func springs() -> Node:
	return _springs


func _apply_hat_rule() -> void:
	if _hair == null:
		return
	_hair.visible = hat_rule != HatRule.HIDE
	_hair.position = Vector3(0.0, -HAT_DROP, 0.0) if hat_rule == HatRule.COMPRESS else Vector3.ZERO
	_hair.scale = _fitted_scale
	if hat_rule == HatRule.COMPRESS:
		_hair.scale.y *= HAT_COMPRESSION
	_hair.set_meta(&"gel_hat_rule", HatRule.keys()[hat_rule].to_lower())


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child: Node in node.get_children():
		_set_layers(child, layers)
