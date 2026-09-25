extends RefCounted
class_name WorldMood
## Weather and time of day for a route (docs/tareas-nacho.md #30/#31/#62/
## #66-#73): each session draws one of four weathers (clear, cloudy, rain,
## fog) and one of three times (day, dusk, night) from the world seed, so
## every peer drives through the same evening drizzle. Solo play (seed 0)
## still varies from run to run.
##
## Applied once by RouteSky when the route is built: the sun, the level's
## Environment (duplicated first -- the .tscn's is shared by every load of the
## level, and a rainy night must not leak into the next run), the painted sky
## and clouds, the terrain's wetness. Rain itself (drops + sound) lives in
## RouteSky, which already follows the camera. Headlights read `active`.
##
## Force one for testing or screenshots with the user argument
## --mood=<weather>_<time>, e.g. --mood=lluvia_noche.
##
## The season (N-305) is drawn the same way, from its own stream so it never
## moves the weather: summer greens or autumn ochres for every leaf, fern and
## blade of grass of the session (LowpolyMaterials.set_season() and the
## terrain's `autumn`). Force it by adding "otono" or "verano" to --mood.

enum Weather { CLEAR, CLOUDY, RAIN, FOG }
enum TimeOfDay { DAY, DUSK, NIGHT }
enum Season { SUMMER, AUTUMN }

const WEATHER_NAMES := {Weather.CLEAR: "soleado", Weather.CLOUDY: "nublado", Weather.RAIN: "lluvia", Weather.FOG: "niebla"}
const TIME_NAMES := {TimeOfDay.DAY: "dia", TimeOfDay.DUSK: "atardecer", TimeOfDay.NIGHT: "noche"}
## Cumulative odds, out of 100.
const WEATHER_ODDS := [[Weather.CLEAR, 45], [Weather.CLOUDY, 70], [Weather.RAIN, 88], [Weather.FOG, 100]]
const TIME_ODDS := [[TimeOfDay.DAY, 60], [TimeOfDay.DUSK, 85], [TimeOfDay.NIGHT, 100]]
const SEASON_NAMES := {Season.SUMMER: "verano", Season.AUTUMN: "otono"}
const SEASON_ODDS := [[Season.SUMMER, 55], [Season.AUTUMN, 100]]

## What the rest of the game reads (headlights, rain, audio). Empty until a
## route has picked one.
static var active: Dictionary = {}
## Same as --mood=<...>, for tests and capture scripts; empty = from the seed.
static var forced_label: String = ""

var weather: int = Weather.CLEAR
var time_of_day: int = TimeOfDay.DAY
var season: int = Season.SUMMER


static func pick(session_seed: int) -> WorldMood:
	var mood := WorldMood.new()
	var forced: String = forced_label
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mood="):
			forced = arg.get_slice("=", 1)
	if forced != "":
		for key: int in WEATHER_NAMES:
			if forced.contains(WEATHER_NAMES[key]):
				mood.weather = key
		for key: int in TIME_NAMES:
			if forced.contains(TIME_NAMES[key]):
				mood.time_of_day = key
		for key: int in SEASON_NAMES:
			if forced.contains(SEASON_NAMES[key]):
				mood.season = key
		LowpolyMaterials.set_season(mood.season)
		LowpolyMaterials.set_night_level(mood.darkness())
		return mood
	var rng := RandomNumberGenerator.new()
	var season_rng := RandomNumberGenerator.new()
	if session_seed != 0:
		rng.seed = hash([session_seed, &"world_mood"])
		season_rng.seed = hash([session_seed, &"season"])
	else:
		rng.randomize()
		season_rng.randomize()
	mood.weather = _from_odds(WEATHER_ODDS, rng.randi_range(0, 99))
	mood.time_of_day = _from_odds(TIME_ODDS, rng.randi_range(0, 99))
	mood.season = _from_odds(SEASON_ODDS, season_rng.randi_range(0, 99))
	# Before anything is dressed: the route picks its mood first thing, and
	# Endless's sky picks it before the streamer builds a single segment.
	LowpolyMaterials.set_season(mood.season)
	LowpolyMaterials.set_night_level(mood.darkness())
	return mood


static func _from_odds(odds: Array, roll: int) -> int:
	for entry: Array in odds:
		if roll < int(entry[1]):
			return int(entry[0])
	return int(odds[-1][0])


func label() -> String:
	return "%s_%s_%s" % [WEATHER_NAMES[weather], TIME_NAMES[time_of_day], SEASON_NAMES[season]]


## For the HUD: "Noche con lluvia", "Atardecer despejado"...
func describe() -> String:
	var when: String = TranslationServer.translate(["WORLD_MOOD_TIME_DAY", "WORLD_MOOD_TIME_DUSK", "WORLD_MOOD_TIME_NIGHT"][time_of_day])
	var sky: String = TranslationServer.translate(["WORLD_MOOD_SKY_CLEAR", "WORLD_MOOD_SKY_CLOUDY", "WORLD_MOOD_SKY_RAIN", "WORLD_MOOD_SKY_FOG"][weather])
	if time_of_day == TimeOfDay.NIGHT and weather == Weather.CLEAR:
		sky = TranslationServer.translate("WORLD_MOOD_SKY_CLEAR_NIGHT")
	return "%s %s" % [when, sky]


## How dark it is, for what lights up after dark (N-304): 0 by day, 0.5 at
## dusk, 1 at night.
func darkness() -> float:
	return [0.0, 0.5, 1.0][time_of_day]


func is_raining() -> bool:
	return weather == Weather.RAIN


## Which nature sound goes under the wind (route_sky.gd): birds by day and at
## dusk, crickets at night, and nothing when it rains -- the rain covers it,
## and birds singing through a downpour sounds wrong.
func nature_bed() -> StringName:
	if is_raining():
		return &""
	return &"crickets" if time_of_day == TimeOfDay.NIGHT else &"birds"


## The far mountains are unshaded, so their light level is set here.
func horizon_light() -> float:
	var light: float = 1.0
	match time_of_day:
		TimeOfDay.DUSK:
			light = 0.72
		TimeOfDay.NIGHT:
			light = 0.16
	if weather == Weather.RAIN:
		light *= 0.75
	return light


## How far into the fog colour the mountains fade (fog swallows them more).
func horizon_haze(base: float) -> float:
	return minf(base + (0.35 if weather == Weather.FOG else (0.15 if weather == Weather.RAIN else 0.0)), 0.95)


## Headlights: how much farther and brighter than the daytime defaults.
func headlight_boost() -> float:
	var boost: float = 1.0
	if time_of_day == TimeOfDay.NIGHT:
		boost = 4.0
	elif time_of_day == TimeOfDay.DUSK:
		boost = 1.5
	if weather in [Weather.RAIN, Weather.FOG]:
		boost = maxf(boost, 1.6)
	return boost


## Changes the level's light and sky. `world_environment` may be null (a route
## built alone in a test): then only `active` is set.
func apply(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	active = {"weather": weather, "time": time_of_day, "season": season, "label": label(), "description": describe(),
		"headlight_boost": headlight_boost(), "rain": is_raining()}
	if world_environment != null and world_environment.environment != null:
		world_environment.environment = world_environment.environment.duplicate(true)
		_apply_environment(world_environment.environment)
	if sun != null:
		_apply_sun(sun)


func _apply_environment(environment: Environment) -> void:
	var fog: Color = environment.fog_light_color
	var ambient: Color = environment.ambient_light_color
	var ambient_energy: float = environment.ambient_light_energy
	var density: float = environment.fog_density
	match time_of_day:
		TimeOfDay.DUSK:
			fog = Color(0.64, 0.5, 0.44)
			ambient = Color(0.62, 0.5, 0.5)
			ambient_energy *= 0.8
		TimeOfDay.NIGHT:
			fog = Color(0.05, 0.07, 0.1)
			ambient = Color(0.32, 0.38, 0.55)
			ambient_energy *= 0.42
	match weather:
		Weather.CLOUDY:
			fog = fog.lerp(Color(0.5, 0.53, 0.54), 0.35)
			density *= 1.3
		Weather.RAIN:
			fog = fog.lerp(Color(0.36, 0.4, 0.43), 0.5).darkened(0.1)
			density *= 1.8
			ambient_energy *= 0.85
		Weather.FOG:
			fog = fog.lerp(Color(0.7, 0.73, 0.72), 0.55)
			density *= 3.2
	environment.fog_light_color = fog
	environment.fog_density = density
	environment.ambient_light_color = ambient
	environment.ambient_light_energy = ambient_energy


func _apply_sun(sun: DirectionalLight3D) -> void:
	var energy: float = sun.light_energy
	match time_of_day:
		TimeOfDay.DUSK:
			sun.rotation_degrees.x = -13.0
			sun.light_color = Color(1.0, 0.72, 0.5)
			energy *= 0.85
		TimeOfDay.NIGHT:
			# Moonlight: high, cold and faint, still casting soft shadows.
			sun.rotation_degrees.x = -40.0
			sun.light_color = Color(0.55, 0.66, 0.95)
			energy *= 0.28
	match weather:
		Weather.CLOUDY:
			energy *= 0.55
		Weather.RAIN:
			energy *= 0.4
		Weather.FOG:
			energy *= 0.6
	sun.light_energy = energy


## The painted sky: gradient and clouds to match. Called by RouteSky once it
## has installed stylized_sky.gdshader.
func apply_sky(sky: ShaderMaterial, fog: Color) -> void:
	if sky == null:
		return
	var top: Color = sky.get_shader_parameter(&"sky_top_color")
	var horizon: Color = sky.get_shader_parameter(&"sky_horizon_color")
	var cloud: Color = sky.get_shader_parameter(&"cloud_color")
	var coverage: float = 0.36
	match time_of_day:
		TimeOfDay.DUSK:
			top = Color(0.27, 0.3, 0.47)
			horizon = Color(0.96, 0.6, 0.42)
			cloud = Color(0.98, 0.78, 0.66)
		TimeOfDay.NIGHT:
			top = Color(0.015, 0.025, 0.06)
			horizon = Color(0.07, 0.1, 0.16)
			cloud = Color(0.14, 0.16, 0.22)
	match weather:
		Weather.CLOUDY:
			coverage = 0.72
			top = top.lerp(Color(0.45, 0.5, 0.53), 0.4)
		Weather.RAIN:
			coverage = 0.92
			top = top.lerp(Color(0.3, 0.33, 0.36), 0.55)
			cloud = cloud.darkened(0.35)
		Weather.FOG:
			coverage = 0.6
			top = top.lerp(fog, 0.6)
	horizon = horizon.lerp(fog, 0.35)
	sky.set_shader_parameter(&"sky_top_color", top)
	sky.set_shader_parameter(&"sky_horizon_color", horizon)
	sky.set_shader_parameter(&"ground_horizon_color", horizon)
	sky.set_shader_parameter(&"cloud_color", cloud)
	sky.set_shader_parameter(&"cloud_shade_color", cloud.lerp(top, 0.25))
	sky.set_shader_parameter(&"coverage", coverage)


## Wet asphalt and the season's grass on the route's terrain (the one shared
## ShaderMaterial).
func apply_ground(route_root: Node) -> void:
	if route_root == null:
		return
	var wetness: float = 1.0 if is_raining() else (0.35 if weather == Weather.FOG else 0.0)
	for body: Node in route_root.find_children("Terrain_*", "StaticBody3D", true, false):
		for mesh: Node in body.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).material_override is ShaderMaterial:
				var terrain_material := (mesh as MeshInstance3D).material_override as ShaderMaterial
				terrain_material.set_shader_parameter(&"wetness", wetness)
				terrain_material.set_shader_parameter(&"autumn", 1.0 if season == Season.AUTUMN else 0.0)
				return
