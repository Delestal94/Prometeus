class_name GelHairLibrary
extends RefCounted
## Low-poly, head-local gel hair and facial-hair meshes (S-311.62).
## Attachment, head morph fitting and spring bones intentionally belong to S-311.63/64.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const TRIANGLE_LIMIT: int = 1500
const HAIR_ALPHA: float = 0.86
const FACE_HAIR_COLOR := Color("382b29")


static func build_hairstyle(requested_id: StringName) -> Node3D:
	var definition: Dictionary = Catalog.hairstyle(requested_id)
	var style_id: StringName = definition[&"id"]
	var color: Color = definition[&"color"]
	var root := _root("GelHair_%s" % style_id, &"gel_hair", style_id, color)
	var material := _material(color)
	match style_id:
		&"quiff":
			_quiff(root, material)
		&"curls":
			_curls(root, material)
		&"pigtails":
			_pigtails(root, material)
		&"mohawk":
			_mohawk(root, material)
		&"afro":
			_afro(root, material)
		&"fringe":
			_fringe(root, material)
		&"braid":
			_braid(root, material)
		&"bun":
			_bun(root, material)
		&"long":
			_long_hair(root, material)
	return root


static func build_eyebrows(requested_id: StringName) -> Node3D:
	var style_id: StringName = Catalog.valid_eyebrows(requested_id)
	var root := _root("GelEyebrows_%s" % style_id, &"gel_face_accessory", style_id, FACE_HAIR_COLOR)
	var material := _material(FACE_HAIR_COLOR)
	for side: float in [-1.0, 1.0]:
		var position := Vector3(side * 0.085, 0.045, -0.222)
		match style_id:
			&"soft":
				_strand(root, position, Vector3(0.055, 0.012, 0.014), side * -0.08, material)
			&"thick":
				_strand(root, position, Vector3(0.062, 0.021, 0.018), side * -0.05, material)
			&"angled":
				_strand(root, position, Vector3(0.06, 0.014, 0.016), side * -0.3, material)
			&"arched":
				_blob(root, position + Vector3(0.0, 0.008, 0.0), Vector3(0.06, 0.018, 0.014), material)
			&"split":
				_strand(root, position + Vector3(side * 0.02, 0.0, 0.0),
					Vector3(0.032, 0.014, 0.014), side * -0.1, material)
				_strand(root, position - Vector3(side * 0.026, -0.006, 0.0),
					Vector3(0.019, 0.012, 0.014), side * -0.25, material)
	return root


static func build_moustache(requested_id: StringName) -> Node3D:
	var style_id: StringName = Catalog.valid_moustache(requested_id)
	var root := _root("GelMoustache_%s" % style_id, &"gel_face_accessory", style_id, FACE_HAIR_COLOR)
	var material := _material(FACE_HAIR_COLOR)
	for side: float in [-1.0, 1.0]:
		var position := Vector3(side * 0.043, -0.075, -0.226)
		match style_id:
			&"pencil":
				_strand(root, position, Vector3(0.043, 0.01, 0.012), side * 0.08, material)
			&"handlebar":
				_strand(root, position + Vector3(side * 0.018, 0.008, 0.0),
					Vector3(0.062, 0.014, 0.014), side * 0.2, material)
			&"walrus":
				_blob(root, position + Vector3(0.0, -0.012, 0.0), Vector3(0.055, 0.035, 0.018), material)
			&"chevron":
				_strand(root, position, Vector3(0.052, 0.022, 0.016), side * -0.24, material)
			&"curled":
				_blob(root, position + Vector3(side * 0.024, 0.006, 0.0), Vector3(0.045, 0.017, 0.016), material)
				_blob(root, position + Vector3(side * 0.061, 0.018, 0.0), Vector3(0.022, 0.022, 0.015), material)
	return root


static func triangle_count(root: Node) -> int:
	var total: int = 0
	for child: Node in root.get_children():
		if child is MeshInstance3D and child.mesh != null:
			for surface: int in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				total += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		total += triangle_count(child)
	return total


static func _quiff(root: Node3D, material: Material) -> void:
	for index: int in 5:
		var t: float = float(index) / 4.0
		_blob(root, Vector3(lerpf(-0.16, 0.11, t), 0.205 + sin(t * PI) * 0.055, -0.085),
			Vector3(0.095, 0.105 + t * 0.025, 0.09), material)


static func _curls(root: Node3D, material: Material) -> void:
	for position: Vector3 in _crown_positions():
		_blob(root, position, Vector3.ONE * 0.09, material)
	for side: float in [-1.0, 1.0]:
		_blob(root, Vector3(side * 0.2, 0.09, -0.01), Vector3.ONE * 0.075, material)
		_blob(root, Vector3(side * 0.215, 0.0, 0.01), Vector3.ONE * 0.065, material)


static func _pigtails(root: Node3D, material: Material) -> void:
	_scalp(root, material)
	for side: float in [-1.0, 1.0]:
		_blob(root, Vector3(side * 0.245, 0.13, 0.02), Vector3.ONE * 0.075, material)
		_blob(root, Vector3(side * 0.29, 0.06, 0.035), Vector3(0.09, 0.1, 0.08), material)
		_blob(root, Vector3(side * 0.3, -0.035, 0.05), Vector3(0.07, 0.09, 0.065), material)


static func _mohawk(root: Node3D, material: Material) -> void:
	for index: int in 7:
		var z: float = lerpf(-0.17, 0.17, float(index) / 6.0)
		_blob(root, Vector3(0.0, 0.235, z), Vector3(0.055, 0.14, 0.07), material)


static func _afro(root: Node3D, material: Material) -> void:
	for position: Vector3 in _crown_positions():
		_blob(root, position + Vector3(0.0, 0.035, 0.0), Vector3.ONE * 0.125, material)
	for side: float in [-1.0, 1.0]:
		for height: float in [-0.02, 0.1, 0.2]:
			_blob(root, Vector3(side * 0.23, height, 0.015), Vector3.ONE * 0.115, material)


static func _fringe(root: Node3D, material: Material) -> void:
	_scalp(root, material)
	for index: int in 5:
		var x: float = lerpf(-0.15, 0.15, float(index) / 4.0)
		_strand(root, Vector3(x, 0.115 - absf(x) * 0.18, -0.205),
			Vector3(0.052, 0.105, 0.035), x * 0.8, material)


static func _braid(root: Node3D, material: Material) -> void:
	_scalp(root, material)
	for index: int in 7:
		var y: float = 0.11 - index * 0.075
		var x: float = 0.022 if index % 2 == 0 else -0.022
		_blob(root, Vector3(x, y, 0.235), Vector3(0.065, 0.075, 0.055), material)


static func _bun(root: Node3D, material: Material) -> void:
	_scalp(root, material)
	_blob(root, Vector3(0.0, 0.15, 0.235), Vector3(0.13, 0.13, 0.115), material)
	_blob(root, Vector3(0.0, 0.185, 0.29), Vector3(0.09, 0.09, 0.08), material)


static func _long_hair(root: Node3D, material: Material) -> void:
	_scalp(root, material)
	for side: float in [-1.0, 1.0]:
		for index: int in 4:
			_blob(root, Vector3(side * (0.19 + index * 0.012), 0.09 - index * 0.105, 0.08),
				Vector3(0.075, 0.115, 0.075), material)
	for index: int in 3:
		_blob(root, Vector3(lerpf(-0.12, 0.12, float(index) / 2.0), -0.02 - index * 0.02, 0.22),
			Vector3(0.085, 0.16, 0.055), material)


static func _scalp(root: Node3D, material: Material) -> void:
	for position: Vector3 in _crown_positions():
		_blob(root, position, Vector3(0.115, 0.1, 0.105), material)


static func _crown_positions() -> Array[Vector3]:
	return [
		Vector3(-0.13, 0.17, -0.09), Vector3(0.0, 0.21, -0.11), Vector3(0.13, 0.17, -0.09),
		Vector3(-0.14, 0.19, 0.07), Vector3(0.0, 0.24, 0.05), Vector3(0.14, 0.19, 0.07),
		Vector3(0.0, 0.18, 0.16),
	]


static func _root(label: String, group: StringName, style_id: StringName, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group(group, true)
	root.set_meta(&"gel_style_id", style_id)
	root.set_meta(&"gel_color", color)
	root.set_meta(&"gel_triangle_limit", TRIANGLE_LIMIT)
	return root


static func _blob(root: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var instance := MeshInstance3D.new()
	instance.name = "GelBlob"
	instance.mesh = mesh
	instance.position = position
	instance.scale = size * 2.0
	instance.material_override = material
	root.add_child(instance)


static func _strand(
	root: Node3D,
	position: Vector3,
	size: Vector3,
	roll: float,
	material: Material
) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 2
	var instance := MeshInstance3D.new()
	instance.name = "GelStrand"
	instance.mesh = mesh
	instance.position = position
	instance.scale = size * 2.0
	instance.rotation.z = roll
	instance.material_override = material
	root.add_child(instance)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, HAIR_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.3
	return material
