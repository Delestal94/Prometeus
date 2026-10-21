class_name GelCostumeLibrary
extends RefCounted
## Low-poly costume shells authored in the gel body's local space (S-311.71).
## Pieces carry intended bone metadata so S-311.74 can transfer weights and
## proportion morphs without changing the catalog or rebuilding their art.

const Catalog := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const TRIANGLE_LIMIT: int = 3500


static func build_costume(requested_id: StringName) -> Node3D:
	var definition: Dictionary = Catalog.costume(requested_id)
	var costume_id: StringName = definition[&"id"]
	var primary := _material(definition[&"primary"])
	var secondary := _material(definition[&"secondary"])
	var root := Node3D.new()
	root.name = "GelCostume_%s" % costume_id
	root.add_to_group(&"gel_costume", true)
	root.add_to_group(&"gel_clothing", true)
	root.set_meta(&"gel_costume_id", costume_id)
	root.set_meta(&"gel_costume_signature", definition[&"signature"])
	root.set_meta(&"gel_hat_rule", definition[&"hat_rule"])
	root.set_meta(&"gel_triangle_limit", TRIANGLE_LIMIT)
	match costume_id:
		&"courier": _courier(root, primary, secondary)
		&"mail_carrier": _mail_carrier(root, primary, secondary)
		&"firefighter": _firefighter(root, primary, secondary)
		&"astronaut": _astronaut(root, primary, secondary)
		&"pirate": _pirate(root, primary, secondary)
		&"chef": _chef(root, primary, secondary)
		&"dinosaur": _dinosaur(root, primary, secondary)
		&"bee": _bee(root, primary, secondary)
		&"mummy": _mummy(root, primary, secondary)
		&"robot": _robot(root, primary, secondary)
		&"superhero": _superhero(root, primary, secondary)
		&"skeleton": _skeleton(root, primary, secondary)
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


static func _courier(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	_box(root, "SafetyYoke", Vector3(0.0, 1.30, -0.235), Vector3(0.66, 0.12, 0.035), secondary)
	_box(root, "Belt", Vector3(0.0, 0.83, -0.22), Vector3(0.67, 0.10, 0.05), secondary)
	_box(root, "parcel_badge", Vector3(0.18, 1.18, -0.27), Vector3(0.14, 0.13, 0.035), secondary)
	_cap(root, primary, secondary)


static func _mail_carrier(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	_box(root, "PostalStripe", Vector3(0.0, 1.24, -0.245), Vector3(0.62, 0.07, 0.03), secondary)
	_box(root, "mail_satchel", Vector3(0.42, 0.92, -0.02), Vector3(0.24, 0.40, 0.16), secondary,
		&"pelvis")
	_capsule(root, "SatchelStrap", Vector3(0.16, 1.14, -0.24), Vector3(0.035, 0.66, 0.035),
		primary, Vector3(0.0, 0.0, -0.34))
	_cap(root, primary, secondary)


static func _firefighter(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	for y: float in [0.86, 1.17]:
		_box(root, "ReflectiveBand", Vector3(0.0, y, -0.245), Vector3(0.70, 0.075, 0.035), secondary)
	_cylinder(root, "Helmet", Vector3(0.0, 1.73, 0.0), Vector3(0.53, 0.22, 0.53), primary, &"head")
	_cylinder(root, "HelmetBrim", Vector3(0.0, 1.62, 0.0), Vector3(0.67, 0.055, 0.67), secondary,
		&"head")
	_capsule(root, "air_tank", Vector3(0.0, 1.06, 0.33), Vector3(0.24, 0.68, 0.24), secondary,
		Vector3.ZERO, &"chest")


static func _astronaut(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	_box(root, "ControlPanel", Vector3(0.0, 1.13, -0.29), Vector3(0.40, 0.20, 0.08), secondary)
	var visor := _material(Color(0.25, 0.65, 0.88, 0.32), true)
	_sphere(root, "HelmetVisor", Vector3(0.0, 1.66, -0.04), Vector3(0.58, 0.58, 0.55), visor, &"head")
	_box(root, "life_support", Vector3(0.0, 1.10, 0.34), Vector3(0.50, 0.58, 0.18), secondary)
	for side: float in [-1.0, 1.0]:
		_box(root, "Boot", Vector3(side * 0.19, 0.14, -0.07), Vector3(0.28, 0.25, 0.40), primary,
			&"foot.L" if side < 0.0 else &"foot.R")


static func _pirate(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	for y: float in [0.91, 1.08, 1.25]:
		_box(root, "ShirtStripe", Vector3(0.0, y, -0.25), Vector3(0.64, 0.07, 0.035), secondary)
	_capsule(root, "Sash", Vector3(0.0, 0.90, -0.26), Vector3(0.08, 0.72, 0.05), secondary,
		Vector3(0.0, 0.0, PI / 2.7), &"pelvis")
	_box(root, "tricorn", Vector3(0.0, 1.82, 0.0), Vector3(0.62, 0.10, 0.45), primary, &"head")
	_box(root, "TricornFront", Vector3(0.0, 1.86, -0.14), Vector3(0.42, 0.20, 0.08), secondary, &"head")


static func _chef(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	for y: float in [1.03, 1.18, 1.33]:
		for side: float in [-1.0, 1.0]:
			_sphere(root, "CoatButton", Vector3(side * 0.10, y, -0.27), Vector3.ONE * 0.045, secondary)
	_capsule(root, "Neckerchief", Vector3(0.0, 1.39, -0.25), Vector3(0.24, 0.09, 0.05), secondary,
		Vector3(0.0, 0.0, PI / 2.0))
	_cylinder(root, "toque", Vector3(0.0, 1.89, 0.0), Vector3(0.42, 0.34, 0.42), primary, &"head")
	for side: float in [-1.0, 0.0, 1.0]:
		_sphere(root, "ToquePuff", Vector3(side * 0.13, 2.06, 0.0), Vector3.ONE * 0.22, primary, &"head")


static func _dinosaur(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	_capsule(root, "Belly", Vector3(0.0, 1.05, -0.27), Vector3(0.38, 0.68, 0.06), secondary)
	for index: int in 5:
		_sphere(root, "BackSpike", Vector3(0.0, 1.46 - index * 0.23, 0.31),
			Vector3(0.09, 0.14, 0.16), secondary, &"chest" if index < 3 else &"pelvis")
	for index: int in 4:
		_spring_piece(_capsule(root, "dino_tail" if index == 0 else "TailSegment",
			Vector3(0.0, 0.74 - index * 0.07, 0.45 + index * 0.20),
			Vector3(0.22 - index * 0.03, 0.34, 0.22 - index * 0.03), primary,
			Vector3(PI / 2.0, 0.0, 0.0), &"pelvis"), &"dino_tail", index)


static func _bee(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	for y: float in [0.88, 1.05, 1.22, 1.39]:
		_box(root, "BeeStripe", Vector3(0.0, y, -0.245), Vector3(0.67, 0.09, 0.04), secondary)
	var wing := _material(Color(0.72, 0.92, 1.0, 0.58), true)
	for side: float in [-1.0, 1.0]:
		_sphere(root, "bee_wings" if side < 0.0 else "BeeWing", Vector3(side * 0.31, 1.25, 0.30),
			Vector3(0.34, 0.48, 0.08), wing, &"chest")
		var chain: StringName = &"bee_antenna_l" if side < 0.0 else &"bee_antenna_r"
		for index: int in 3:
			_spring_piece(_capsule(root, "Antenna", Vector3(side * (0.10 + index * 0.05),
				1.88 + index * 0.13, -0.01), Vector3(0.035, 0.20, 0.035), secondary,
				Vector3(0.0, 0.0, side * (-0.16 - index * 0.10)), &"head"), chain, index)


static func _mummy(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, secondary)
	for index: int in 7:
		var y: float = 0.82 + index * 0.10
		_box(root, "TorsoWrap", Vector3(0.0, y, -0.255),
			Vector3(0.69, 0.075, 0.045), primary, &"chest" if index > 2 else &"pelvis")
	for side: float in [-1.0, 1.0]:
		for index: int in 4:
			_capsule(root, "LimbWrap", Vector3(side * (0.42 + index * 0.02), 1.23 - index * 0.15, 0.0),
				Vector3(0.11, 0.24, 0.11), primary, Vector3(0.0, 0.0, side * 0.18),
				&"upper_arm.L" if side < 0.0 else &"upper_arm.R")
	for index: int in 3:
		_spring_piece(_box(root, "loose_wrap" if index == 0 else "HangingWrap",
			Vector3(0.27 + index * 0.025, 0.88 - index * 0.20, -0.28), Vector3(0.18, 0.26, 0.045),
			primary, &"pelvis", Vector3(0.0, 0.0, -0.12 - index * 0.06)), &"mummy_wrap", index)


static func _robot(root: Node3D, primary: Material, secondary: Material) -> void:
	_box(root, "RobotTorso", Vector3(0.0, 1.10, 0.0), Vector3(0.72, 0.68, 0.48), primary)
	_box(root, "chest_light", Vector3(0.0, 1.20, -0.27), Vector3(0.25, 0.20, 0.08), secondary)
	_box(root, "RobotHead", Vector3(0.0, 1.68, 0.0), Vector3(0.50, 0.42, 0.44), primary, &"head")
	for side: float in [-1.0, 1.0]:
		_sphere(root, "Eye", Vector3(side * 0.12, 1.71, -0.235), Vector3.ONE * 0.07, secondary, &"head")
		_box(root, "Shoulder", Vector3(side * 0.48, 1.35, 0.0), Vector3(0.24, 0.26, 0.34), primary,
			&"upper_arm.L" if side < 0.0 else &"upper_arm.R")
	_capsule(root, "Antenna", Vector3(0.0, 2.00, 0.0), Vector3(0.04, 0.28, 0.04), secondary,
		Vector3.ZERO, &"head")


static func _superhero(root: Node3D, primary: Material, secondary: Material) -> void:
	_torso(root, primary)
	_box(root, "HeroBelt", Vector3(0.0, 0.84, -0.23), Vector3(0.68, 0.10, 0.06), secondary,
		&"pelvis")
	_box(root, "HeroEmblem", Vector3(0.0, 1.23, -0.275), Vector3(0.22, 0.22, 0.045), secondary,
		&"chest", Vector3(0.0, 0.0, PI / 4.0))
	for index: int in 3:
		_spring_piece(_box(root, "hero_cape" if index == 0 else "CapePanel",
			Vector3(0.0, 1.30 - index * 0.32, 0.34 + index * 0.025),
			Vector3(0.72 - index * 0.07, 0.35, 0.055), secondary, &"chest",
			Vector3(0.10 + index * 0.035, 0.0, 0.0)), &"hero_cape", index)
	for side: float in [-1.0, 1.0]:
		_box(root, "CapeClasp", Vector3(side * 0.24, 1.44, 0.12), Vector3.ONE * 0.11, secondary)


static func _skeleton(root: Node3D, bone: Material, accent: Material) -> void:
	root.set_meta(&"gel_costume_interior", true)
	_capsule(root, "Spine", Vector3(0.0, 1.10, 0.0), Vector3(0.075, 0.72, 0.075), bone)
	for index: int in 5:
		var y: float = 1.02 + index * 0.11
		_capsule(root, "inner_ribs" if index == 2 else "Rib", Vector3(0.0, y, 0.0),
			Vector3(0.58 - index * 0.045, 0.055, 0.055), bone, Vector3(0.0, 0.0, PI / 2.0))
	_sphere(root, "Skull", Vector3(0.0, 1.68, 0.0), Vector3(0.34, 0.40, 0.31), bone, &"head")
	for side: float in [-1.0, 1.0]:
		_sphere(root, "EyeSocket", Vector3(side * 0.085, 1.72, -0.16), Vector3.ONE * 0.065, accent, &"head")
		_capsule(root, "ArmBone", Vector3(side * 0.43, 1.18, 0.0), Vector3(0.06, 0.70, 0.06), bone,
			Vector3(0.0, 0.0, side * -0.22), &"upper_arm.L" if side < 0.0 else &"upper_arm.R")
		_capsule(root, "LegBone", Vector3(side * 0.18, 0.48, 0.0), Vector3(0.075, 0.88, 0.075), bone,
			Vector3.ZERO, &"thigh.L" if side < 0.0 else &"thigh.R")
	_mark_interior(root)


static func _torso(root: Node3D, material: Material) -> void:
	_box(root, "CostumeTorso", Vector3(0.0, 1.10, 0.0), Vector3(0.68, 0.70, 0.46), material)


static func _cap(root: Node3D, crown: Material, brim: Material) -> void:
	_cylinder(root, "CapCrown", Vector3(0.0, 1.81, 0.0), Vector3(0.46, 0.20, 0.46), crown, &"head")
	_box(root, "CapBrim", Vector3(0.0, 1.75, -0.26), Vector3(0.36, 0.055, 0.28), brim, &"head")


static func _box(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		bone: StringName = &"chest", rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(root, label, mesh, position, rotation, material, bone)


static func _sphere(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		bone: StringName = &"chest") -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var piece := _piece(root, label, mesh, position, Vector3.ZERO, material, bone)
	piece.scale = size
	return piece


static func _cylinder(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		bone: StringName = &"chest") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = size.x * 0.5
	mesh.bottom_radius = size.z * 0.5
	mesh.height = size.y
	mesh.radial_segments = 8
	return _piece(root, label, mesh, position, Vector3.ZERO, material, bone)


static func _capsule(root: Node3D, label: String, position: Vector3, size: Vector3, material: Material,
		rotation: Vector3 = Vector3.ZERO, bone: StringName = &"chest") -> MeshInstance3D:
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
	piece.set_meta(&"gel_costume_bone", bone)
	root.add_child(piece)
	return piece


static func _spring_piece(instance: MeshInstance3D, chain: StringName, index: int) -> void:
	instance.set_meta(&"gel_spring_chain", chain)
	instance.set_meta(&"gel_spring_index", index)


static func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.56
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent or color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return material


static func _mark_interior(node: Node) -> void:
	for child: Node in node.get_children():
		if child is GeometryInstance3D:
			child.add_to_group(&"gel_costume_interior", true)
		_mark_interior(child)
