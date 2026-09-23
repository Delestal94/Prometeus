extends RefCounted
class_name LowpolyMaterials
## Subtle surface grain for the flat-colour low-poly models (the PEAK look:
## colour first, texture only as a whisper).
##
## Every authored GLB names its materials after the palette entry that made
## them in Blender ("wood", "roof", "leaf", ... -- see assets/tools/
## lowpoly_kit.py and build_lowpoly_glb_assets.py). apply() swaps the ones
## listed in DETAIL for a copy that keeps the exact colour and multiplies in a
## greyscale detail map from assets/textures/detail/.
##
## World-space triplanar mapping, because the models are built from scaled
## primitives whose UVs stretch with every box: this way a plank is the same
## size on a porch and on a barn, and a tree's bark doesn't grow with the tree.
## Copies are cached per (material, colour), so every oak shares one material
## and batching is unaffected.

const DETAIL_DIR: String = "res://assets/textures/detail/tx_detail_%s_512.png"
## Detail maps average ~0.86 (art/tools/make_detail_textures.py); this puts
## the average colour back where the palette had it.
const DETAIL_GAIN: float = 1.16
## palette material -> [detail map, metres per repeat]
const DETAIL: Dictionary = {
	"wood": ["wood_planks", 1.4],
	"barn_red": ["wood_planks", 1.8],
	"wall": ["plaster", 2.4],
	"plaster": ["plaster", 2.4],
	"roof": ["roof_shingles", 1.4],
	"roof_blue": ["roof_shingles", 1.4],
	"chimney": ["stone", 1.2],
	"stone": ["stone", 1.6],
	"concrete": ["stone", 2.2],
	"trunk": ["bark", 1.1],
	"birch": ["bark", 1.1],
	"leaf": ["foliage", 0.9],
	"leaf_dark": ["foliage", 0.9],
	"leaf_light": ["foliage", 0.9],
	"fern": ["foliage", 1.0],
	"grass": ["grass", 1.0],
	"hay": ["grass", 0.8],
}

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}


## Re-dresses every mesh under `root` in place. Safe to call more than once.
static func apply(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface: int in range(instance.mesh.get_surface_count()):
			var source := instance.get_surface_override_material(surface) as BaseMaterial3D
			if source == null:
				source = instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var textured: BaseMaterial3D = textured_for(source)
			if textured != null:
				instance.set_surface_override_material(surface, textured)


## The detailed twin of a palette material, or null when it has no detail
## entry (glass, paint, signs -- those stay flat on purpose).
static func textured_for(source: BaseMaterial3D) -> BaseMaterial3D:
	if source.albedo_texture != null and source.uv1_world_triplanar:
		return null  # already one of ours
	var key: String = source.resource_name.get_slice(".", 0)
	if not DETAIL.has(key):
		return null
	var cache_key: String = "%s|%s" % [key, source.albedo_color.to_html()]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var map: String = DETAIL[key][0]
	var tile: float = DETAIL[key][1]
	if not _textures.has(map):
		_textures[map] = load(DETAIL_DIR % map)
	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = Color(source.albedo_color.r * DETAIL_GAIN, source.albedo_color.g * DETAIL_GAIN, source.albedo_color.b * DETAIL_GAIN, source.albedo_color.a)
	material.albedo_texture = _textures[map]
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / tile
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = source.roughness
	material.metallic = source.metallic
	_materials[cache_key] = material
	return material
