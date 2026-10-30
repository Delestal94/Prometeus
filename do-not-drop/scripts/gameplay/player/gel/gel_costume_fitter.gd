class_name GelCostumeFitter
extends RefCounted
## Transfers the real body's morph contract and bone targets to procedural clothes (S-311.74).

const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")

var _pieces: Array[MeshInstance3D] = []
var _base_transforms: Dictionary = {}
var _last_values: Dictionary = {}
var _morph_names: Array[StringName] = []


func setup(costume: Node3D, gel_model: Node) -> bool:
	_pieces.clear()
	_base_transforms.clear()
	_last_values.clear()
	_morph_names.clear()
	var skeleton: Skeleton3D = _find_skeleton(gel_model)
	var body: MeshInstance3D = _find_morph_body(gel_model)
	if costume == null or skeleton == null or body == null:
		return false
	for definition: Dictionary in Proportions.parameter_definitions():
		if definition[&"driver"] == &"morph":
			var morph_name: StringName = definition[&"name"]
			if body.find_blend_shape_by_name(morph_name) < 0:
				return false
			_morph_names.append(morph_name)
	_collect_pieces(costume)
	if _pieces.is_empty():
		return false
	for piece: MeshInstance3D in _pieces:
		var bone: StringName = piece.get_meta(&"gel_costume_bone", &"")
		if skeleton.find_bone(bone) < 0:
			return false
		_base_transforms[piece] = piece.transform
		piece.set_meta(&"gel_costume_morphs", _morph_names.duplicate())
		piece.set_meta(&"gel_costume_weights", {bone: 1.0})
		piece.add_to_group(&"gel_clothing_piece", true)
		var material := piece.material_override as StandardMaterial3D
		if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			material.render_priority = 1
			piece.set_meta(&"gel_costume_opaque", true)
	return true


func apply(proportions: GelBodyProportions) -> bool:
	var values: Dictionary = proportions.as_dictionary()
	if values == _last_values or _pieces.is_empty():
		return false
	for piece: MeshInstance3D in _pieces:
		var base: Transform3D = _base_transforms[piece]
		var bone: StringName = piece.get_meta(&"gel_costume_bone")
		var factors: Vector3 = _scale_for(bone, values)
		var origin: Vector3 = _fit_origin(base.origin, bone, values)
		piece.transform = Transform3D(base.basis.scaled_local(factors), origin)
	_last_values = values.duplicate(true)
	return true


func morph_names() -> Array[StringName]:
	return _morph_names.duplicate()


func piece_count() -> int:
	return _pieces.size()


func _scale_for(bone: StringName, values: Dictionary) -> Vector3:
	var thickness: float = 1.0 + float(values[&"general_thickness"]) * 0.12
	var result := Vector3(thickness, float(values[&"total_height"]), thickness)
	if bone == &"head":
		return GelFace.head_shape_axes(float(values[&"head_shape"])) * float(values[&"head_size"])
	if bone == &"chest":
		result.x *= 1.0 + float(values[&"shoulders"]) * 0.14
		result.z *= 1.0 + float(values[&"chest"]) * 0.16 + float(values[&"belly"]) * 0.08
		result.y *= float(values[&"torso_length"])
	elif bone == &"pelvis":
		result.x *= 1.0 + float(values[&"hips"]) * 0.16
		result.z *= 1.0 + float(values[&"belly"]) * 0.16
	elif String(bone).begins_with("upper_arm"):
		var arm_width: float = 1.0 + float(values[&"arm_thickness"]) * 0.16
		result = Vector3(arm_width, float(values[&"arm_length"]), arm_width)
	elif String(bone).begins_with("thigh") or String(bone).begins_with("foot"):
		var leg_width: float = 1.0 + float(values[&"leg_thickness"]) * 0.16
		result = Vector3(leg_width, float(values[&"leg_length"]), leg_width)
		if String(bone).begins_with("foot"):
			result.z *= 1.0 + float(values[&"foot_size"]) * 0.16
	elif String(bone).begins_with("hand"):
		result = Vector3.ONE * (1.0 + float(values[&"hand_size"]) * 0.16)
	return result


func _fit_origin(origin: Vector3, bone: StringName, values: Dictionary) -> Vector3:
	var fitted := origin
	if bone == &"head":
		# The real head_shape morph scales about its centre, not the piece.
		var centre: Vector3 = GelFace.HEAD_SHAPE_CENTRE
		fitted = centre + (origin - centre) * GelFace.head_shape_axes(float(values[&"head_shape"]))
	fitted.y *= float(values[&"total_height"])
	if bone == &"head":
		fitted.x *= float(values[&"head_size"])
	elif bone == &"chest":
		fitted.x *= 1.0 + float(values[&"shoulders"]) * 0.10
	elif bone == &"pelvis":
		fitted.x *= 1.0 + float(values[&"hips"]) * 0.10
	elif String(bone).begins_with("upper_arm"):
		fitted.x *= float(values[&"arm_length"])
	elif String(bone).begins_with("thigh") or String(bone).begins_with("foot"):
		fitted.y *= float(values[&"leg_length"])
	return fitted


func _collect_pieces(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and child.has_meta(&"gel_costume_bone"):
			_pieces.append(child)
		_collect_pieces(child)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_morph_body(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_blend_shape_count() > 0:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_morph_body(child)
		if found != null:
			return found
	return null
