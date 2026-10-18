class_name GelEnvironmentResponse
extends Node
## Presentation-only response to the shared world mood. Rain adds tiny shader
## ripples and wet sheen; the route's ambient wind gently bends the upper body.

const WIND_DIRECTION := Vector3(0.8, 0.0, 0.6)
const WET_RATE: float = 3.0
const DRY_RATE: float = 0.12
const CLEAR_WIND: float = 0.45
const CLOUDY_WIND: float = 0.68
const RAIN_WIND: float = 0.9
const FOG_WIND: float = 0.25

var _mesh: MeshInstance3D
var _time: float = 0.0
var _phase: float = 0.0
var _rain: float = 0.0
var _wetness: float = 0.0
var _wind: Vector4 = Vector4.ZERO


func _exit_tree() -> void:
	reset_environment()


func setup(model: Node, phase_seed: int = 0) -> bool:
	_mesh = PlayerAppearance.find_mesh_instance(model)
	_phase = float(posmod(phase_seed * 73, 997)) / 997.0
	reset_environment()
	return _mesh != null


func update_environment(delta: float) -> void:
	var weather: int = int(WorldMood.active.get("weather", WorldMood.Weather.CLEAR))
	var raining: bool = bool(WorldMood.active.get("rain", weather == WorldMood.Weather.RAIN))
	advance_environment(raining, WIND_DIRECTION, wind_strength_for(weather), delta)


func advance_environment(
	raining: bool,
	world_wind_direction: Vector3,
	wind_strength: float,
	delta: float
) -> void:
	var step: float = maxf(delta, 0.0)
	_time = fmod(_time + step, 4096.0)
	_rain = 1.0 if raining else 0.0
	_wetness = move_toward(_wetness, _rain, (WET_RATE if raining else DRY_RATE) * step)
	var direction := Vector3(world_wind_direction.x, 0.0, world_wind_direction.z)
	if direction.length_squared() <= 0.000001:
		direction = WIND_DIRECTION
	var local_direction: Vector3 = direction.normalized()
	if _mesh != null and is_instance_valid(_mesh):
		local_direction = (_mesh.global_basis.inverse() * local_direction).normalized()
	_wind = Vector4(
		local_direction.x,
		local_direction.y,
		local_direction.z,
		clampf(wind_strength, 0.0, 1.0)
	)
	_upload()


func reset_environment() -> void:
	_time = 0.0
	_rain = 0.0
	_wetness = 0.0
	_wind = Vector4.ZERO
	_upload()


func weather_uniform() -> Vector4:
	return Vector4(_time, _phase, _rain, _wetness)


func wind_uniform() -> Vector4:
	return _wind


static func wind_strength_for(weather: int) -> float:
	match weather:
		WorldMood.Weather.CLOUDY:
			return CLOUDY_WIND
		WorldMood.Weather.RAIN:
			return RAIN_WIND
		WorldMood.Weather.FOG:
			return FOG_WIND
		_:
			return CLEAR_WIND


func _upload() -> void:
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.set_instance_shader_parameter(&"gel_wind", _wind)
		_mesh.set_instance_shader_parameter(&"gel_weather", weather_uniform())
