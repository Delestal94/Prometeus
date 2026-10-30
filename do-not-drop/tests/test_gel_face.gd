extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_face.gd
## S-311.57: compare internal/surface faces and keep no face as the default.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const GelFaceScript := preload("res://scripts/gameplay/player/gel/gel_face.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Catalog := preload("res://scripts/core/face_catalog.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model: Node3D = GEL_SCENE.instantiate() as Node3D
	root.add_child(model)
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(model)
	var internal_face: BoneAttachment3D = GelFaceScript.new()
	var surface_face: BoneAttachment3D = GelFaceScript.new()
	_expect(internal_face.setup(model, skeleton, 1, GelFaceScript.Mode.INTERNAL),
		"the internal candidate attaches to the real gel head")
	_expect(surface_face.setup(model, skeleton, 1, GelFaceScript.Mode.SURFACE),
		"the surface candidate attaches to the real gel head")
	_expect(internal_face.visible_layer_count() == 0 and surface_face.visible_layer_count() == 0,
		"new gel characters have no face by default")
	_expect(internal_face.face_id == &"none" and surface_face.face_id == &"none",
		"the faceless default has its stable library ID")
	var preselected_face: BoneAttachment3D = GelFaceScript.new()
	preselected_face.set_expression(&"hearts", &"smile")
	_expect(preselected_face.setup(model, skeleton, 1) and preselected_face.eyes_id == &"hearts",
		"an expression chosen before setup is preserved")

	var centre_uv := Vector2(0.5, 0.5)
	var internal_point: Vector3 = GelFaceScript.face_model_point(centre_uv, GelFaceScript.Mode.INTERNAL)
	var surface_point: Vector3 = GelFaceScript.face_model_point(centre_uv, GelFaceScript.Mode.SURFACE)
	_expect(GelFaceScript.ellipsoid_distance(internal_point) < 0.9,
		"the floating candidate remains visibly inside the gel shell")
	_expect(GelFaceScript.ellipsoid_distance(surface_point) > 1.0,
		"the surface candidate clears the gel shell without z-fighting")
	_expect(GelFaceScript.SELECTED_MODE == GelFaceScript.Mode.SURFACE,
		"the reviewed surface candidate is the production selection")

	surface_face.set_expression(&"classic", &"smile")
	_expect(surface_face.visible_layer_count() == 3,
		"a chosen expression reveals its eyes, brows and mouth layers")
	var proportions: Resource = Proportions.new()
	proportions.set(&"head_size", 1.25)
	proportions.set(&"head_shape", 1.0)
	surface_face.apply_proportions(proportions)
	var eyes := surface_face.get_node(^"Eyes") as MeshInstance3D
	var narrow_mesh: Mesh = eyes.mesh
	_expect(eyes.scale.is_equal_approx(Vector3.ONE * 1.25),
		"the face follows head size without a non-uniform scale")
	proportions.set(&"head_shape", -1.0)
	surface_face.apply_proportions(proportions)
	_expect(eyes.mesh != narrow_mesh, "a head-shape edit rebuilds the face patch")
	var narrow_front: Vector3 = GelFaceScript.face_model_point(
		centre_uv, GelFaceScript.Mode.SURFACE, GelFaceScript.head_shape_axes(1.0))
	var wide_front: Vector3 = GelFaceScript.face_model_point(
		centre_uv, GelFaceScript.Mode.SURFACE, GelFaceScript.head_shape_axes(-1.0))
	_expect(wide_front.z < surface_point.z and surface_point.z < narrow_front.z,
		"the face sits deeper on the narrow (+1) head and further out on the wide (-1) head")
	_expect(surface_face.bone_name == &"head" and surface_face.get_parent() == skeleton,
		"the face follows head animation through its real bone")

	var expected_faces: Array[StringName] = [
		&"none", &"happy", &"worried", &"sleeping", &"angry", &"surprised",
		&"wink", &"crossed", &"tongue", &"crying", &"loved", &"knockout",
	]
	_expect(Catalog.GEL_FACES.size() == 12, "the gel library contains exactly twelve faces")
	for index: int in expected_faces.size():
		var face: Dictionary = Catalog.GEL_FACES[index]
		_expect(face.id == expected_faces[index], "gel face %d has the stable expected ID" % index)
		_expect(Catalog.texture("eyes", face.eyes) != null, "eyes exist for gel face %s" % face.id)
		_expect(Catalog.texture("mouth", face.mouth) != null, "mouth exists for gel face %s" % face.id)
		for locale: String in ["es", "en"]:
			TranslationServer.set_locale(locale)
			_expect(TranslationServer.translate(face.title) != face.title,
				"gel face %s has a %s title" % [face.id, locale])
		surface_face.set_face(face.id)
		_expect(surface_face.face_id == face.id, "gel face %s applies by ID" % face.id)
	surface_face.set_face(&"not_a_face")
	_expect(surface_face.face_id == &"none" and surface_face.visible_layer_count() == 0,
		"an unknown face safely falls back to the faceless default")

	internal_face.queue_free()
	surface_face.queue_free()
	preselected_face.queue_free()
	model.queue_free()
	if _failures == 0:
		print("PASS: gel face candidates are reproducible; surface selected, none by default")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
