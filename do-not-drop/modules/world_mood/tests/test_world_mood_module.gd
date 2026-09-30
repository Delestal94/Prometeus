extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/world_mood/tests/test_world_mood_module.gd
##
## The world_mood module on its own (docs/modulos.md): the same seed picks
## the same weather, time and season and different seeds differ; a forced
## label wins; picking hands the season and the darkness to DetailMaterials;
## apply() fills `active`, duplicates the level's Environment before
## changing it and dims the sun for rain; apply_sky() sets the sky material's
## parameters; apply_ground() reaches the first terrain body's material;
## darkness, nature bed and headlight boost follow the time and weather.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	WorldMood.forced_label = ""
	var one: WorldMood = WorldMood.pick(4242)
	var same: WorldMood = WorldMood.pick(4242)
	_expect(one.label() == same.label(), "The same seed picks the same mood (%s)" % one.label())
	var labels: Dictionary = {}
	for seed_value: int in range(1, 40):
		labels[WorldMood.pick(seed_value).label()] = true
	_expect(labels.size() > 3, "Different seeds pick different moods (%d kinds)" % labels.size())
	WorldMood.forced_label = "lluvia_noche_otono"
	var forced: WorldMood = WorldMood.pick(4242)
	_expect(forced.weather == WorldMood.Weather.RAIN and forced.time_of_day == WorldMood.TimeOfDay.NIGHT
		and forced.season == WorldMood.Season.AUTUMN, "A forced label wins (%s)" % forced.label())
	_expect(DetailMaterials.season == WorldMood.Season.AUTUMN and is_equal_approx(DetailMaterials.night_level, 1.0),
		"Picking hands the season and the darkness to DetailMaterials")
	_expect(is_equal_approx(forced.darkness(), 1.0) and forced.is_raining() and forced.nature_bed() == &"",
		"Night is dark, rain is rain and covers the birds")
	_expect(forced.headlight_boost() >= 4.0, "Headlights boost at night (got %.1f)" % forced.headlight_boost())
	WorldMood.forced_label = "soleado_dia_verano"
	var day: WorldMood = WorldMood.pick(1)
	var plain_day: bool = is_zero_approx(day.darkness()) and day.nature_bed() == &"birds"
	_expect(plain_day and is_equal_approx(day.headlight_boost(), 1.0), "Day is bright with birds and plain headlights")
	_expect(is_zero_approx(DetailMaterials.night_level), "By day nothing glows")

	var world := WorldEnvironment.new()
	var shared := Environment.new()
	shared.fog_density = 0.01
	world.environment = shared
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	root.add_child(world)
	root.add_child(sun)
	WorldMood.forced_label = "lluvia_atardecer"
	var rainy: WorldMood = WorldMood.pick(1)
	rainy.apply(world, sun)
	var active_dusk_rain: bool = WorldMood.active.get("rain", false) == true \
		and WorldMood.active.get("time", -1) == WorldMood.TimeOfDay.DUSK
	_expect(active_dusk_rain, "apply() fills the active mood for the rest of the game (got %s)" % [WorldMood.active])
	_expect(world.environment != shared and is_equal_approx(shared.fog_density, 0.01),
		"The level's environment is duplicated, the shared one untouched")
	_expect(world.environment.fog_density > 0.015, "Rain thickens the fog (got %.3f)" % world.environment.fog_density)
	_expect(sun.light_energy < 0.5, "Rain at dusk dims the sun (got %.2f)" % sun.light_energy)
	var sky := ShaderMaterial.new()
	sky.shader = Shader.new()
	sky.shader.code = "\n".join(["shader_type sky;", "uniform vec4 sky_top_color : source_color;",
		"uniform vec4 sky_horizon_color : source_color;", "uniform vec4 ground_horizon_color : source_color;",
		"uniform vec4 cloud_color : source_color;", "uniform vec4 cloud_shade_color : source_color;",
		"uniform float coverage;", "void sky() { COLOR = sky_top_color.rgb; }"])
	sky.set_shader_parameter(&"sky_top_color", Color.WHITE)
	sky.set_shader_parameter(&"sky_horizon_color", Color.WHITE)
	sky.set_shader_parameter(&"cloud_color", Color.WHITE)
	rainy.apply_sky(sky, Color(0.4, 0.4, 0.4))
	_expect(float(sky.get_shader_parameter(&"coverage")) > 0.9,
		"Rain covers the sky with cloud (got %s)" % [sky.get_shader_parameter(&"coverage")])
	var terrain_root := Node3D.new()
	var body := StaticBody3D.new()
	body.name = "Terrain_0_0"
	var mesh := MeshInstance3D.new()
	var ground := ShaderMaterial.new()
	ground.shader = Shader.new()
	ground.shader.code = "\n".join(["shader_type spatial;", "uniform float wetness;", "uniform float autumn;",
		"uniform float night_road;", "void fragment() { ALBEDO = vec3(wetness); }"])
	mesh.material_override = ground
	body.add_child(mesh)
	terrain_root.add_child(body)
	root.add_child(terrain_root)
	rainy.apply_ground(terrain_root)
	_expect(is_equal_approx(float(ground.get_shader_parameter(&"wetness")), 1.0), "Rain wets the terrain material")
	WorldMood.forced_label = ""
	world.free()
	sun.free()
	terrain_root.free()
	if _failures == 0:
		print("PASS: moods pick from the seed, dress the materials and set light, sky and ground")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
