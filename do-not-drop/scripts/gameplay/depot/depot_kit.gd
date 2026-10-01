class_name DepotKit
extends RefCounted
## Builds a lot of static geometry cheaply: every box, cylinder and imported
## prop handed to it is appended into one SurfaceTool per material, and
## commit() turns each into a single MeshInstance3D. The whole depot shell
## (walls, trusses, racking, furniture) ends up as a couple of dozen draw
## calls instead of the ~2,000 separate nodes it is made of -- the same idea
## as DressingBatcher, done at build time instead of after the fact.
##
## Everything is placed in the owner's local space. Solid pieces also get a
## box shape on one shared StaticBody3D (world layer, like route.gd's boxes).

const Layout = preload("res://scripts/gameplay/depot/depot_layout.gd")
const DETAIL_DIR: String = "res://assets/textures/detail/tx_detail_%s_512.png"
const DETAIL_GAIN: float = 1.16
## The depot's own low-poly pieces (assets/tools/build_depot_props.py).
const DEPOT_MODELS: String = "res://assets/models/environment/depot/%s.glb"

var owner: Node3D
## Where solid pieces put their shapes: a StaticBody3D made here, or the
## owner itself when it's already a moving body (the forklift).
var body: CollisionObject3D
var _tools: Dictionary = {}  # material instance id -> SurfaceTool
var _materials: Dictionary = {}  # material instance id -> Material
var _shadowless: Dictionary = {}  # material instance id -> true

static var _material_cache: Dictionary = {}
## Model parts per path, loaded and detailed once per session.
static var _model_cache: Dictionary = {}
## Flat GLB materials shared by palette name and colour, across files: every
## depot model's "depot_blue" lands in the same batch.
static var _shared_materials: Dictionary = {}
static var _merged_cache: Dictionary = {}


## Path of one of the depot's own models, by file name without extension.
static func depot_model(model_name: String) -> String:
	return DEPOT_MODELS % model_name


func _init(owner_node: Node3D, collider_name: String = "Colliders", host: CollisionObject3D = null) -> void:
	owner = owner_node
	if host != null:
		body = host
		return
	var static_body := StaticBody3D.new()
	static_body.name = collider_name
	static_body.collision_layer = 1
	static_body.collision_mask = 6
	owner.add_child(static_body)
	body = static_body


## A box centred at `center`, optionally turned `yaw` radians about Y.
func box(size: Vector3, center: Vector3, material: Material, solid: bool = false, yaw: float = 0.0) -> void:
	box_xf(size, Transform3D(Basis(Vector3.UP, yaw), center), material, solid)


func box_xf(size: Vector3, xform: Transform3D, material: Material, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	add_mesh(mesh, xform, material)
	if solid:
		collider(size, xform)


## Axis-aligned box between two corners -- handy for walls and slabs.
func span(from: Vector3, to: Vector3, material: Material, solid: bool = false) -> void:
	var low := Vector3(minf(from.x, to.x), minf(from.y, to.y), minf(from.z, to.z))
	var high := Vector3(maxf(from.x, to.x), maxf(from.y, to.y), maxf(from.z, to.z))
	box(high - low, (low + high) * 0.5, material, solid)


func cylinder(radius: float, height: float, xform: Transform3D, material: Material, sides: int = 12, solid: bool = false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	add_mesh(mesh, xform, material)
	if solid:
		collider(Vector3(radius * 2.0, height, radius * 2.0), xform)


func add_mesh(mesh: Mesh, xform: Transform3D, material: Material, casts_shadow: bool = true) -> void:
	var id: int = material.get_instance_id()
	if not _tools.has(id):
		var tool := SurfaceTool.new()
		_tools[id] = tool
		_materials[id] = material
	if not casts_shadow:
		_shadowless[id] = true
	for surface: int in range(mesh.get_surface_count()):
		(_tools[id] as SurfaceTool).append_from(mesh, surface, xform)


## Marks a material's whole batch as never casting a shadow (N-319): the floor
## slab and the wall lining gain nothing from it, and every lamp that does cast
## re-draws each batch it touches.
func shadowless(material: Material) -> void:
	_shadowless[material.get_instance_id()] = true


## An imported low-poly model (pallet, crate, cargo box...) folded into the
## batch with its own palette materials, detailed the same way the route's
## props are (LowpolyMaterials).
func model(path: String, xform: Transform3D) -> void:
	var parts: Array = _model_parts(path)
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var local: Transform3D = part[1]
		var materials: Array = part[2]
		for surface: int in range(mesh.get_surface_count()):
			var material: Material = materials[surface]
			if material == null:
				material = flat(Color("9a8f80"))
			var id: int = material.get_instance_id()
			if not _tools.has(id):
				_tools[id] = SurfaceTool.new()
				_materials[id] = material
			(_tools[id] as SurfaceTool).append_from(mesh, surface, xform * local)


## Same as model(), but standing on `xform`'s origin: most imported props
## are centred on their origin, so this lifts them by their own half height.
func model_grounded(path: String, xform: Transform3D) -> void:
	var bounds: AABB = model_bounds(path)
	model(path, xform * Transform3D(Basis.IDENTITY, Vector3(0.0, -bounds.position.y, 0.0)))


## A model's visible extent in its own space.
func model_bounds(path: String) -> AABB:
	var result := AABB()
	var first: bool = true
	for part: Array in _model_parts(path):
		var box: AABB = (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func collider(size: Vector3, xform: Transform3D) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.transform = xform
	body.add_child(shape)


## One MeshInstance3D per material. Call once, after everything is added.
func commit(prefix: String = "Batch") -> Array[MeshInstance3D]:
	var made: Array[MeshInstance3D] = []
	var index: int = 0
	for id: int in _tools:
		var mesh := ArrayMesh.new()
		(_tools[id] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(0, _materials[id])
		var instance := MeshInstance3D.new()
		instance.name = "%s%d" % [prefix, index]
		instance.mesh = mesh
		if _shadowless.has(id):
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		owner.add_child(instance)
		made.append(instance)
		index += 1
	_tools.clear()
	_materials.clear()
	return made


## A model folded into one mesh, one surface per material: for pieces that
## move on their own node (door slats, clock hands, the supplies on the
## counter). Shared per path.
static func merged_mesh(path: String) -> ArrayMesh:
	if _merged_cache.has(path):
		return _merged_cache[path]
	var tools: Dictionary = {}
	var materials: Dictionary = {}
	for part: Array in _model_parts(path):
		var mesh: Mesh = part[0]
		for surface: int in range(mesh.get_surface_count()):
			var material: Material = part[2][surface]
			if material == null:
				material = flat(Color("9a8f80"))
			var id: int = material.get_instance_id()
			if not tools.has(id):
				tools[id] = SurfaceTool.new()
				materials[id] = material
			(tools[id] as SurfaceTool).append_from(mesh, surface, part[1])
	var merged := ArrayMesh.new()
	for id: int in tools:
		(tools[id] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, materials[id])
	_merged_cache[path] = merged
	return merged


## [mesh, transform relative to the model root, [material per surface]] for
## every mesh in a model file, loaded and detailed once per path.
static func _model_parts(path: String) -> Array:
	if _model_cache.has(path):
		return _model_cache[path]
	var parts: Array = []
	var packed := load(path) as PackedScene
	if packed != null:
		var instance: Node3D = packed.instantiate() as Node3D
		LowpolyMaterials.apply(instance)
		for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			if part.mesh == null:
				continue
			var local: Transform3D = Transform3D.IDENTITY
			var walker: Node = part
			while walker != instance and walker is Node3D:
				local = (walker as Node3D).transform * local
				walker = walker.get_parent()
			var materials: Array = []
			for surface: int in range(part.mesh.get_surface_count()):
				var material: Material = part.get_surface_override_material(surface)
				if material == null:
					material = part.mesh.surface_get_material(surface)
				materials.append(_shared(material))
			parts.append([part.mesh, local, materials])
		instance.free()
	_model_cache[path] = parts
	return parts


## One material per (palette name, colour, finish) for plain flat GLB
## materials, so pieces from different files batch together. Textured,
## see-through or glowing ones are left alone.
static func _shared(material: Material) -> Material:
	var base := material as StandardMaterial3D
	# The diamond mesh is the same material in the cage panels, the window and the roll cages: one batch.
	if base != null and base.resource_name.get_slice(".", 0) == "cage_mesh" and base.albedo_texture != null:
		if not _shared_materials.has("cage_mesh"):
			_shared_materials["cage_mesh"] = base
		return _shared_materials["cage_mesh"]
	if (base == null or base.albedo_texture != null or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			or base.emission_enabled):
		return material
	var key: String = "%s|%s|%.2f|%.2f|%d" % [base.resource_name.get_slice(".", 0), base.albedo_color.to_html(),
			base.roughness, base.metallic, int(base.vertex_color_use_as_albedo)]
	if not _shared_materials.has(key):
		_shared_materials[key] = _glowing_yellow(base)
	return _shared_materials[key]


## The kit's yellows (the "warning" and "ui_yellow" palette materials: bollards, guards, posts, signs) glow a
## little on their own, so under the hall's low light they stay yellow and not olive.
const YELLOW_MATERIALS: Array[String] = ["warning", "ui_yellow"]
const YELLOW_EMISSION: float = 0.7


static func _glowing_yellow(base: StandardMaterial3D) -> StandardMaterial3D:
	if not YELLOW_MATERIALS.has(base.resource_name.get_slice(".", 0)):
		return base
	var made := base.duplicate() as StandardMaterial3D
	made.emission_enabled = true
	made.emission = base.albedo_color
	made.emission_energy_multiplier = YELLOW_EMISSION
	return made


## A flat palette colour -- glass, paint, plastic. Shared per colour.
static func flat(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var key: String = "flat:%s:%.2f:%.2f" % [color.to_html(), roughness, metallic]
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = metallic
		_material_cache[key] = material
	return _material_cache[key]


## Paint that lets what is under it show through (`color`'s alpha): a worn
## arrow on a walkway. Lit like the floor it lies on.
static func tint(color: Color) -> StandardMaterial3D:
	var key: String = "tint:%s" % color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.7
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material_cache[key] = material
	return _material_cache[key]


## The pictogram atlas (assets/textures/depot): white shapes on transparent, 4 x 4 cells
## of 128 px. Unlit and cut out (no sorting), tinted per quad through its vertex colour,
## so every icon on every sign shares this one batch.
const PICTOGRAMS: String = "res://assets/textures/depot/tx_depot_pictograms_512.png"


static func pictograms() -> StandardMaterial3D:
	var key: String = "pictograms"
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(PICTOGRAMS)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.4
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_material_cache[key] = material
	return _material_cache[key]


## Unlit paint, drawn at exactly its colour: shapes that sit beside Label3D
## text (unshaded too) and should read just as bright -- a sign's arrows.
static func unlit(color: Color) -> StandardMaterial3D:
	var key: String = "unlit:%s" % color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material_cache[key] = material
	return _material_cache[key]


## A palette colour with a greyscale detail map multiplied in, mapped in
## world space so a slab and a wall share one texel size (same look as
## LowpolyMaterials gives the imported props).
static func detailed(color: Color, detail: String, metres: float, roughness: float = 0.9) -> StandardMaterial3D:
	var key: String = "detail:%s:%s:%.2f" % [color.to_html(), detail, metres]
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(minf(color.r * DETAIL_GAIN, 1.0), minf(color.g * DETAIL_GAIN, 1.0), minf(color.b * DETAIL_GAIN, 1.0), color.a)
		material.albedo_texture = load(DETAIL_DIR % detail) if detail.find("/") == -1 else load(detail)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE / metres
		material.roughness = roughness
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material_cache[key] = material
	return _material_cache[key]


## Something that glows: lamp tubes, screens, indicator lights.
static func glow(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var key: String = "glow:%s:%.2f" % [color.to_html(), energy]
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material_cache[key] = material
	return _material_cache[key]


## A pool of warm light laid on a surface (N-319): additive and unshaded, a
## soft disc fading to nothing at its rim. The floor under each lamp gets one,
## so the hall reads as lit from above without a real light per lamp.
static func light_pool(color: Color) -> StandardMaterial3D:
	var key: String = "pool:%s" % color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.albedo_texture = _radial_texture()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.disable_fog = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material_cache[key] = material
	return _material_cache[key]


## A soft stain on the floor (oil, rubber, wear): the same disc, dark and
## see-through, lit like the floor it lies on.
static func stain(color: Color) -> StandardMaterial3D:
	var key: String = "stain:%s" % color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.albedo_texture = _radial_texture()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material_cache[key] = material
	return _material_cache[key]


## Wire mesh on a flat panel: a square lattice with holes, world-mapped at
## `cell` metres, for the supplies cage and the railings.
static func wire_mesh(color: Color, cell: float = 0.12) -> StandardMaterial3D:
	var key: String = "wire:%s:%.2f" % [color.to_html(), cell]
	if not _material_cache.has(key):
		var image := Image.create(16, 16, true, Image.FORMAT_RGBA8)
		image.fill(Color(1.0, 1.0, 1.0, 0.0))
		for index: int in range(16):
			for thickness: int in range(2):
				image.set_pixel(index, thickness, Color.WHITE)
				image.set_pixel(thickness, index, Color.WHITE)
		image.generate_mipmaps()
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.12
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE / cell
		material.roughness = 0.5
		material.metallic = 0.4
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_material_cache[key] = material
	return _material_cache[key]


## A flat quad lying on the floor (or hung over it), `size` across (x by z),
## turned `yaw` about Y. For paint, pools and stains: never casts a shadow.
func floor_quad(size: Vector2, centre: Vector3, material: Material, yaw: float = 0.0) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	add_mesh(quad, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5), centre), material, false)


## Contact shadows (N-319, no SSAO in GL Compatibility): ONE multiplicative batch for the whole depot. A
## radial gradient (a GradientTexture2D, 64 px, 40 % darker in the middle and none at the rim) darkens what is
## under it, so a quad a little bigger than a prop's footprint grounds the prop on the floor.
const CONTACT_ALPHA: float = 0.45
const CONTACT_MARGIN: float = 1.2


static func contact_material() -> StandardMaterial3D:
	var key: String = "contact"
	if not _material_cache.has(key):
		var gradient := Gradient.new()
		# Multiplicative blending ignores alpha: the shade is the colour (1 - CONTACT_ALPHA at the middle,
		# white at the rim).
		gradient.set_color(0, Color(1.0 - CONTACT_ALPHA, 1.0 - CONTACT_ALPHA, 1.0 - CONTACT_ALPHA, 1.0))
		gradient.set_color(1, Color.WHITE)
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_fog = true
		_material_cache[key] = material
	return _material_cache[key]


## A soft shadow under a prop standing at `at` (its base, on the floor) with the footprint `size` (x by z),
## turned `yaw`: the quad is CONTACT_MARGIN times the footprint.
func contact(at: Vector3, size: Vector2, yaw: float = 0.0) -> void:
	floor_quad(size * CONTACT_MARGIN + Vector2.ONE * 0.1, Vector3(at.x, Layout.FLOOR_TOP + 0.026, at.z),
			contact_material(), yaw)


## Wear and grime: ONE alpha batch with vertex colours and the soft radial fade, for scuffs, rust, the
## floor's slab-to-slab variation and the dirt at the foot of the walls.
static func wear_material() -> StandardMaterial3D:
	var key: String = "wear"
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_texture = _radial_texture()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_fog = true
		_material_cache[key] = material
	return _material_cache[key]


## A soft patch of `colour` (its alpha is the strength) `size` across, placed by `xform` (a quad facing +Z).
func wear(xform: Transform3D, size: Vector2, colour: Color) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var corners: Array[Vector2] = [Vector2(-half.x, half.y), Vector2(half.x, half.y), Vector2(half.x, -half.y),
			Vector2(-half.x, -half.y)]
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	tool.set_color(colour)
	tool.set_normal(Vector3.BACK)
	for index: int in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(uvs[index])
		tool.add_vertex(Vector3(corners[index].x, corners[index].y, 0.0))
	add_mesh(tool.commit(), xform, wear_material(), false)


## A wear patch lying on the floor (see wear()), `lift` above the floor's top.
func wear_floor(centre: Vector2, size: Vector2, colour: Color, yaw: float = 0.0, lift: float = 0.03) -> void:
	wear(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5),
			Vector3(centre.x, Layout.FLOOR_TOP + lift, centre.y)), size, colour)


## Slightly see-through glazing for the office and the skylights.
static func glass(color: Color = Color(0.72, 0.86, 0.9, 0.32)) -> StandardMaterial3D:
	var key: String = "glass:%s" % color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.08
		material.metallic = 0.2
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material_cache[key] = material
	return _material_cache[key]


## Corrugated sheet metal: vertical ribs baked into a tiny greyscale texture
## (world-mapped, so every wall's ribs line up at the same pitch).
static func ribbed(color: Color, rib_metres: float = 0.9, roughness: float = 0.55, metallic: float = 0.25) -> StandardMaterial3D:
	var key: String = "ribbed:%s:%.2f" % [color.to_html(), rib_metres]
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(minf(color.r * 1.1, 1.0), minf(color.g * 1.1, 1.0), minf(color.b * 1.1, 1.0), color.a)
		material.albedo_texture = _rib_texture()
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE / rib_metres
		material.roughness = roughness
		material.metallic = metallic
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material_cache[key] = material
	return _material_cache[key]


## Hazard paint: diagonal bands of two colours, `period` metres apart,
## world-mapped. Built here rather than read from a file so it tiles without
## a seam -- the warning texture's bands broke at every tile edge.
static func stripes(a: Color, b: Color, period: float = 0.5, roughness: float = 0.7) -> StandardMaterial3D:
	var key: String = "stripes:%s:%s:%.2f" % [a.to_html(), b.to_html(), period]
	if not _material_cache.has(key):
		var size: int = 64
		var image := Image.create(size, size, false, Image.FORMAT_RGB8)
		for y: int in range(size):
			for x: int in range(size):
				# Two bands per tile along x + y: one full period wraps exactly.
				var phase: float = fposmod(float(x + y) / float(size) * 2.0, 1.0)
				image.set_pixel(x, y, a if phase < 0.5 else b)
		image.generate_mipmaps()
		var material := StandardMaterial3D.new()
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE / (period * 2.0)
		material.roughness = roughness
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material_cache[key] = material
	return _material_cache[key]


static func _radial_texture() -> ImageTexture:
	if _material_cache.has("radial_texture"):
		return _material_cache["radial_texture"]
	var size: int = 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in range(size):
		for x: int in range(size):
			var distance: float = Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var fade: float = clampf(1.0 - distance, 0.0, 1.0)
			# Smooth at the centre and the rim: no ring shows where it ends.
			var alpha: float = fade * fade * (3.0 - 2.0 * fade)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_material_cache["radial_texture"] = texture
	return texture


static func _rib_texture() -> ImageTexture:
	if _material_cache.has("rib_texture"):
		return _material_cache["rib_texture"]
	var image := Image.create(64, 4, false, Image.FORMAT_L8)
	for x: int in range(64):
		# Two ribs per tile: a bright crest, a soft shadowed trough.
		var wave: float = 0.5 + 0.5 * cos(TAU * 2.0 * x / 64.0)
		var value: float = lerpf(0.74, 1.0, pow(wave, 0.7))
		for y: int in range(4):
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_material_cache["rib_texture"] = texture
	return texture
