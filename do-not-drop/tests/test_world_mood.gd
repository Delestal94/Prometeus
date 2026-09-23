extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_mood.gd
## Weather and time of day (world_mood.gd, docs/tareas-nacho.md #66-#73):
##   - the same session seed always gives the same mood (every peer drives
##     through the same weather), and different seeds reach every weather;
##   - applying one works on a copy of the level's Environment, never the
##     one the .tscn shares between loads (a rainy night must not stick);
##   - rain wets the terrain and night makes the headlights matter.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(WorldMood.pick(1234).label() == WorldMood.pick(1234).label(), "Same seed, same mood")
	var seen: Dictionary = {}
	var times: Dictionary = {}
	for seed_value: int in range(1, 400):
		var mood := WorldMood.pick(seed_value)
		seen[mood.weather] = true
		times[mood.time_of_day] = true
	_expect(seen.size() == 4 and times.size() == 3, "Across seeds every weather and time turns up (%d weathers, %d times)" % [seen.size(), times.size()])

	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	var world_environment: WorldEnvironment = level.get_node(^"WorldEnvironment")
	var shared: Environment = world_environment.environment
	var shared_fog: Color = shared.fog_light_color
	var shared_density: float = shared.fog_density
	var rainy_night := WorldMood.new()
	rainy_night.weather = WorldMood.Weather.RAIN
	rainy_night.time_of_day = WorldMood.TimeOfDay.NIGHT
	root.add_child(level)
	await process_frame
	rainy_night.apply(world_environment, level.get_node(^"Sun"))
	_expect(world_environment.environment != shared, "The level gets its own Environment")
	_expect(shared.fog_light_color == shared_fog and is_equal_approx(shared.fog_density, shared_density), "The shared Environment is left exactly as it was")
	_expect(world_environment.environment.fog_density > shared_density, "Rain thickens the fog")
	_expect(float(WorldMood.active["headlight_boost"]) > 2.0 and bool(WorldMood.active["rain"]), "A rainy night turns the headlights up and brings rain")
	rainy_night.apply_ground(level.get_node(^"World/Route"))
	var wet: float = -1.0
	for body: Node in level.get_node(^"World/Route").find_children("Terrain_*", "StaticBody3D", true, false):
		for mesh: Node in body.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).material_override is ShaderMaterial:
				wet = float(((mesh as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(&"wetness"))
		if wet >= 0.0:
			break
	_expect(is_equal_approx(wet, 1.0), "Rain soaks the road (wetness %.2f)" % wet)
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: moods are shared by seed, varied across seeds, and never leak into the next load")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
