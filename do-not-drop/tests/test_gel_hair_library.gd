extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_hair_library.gd
## Guards the standalone S-311.62 library before attachment and spring bones are added.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const Library := preload("res://scripts/gameplay/player/gel/gel_hair_library.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(Catalog.HAIRSTYLES.size() == 10, "the catalog has exactly ten hairstyles")
	_expect(Catalog.EYEBROWS.size() == 5, "the catalog has exactly five eyebrow styles")
	_expect(Catalog.MOUSTACHES.size() == 5, "the catalog has exactly five moustache styles")
	_expect(Catalog.HAIRSTYLES[0][&"id"] == &"bald", "bald is the default hairstyle")
	_expect(Catalog.hairstyle(&"invalid")[&"id"] == &"bald", "invalid hair falls back to bald")

	var ids: Dictionary = {}
	var colors: Dictionary = {}
	for definition: Dictionary in Catalog.HAIRSTYLES:
		var style_id: StringName = definition[&"id"]
		var color: Color = definition[&"color"]
		_expect(not ids.has(style_id), "%s has a unique stable ID" % style_id)
		_expect(not colors.has(color.to_html(false)), "%s has its own colour" % style_id)
		ids[style_id] = true
		colors[color.to_html(false)] = true
		var hair: Node3D = Library.build_hairstyle(style_id)
		root.add_child(hair)
		var triangles: int = Library.triangle_count(hair)
		_expect(triangles == 0 if style_id == &"bald" else triangles > 0,
			"%s has the expected visible geometry (%d triangles)" % [style_id, triangles])
		_expect(triangles <= Library.TRIANGLE_LIMIT,
			"%s stays within 1500 triangles (got %d)" % [style_id, triangles])
		_expect(hair.is_in_group(&"gel_hair"), "%s is discoverable as gel_hair" % style_id)
		_expect(hair.get_meta(&"gel_color") == color, "%s retains its catalog colour" % style_id)
		_check_geometry(hair, style_id)
		hair.free()

	_check_accessories(Catalog.EYEBROWS, Callable(Library, &"build_eyebrows"), "eyebrows")
	_check_accessories(Catalog.MOUSTACHES, Callable(Library, &"build_moustache"), "moustache")
	var no_brows: Node3D = Library.build_eyebrows(&"none")
	var no_moustache: Node3D = Library.build_moustache(&"none")
	_expect(Library.triangle_count(no_brows) == 0, "eyebrows are optional")
	_expect(Library.triangle_count(no_moustache) == 0, "moustaches are optional")
	no_brows.free()
	no_moustache.free()

	if _failures == 0:
		print("PASS: ten low-poly gel hairstyles, five eyebrows and five optional moustaches")
	quit(_failures)


func _check_accessories(styles: Array[StringName], builder: Callable, label: String) -> void:
	for style_id: StringName in styles:
		var accessory: Node3D = builder.call(style_id)
		root.add_child(accessory)
		var triangles: int = Library.triangle_count(accessory)
		_expect(triangles > 0, "%s %s has visible geometry" % [label, style_id])
		_expect(triangles <= Library.TRIANGLE_LIMIT,
			"%s %s stays within 1500 triangles (got %d)" % [label, style_id, triangles])
		_expect(accessory.get_meta(&"gel_style_id") == style_id, "%s %s retains its stable ID" % [label, style_id])
		_check_geometry(accessory, "%s_%s" % [label, style_id])
		accessory.free()


func _check_geometry(node: Node, label: String) -> void:
	var bad_vertices: int = 0
	for child: Node in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			for surface: int in child.mesh.get_surface_count():
				var vertices: PackedVector3Array = child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					if not vertex.is_finite():
						bad_vertices += 1
		_check_geometry(child, label)
	_expect(bad_vertices == 0, "%s has finite mesh vertices" % label)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
