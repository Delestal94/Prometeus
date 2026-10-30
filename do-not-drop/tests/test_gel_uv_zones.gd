extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_uv_zones.gd
## S-311.16: what the player sees does not stretch with any morph. UV0 is the same
## for every blend shape (glTF morphs cannot move it), every LOD carries the six
## requested zones plus the neck in its vertex colours, gel skins are sampled from
## the deformed model-space position (not UV0), and the face patch rebuilt on the
## real head_shape morph keeps its drawing within 15 % of one uniform scale while
## staying on the deformed shell.
## UV0 overlap is checked independently by art/gel_character/validate_glb.py.

const BASE: String = "res://assets/models/characters/gel/gel_body_lod%d.glb"
const GelFaceScript := preload("res://scripts/gameplay/player/gel/gel_face.gd")
const SHADERS: Array[String] = [
	"res://shaders/gel/gel_body.gdshader",
	"res://shaders/gel/gel_body_opaque.gdshader",
]
## Blender zones() colours (art/gel_character/build_gel_body.py).
const ZONES: Dictionary = {
	&"head": Color(0, 0, 1), &"neck": Color(0, 1, 1), &"torso": Color(1, 0, 1),
	&"arm": Color(1, 0, 0), &"hand": Color(1, 1, 1), &"leg": Color(0, 1, 0),
	&"foot": Color(1, 1, 0),
}
const MAX_STRETCH: float = 0.15
const FACE_STEPS: int = 16

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for lod: int in range(3):
		_check_lod(lod)
	_check_shaders()
	_check_face()
	await _check_player_face()
	if _failures == 0:
		print("PASS: UV0, zone mask, skins and faces hold under every morph")
	quit(_failures)


func _check_lod(lod: int) -> void:
	var scene: PackedScene = load(BASE % lod)
	var model: Node = scene.instantiate()
	var mesh_instance := _find_mesh(model)
	var mesh := mesh_instance.mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var shapes: Array = mesh.surface_get_blend_shape_arrays(0)
	var moved_uv: int = 0
	for shape: Array in shapes:
		var shape_uv: Variant = shape[Mesh.ARRAY_TEX_UV]
		if shape_uv is PackedVector2Array and (shape_uv as PackedVector2Array).size() > 0 \
				and shape_uv != uv:
			moved_uv += 1
	_expect(shapes.size() == 11 and moved_uv == 0,
		"LOD%d keeps UV0 fixed under all %d morphs (%d move it)" % [lod, shapes.size(), moved_uv])
	var centres: Dictionary = {}
	var counts: Dictionary = {}
	var unknown: int = 0
	for index: int in vertices.size():
		var zone: StringName = _zone(colours[index])
		if zone == &"":
			unknown += 1
			continue
		var point: Vector3 = vertices[index]
		centres[zone] = centres.get(zone, Vector3.ZERO) + Vector3(absf(point.x), point.y, point.z)
		counts[zone] = int(counts.get(zone, 0)) + 1
	_expect(unknown == 0 and counts.size() == ZONES.size(),
		"LOD%d paints every vertex with one of the %d zones (%d unknown, %d zones)" % [
			lod, ZONES.size(), unknown, counts.size()])
	if counts.size() != ZONES.size():
		model.free()
		return
	for zone: StringName in centres:
		centres[zone] /= float(counts[zone])
	_expect(centres[&"head"].y > centres[&"neck"].y and centres[&"neck"].y > centres[&"torso"].y
		and centres[&"torso"].y > centres[&"leg"].y and centres[&"leg"].y > centres[&"foot"].y,
		"LOD%d stacks head, neck, torso, legs and feet from top to bottom" % lod)
	_expect(centres[&"hand"].x > centres[&"arm"].x and centres[&"arm"].x > centres[&"torso"].x,
		"LOD%d places arms outside the torso and hands at their ends" % lod)
	model.free()


func _check_shaders() -> void:
	var uv_word := RegEx.create_from_string("\\bUV\\b")
	for path: String in SHADERS:
		var code: String = RegEx.create_from_string("//[^\\n]*").sub((load(path) as Shader).code, "", true)
		var uv_reads: int = uv_word.search_all(code).size()
		_expect(code.contains("model_position = VERTEX;") and uv_reads == 1
			and code.contains("texture(thickness_map, UV)"),
			"%s samples skins from the deformed model position; UV0 only reads thickness" % path)


## Each patch triangle is compared with the same triangle at the rest head: the
## two principal stretches may grow together (head size and area), but their
## ratio is the visible distortion of the drawing.
func _check_face() -> void:
	var rest: PackedVector3Array = _patch(Vector3.ONE)
	for head_shape: float in [-1.0, -0.5, 0.5, 1.0]:
		var axes: Vector3 = GelFaceScript.head_shape_axes(head_shape)
		var deformed: PackedVector3Array = _patch(axes)
		var worst: float = 0.0
		for row: int in FACE_STEPS:
			for column: int in FACE_STEPS:
				var a: int = row * (FACE_STEPS + 1) + column
				var below: int = a + FACE_STEPS + 1
				for triangle: Array in [[a, a + 1, below], [a + 1, below + 1, below]]:
					worst = maxf(worst, _anisotropy(rest, deformed, triangle))
		_expect(worst <= MAX_STRETCH,
			"head_shape %.1f distorts the face drawing by %.1f %% (limit 15 %%)" % [head_shape, worst * 100.0])
		var centre: Vector3 = GelFaceScript.face_model_point(Vector2(0.5, 0.5), GelFaceScript.Mode.SURFACE, axes)
		var shell: float = _shell_distance(centre, axes)
		print("face head_shape %.1f: max distortion %.2f %%, centre shell %.4f" % [head_shape, worst * 100.0, shell])
		_expect(shell > 1.0 and shell < 1.03,
			"head_shape %.1f keeps the face on the deformed shell (%.4f)" % [head_shape, shell])


## The real player builds its face after the body: it must still pick up the
## current proportions and every later edit.
func _check_player_face() -> void:
	var player: Node = (load("res://scenes/gameplay/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	var state := player.get_node(^"GelProportions") as PlayerGelProportionSync
	var face: GelFace = _find_face(player)
	_expect(face != null and face.head_axes().is_equal_approx(
		GelFaceScript.head_shape_axes(state.proportions.head_shape)),
		"the player's face starts on the current head shape")
	state.proportions.head_shape = 1.0
	state.proportions.head_size = 1.2
	state.proportions_changed.emit(state.proportions)
	var eyes := face.get_node_or_null(^"Eyes") as MeshInstance3D if face != null else null
	_expect(face != null and face.head_axes().is_equal_approx(GelFaceScript.head_shape_axes(1.0))
		and eyes != null and eyes.scale.is_equal_approx(Vector3.ONE * 1.2),
		"a head-shape edit refits the player's face")
	player.queue_free()
	await process_frame


func _find_face(node: Node) -> GelFace:
	if node is GelFace:
		return node
	for child: Node in node.get_children():
		var found := _find_face(child)
		if found != null:
			return found
	return null


func _patch(axes: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for row: int in range(FACE_STEPS + 1):
		for column: int in range(FACE_STEPS + 1):
			var uv := Vector2(float(column) / FACE_STEPS, float(row) / FACE_STEPS)
			points.append(GelFaceScript.face_model_point(uv, GelFaceScript.Mode.SURFACE, axes))
	return points


func _anisotropy(rest: PackedVector3Array, deformed: PackedVector3Array, triangle: Array) -> float:
	var r1: Vector3 = rest[triangle[1]] - rest[triangle[0]]
	var r2: Vector3 = rest[triangle[2]] - rest[triangle[0]]
	var d1: Vector3 = deformed[triangle[1]] - deformed[triangle[0]]
	var d2: Vector3 = deformed[triangle[2]] - deformed[triangle[0]]
	# Right Cauchy-Green tensor C = G_rest^-1 G_deformed in the rest edge basis.
	var ga := r1.dot(r1)
	var gb := r1.dot(r2)
	var gc := r2.dot(r2)
	var ha := d1.dot(d1)
	var hb := d1.dot(d2)
	var hc := d2.dot(d2)
	var det := ga * gc - gb * gb
	var c11 := (gc * ha - gb * hb) / det
	var c12 := (gc * hb - gb * hc) / det
	var c21 := (ga * hb - gb * ha) / det
	var c22 := (ga * hc - gb * hb) / det
	var trace := c11 + c22
	var root := sqrt(maxf(trace * trace * 0.25 - (c11 * c22 - c12 * c21), 0.0))
	var high := trace * 0.5 + root
	var low := maxf(trace * 0.5 - root, 1e-9)
	return sqrt(high / low) - 1.0


func _shell_distance(point: Vector3, axes: Vector3) -> float:
	var centre: Vector3 = GelFaceScript.HEAD_SHAPE_CENTRE \
		+ (GelFaceScript.HEAD_CENTRE - GelFaceScript.HEAD_SHAPE_CENTRE) * axes
	var radii: Vector3 = GelFaceScript.HEAD_RADII * axes
	var relative: Vector3 = point - centre
	return Vector3(relative.x / radii.x, relative.y / radii.y, relative.z / radii.z).length()


func _zone(colour: Color) -> StringName:
	for zone: StringName in ZONES:
		var expected: Color = ZONES[zone]
		if absf(colour.r - expected.r) < 0.1 and absf(colour.g - expected.g) < 0.1 \
				and absf(colour.b - expected.b) < 0.1:
			return zone
	return &""


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
