class_name DepotAtmosphere
extends Node
## The air inside the depot (N-319): no distance haze under the roof and an
## ambient of its own, low and cool, so the lamps' light is what shapes the
## hall instead of a milky wash -- and so a sunny noon and a rainy night look
## alike indoors: the hall's lamps are always on and the weather only shows in
## its skylights, windows and door. The level's fog and ambient (level_base.tscn,
## then WorldMood) stay as they are outdoors: while the viewer is under the
## depot's roof the level's Environment is blended toward the interior values,
## and back out again at the door. It is one point test per frame, and nothing
## at all once the blend has settled.
##
## Inside, each value is `base x (1 - share) + interior x share` (INSIDE_FIXED_SHARE
## of it is the depot's own, the rest still follows the weather a little), so it
## can always be undone: when WorldMood swaps the Environment for a copy made
## while this was half applied, the base is recovered from the copy. The shared
## Environment is put back as it was when this node leaves the tree.

## How much of the outdoor fog density stays inside: next to nothing in 30 m.
const INSIDE_FOG_SHARE: float = 0.1
## How much of the ambient is the depot's own, whatever the sky does: the rest is the level's.
const INSIDE_FIXED_SHARE: float = 0.8
## The depot's own ambient: a cool, low grey-blue, none of it from the sky (the level's
## ambient comes from its sky, and under a roof that only made the hall cold and cyan).
const INSIDE_AMBIENT_ENERGY: float = 0.25
const INSIDE_AMBIENT_COLOUR := Color("9c978f")
const INSIDE_SKY_CONTRIBUTION: float = 0.0
## The sky's share of the ambient is almost all gone (the sky is far brighter than any
## colour the ambient is tinted with, and it is what made a clear day wash the hall out).
const INSIDE_SKY_FIXED_SHARE: float = 0.97
## The sun's shadows go fully dark under the roof (they are 85 % outside: the other 15 %
## of its light came through the roof and the walls and made the clear days brighter indoors).
const INSIDE_SHADOW_OPACITY: float = 1.0
## Blend per second: a walk through the door takes about half a second.
const FADE_PER_SECOND: float = 2.2
## What the outdoor values recovered by _adopt() can be at most: the sky's share is
## divided by (1 - 0.97 x blend), so an Environment that wasn't blended the way this
## expects (an unblended copy swapped in while the camera is inside) would inflate them.
const MAX_BASE_ENERGY: float = 4.0
const MAX_BASE_DENSITY: float = 0.2

var _depot: Node3D
var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D
var _sun_shadow_opacity: float = 1.0
var _environment: Environment
var _blend: float = 0.0
var _base_density: float = 0.0
var _base_energy: float = 0.0
var _base_sky: float = 1.0
var _base_colour := Color.WHITE


func _init(depot: Node3D = null) -> void:
	_depot = depot


func _ready() -> void:
	var found: Array[Node] = get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if found.is_empty() or _depot == null:
		set_process(false)
		return
	_world_environment = found[0] as WorldEnvironment
	var suns: Array[Node] = get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	if not suns.is_empty():
		_sun = suns[0] as DirectionalLight3D
		_sun_shadow_opacity = _sun.shadow_opacity


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or _world_environment == null:
		return
	var target: float = 1.0 if bool(_depot.call(&"covers", camera.global_position)) else 0.0
	var current: Environment = _world_environment.environment
	if current == _environment and is_equal_approx(_blend, target):
		return
	if current != _environment:
		_adopt(current)
	_blend = move_toward(_blend, target, FADE_PER_SECOND * delta)
	_apply()


func _exit_tree() -> void:
	# The Environment may be a resource shared with the next level: as it was.
	if _environment != null:
		_blend = 0.0
		_apply()
		_environment = null


## Current interior blend, 0 (outdoor values) to 1 (interior).
func blend() -> float:
	return _blend


## The ambient energy, sky share and colour the depot has under its roof with
## the level's `base` values: what _apply() sets at a full blend.
static func interior(base_energy: float, base_sky: float, base_colour: Color) -> Dictionary:
	var keep: float = 1.0 - INSIDE_FIXED_SHARE
	return {
		"energy": base_energy * keep + INSIDE_AMBIENT_ENERGY * INSIDE_FIXED_SHARE,
		"sky": lerpf(base_sky, INSIDE_SKY_CONTRIBUTION, INSIDE_SKY_FIXED_SHARE),
		"colour": base_colour.lerp(INSIDE_AMBIENT_COLOUR, INSIDE_FIXED_SHARE),
	}


## Starts working on `environment`, recovering what it was before any blend.
func _adopt(environment: Environment) -> void:
	_environment = environment
	if environment == null:
		return
	# value = base x (1 - w) + interior x w, with w = blend x fixed share: undone for base.
	var weight: float = _blend * INSIDE_FIXED_SHARE
	var keep: float = 1.0 - weight
	_base_density = clampf(environment.fog_density / lerpf(1.0, INSIDE_FOG_SHARE, _blend), 0.0, MAX_BASE_DENSITY)
	_base_energy = clampf((environment.ambient_light_energy - INSIDE_AMBIENT_ENERGY * weight) / keep,
			0.0, MAX_BASE_ENERGY)
	var sky_weight: float = _blend * INSIDE_SKY_FIXED_SHARE
	_base_sky = clampf((environment.ambient_light_sky_contribution - INSIDE_SKY_CONTRIBUTION * sky_weight)
			/ (1.0 - sky_weight), 0.0, 1.0)
	var ambient: Color = environment.ambient_light_color
	_base_colour = Color(clampf((ambient.r - INSIDE_AMBIENT_COLOUR.r * weight) / keep, 0.0, 1.0),
			clampf((ambient.g - INSIDE_AMBIENT_COLOUR.g * weight) / keep, 0.0, 1.0),
			clampf((ambient.b - INSIDE_AMBIENT_COLOUR.b * weight) / keep, 0.0, 1.0), ambient.a)


func _apply() -> void:
	if _environment == null:
		return
	var weight: float = _blend * INSIDE_FIXED_SHARE
	_environment.fog_density = _base_density * lerpf(1.0, INSIDE_FOG_SHARE, _blend)
	_environment.ambient_light_energy = lerpf(_base_energy, INSIDE_AMBIENT_ENERGY, weight)
	_environment.ambient_light_sky_contribution = lerpf(_base_sky, INSIDE_SKY_CONTRIBUTION,
			_blend * INSIDE_SKY_FIXED_SHARE)
	var colour: Color = _base_colour.lerp(INSIDE_AMBIENT_COLOUR, weight)
	_environment.ambient_light_color = Color(colour.r, colour.g, colour.b, _base_colour.a)
	if _sun != null and is_instance_valid(_sun):
		_sun.shadow_opacity = lerpf(_sun_shadow_opacity, INSIDE_SHADOW_OPACITY, _blend)
