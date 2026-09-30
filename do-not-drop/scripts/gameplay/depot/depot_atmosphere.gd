class_name DepotAtmosphere
extends Node
## The air inside the depot (N-319): no distance haze under the roof and a
## lower, cooler ambient, so the lamps' light is what shapes the hall instead
## of a milky wash. The level's fog and ambient (level_base.tscn, then
## WorldMood) stay as they are outdoors: while the viewer is under the depot's
## roof the level's Environment is blended toward the interior values, and
## back out again at the door. It is one point test per frame, and nothing at
## all once the blend has settled.
##
## The blend is multiplicative (each value = base x factor), so it can always
## be undone: when WorldMood swaps the Environment for a copy made while this
## was half applied, the base is recovered from the copy. The shared
## Environment is put back as it was when this node leaves the tree.

## How much of the outdoor fog density stays inside: next to nothing in 30 m.
const INSIDE_FOG_SHARE: float = 0.1
## How much of the ambient light stays inside, and its tint (multiplies the colour).
const INSIDE_AMBIENT_SHARE: float = 0.85
const INSIDE_AMBIENT_TINT := Color(1.1, 1.0, 0.92)
## How much of the sky's share of the ambient stays inside: the level's ambient
## comes from its (blue) sky, and under a roof that only made the hall cold and
## cyan -- the flat ambient colour, tinted, does the job.
const INSIDE_SKY_SHARE: float = 0.3
## Blend per second: a walk through the door takes about half a second.
const FADE_PER_SECOND: float = 2.2

var _depot: Node3D
var _world_environment: WorldEnvironment
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


## Starts working on `environment`, recovering what it was before any blend.
func _adopt(environment: Environment) -> void:
	_environment = environment
	if environment == null:
		return
	var density_factor: float = lerpf(1.0, INSIDE_FOG_SHARE, _blend)
	var energy_factor: float = lerpf(1.0, INSIDE_AMBIENT_SHARE, _blend)
	_base_density = environment.fog_density / density_factor
	_base_energy = environment.ambient_light_energy / energy_factor
	_base_sky = environment.ambient_light_sky_contribution / lerpf(1.0, INSIDE_SKY_SHARE, _blend)
	var tint: Color = Color.WHITE.lerp(INSIDE_AMBIENT_TINT, _blend)
	_base_colour = Color(environment.ambient_light_color.r / tint.r, environment.ambient_light_color.g / tint.g,
			environment.ambient_light_color.b / tint.b, environment.ambient_light_color.a)


func _apply() -> void:
	if _environment == null:
		return
	_environment.fog_density = _base_density * lerpf(1.0, INSIDE_FOG_SHARE, _blend)
	_environment.ambient_light_energy = _base_energy * lerpf(1.0, INSIDE_AMBIENT_SHARE, _blend)
	_environment.ambient_light_sky_contribution = _base_sky * lerpf(1.0, INSIDE_SKY_SHARE, _blend)
	var tint: Color = Color.WHITE.lerp(INSIDE_AMBIENT_TINT, _blend)
	_environment.ambient_light_color = Color(_base_colour.r * tint.r, _base_colour.g * tint.g,
			_base_colour.b * tint.b, _base_colour.a)
