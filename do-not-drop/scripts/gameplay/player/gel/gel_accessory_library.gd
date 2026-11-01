class_name GelAccessoryLibrary
extends RefCounted
## Independent low-poly accessory pieces authored in gel-body local space (S-311.72).
## Every piece retains its intended bone so later fitting can mount it without changing IDs.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_accessory_catalog.gd")
const TRIANGLE_LIMIT: int = 1200


static func build_accessory(requested_id: StringName) -> Node3D:
	var definition: Dictionary = Catalog.accessory(requested_id)
	var accessory_id: StringName = definition[&"id"]
	var primary := _material(definition[&"color"])
	var accent := _material(definition[&"accent"])
	var root := Node3D.new()
	root.name = "GelAccessory_%s" % accessory_id
	root.add_to_group(&"gel_accessory", true)
	root.set_meta(&"gel_accessory_id", accessory_id)
	root.set_meta(&"gel_accessory_signature", definition[&"signature"])
	root.set_meta(&"gel_accessory_anchor", definition[&"anchor"])
	root.set_meta(&"gel_accessory_bone", definition[&"bone"])
	root.set_meta(&"gel_hat_rule", definition[&"hat_rule"])
	root.set_meta(&"gel_triangle_limit", TRIANGLE_LIMIT)
	match accessory_id:
		&"cap": _cap(root, primary, accent)
		&"hard_hat": _hard_hat(root, primary, accent)
		&"glasses": _glasses(root, primary, accent)
		&"scarf": _scarf(root, primary, accent)
		&"backpack": _backpack(root, primary, accent)
		&"bow_tie": _bow_tie(root, primary, accent)
		&"crown": _crown(root, primary, accent)
		&"headphones": _headphones(root, primary, accent)
		&"fake_moustache": _fake_moustache(root, primary, accent)
		&"party_hat": _party_hat(root, primary, accent)
		&"snorkel": _snorkel(root, primary, accent)
		&"flower": _flower(root, primary, accent)
		&"monocle": _monocle(root, primary, accent)
		&"wristwatch": _wristwatch(root, primary, accent)
		&"fairy_wings": _fairy_wings(root, primary, accent)
		&"reflective_vest": _reflective_vest(root, primary, accent)
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


static func _cap(root: Node3D, primary: Material, accent: Material) -> void:
	_cylinder(root, "CapCrown", Vector3(0.0, 1.84, 0.0), Vector3(0.48, 0.20, 0.48), primary)
	_box(root, "cap_brim", Vector3(0.0, 1.77, -0.28), Vector3(0.38, 0.055, 0.30), accent)


static func _hard_hat(root: Node3D, primary: Material, accent: Material) -> void:
	_sphere(root, "HelmetShell", Vector3(0.0, 1.83, 0.0), Vector3(0.52, 0.30, 0.49), primary)
	_cylinder(root, "HelmetBrim", Vector3(0.0, 1.70, 0.0), Vector3(0.62, 0.055, 0.62), accent)
	_box(root, "helmet_ridge", Vector3(0.0, 2.00, 0.0), Vector3(0.08, 0.18, 0.44), accent)


static func _glasses(root: Node3D, frame: Material, lens: Material) -> void:
	for side: float in [-1.0, 1.0]:
		_sphere(root, "Lens", Vector3(side * 0.16, 1.70, -0.30), Vector3(0.25, 0.20, 0.035), lens)
		_box(root, "Temple", Vector3(side * 0.28, 1.70, -0.18), Vector3(0.18, 0.035, 0.035), frame)
	_box(root, "glasses_bridge", Vector3(0.0, 1.70, -0.32), Vector3(0.10, 0.035, 0.035), frame)


static func _scarf(root: Node3D, primary: Material, accent: Material) -> void:
	_cylinder(root, "ScarfLoop", Vector3(0.0, 1.43, 0.0), Vector3(0.48, 0.14, 0.48), primary, &"chest")
	_box(root, "scarf_tail", Vector3(0.17, 1.16, -0.27), Vector3(0.18, 0.52, 0.055), accent, &"chest",
		Vector3(0.0, 0.0, -0.16))


static func _backpack(root: Node3D, primary: Material, accent: Material) -> void:
	_box(root, "PackBody", Vector3(0.0, 1.08, 0.39), Vector3(0.58, 0.68, 0.24), primary, &"chest")
	_box(root, "backpack_pocket", Vector3(0.0, 0.99, 0.54), Vector3(0.40, 0.27, 0.10), accent, &"chest")
	for side: float in [-1.0, 1.0]:
		_capsule(root, "ShoulderStrap", Vector3(side * 0.25, 1.16, 0.13), Vector3(0.045, 0.63, 0.045),
			accent, Vector3(0.0, 0.0, side * 0.12), &"chest")


static func _bow_tie(root: Node3D, primary: Material, accent: Material) -> void:
	for side: float in [-1.0, 1.0]:
		_box(root, "BowWing", Vector3(side * 0.12, 1.42, -0.28), Vector3(0.22, 0.16, 0.055), primary,
			&"chest", Vector3(0.0, 0.0, side * 0.45))
	_sphere(root, "bow_knot", Vector3(0.0, 1.42, -0.31), Vector3.ONE * 0.10, accent, &"chest")


static func _crown(root: Node3D, primary: Material, accent: Material) -> void:
	_cylinder(root, "CrownBand", Vector3(0.0, 1.89, 0.0), Vector3(0.48, 0.16, 0.48), primary)
	for side: float in [-1.0, 0.0, 1.0]:
		_box(root, "CrownPoint", Vector3(side * 0.17, 2.06, 0.0), Vector3(0.10, 0.25, 0.10), primary,
			&"head", Vector3(0.0, 0.0, side * -0.18))
	_sphere(root, "crown_jewel", Vector3(0.0, 1.91, -0.25), Vector3.ONE * 0.075, accent)


static func _headphones(root: Node3D, primary: Material, accent: Material) -> void:
	_capsule(root, "headphone_band", Vector3(0.0, 1.88, 0.0), Vector3(0.62, 0.055, 0.055), primary,
		Vector3(0.0, 0.0, PI / 2.0))
	for side: float in [-1.0, 1.0]:
		_box(root, "EarCup", Vector3(side * 0.36, 1.69, 0.0), Vector3(0.12, 0.28, 0.22), accent)
		_capsule(root, "BandSide", Vector3(side * 0.31, 1.87, 0.0), Vector3(0.045, 0.30, 0.045), primary)


static func _fake_moustache(root: Node3D, primary: Material, accent: Material) -> void:
	for side: float in [-1.0, 1.0]:
		_capsule(root, "MoustacheWing", Vector3(side * 0.10, 1.56, -0.32), Vector3(0.09, 0.25, 0.055), primary,
			Vector3(PI / 2.0, 0.0, side * 0.70))
	_sphere(root, "moustache_center", Vector3(0.0, 1.58, -0.34), Vector3.ONE * 0.055, accent)


static func _party_hat(root: Node3D, primary: Material, accent: Material) -> void:
	_cylinder(root, "PartyCone", Vector3(0.0, 2.00, 0.0), Vector3(0.42, 0.52, 0.05), primary)
	_sphere(root, "party_pom", Vector3(0.0, 2.28, 0.0), Vector3.ONE * 0.11, accent)


static func _snorkel(root: Node3D, primary: Material, accent: Material) -> void:
	_capsule(root, "SnorkelTube", Vector3(0.37, 1.75, 0.0), Vector3(0.055, 0.55, 0.055), primary)
	_capsule(root, "Mouthpiece", Vector3(0.22, 1.52, -0.22), Vector3(0.055, 0.30, 0.055), primary,
		Vector3(0.0, 0.0, PI / 2.0))
	_sphere(root, "snorkel_tip", Vector3(0.37, 2.04, 0.0), Vector3.ONE * 0.09, accent)


static func _flower(root: Node3D, primary: Material, accent: Material) -> void:
	for index: int in 6:
		var angle: float = TAU * float(index) / 6.0
		_sphere(root, "Petal", Vector3(cos(angle) * 0.10 - 0.25, sin(angle) * 0.10 + 1.88, -0.23),
			Vector3(0.12, 0.08, 0.035), primary)
	_sphere(root, "flower_center", Vector3(-0.25, 1.88, -0.26), Vector3.ONE * 0.08, accent)


static func _monocle(root: Node3D, primary: Material, lens: Material) -> void:
	_sphere(root, "monocle_lens", Vector3(0.15, 1.70, -0.31), Vector3(0.23, 0.23, 0.025), lens)
	_cylinder(root, "MonocleFrame", Vector3(0.15, 1.70, -0.34), Vector3(0.27, 0.025, 0.27), primary)
	_capsule(root, "MonocleChain", Vector3(0.22, 1.48, -0.32), Vector3(0.025, 0.42, 0.025), primary,
		Vector3(0.0, 0.0, -0.18))


static func _wristwatch(root: Node3D, primary: Material, accent: Material) -> void:
	_capsule(root, "WatchStrap", Vector3(-0.48, 0.97, 0.0), Vector3(0.055, 0.28, 0.055), primary,
		Vector3(0.0, 0.0, PI / 2.0), &"hand.L")
	_box(root, "watch_face", Vector3(-0.48, 0.97, -0.09), Vector3(0.16, 0.14, 0.055), accent, &"hand.L")


static func _fairy_wings(root: Node3D, primary: Material, accent: Material) -> void:
	var wing_material := _material((primary as StandardMaterial3D).albedo_color, true)
	for side: float in [-1.0, 1.0]:
		_sphere(root, "Wing", Vector3(side * 0.31, 1.25, 0.35), Vector3(0.34, 0.53, 0.055),
			wing_material, &"chest")
	_sphere(root, "wing_core", Vector3(0.0, 1.22, 0.35), Vector3(0.16, 0.38, 0.10), accent, &"chest")


## High-vis tabard worn over the costume torso (S-305): open sides, a V-neck gap between the front
## panels and two silver reflective bands. It is a shell: GelCostumeFitter scales it with the chest bone
## and its x/z offsets (gel_fit_shell), so it keeps clear of the torso at every proportion.
static func _reflective_vest(root: Node3D, primary: Material, accent: Material) -> void:
	var silver := _reflective_material((accent as StandardMaterial3D).albedo_color)
	for side: float in [-1.0, 1.0]:
		_box(root, "VestFront", Vector3(side * 0.245, 1.13, -0.33), Vector3(0.30, 0.66, 0.04), primary, &"chest")
		_box(root, "ShoulderStrap", Vector3(side * 0.30, 1.48, -0.01), Vector3(0.12, 0.04, 0.68), primary,
			&"chest")
		_box(root, "VestHem", Vector3(side * 0.395, 0.83, -0.01), Vector3(0.04, 0.05, 0.66), primary,
			&"chest")
		for y: float in [1.02, 1.22]:
			var label: String = "vest_stripe" if side < 0.0 and y > 1.1 else "VestStripe"
			_box(root, label, Vector3(side * 0.245, y, -0.356), Vector3(0.30, 0.07, 0.012), silver, &"chest")
	_box(root, "VestBack", Vector3(0.0, 1.13, 0.31), Vector3(0.80, 0.66, 0.04), primary, &"chest")
	for y: float in [1.02, 1.22]:
		_box(root, "VestStripe", Vector3(0.0, y, 0.336), Vector3(0.80, 0.07, 0.012), silver, &"chest")
	for piece: Node in root.get_children():
		piece.set_meta(&"gel_costume_bone", &"chest")
		piece.set_meta(&"gel_fit_shell", true)


static func _box(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		bone: StringName = &"head", rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(root, label, mesh, position, rotation, material, bone)


static func _sphere(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		bone: StringName = &"head") -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var piece := _piece(root, label, mesh, position, Vector3.ZERO, material, bone)
	piece.scale = size
	return piece


static func _cylinder(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		bone: StringName = &"head") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = size.x * 0.5
	mesh.bottom_radius = size.z * 0.5
	mesh.height = size.y
	mesh.radial_segments = 8
	return _piece(root, label, mesh, position, Vector3.ZERO, material, bone)


static func _capsule(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		rotation: Vector3 = Vector3.ZERO, bone: StringName = &"head") -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 2
	var piece := _piece(root, label, mesh, position, rotation, material, bone)
	piece.scale = size
	return piece


static func _piece(root: Node3D, label: String, mesh: PrimitiveMesh, position: Vector3, rotation: Vector3,
		material: Material, bone: StringName) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.mesh = mesh
	piece.position = position
	piece.rotation = rotation
	piece.material_override = material
	piece.set_meta(&"gel_accessory_bone", bone)
	root.add_child(piece)
	return piece


static func _reflective_material(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.metallic = 0.65
	material.roughness = 0.22
	return material


static func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.56
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent or color.a < 1.0:
		material.albedo_color.a = 0.58
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return material
