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

const DETAIL_DIR: String = "res://assets/textures/detail/tx_detail_%s_512.png"
const DETAIL_GAIN: float = 1.16

var owner: Node3D
## Where solid pieces put their shapes: a StaticBody3D made here, or the
## owner itself when it's already a moving body (the forklift).
var body: CollisionObject3D
var _tools: Dictionary = {}  # material instance id -> SurfaceTool
var _materials: Dictionary = {}  # material instance id -> Material
var _shadowless: Dictionary = {}  # material instance id -> true
var _model_cache: Dictionary = {}

static var _material_cache: Dictionary = {}


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


## [mesh, transform relative to the model root, [material per surface]] for
## every mesh in a model file, loaded and detailed once per path.
func _model_parts(path: String) -> Array:
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
				materials.append(material)
			parts.append([part.mesh, local, materials])
		instance.free()
	_model_cache[path] = parts
	return parts


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
