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

## Foliage by season (N-305, WorldMood.Season): palette entry -> [autumn
## colour, how far toward it]. Summer keeps the palette as authored. Each
## green lands on its own ochre, so a tree's light and dark leaves still
## read apart; grass only dries a little (it's everywhere, and a whole
## orange landscape reads as fire, not autumn).
const AUTUMN: Dictionary = {
	"leaf": [Color(0.78, 0.42, 0.14), 0.78],
	"leaf_dark": [Color(0.55, 0.22, 0.1), 0.72],
	"leaf_light": [Color(0.92, 0.66, 0.2), 0.8],
	"fern": [Color(0.62, 0.42, 0.18), 0.6],
	"grass": [Color(0.62, 0.55, 0.28), 0.45],
}

## The session's season (WorldMood.Season: 0 summer, 1 autumn). Set by
## WorldMood.pick() before anything is dressed; part of every cache key, so a
## restart into the other season never reuses the last one's leaves.
static var season: int = 0
static var _textures: Dictionary = {}
static var _materials: Dictionary = {}


static func set_season(value: int) -> void:
	season = value


## How dark it is (N-304): 0 by day, 0.5 at dusk, 1 at night. Set by
## WorldMood.pick() with the season; light_up() and the batcher's cache read it.
static var night_level: float = 0.0
## What glows after dark: palette entry -> [light colour, emission energy at
## full night]. Only where light_up() is asked to -- a car's "window" is glass,
## a house's "window" is a lit room.
const NIGHT_GLOW: Dictionary = {
	"lamp_glass": [Color(1.0, 0.8, 0.52), 3.2],
	"lamp": [Color(1.0, 0.9, 0.72), 2.2],
	"window": [Color(1.0, 0.72, 0.38), 1.3],
}
static var _glowing: Dictionary = {}


static func set_night_level(value: float) -> void:
	night_level = clampf(value, 0.0, 1.0)


## Switches on the NIGHT_GLOW `keys` under `root` for the current
## night_level: an emissive twin of each matching material, shared per
## (entry, colour, level) so batching still merges them. Nothing by day.
static func light_up(root: Node, keys: Array) -> int:
	if night_level <= 0.0:
		return 0
	var lit: int = 0
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
			var key: String = source.resource_name.get_slice(".", 0).get_slice("|", 0)
			if not keys.has(key) or not NIGHT_GLOW.has(key):
				continue
			var cache_key: String = "%s|%s|%.2f" % [key, source.albedo_color.to_html(), night_level]
			if not _glowing.has(cache_key):
				var glow := source.duplicate() as BaseMaterial3D
				glow.resource_name = key + "|glow"
				glow.emission_enabled = true
				glow.emission = NIGHT_GLOW[key][0]
				glow.emission_energy_multiplier = float(NIGHT_GLOW[key][1]) * night_level
				_glowing[cache_key] = glow
			instance.set_surface_override_material(surface, _glowing[cache_key])
			lit += 1
	return lit


## The palette colour this season: summer as authored, autumn per AUTUMN.
static func seasonal_color(key: String, color: Color) -> Color:
	if season != 1 or not AUTUMN.has(key):
		return color
	var target: Color = AUTUMN[key][0]
	var shifted: Color = color.lerp(target, float(AUTUMN[key][1]))
	shifted.a = color.a
	return shifted


## Re-dresses every mesh under `root` in place. Safe to call more than once.
##
## A surface that brings its own vertex colour -- the ambient occlusion baked
## into the houses, vehicles and big props by assets/tools/bake_vertex_ao.py
## (N-308.1) -- gets it multiplied into the albedo: Godot's glTF importer
## doesn't switch that on by itself. Those materials are cached apart, so a
## model without the bake never shares a material with one that has it.
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
			var baked: bool = (instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var textured: BaseMaterial3D = textured_for(source, baked)
			if textured != null:
				instance.set_surface_override_material(surface, textured)
			elif baked and not source.vertex_color_use_as_albedo:
				instance.set_surface_override_material(surface, _with_vertex_colour(source))


static var _vertex_coloured: Dictionary = {}


## The same material with the vertex colour multiplied in, shared per source.
static func _with_vertex_colour(source: BaseMaterial3D) -> BaseMaterial3D:
	var key: int = source.get_instance_id()
	if not _vertex_coloured.has(key):
		var copy := source.duplicate() as BaseMaterial3D
		copy.vertex_color_use_as_albedo = true
		_vertex_coloured[key] = copy
	return _vertex_coloured[key]


## The detailed twin of a palette material, or null when it has no detail
## entry (glass, paint, signs -- those stay flat on purpose).
static func textured_for(source: BaseMaterial3D, vertex_colour: bool = false) -> BaseMaterial3D:
	if source.albedo_texture != null and source.uv1_world_triplanar:
		return null  # already one of ours
	var key: String = source.resource_name.get_slice(".", 0)
	if not DETAIL.has(key):
		return null
	var cache_key: String = "%s|%s|%d|%d" % [key, source.albedo_color.to_html(), season if AUTUMN.has(key) else 0, int(vertex_colour)]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var map: String = DETAIL[key][0]
	var tile: float = DETAIL[key][1]
	if not _textures.has(map):
		_textures[map] = load(DETAIL_DIR % map)
	var material := StandardMaterial3D.new()
	material.resource_name = key
	var base: Color = seasonal_color(key, source.albedo_color)
	material.albedo_color = Color(base.r * DETAIL_GAIN, base.g * DETAIL_GAIN, base.b * DETAIL_GAIN, base.a)
	material.albedo_texture = _textures[map]
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / tile
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = source.roughness
	material.metallic = source.metallic
	material.vertex_color_use_as_albedo = vertex_colour
	_materials[cache_key] = material
	return material
