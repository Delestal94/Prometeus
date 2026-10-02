class_name PackageBoxDressing
extends RefCounted
## What the box is made of, seen from outside: the cardboard details, the highlight rim, the per-package
## material, the damage dents and the courier's label. Split out of package_feedback.gd (N-225.5) like
## package_rescue.gd is of package.gd: the state (the nodes it builds) stays on the PackageFeedback, which keeps
## the identity (_apply_identity) that decides what gets built and in which order. Presentation only.

const PackageShippingLabel = preload("res://scripts/gameplay/package/package_shipping_label.gd")
const OUTLINE_WIDTH: float = 0.012
const OUTLINE_COLOR := Color(1.0, 0.84, 0.48)

## Shared across every package instance, keyed by color: these decorative
## pieces (the dents) are never
## mutated after creation, unlike _box's own _material (highlight/state
## color do change that one per-instance) -- so unlike that one, these are
## safe to reuse instead of allocating a fresh StandardMaterial3D per box.
static var _flat_material_cache: Dictionary = {}


static func add_cardboard_details(f: PackageFeedback, size: Vector3) -> void:
	# Raised tape and four lid flaps break the perfectly smooth cube silhouette.
	var tape := box_piece(Vector3(size.x * 0.22, 0.012, size.z + 0.025), Color("c99a55"))
	tape.name = "PackingTape"
	tape.position.y = size.y * 0.5 + 0.007
	f._box.add_child(tape)
	for side: float in [-1.0, 1.0]:
		var flap := box_piece(Vector3(size.x * 0.46, 0.014, size.z * 0.22), Color("ad7a42"))
		flap.name = "CardboardFlap"
		flap.position = Vector3(0.0, size.y * 0.5 + 0.011, side * size.z * 0.27)
		flap.rotation.x = side * 0.12
		f._box.add_child(flap)


## An inverted hull: a plain box a hair larger than the box body, drawn
## only from the inside and opaque, so it shows as a thin warm rim around the
## silhouette and never over the printed faces. It's sized from the body
## mesh (the model is hollow -- it opens for unboxing -- so its own mesh
## can't be reused as the hull without its inner walls showing through).
static func build_outline(f: PackageFeedback, shape_size: Vector3) -> void:
	var body_bounds := AABB(Vector3(-shape_size.x, 0.0, -shape_size.z) * 0.5, shape_size)
	var body := f._box.find_child("Body", true, false) as MeshInstance3D
	if body != null:
		body_bounds = f._box.global_transform.affine_inverse() * body.global_transform * body.get_aabb()
	var hull := BoxMesh.new()
	hull.size = body_bounds.size + Vector3.ONE * OUTLINE_WIDTH * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = OUTLINE_COLOR
	f._outline = MeshInstance3D.new()
	f._outline.name = "HighlightOutline"
	(f._outline as MeshInstance3D).mesh = hull
	(f._outline as MeshInstance3D).material_override = material
	(f._outline as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f._outline.position = body_bounds.get_center()
	f._box.add_child(f._outline)
	f._apply_outline()


## Every surface of the box shares one imported material (the printed
## atlas); this swaps in a per-package copy so glowing or tinting one box
## never touches the others.
static func adopt_box_material(f: PackageFeedback, model: Node) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and f._material.albedo_texture == null:
				var copy := source.duplicate() as StandardMaterial3D
				copy.emission_enabled = f._material.emission_enabled
				copy.emission = f._material.emission
				copy.emission_energy_multiplier = f._material.emission_energy_multiplier
				f._material = copy
			mesh_instance.set_surface_override_material(surface, f._material)
	f._set_state(f._state)


static func add_dent_pieces(f: PackageFeedback, half: Vector3) -> void:
	var dents := Node3D.new()
	dents.name = "DamageDents"
	f._box.add_child(dents)
	var spots: Array = [
		[Vector3(-half.x * 0.55, half.y * 0.45, half.z + 0.004), 0.0],
		[Vector3(half.x * 0.5, -half.y * 0.4, half.z + 0.004), 0.0],
		[Vector3(half.x + 0.004, half.y * 0.3, -half.z * 0.4), PI * 0.5],
	]
	for spot: Array in spots:
		var dent := box_piece(Vector3(0.14, 0.1, 0.012), Color("6e4a2a"))
		dent.position = spot[0]
		dent.rotation = Vector3(0.0, spot[1], 0.45)
		dent.scale = Vector3.ZERO
		dents.add_child(dent)
		f._dent_pieces.append(dent)


## The courier's label (package_shipping_label.gd). Same detachable rigid
## body as before -- a hard enough hit tears it off.
static func add_shipping_label(f: PackageFeedback, shipping_data: String, parties: String,
		box_size: Vector3) -> void:
	f._shipping_label = PackageShippingLabel.build(shipping_data, parties, box_size)
	f._shipping_text = f._shipping_label.get_node(^"ShippingText") as Label3D
	f._shipping_parties = f._shipping_label.get_node(^"ShippingParties") as Label3D
	f._shipping_data = shipping_data
	f._shipping_parties_data = parties
	# On the Box, not the package root: the box wobbles, bounces and grows
	# (traps, impacts, placing it down), and a label left behind had the box
	# face sweeping back and forth through it -- the label kept vanishing.
	f._box.add_child(f._shipping_label)


static func box_piece(size: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = flat_material(color)
	return piece


static func flat_material(color: Color) -> StandardMaterial3D:
	if not _flat_material_cache.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_flat_material_cache[color] = material
	return _flat_material_cache[color]
