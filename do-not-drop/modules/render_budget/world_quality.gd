class_name WorldQuality
## Graphics quality presets (tareas de Nacho N-205): three levels that trade
## looks for frames on modest hardware. GameSettings keeps the chosen level
## and calls apply(); everything added to the tree later (a new level, the
## rain, the dust) picks the level up through watch().
##
## What a level changes -- all of it per machine, none of it gameplay:
##   - how far the sun's shadows reach (DirectionalLight3D);
##   - how far away the batched roadside dressing is still drawn
##     (DressingBatcher's visibility ranges, scaled);
##   - how many particles dust and rain emit (GPUParticles3D.amount);
##   - the 3D render resolution (Viewport.scaling_3d_scale);
##   - multisample antialiasing (Viewport.msaa_3d, N-314): the low-poly
##     silhouettes had no antialiasing at all. Low keeps it off and relies
##     on its lower render scale; Medium 2x, High 4x.
##   - how soft the sun's shadow edges are (N-318.3). In the Compatibility
##     renderer a light's shadow_blur and angular distance do nothing: the
##     edge is a fixed PCF kernel of `shadow_filter` taps (5 or 13), measured
##     in texels of the directional shadow atlas. So the softness comes from
##     the filter quality and the atlas size together: a smaller atlas has
##     bigger texels, and the sun's cascades keep the shadows near the camera
##     (the truck's, the house's) sharp while the far ones (a hill's across the
##     road) go soft. Half the engine's atlas is also cheaper at every level.
##   - how many lamps may cast a shadow (N-319, "shadowed_lights"): a lit
##     interior marks a handful of its lights with a rank (SHADOW_RANK_META,
##     0 = the one that matters most) and only those under the level's budget
##     keep their shadow. Low has none.
## Not the number of plants: the dresser draws them from the session's
## shared RNG, so placing fewer on one machine would move every prop after
## them and every peer would see a different road.

enum Level { LOW, MEDIUM, HIGH }

const NAMES: Array[String] = ["Baja", "Media", "Alta"]
## "shadow_filter" is a RenderingServer.ShadowQuality (SHADOW_QUALITY_SOFT_LOW
## = 2, _SOFT_MEDIUM = 3, _SOFT_HIGH = 4; kept as plain ints so the table stays
## a constant, and test_world_quality checks them against the enum); "shadow_atlas"
## is the side of the directional shadow atlas in pixels (was the engine's 4096
## with SOFT_LOW at every level: a crisp, PCF-5 edge). Not below 2048: at 1024
## a far hill's shadow on the road came out in visible steps.
const PRESETS: Dictionary = {
	Level.LOW: {"shadow_distance": 40.0, "range_scale": 0.55, "particle_scale": 0.35, "render_scale": 0.75,
		"msaa": Viewport.MSAA_DISABLED, "shadow_filter": 2, "shadow_atlas": 2048, "shadowed_lights": 0},
	Level.MEDIUM: {"shadow_distance": 65.0, "range_scale": 0.8, "particle_scale": 0.65, "render_scale": 0.9,
		"msaa": Viewport.MSAA_2X, "shadow_filter": 3, "shadow_atlas": 2048, "shadowed_lights": 1},
	Level.HIGH: {"shadow_distance": 90.0, "range_scale": 1.0, "particle_scale": 1.0, "render_scale": 1.0,
		"msaa": Viewport.MSAA_4X, "shadow_filter": 4, "shadow_atlas": 2048, "shadowed_lights": 3},
}
## Where each node's own full-quality value is kept, to scale from it.
const BASE_RANGE_META: StringName = &"quality_base_range"
const BASE_AMOUNT_META: StringName = &"quality_base_amount"
## A light's place in the shadow queue: only ranks under "shadowed_lights" cast.
const SHADOW_RANK_META: StringName = &"quality_shadow_rank"

static var level: int = Level.HIGH
static var _watched: SceneTree = null


static func setting(key: String) -> float:
	return float(PRESETS[level][key])


## Sets the level and applies it to everything already in `tree`.
static func apply(tree: SceneTree, new_level: int) -> void:
	level = clampi(new_level, Level.LOW, Level.HIGH)
	if tree == null:
		return
	tree.root.scaling_3d_scale = setting("render_scale")
	tree.root.msaa_3d = int(PRESETS[level]["msaa"]) as Viewport.MSAA
	apply_shadow_softness(int(PRESETS[level]["shadow_filter"]), int(PRESETS[level]["shadow_atlas"]))
	for node: Node in tree.root.find_children("*", "", true, false):
		apply_to(node)


## The shadow filter (a RenderingServer.ShadowQuality) and the directional
## atlas side, straight to the renderer: they are project-wide, not per light,
## and project.godot leaves them at the engine's defaults. The positional
## filter goes along with it in case the renderer shares one kernel between
## both (nothing in the game casts a positional shadow, so it costs nothing).
static func apply_shadow_softness(filter: int, atlas_size: int) -> void:
	var last: int = RenderingServer.SHADOW_QUALITY_MAX - 1
	var quality: RenderingServer.ShadowQuality = clampi(filter, 0, last) as RenderingServer.ShadowQuality
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(quality)
	RenderingServer.directional_shadow_atlas_set_size(atlas_size, true)


## Applies the current level to one node, if it's something a level changes.
static func apply_to(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).directional_shadow_max_distance = setting("shadow_distance")
	elif node is Light3D and node.has_meta(SHADOW_RANK_META):
		(node as Light3D).shadow_enabled = int(node.get_meta(SHADOW_RANK_META)) < int(setting("shadowed_lights"))
	elif node is GeometryInstance3D and node.has_meta(BASE_RANGE_META):
		(node as GeometryInstance3D).visibility_range_end = float(node.get_meta(BASE_RANGE_META)) * setting("range_scale")
	elif node is GPUParticles3D:
		var particles := node as GPUParticles3D
		if not particles.has_meta(BASE_AMOUNT_META):
			particles.set_meta(BASE_AMOUNT_META, particles.amount)
		var wanted: int = maxi(1, roundi(int(particles.get_meta(BASE_AMOUNT_META)) * setting("particle_scale")))
		if particles.amount != wanted:
			particles.amount = wanted


## Keeps applying the level to whatever joins `tree` from now on.
static func watch(tree: SceneTree) -> void:
	if tree == null or _watched == tree:
		return
	_watched = tree
	tree.node_added.connect(func(node: Node) -> void:
		if node is DirectionalLight3D or node is GPUParticles3D or node.has_meta(BASE_RANGE_META) \
				or node.has_meta(SHADOW_RANK_META):
			# Deferred: the node's owner sets its own values right after adding it.
			# Checked before the call: a node freed in the meantime (a route
			# built and thrown away in the same frame) can't even be passed to
			# apply_to()'s typed argument.
			var later: Callable = func() -> void:
				if is_instance_valid(node):
					apply_to(node)
			later.call_deferred())
