extends BoneAttachment3D
## Two curved alpha-cutout layers on the head. Works with GL Compatibility;
## no decals, per-player viewport, extra skeleton, or texture baking at runtime.
const Catalog = preload("res://scripts/presentation/face_catalog.gd")
var _eyes: MeshInstance3D
var _mouth: MeshInstance3D
var eyes_id: StringName = Catalog.DEFAULT_EYES
var mouth_id: StringName = Catalog.DEFAULT_MOUTH

## Blinks: the eye layer squashes onto the eye line for a moment, every few
## seconds and sometimes twice. Presentation only: each peer blinks on its
## own clock, so nothing is replicated. Eye-line heights (texture v) come
## from the SVGs; styles missing here (already-closed ^^ eyes, none) never blink.
const EYE_LINE_V: Dictionary = {
	&"classic": 0.416, &"wink": 0.416, &"lashes": 0.422, &"worried": 0.428, &"sleepy": 0.43,
}
const BLINK_CLOSE: float = 0.06
const BLINK_HOLD: float = 0.04
const BLINK_OPEN: float = 0.1
var _blink_time: float = -1.0
var _next_blink: float = 0.0
var _double_pending: bool = false
var _rng := RandomNumberGenerator.new()

func setup(model: Node3D, skeleton: Skeleton3D, layers: int) -> void:
	name = "CharacterFace"
	bone_name = "head"
	skeleton.add_child(self)
	var bone: int = skeleton.find_bone(bone_name)
	var head_rest: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(bone)
	var mesh: ArrayMesh = _curved_patch(head_rest.affine_inverse())
	_eyes = _layer("Eyes", mesh, layers)
	_mouth = _layer("Mouth", mesh, layers)
	_rng.randomize()
	_next_blink = _rng.randf_range(0.8, 4.0)
	set_expression(eyes_id, mouth_id)

func set_expression(eyes: StringName, mouth: StringName) -> void:
	eyes_id = Catalog.valid_eyes(eyes)
	mouth_id = Catalog.valid_mouth(mouth)
	if _eyes == null:
		return
	(_eyes.material_override as StandardMaterial3D).albedo_texture = Catalog.texture("eyes", eyes_id)
	(_mouth.material_override as StandardMaterial3D).albedo_texture = Catalog.texture("mouth", mouth_id)
	_eyes.visible = eyes_id != &"none"
	_mouth.visible = mouth_id != &"none"
	_blink_time = -1.0
	_squash_eyes(0.0)

## Starts a blink now (if the eyes can blink): also a reaction, e.g. a landing.
func blink() -> void:
	if _eyes != null and EYE_LINE_V.has(eyes_id) and _blink_time < 0.0:
		_blink_time = 0.0

func _process(delta: float) -> void:
	if _eyes == null or not _eyes.visible:
		return
	if _blink_time < 0.0:
		_next_blink -= delta
		if _next_blink <= 0.0:
			blink()
			_next_blink = 0.5  # styles that don't blink just check again later
		return
	_blink_time += delta
	var reopen: float = _blink_time - BLINK_CLOSE - BLINK_HOLD
	var closed: float = smoothstep(0.0, BLINK_CLOSE, _blink_time) if reopen < 0.0 else 1.0 - smoothstep(0.0, BLINK_OPEN, reopen)
	_squash_eyes(closed)
	if reopen >= BLINK_OPEN:
		_blink_time = -1.0
		_squash_eyes(0.0)
		# About one blink in five comes as a quick double.
		_double_pending = not _double_pending and _rng.randf() < 0.2
		_next_blink = 0.12 if _double_pending else _rng.randf_range(2.2, 5.5)

## 0 open .. 1 shut: squashes the eye texture onto its eye line. Done in UV,
## not by moving the curved patch, so the lids close along the head's surface.
func _squash_eyes(closed: float) -> void:
	var line: float = EYE_LINE_V.get(eyes_id, 0.416)
	var height: float = 1.0 - 0.92 * closed
	var material := _eyes.material_override as StandardMaterial3D
	material.uv1_scale = Vector3(1.0, 1.0 / height, 1.0)
	material.uv1_offset = Vector3(0.0, line - line / height, 0.0)

func _layer(label: String, mesh: ArrayMesh, layers: int) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.layers = layers
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Clamped: a blink stretches the eye texture's UVs past its (empty) edges.
	material.texture_repeat = false
	part.material_override = material
	add_child(part)
	return part

## Model-space point of the face patch for a texture coordinate.
static func _patch_point(uv: Vector2) -> Vector3:
	var longitude: float = (uv.x - 0.5) * 1.9
	var latitude: float = (0.5 - uv.y) * 1.5
	# Exported head: centre 1.445 m, ellipsoid radii .2875/.29/.2625.
	# A 3 mm offset clears the decimated skin without a floating sticker.
	return Vector3(0.2905 * sin(longitude) * cos(latitude),
		1.445 + 0.293 * sin(latitude), -0.2655 * cos(longitude) * cos(latitude))

static func _curved_patch(to_bone: Transform3D) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS: int = 20
	for row: int in range(STEPS + 1):
		for column: int in range(STEPS + 1):
			var uv := Vector2(float(column) / STEPS, float(row) / STEPS)
			surface.set_uv(uv)
			surface.add_vertex(to_bone * _patch_point(uv))
	for row: int in range(STEPS):
		for column: int in range(STEPS):
			var a: int = row * (STEPS + 1) + column
			for index: int in [a, a + STEPS + 1, a + 1, a + 1, a + STEPS + 1, a + STEPS + 2]:
				surface.add_index(index)
	surface.generate_normals()
	return surface.commit()
