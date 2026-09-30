extends RefCounted
class_name DetailMaterials
## Subtle surface grain for flat-colour low-poly models (the PEAK look:
## colour first, texture only as a whisper), plus their seasonal tint and
## what glows after dark.
##
## Every authored model names its materials after the palette entry that
## made them ("wood", "roof", "leaf"...). apply() swaps the ones listed in
## `detail` for a copy that keeps the exact colour and multiplies in a
## greyscale detail map from `detail_dir`.
##
## World-space triplanar mapping, because the models are built from scaled
## primitives whose UVs stretch with every box: this way a plank is the same
## size on a porch and on a barn, and a tree's bark doesn't grow with the tree.
## Copies are cached per (material, colour), so every oak shares one material
## and batching is unaffected.
##
## Portable module (docs/modulos.md): the tables below are configuration the
## game fills in before the first apply() -- in Take My Package that is
## scripts/presentation/lowpoly_materials.gd. Empty tables make it inert.

## Where the detail maps live: a format with one %s for the map's name.
static var detail_dir: String = ""
## Detail maps average less than 1; this puts the average colour back.
static var detail_gain: float = 1.0
## palette material -> [detail map, metres per repeat]
static var detail: Dictionary = {}
## Palette entries lifted before the detail goes on: entry -> colour.
static var lifted: Dictionary = {}
## Foliage by season: palette entry -> [autumn colour, how far toward it].
static var autumn: Dictionary = {}
## Words in a model's file name that keep their green all year.
static var evergreen_words: Array[String] = []
## What glows after dark: palette entry -> [light colour, emission energy at
## full night]. Only where light_up() is asked to.
static var night_glow: Dictionary = {}
## Textures handed in directly (tests, or a game without files): map -> texture.
static var textures: Dictionary = {}

## The session's season (0 summer, 1 autumn). Set before anything is
## dressed; part of every cache key, so a restart into the other season
## never reuses the last one's leaves.
static var season: int = 0
static var _materials: Dictionary = {}


static func set_season(value: int) -> void:
	season = value


## How dark it is: 0 by day, 0.5 at dusk, 1 at night. Set with the season;
## light_up() and the batcher's cache read it.
static var night_level: float = 0.0
static var _glowing: Dictionary = {}


static func set_night_level(value: float) -> void:
	night_level = clampf(value, 0.0, 1.0)


## Switches on the `night_glow` `keys` under `root` for the current
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
			if not keys.has(key) or not night_glow.has(key):
				continue
			var cache_key: String = "%s|%s|%.2f" % [key, source.albedo_color.to_html(), night_level]
			if not _glowing.has(cache_key):
				var glow := source.duplicate() as BaseMaterial3D
				glow.resource_name = key + "|glow"
				glow.emission_enabled = true
				glow.emission = night_glow[key][0]
				glow.emission_energy_multiplier = float(night_glow[key][1]) * night_level
				_glowing[cache_key] = glow
			instance.set_surface_override_material(surface, _glowing[cache_key])
			lit += 1
	return lit


## The palette colour this season: summer as authored, autumn per autumn.
static func seasonal_color(key: String, color: Color, evergreen: bool = false) -> Color:
	if season != 1 or evergreen or not autumn.has(key):
		return color
	var target: Color = autumn[key][0]
	var shifted: Color = color.lerp(target, float(autumn[key][1]))
	shifted.a = color.a
	return shifted


## Re-dresses every mesh under `root` in place. Safe to call more than once.
##
## A surface that brings its own vertex colour (ambient occlusion baked into
## the model) gets it multiplied into the albedo: Godot's glTF importer
## doesn't switch that on by itself. Those materials are cached apart, so a
## model without the bake never shares a material with one that has it.
static func apply(root: Node) -> void:
	var evergreen: bool = is_evergreen(root.scene_file_path)
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
			var textured: BaseMaterial3D = textured_for(source, baked, evergreen)
			if textured != null:
				instance.set_surface_override_material(surface, textured)
			elif baked and not source.vertex_color_use_as_albedo:
				instance.set_surface_override_material(surface, _with_vertex_colour(source))


static var _vertex_coloured: Dictionary = {}


## Whether the model at `path` keeps its green in autumn (evergreen).
static func is_evergreen(path: String) -> bool:
	var file: String = path.get_file()
	for word: String in evergreen_words:
		if file.contains(word):
			return true
	return false


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
static func textured_for(source: BaseMaterial3D, vertex_colour: bool = false, evergreen: bool = false) -> BaseMaterial3D:
	if source.albedo_texture != null and source.uv1_world_triplanar:
		return null  # already one of ours
	var key: String = source.resource_name.get_slice(".", 0)
	if not detail.has(key):
		return null
	var cache_key: String = "%s|%s|%d|%d" % [key, source.albedo_color.to_html(), season if autumn.has(key) and not evergreen else 0, int(vertex_colour)]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var map: String = detail[key][0]
	var tile: float = detail[key][1]
	if not textures.has(map):
		textures[map] = load(detail_dir % map) if detail_dir != "" else null
	var material := StandardMaterial3D.new()
	material.resource_name = key
	var authored: Color = lifted.get(key, source.albedo_color)
	var base: Color = seasonal_color(key, Color(authored, source.albedo_color.a), evergreen)
	material.albedo_color = Color(base.r * detail_gain, base.g * detail_gain, base.b * detail_gain, base.a)
	material.albedo_texture = textures[map]
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / tile
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness = source.roughness
	material.metallic = source.metallic
	material.vertex_color_use_as_albedo = vertex_colour
	_materials[cache_key] = material
	return material
