extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_quality.gd
## Graphics quality presets (tareas de Nacho N-205): each level sets its
## shadow distance, dressing draw distance, particle count and 3D render
## scale; changing it applies at once to what's on screen and to what loads
## afterwards, and the choice is saved with the rest of the settings.
## Shadow softness (N-318.3): in the Compatibility renderer the Sun's
## shadow_blur does nothing, so a level sets the renderer's shadow filter and
## directional atlas instead (world_quality.gd), Low the cheapest and High the
## softest, and the levels' Sun softens its shadows a little (shadow_opacity)
## without touching the biases that keep them attached to what casts them.

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
		_expect(root.msaa_3d == int(preset.msaa), "%s: MSAA %d (%d)" % [name, int(preset.msaa), root.msaa_3d])
	# Lower quality really is lighter, level by level.
	var low: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.LOW]
	var high: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.HIGH]
	for key: String in ["shadow_distance", "range_scale", "particle_scale", "render_scale"]:
		_expect(float(low[key]) < float(high[key]), "Low trims %s below high" % key)
	_expect(int(high.msaa) > int(low.msaa) and int(high.msaa) != Viewport.MSAA_DISABLED,
		"High smooths the low-poly edges with MSAA; Low saves it (N-314)")
	_check_shadow_softness()

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
		print("PASS: each quality level sets shadows, draw distance, particles and scale, live, and is saved")
	quit(_failures)


## The presets' shadow filter and atlas, and the Sun each level scene ships.
func _check_shadow_softness() -> void:
	var low: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.LOW]
	var medium: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.MEDIUM]
	var high: Dictionary = WorldQuality.PRESETS[WorldQuality.Level.HIGH]
	_expect(int(low.shadow_filter) == RenderingServer.SHADOW_QUALITY_SOFT_LOW
		and int(medium.shadow_filter) == RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		and int(high.shadow_filter) == RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"The presets' shadow_filter ints are the RenderingServer.ShadowQuality values they say")
	_expect(int(low.shadow_filter) < int(medium.shadow_filter) and int(medium.shadow_filter) < int(high.shadow_filter),
		"Each level filters its shadows more than the one below")
	_expect(int(low.shadow_atlas) <= int(medium.shadow_atlas) and int(medium.shadow_atlas) <= int(high.shadow_atlas),
		"No level has a bigger shadow atlas than the one above it")
	for level: int in [WorldQuality.Level.LOW, WorldQuality.Level.MEDIUM, WorldQuality.Level.HIGH]:
		var atlas: int = int(WorldQuality.PRESETS[level].shadow_atlas)
		_expect(atlas >= 2048 and atlas <= 4096 and nearest_po2(atlas) == atlas,
			"Atlas %d is a power of two in 2048..4096 (at 1024 a far shadow's edge steps)" % atlas)
	# The Sun in both level scenes, read from the scene file without running it.
	for path: String in ["res://scenes/gameplay/level_base.tscn", "res://scenes/gameplay/level_endless.tscn"]:
		var sun: Dictionary = _scene_node_properties(path, "Sun")
		_expect(bool(sun.get("shadow_enabled", false)), "%s: the Sun casts shadows" % path)
		var opacity: float = float(sun.get("shadow_opacity", 1.0))
		_expect(opacity >= 0.7 and opacity < 1.0,
			"%s: the Sun's shadows are a little lighter than black, not washed out (opacity %.2f)" % [path, opacity])
		_expect(float(sun.get("shadow_bias", 0.1)) <= 0.08 and float(sun.get("shadow_normal_bias", 1.0)) <= 3.0,
			"%s: the Sun's biases stay small, so shadows stay attached to what casts them" % path)


func _scene_node_properties(path: String, node_name: String) -> Dictionary:
	var state: SceneState = (load(path) as PackedScene).get_state()
	var found: Dictionary = {}
	for i: int in state.get_node_count():
		if String(state.get_node_name(i)) != node_name:
			continue
		for p: int in state.get_node_property_count(i):
			found[String(state.get_node_property_name(i, p))] = state.get_node_property_value(i, p)
	return found


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
