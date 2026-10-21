extends SceneTree
## S-311.71: the twelve promised costumes have stable IDs, recognizable
## signature geometry and bounded low-poly shells ready for later rig transfer.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const Library := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")

const EXPECTED_IDS: Array[StringName] = [
	&"courier", &"mail_carrier", &"firefighter", &"astronaut", &"pirate", &"chef",
	&"dinosaur", &"bee", &"mummy", &"robot", &"superhero", &"skeleton",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Catalog.ids() == EXPECTED_IDS, "the catalog has exactly the twelve authored costumes in stable order")
	_expect(Catalog.costume(&"invalid")[&"id"] == Catalog.DEFAULT_ID, "invalid IDs fall back to courier")
	var ids: Dictionary = {}
	var signatures: Dictionary = {}
	for definition: Dictionary in Catalog.COSTUMES:
		var costume_id: StringName = definition[&"id"]
		var signature: StringName = definition[&"signature"]
		_expect(not ids.has(costume_id), "%s has a unique stable ID" % costume_id)
		_expect(not signatures.has(signature), "%s has unique signature geometry" % costume_id)
		_expect(_color_is_finite(definition[&"primary"])
			and _color_is_finite(definition[&"secondary"]), "%s has finite authored colours" % costume_id)
		ids[costume_id] = true
		signatures[signature] = true
		_check_costume(definition)
	if _failures == 0:
		print("PASS: twelve distinct low-poly gel costumes, including an interior skeleton")
	quit(_failures)


func _check_costume(definition: Dictionary) -> void:
	var costume_id: StringName = definition[&"id"]
	var root_node: Node3D = Library.build_costume(costume_id)
	root.add_child(root_node)
	var triangles: int = Library.triangle_count(root_node)
	_expect(root_node.is_in_group(&"gel_costume"), "%s is discoverable as gel_costume" % costume_id)
	_expect(root_node.get_meta(&"gel_costume_id") == costume_id, "%s keeps its catalog ID" % costume_id)
	_expect(root_node.get_meta(&"gel_hat_rule") == definition[&"hat_rule"], "%s keeps its hair rule" % costume_id)
	_expect(root_node.find_child(String(definition[&"signature"]), true, false) != null,
		"%s contains its recognizable %s" % [costume_id, definition[&"signature"]])
	_expect(triangles > 0 and triangles <= Library.TRIANGLE_LIMIT,
		"%s stays within %d triangles (got %d)" % [costume_id, Library.TRIANGLE_LIMIT, triangles])
	_check_geometry(root_node, costume_id)
	if costume_id == &"skeleton":
		_expect(bool(root_node.get_meta(&"gel_costume_interior", false)),
			"the skeleton declares that its bones render inside the gel")
		_expect(get_nodes_in_group(&"gel_costume_interior").size() >= 10,
			"the skeleton marks its visible internal bones")
	root_node.free()


func _check_geometry(node: Node, label: String) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var piece := child as MeshInstance3D
			_expect(piece.mesh != null and piece.transform.is_finite(), "%s has finite visible pieces" % label)
			_expect(piece.has_meta(&"gel_costume_bone"), "%s pieces retain their future rig target" % label)
			if piece.mesh != null:
				for surface: int in piece.mesh.get_surface_count():
					var vertices: PackedVector3Array = piece.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in vertices:
						_expect(vertex.is_finite(), "%s has finite mesh vertices" % label)
		_check_geometry(child, label)


func _color_is_finite(color: Color) -> bool:
	return is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
