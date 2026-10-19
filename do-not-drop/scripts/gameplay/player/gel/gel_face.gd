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
const EYE_LINE_V: Dictionary = {
	&"classic": 0.416, &"joyful": 0.416, &"worried": 0.416,
	&"wink": 0.416, &"lashes": 0.416, &"determined": 0.43,
	&"crying": 0.416, &"hearts": 0.416,
}
const BLINK_CLOSE: float = 0.06
const BLINK_HOLD: float = 0.04
const BLINK_OPEN: float = 0.10
const GAZE_LIMIT := Vector2(0.035, 0.025)
const GAZE_SMOOTHING: float = 10.0
const MOUTH_LINE_V: float = 0.66
const VOICE_THRESHOLD: float = 0.012
const VOICE_FULL_OPEN: float = 0.16
const MOUTH_STRETCH: float = 0.38
const MOUTH_SMOOTHING: float = 16.0

var eyes_id: StringName = DEFAULT_EYES
var mouth_id: StringName = DEFAULT_MOUTH
var face_id: StringName = &"none"
var mode: Mode = SELECTED_MODE

var _eyes: MeshInstance3D
var _brows: MeshInstance3D
var _mouth: MeshInstance3D
var _blink_time: float = -1.0
var _blink_amount: float = 0.0
var _next_blink: float = 0.0
var _double_pending: bool = false
var _has_gaze_target: bool = false
var _gaze_world_target: Vector3 = Vector3.ZERO
var _gaze_offset: Vector2 = Vector2.ZERO
var _voice_amplitude: float = 0.0
var _mouth_openness: float = 0.0
var _rng := RandomNumberGenerator.new()


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
	_rng.randomize()
	_next_blink = _rng.randf_range(0.8, 4.0)
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
	_reset_blink()
	_apply_eye_uv()
	_apply_mouth_uv()


func set_face(face_name: StringName) -> void:
	var face: Dictionary = Catalog.gel_face(face_name)
	set_expression(face.eyes, face.mouth)
	self.face_id = face.id


## Starts a blink immediately when the current eye style can close.
func blink() -> void:
	if _eyes != null and EYE_LINE_V.has(eyes_id) and _blink_time < 0.0:
		_blink_time = 0.0


func _reset_blink() -> void:
	_blink_time = -1.0
	_blink_amount = 0.0


## World-space point followed by the eyes. The player-facing controller picks
## a carried box first, otherwise the nearest crewmate.
func set_gaze_target(world_position: Vector3) -> void:
	_gaze_world_target = world_position
	_has_gaze_target = true


func clear_gaze_target() -> void:
	_has_gaze_target = false


## Recent voice RMS in 0..1, supplied by VoicePlayback.
func set_voice_amplitude(value: float) -> void:
	_voice_amplitude = clampf(value, 0.0, 1.0)


func gaze_offset() -> Vector2:
	return _gaze_offset


func mouth_openness() -> float:
	return _mouth_openness


func _process(delta: float) -> void:
	advance_animation(delta)


## Separate from _process so headless tests can advance exact intervals.
func advance_animation(delta: float) -> void:
	if _eyes == null:
		return
	_advance_blink(delta)
	_advance_gaze(delta)
	_advance_mouth(delta)
	_apply_eye_uv()
	_apply_mouth_uv()


func _advance_blink(delta: float) -> void:
	if _blink_time < 0.0:
		_next_blink -= delta
		if _next_blink <= 0.0:
			blink()
			_next_blink = 0.5
		return
	_blink_time += delta
	var reopen: float = _blink_time - BLINK_CLOSE - BLINK_HOLD
	_blink_amount = (
		smoothstep(0.0, BLINK_CLOSE, _blink_time)
		if reopen < 0.0
		else 1.0 - smoothstep(0.0, BLINK_OPEN, reopen)
	)
	if reopen >= BLINK_OPEN:
		_reset_blink()
		_double_pending = not _double_pending and _rng.randf() < 0.2
		_next_blink = 0.12 if _double_pending else _rng.randf_range(2.2, 5.5)


func _advance_gaze(delta: float) -> void:
	var desired := Vector2.ZERO
	if _has_gaze_target:
		var local: Vector3 = to_local(_gaze_world_target)
		var depth: float = -local.z
		if depth > 0.05:
			desired = Vector2(
				clampf(local.x / depth, -1.0, 1.0) * GAZE_LIMIT.x,
				clampf(local.y / depth, -1.0, 1.0) * GAZE_LIMIT.y
			)
	var weight: float = 1.0 - exp(-GAZE_SMOOTHING * maxf(delta, 0.0))
	_gaze_offset = _gaze_offset.lerp(desired, weight)


func _advance_mouth(delta: float) -> void:
	var target: float = inverse_lerp(VOICE_THRESHOLD, VOICE_FULL_OPEN, _voice_amplitude)
	var weight: float = 1.0 - exp(-MOUTH_SMOOTHING * maxf(delta, 0.0))
	_mouth_openness = lerpf(_mouth_openness, clampf(target, 0.0, 1.0), weight)


func _apply_eye_uv() -> void:
	if _eyes == null:
		return
	var height: float = 1.0 - 0.92 * _blink_amount
	var line: float = float(EYE_LINE_V.get(eyes_id, 0.416))
	var material := _eyes.material_override as StandardMaterial3D
	material.uv1_scale = Vector3(1.0, 1.0 / height, 1.0)
	material.uv1_offset = Vector3(
		_gaze_offset.x,
		line - line / height + _gaze_offset.y,
		0.0
	)


func _apply_mouth_uv() -> void:
	if _mouth == null:
		return
	var height: float = 1.0 + MOUTH_STRETCH * _mouth_openness
	var material := _mouth.material_override as StandardMaterial3D
	material.uv1_scale = Vector3(1.0, 1.0 / height, 1.0)
	material.uv1_offset = Vector3(0.0, MOUTH_LINE_V - MOUTH_LINE_V / height, 0.0)


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
