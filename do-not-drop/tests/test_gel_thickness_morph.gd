extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_thickness_morph.gd
## S-311.15: smooth normals and the baked thickness map follow the general-thickness morph.

const GEL_SCENE := preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GEL_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body.tres")
const OPAQUE_MATERIAL: ShaderMaterial = preload("res://shaders/gel/gel_body_opaque.tres")
const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const SkinCatalog := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const SkinApplier := preload("res://scripts/gameplay/player/gel/gel_skin_applier.gd")
const REPORT := "res://../art/gel_character/review_bloque_b/s311_15_thickness_morph_final.json"

var _failures: int = 0


func _init() -> void:
	var model := GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	var mesh := _find_mesh(model)
	_expect(mesh != null, "the shipping LOD0 contains its skinned gel mesh")
	if mesh != null:
		mesh.material_override = GEL_MATERIAL
		_check_smooth_normals(mesh.mesh)
		_check_morph_shader_contract(model, mesh)
	_check_report()
	_check_shader(GEL_MATERIAL.shader, "transparent")
	_check_shader(OPAQUE_MATERIAL.shader, "opaque")
	model.free()
	if _failures == 0:
		print("PASS: smooth normals and morph-corrected thickness stay coherent at both extremes")
	quit(_failures)


func _check_morph_shader_contract(model: Node3D, mesh: MeshInstance3D) -> void:
	var shaper := Shaper.new()
	_expect(shaper.setup(model), "the shipping gel model accepts proportion shaping")
	var proportions := Proportions.new()
	for weight: float in [-1.0, 0.0, 1.0]:
		proportions.general_thickness = weight
		_expect(shaper.apply(proportions), "general thickness %+.1f is applied" % weight)
		var surface := mesh.get_instance_shader_parameter(&"gel_skin_surface") as Vector4
		_expect(is_equal_approx(_unpack_weight(surface.z), weight),
			"general thickness %+.1f reaches the shader carrier" % weight)
		var morph_index := mesh.find_blend_shape_by_name(&"general_thickness")
		_expect(morph_index >= 0 and is_equal_approx(mesh.get_blend_shape_value(morph_index), weight),
			"general thickness %+.1f reaches the matching morph" % weight)

	proportions.general_thickness = -1.0
	shaper.apply(proportions)
	var definition: Resource = SkinCatalog.skin(&"fruit_bits")
	_expect(SkinApplier.apply(mesh, definition), "a skin applies after the thickness morph")
	var skinned_surface := mesh.get_instance_shader_parameter(&"gel_skin_surface") as Vector4
	_expect(roundi(skinned_surface.z) == int(definition.get(&"interior_mode")),
		"the packed value preserves the selected integer skin mode")
	_expect(is_equal_approx(_unpack_weight(skinned_surface.z), -1.0),
		"changing skin preserves the negative general-thickness extreme")


func _check_smooth_normals(mesh: ArrayMesh) -> void:
	var vertices_checked: int = 0
	var coincident_normals: Dictionary = {}
	var worst_dot: float = 1.0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		_expect(normals.size() == vertices.size(),
			"surface %d has one authored normal per imported vertex" % surface)
		for index: int in mini(vertices.size(), normals.size()):
			var normal: Vector3 = normals[index]
			_expect(normal.is_finite() and absf(normal.length() - 1.0) < 0.001,
				"surface %d vertex %d has a finite unit normal" % [surface, index])
			var position: Vector3 = vertices[index]
			var key := Vector3i(
				roundi(position.x * 100_000.0),
				roundi(position.y * 100_000.0),
				roundi(position.z * 100_000.0)
			)
			if coincident_normals.has(key):
				worst_dot = minf(worst_dot, normal.dot(coincident_normals[key]))
			else:
				coincident_normals[key] = normal
			vertices_checked += 1
	_expect(vertices_checked > 0, "the runtime normal gate inspected the imported LOD0")
	_expect(worst_dot > 0.995,
		"coincident vertices across UV seams keep matching smooth normals (worst dot %.6f)" % worst_dot)


func _check_shader(shader: Shader, label: String) -> void:
	var code: String = shader.code
	_expect("float general_thickness_weight()" in code,
		"the %s shader decodes the packed morph weight" % label)
	_expect("1.0 + general_thickness_weight() * 0.21" in code,
		"the %s shader corrects the base thickness at both morph extremes" % label)
	_expect(code.count("instance uniform") == 16,
		"the %s shader stays within the sixteen instance-uniform budget" % label)


func _check_report() -> void:
	var file := FileAccess.open(REPORT, FileAccess.READ)
	_expect(file != null, "the final S-311.15 evidence report is readable")
	if file == null:
		return
	var report: Dictionary = JSON.parse_string(file.get_as_text())
	var errors: Dictionary = report.get(&"relative_mean_error", {})
	var limit: float = errors.get(&"acceptance_max", 0.0)
	_expect(report.get(&"task") == "S-311.15" and bool(report.get(&"decision_complete", false)),
		"the evidence report closes the intended task")
	_expect(float(errors.get(&"minus_one", INF)) < limit
		and float(errors.get(&"plus_one", INF)) < limit,
		"the linear shader correction matches measured extreme means within one percent")


func _unpack_weight(packed_mode: float) -> float:
	return clampf(
		(packed_mode - roundf(packed_mode)) / Shaper.THICKNESS_MODE_PACK_SCALE,
		-1.0,
		1.0
	)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_blend_shape_count() > 0:
		return node
	for child: Node in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
