extends SceneTree
## S-311.72, S-305: sixteen independently buildable low-poly accessories have stable IDs,
## recognizable signature geometry and explicit attachment metadata.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_accessory_catalog.gd")
const Library := preload("res://scripts/gameplay/player/gel/gel_accessory_library.gd")

const EXPECTED_IDS: Array[StringName] = [
	&"cap", &"hard_hat", &"glasses", &"scarf", &"backpack", &"bow_tie", &"crown",
	&"headphones", &"fake_moustache", &"party_hat", &"snorkel", &"flower", &"monocle",
	&"wristwatch", &"fairy_wings", &"reflective_vest",
]
const VALID_ANCHORS: Array[StringName] = [&"head", &"face", &"neck", &"back", &"wrist", &"torso"]
const VALID_HAT_RULES: Array[StringName] = [&"none", &"compress", &"hide"]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Catalog.ids() == EXPECTED_IDS, "the catalog has exactly sixteen accessories in stable order")
	_expect(Catalog.accessory(&"invalid")[&"id"] == Catalog.DEFAULT_ID, "invalid IDs fall back to cap")
	var ids: Dictionary = {}
	var signatures: Dictionary = {}
	for definition: Dictionary in Catalog.ACCESSORIES:
		var accessory_id: StringName = definition[&"id"]
		var signature: StringName = definition[&"signature"]
		_expect(not ids.has(accessory_id), "%s has a unique stable ID" % accessory_id)
		_expect(not signatures.has(signature), "%s has unique signature geometry" % accessory_id)
		_expect(definition[&"anchor"] in VALID_ANCHORS, "%s uses a supported body anchor" % accessory_id)
		_expect(definition[&"hat_rule"] in VALID_HAT_RULES, "%s declares a valid hair rule" % accessory_id)
		_expect(_color_is_finite(definition[&"color"]) and _color_is_finite(definition[&"accent"]),
			"%s has finite authored colours" % accessory_id)
		ids[accessory_id] = true
		signatures[signature] = true
		_check_accessory(definition)
	_check_vest()
	if _failures == 0:
		print("PASS: sixteen distinct loose accessories are ready for gel attachment")
	quit(_failures)


## S-305: the high-vis vest is fluorescent, wears two silver bands on the chest bone and opts into
## the torso shell fit (the rigid accessories do not).
func _check_vest() -> void:
	var vest: Node3D = Library.build_accessory(&"reflective_vest")
	var bands: int = 0
	var rigid_pieces: int = 0
	for child: Node in vest.get_children():
		var piece := child as MeshInstance3D
		if piece == null:
			continue
		_expect(piece.get_meta(&"gel_accessory_bone") == &"chest", "vest pieces hang on the chest bone")
		_expect(piece.get_meta(&"gel_costume_bone", &"") == &"chest" and bool(piece.get_meta(&"gel_fit_shell", false)),
			"vest pieces opt into the torso shell fit")
		var material := piece.material_override as StandardMaterial3D
		if material.metallic > 0.3:
			bands += 1
			_expect(material.albedo_color.v > 0.7 and material.albedo_color.s < 0.15, "vest bands read as silver")
		elif piece.mesh is BoxMesh and (piece.mesh as BoxMesh).size.y > 0.5:
			_expect(material.albedo_color.g > 0.9 and material.albedo_color.b < 0.4,
				"vest panels are fluorescent yellow")
	var rigid: Node3D = Library.build_accessory(&"backpack")
	for child: Node in rigid.get_children():
		if child.has_meta(&"gel_fit_shell"):
			rigid_pieces += 1
	_expect(bands >= 6, "the vest carries two bands on each front panel and the back (got %d)" % bands)
	_expect(rigid_pieces == 0, "rigid accessories do not opt into the shell fit")
	vest.free()
	rigid.free()


func _check_accessory(definition: Dictionary) -> void:
	var accessory_id: StringName = definition[&"id"]
	var root_node: Node3D = Library.build_accessory(accessory_id)
	root.add_child(root_node)
	var triangles: int = Library.triangle_count(root_node)
	_expect(root_node.is_in_group(&"gel_accessory"), "%s is discoverable as gel_accessory" % accessory_id)
	_expect(root_node.get_meta(&"gel_accessory_id") == accessory_id, "%s keeps its catalog ID" % accessory_id)
	_expect(root_node.get_meta(&"gel_accessory_anchor") == definition[&"anchor"],
		"%s keeps its attachment anchor" % accessory_id)
	_expect(root_node.get_meta(&"gel_accessory_bone") == definition[&"bone"],
		"%s keeps its intended bone" % accessory_id)
	_expect(root_node.get_meta(&"gel_hat_rule") == definition[&"hat_rule"],
		"%s keeps its hair compatibility rule" % accessory_id)
	_expect(root_node.find_child(String(definition[&"signature"]), true, false) != null,
		"%s contains its recognizable %s" % [accessory_id, definition[&"signature"]])
	_expect(triangles > 0 and triangles <= Library.TRIANGLE_LIMIT,
		"%s stays within %d triangles (got %d)" % [accessory_id, Library.TRIANGLE_LIMIT, triangles])
	_check_geometry(root_node, accessory_id)
	root_node.free()


func _check_geometry(node: Node, label: String) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var piece := child as MeshInstance3D
			_expect(piece.mesh != null and piece.transform.is_finite(), "%s has finite visible pieces" % label)
			_expect(piece.has_meta(&"gel_accessory_bone"), "%s pieces retain their intended bone" % label)
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
