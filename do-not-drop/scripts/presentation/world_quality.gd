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
##   - the 3D render resolution (Viewport.scaling_3d_scale).
## Not the number of plants: the dresser draws them from the session's
## shared RNG, so placing fewer on one machine would move every prop after
## them and every peer would see a different road.

enum Level { LOW, MEDIUM, HIGH }

const NAMES: Array[String] = ["Baja", "Media", "Alta"]
const PRESETS: Dictionary = {
	Level.LOW: {"shadow_distance": 40.0, "range_scale": 0.55, "particle_scale": 0.35, "render_scale": 0.75},
	Level.MEDIUM: {"shadow_distance": 65.0, "range_scale": 0.8, "particle_scale": 0.65, "render_scale": 0.9},
	Level.HIGH: {"shadow_distance": 90.0, "range_scale": 1.0, "particle_scale": 1.0, "render_scale": 1.0},
}
## Where each node's own full-quality value is kept, to scale from it.
const BASE_RANGE_META: StringName = &"quality_base_range"
const BASE_AMOUNT_META: StringName = &"quality_base_amount"

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
	for node: Node in tree.root.find_children("*", "", true, false):
		apply_to(node)


## Applies the current level to one node, if it's something a level changes.
static func apply_to(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).directional_shadow_max_distance = setting("shadow_distance")
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
		if node is DirectionalLight3D or node is GPUParticles3D or node.has_meta(BASE_RANGE_META):
			# Deferred: the node's owner sets its own values right after adding it.
			WorldQuality.apply_to.call_deferred(node))
