class_name GelFace
extends BoneAttachment3D
## Optional face layers fitted to the real gel head. Both authored candidates
## remain available for review; the surface variant is the selected default,
## while a newly created face has no visible eyes or mouth.

enum Mode { INTERNAL, SURFACE }

const Catalog = preload("res://scripts/core/face_catalog.gd")
const SELECTED_MODE: Mode = Mode.SURFACE
const DEFAULT_EYES: StringName = &"none"
const DEFAULT_MOUTH: StringName = &"none"
const HEAD_CENTRE := Vector3(0.0, 1.49, 0.0)
const HEAD_RADII := Vector3(0.245, 0.245, 0.225)
const INTERNAL_SCALE := Vector3(0.84, 0.84, 0.68)
const SURFACE_OFFSET: float = 0.0025
const HEAD_SHAPE_X: float = 0.12
const HEAD_SHAPE_Y: float = -0.10
const PATCH_STEPS: int = 16

var eyes_id: StringName = DEFAULT_EYES
var mouth_id: StringName = DEFAULT_MOUTH
var face_id: StringName = &"none"
var mode: Mode = SELECTED_MODE

var _eyes: MeshInstance3D
var _brows: MeshInstance3D
var _mouth: MeshInstance3D


func setup(model: Node3D, skeleton: Skeleton3D, layers: int, face_mode: Mode = SELECTED_MODE) -> bool:
	if skeleton == null or skeleton.find_bone(&"head") < 0:
		return false
	name = "GelFace"
	bone_name = &"head"
	mode = face_mode
	skeleton.add_child(self)
	var bone: int = skeleton.find_bone(bone_name)
	var head_rest: Transform3D = (
		model.global_transform.affine_inverse()
		* skeleton.global_transform
		* skeleton.get_bone_global_rest(bone)
	)
	var mesh: ArrayMesh = _curved_patch(head_rest.affine_inverse(), mode)
	_eyes = _layer("Eyes", mesh, layers)
	_brows = _layer("Brows", mesh, layers)
	_mouth = _layer("Mouth", mesh, layers)
	if face_id == &"":
		set_expression(eyes_id, mouth_id)
	else:
		set_face(face_id)
	return true


func set_expression(eyes: StringName, mouth: StringName) -> void:
	face_id = &""
	eyes_id = Catalog.valid_eyes(eyes)
	mouth_id = Catalog.valid_mouth(mouth)
	if _eyes == null:
		return
	(_eyes.material_override as StandardMaterial3D).albedo_texture = Catalog.texture("eyes", eyes_id)
	var brows: Texture2D = Catalog.texture("brows", eyes_id)
	(_brows.material_override as StandardMaterial3D).albedo_texture = brows
	(_mouth.material_override as StandardMaterial3D).albedo_texture = Catalog.texture("mouth", mouth_id)
	_eyes.visible = eyes_id != &"none"
	_brows.visible = brows != null
	_mouth.visible = mouth_id != &"none"


func set_face(face_name: StringName) -> void:
	var face: Dictionary = Catalog.gel_face(face_name)
	set_expression(face.eyes, face.mouth)
	self.face_id = face.id


func apply_proportions(proportions: Resource) -> void:
	if proportions == null:
		return
	var head_size: float = clampf(float(proportions.get(&"head_size")), 0.75, 1.25)
	var head_shape: float = clampf(float(proportions.get(&"head_shape")), -1.0, 1.0)
	var authored_scale := Vector3(
		1.0 + head_shape * HEAD_SHAPE_X,
		1.0 + head_shape * HEAD_SHAPE_Y,
		1.0
	)
	for visual: MeshInstance3D in [_eyes, _brows, _mouth]:
		if visual == null:
			continue
		visual.set_meta(&"gel_head_base_scale", authored_scale)
		visual.scale = authored_scale * head_size


func visible_layer_count() -> int:
	var count: int = 0
	for visual: MeshInstance3D in [_eyes, _brows, _mouth]:
		if visual != null and visual.visible:
			count += 1
	return count


static func face_model_point(uv: Vector2, face_mode: Mode) -> Vector3:
	var longitude: float = (0.5 - uv.x) * 1.55
	var latitude: float = (0.5 - uv.y) * 1.28
	var relative := Vector3(
		HEAD_RADII.x * sin(longitude) * cos(latitude),
		HEAD_RADII.y * sin(latitude),
		-HEAD_RADII.z * cos(longitude) * cos(latitude)
	)
	if face_mode == Mode.INTERNAL:
		relative *= INTERNAL_SCALE
	else:
		relative *= 1.0 + SURFACE_OFFSET / maxf(relative.length(), 0.0001)
	return HEAD_CENTRE + relative


static func ellipsoid_distance(point: Vector3) -> float:
	var relative: Vector3 = point - HEAD_CENTRE
	return Vector3(
		relative.x / HEAD_RADII.x,
		relative.y / HEAD_RADII.y,
		relative.z / HEAD_RADII.z
	).length()


func _layer(label: String, mesh: ArrayMesh, layers: int) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.layers = layers
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.22
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.texture_repeat = false
	part.material_override = material
	add_child(part)
	return part


static func _curved_patch(to_bone: Transform3D, face_mode: Mode) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in range(PATCH_STEPS + 1):
		for column: int in range(PATCH_STEPS + 1):
			var uv := Vector2(float(column) / PATCH_STEPS, float(row) / PATCH_STEPS)
			surface.set_uv(uv)
			surface.add_vertex(to_bone * face_model_point(uv, face_mode))
	for row: int in range(PATCH_STEPS):
		for column: int in range(PATCH_STEPS):
			var start: int = row * (PATCH_STEPS + 1) + column
			for index: int in [
				start, start + PATCH_STEPS + 1, start + 1,
				start + 1, start + PATCH_STEPS + 1, start + PATCH_STEPS + 2,
			]:
				surface.add_index(index)
	surface.generate_normals()
	return surface.commit()
