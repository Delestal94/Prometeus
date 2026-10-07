class_name GelBodyShaper
extends RefCounted
## Applies GelBodyProportions to an imported gel model on demand (S-311.20).
##
## The original Skeleton3D rests are cached once, so repeated edits never
## accumulate deformation. This object is deliberately not a Node: it has no
## per-frame callback and only writes when apply() receives changed values.

const BONE_LENGTHS: Dictionary = {
	&"leg_length": [&"thigh.L", &"shin.L", &"thigh.R", &"shin.R"],
	&"arm_length": [&"upper_arm.L", &"forearm.L", &"upper_arm.R", &"forearm.R"],
	&"torso_length": [&"pelvis", &"chest"],
	&"neck_length": [&"neck"],
}

var application_count: int = 0

var _skeleton: Skeleton3D
var _bodies: Array[MeshInstance3D] = []
var _base_rests: Array[Transform3D] = []
var _last_values: Dictionary = {}


## Finds the rig and every skinned body below an imported gel model.
func setup(model: Node) -> bool:
	_skeleton = _find_skeleton(model)
	_bodies.clear()
	_collect_bodies(model)
	_base_rests.clear()
	_last_values.clear()
	if _skeleton == null or _bodies.is_empty():
		return false
	for bone_index: int in _skeleton.get_bone_count():
		_base_rests.append(_skeleton.get_bone_rest(bone_index))
	return true


## Returns true only when a new set of proportions was written to the model.
func apply(proportions: GelBodyProportions) -> bool:
	if _skeleton == null or _base_rests.size() != _skeleton.get_bone_count():
		return false
	var values: Dictionary = proportions.as_dictionary()
	if values == _last_values:
		return false
	_restore_rests()
	_apply_total_height(float(values[&"total_height"]))
	for parameter_name: StringName in BONE_LENGTHS:
		_apply_bone_length(BONE_LENGTHS[parameter_name], float(values[parameter_name]))
	_apply_head_size(float(values[&"head_size"]))
	_apply_morphs(values)
	_skeleton.force_update_all_bone_transforms()
	_last_values = values.duplicate(true)
	application_count += 1
	return true


func _restore_rests() -> void:
	for bone_index: int in _base_rests.size():
		_skeleton.set_bone_rest(bone_index, _base_rests[bone_index])


func _apply_total_height(factor: float) -> void:
	var pelvis: int = _skeleton.find_bone(&"pelvis")
	if pelvis < 0:
		return
	var rest: Transform3D = _skeleton.get_bone_rest(pelvis)
	rest.origin.y *= factor
	rest.basis = rest.basis.scaled_local(Vector3(1.0, factor, 1.0))
	_skeleton.set_bone_rest(pelvis, rest)


func _apply_bone_length(bone_names: Array, factor: float) -> void:
	for bone_name: StringName in bone_names:
		var bone_index: int = _skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var rest: Transform3D = _skeleton.get_bone_rest(bone_index)
		rest.basis = rest.basis.scaled_local(Vector3(1.0, factor, 1.0))
		_skeleton.set_bone_rest(bone_index, rest)


func _apply_head_size(factor: float) -> void:
	var head: int = _skeleton.find_bone(&"head")
	if head < 0:
		return
	var rest: Transform3D = _skeleton.get_bone_rest(head)
	rest.basis = rest.basis.scaled_local(Vector3.ONE * factor)
	_skeleton.set_bone_rest(head, rest)


func _apply_morphs(values: Dictionary) -> void:
	for definition: Dictionary in GelBodyProportions.parameter_definitions():
		if definition[&"driver"] != &"morph":
			continue
		var morph_name: StringName = definition[&"name"]
		for body: MeshInstance3D in _bodies:
			var morph_index: int = body.find_blend_shape_by_name(morph_name)
			if morph_index >= 0:
				body.set_blend_shape_value(morph_index, float(values[morph_name]))


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _collect_bodies(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_blend_shape_count() > 0:
		_bodies.append(node)
	for child: Node in node.get_children():
		_collect_bodies(child)
