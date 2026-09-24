extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_quality.gd
## Graphics quality presets (tareas de Nacho N-205): each level sets its
## shadow distance, dressing draw distance, particle count and 3D render
## scale; changing it applies at once to what's on screen and to what loads
## afterwards, and the choice is saved with the rest of the settings.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: Node = root.get_node(^"/root/GameSettings")
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	var dust := GPUParticles3D.new()
	dust.amount = 100
	world.add_child(dust)
	var dressing := MultiMeshInstance3D.new()
	dressing.set_meta(WorldQuality.BASE_RANGE_META, 100.0)
	world.add_child(dressing)
	await process_frame

	for level: int in [WorldQuality.Level.LOW, WorldQuality.Level.MEDIUM, WorldQuality.Level.HIGH]:
		settings.set(&"graphics_quality", level)
		var preset: Dictionary = WorldQuality.PRESETS[level]
		var name: String = WorldQuality.NAMES[level]
		_expect(is_equal_approx(sun.directional_shadow_max_distance, preset.shadow_distance), "%s: shadows reach %.0f m (%.0f)" % [name, preset.shadow_distance, sun.directional_shadow_max_distance])
		_expect(dust.amount == roundi(100 * float(preset.particle_scale)), "%s: particles scaled to %d (%d)" % [name, roundi(100 * float(preset.particle_scale)), dust.amount])
		_expect(is_equal_approx(dressing.visibility_range_end, 100.0 * float(preset.range_scale)), "%s: dressing drawn to %.0f m (%.0f)" % [name, 100.0 * float(preset.range_scale), dressing.visibility_range_end])
		_expect(is_equal_approx(root.scaling_3d_scale, preset.render_scale), "%s: 3D rendered at %.0f%% (%.2f)" % [name, float(preset.render_scale) * 100.0, root.scaling_3d_scale])
	# Lower quality really is lighter, level by level.
	var low: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.LOW]
	var high: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.HIGH]
	for key: String in ["shadow_distance", "range_scale", "particle_scale", "render_scale"]:
		_expect(float(low[key]) < float(high[key]), "Low trims %s below high" % key)

	# What loads after the change gets the level too.
	settings.set(&"graphics_quality", WorldQuality.Level.MEDIUM)
	var rain := GPUParticles3D.new()
	rain.amount = 200
	world.add_child(rain)
	await process_frame
	_expect(rain.amount == roundi(200 * float(WorldQuality.PRESETS[WorldQuality.Level.MEDIUM].particle_scale)), "Rain added later is scaled to the level in use (%d)" % rain.amount)

	var config := ConfigFile.new()
	_expect(config.load(String(settings.get(&"save_path"))) == OK and int(config.get_value("player", "graphics_quality", -1)) == WorldQuality.Level.MEDIUM,
		"The chosen level is saved with the other settings")

	settings.set(&"graphics_quality", WorldQuality.Level.HIGH)
	world.free()
	if _failures == 0:
		print("PASS: each quality level sets shadows, draw distance, particles and render scale, live, and is saved")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
