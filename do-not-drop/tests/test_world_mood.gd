extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_mood.gd
## Weather and time of day (world_mood.gd, docs/tareas-nacho.md #66-#73):
##   - the same session seed always gives the same mood (every peer drives
##     through the same weather), and different seeds reach every weather;
##   - applying one works on a copy of the level's Environment, never the
##     one the .tscn shares between loads (a rainy night must not stick);
##   - rain wets the terrain and night makes the headlights matter;
##   - the season (N-305) is shared by seed too, both turn up across seeds, and
##     autumn really recolours leaves and grass -- the models' materials
##     (LowpolyMaterials), the batched dressing, and the terrain's `autumn` --
##     while summer leaves the palette alone.

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
	_check_outdoor_sounds()
	await _check_seasons()
	if _failures == 0:
		print("PASS: moods are shared by seed, varied across seeds, and never leak into the next load")
	quit(_failures)


## N-305: one season per session, drawn from the seed like the weather but
## from its own stream (it must never move the weather someone already knows
## a seed by), and it actually changes the colours.
func _check_seasons() -> void:
	var seasons: Dictionary = {}
	for seed_value: int in range(1, 200):
		var mood := WorldMood.pick(seed_value)
		_expect(mood.season == WorldMood.pick(seed_value).season, "seed %d: same seed, same season" % seed_value)
		seasons[mood.season] = int(seasons.get(mood.season, 0)) + 1
	_expect(seasons.size() == 2 and int(seasons.values().min()) > 40,
		"Across seeds both seasons turn up often (%s)" % seasons)

	var leaf := StandardMaterial3D.new()
	leaf.resource_name = "leaf"
	leaf.albedo_color = Color(0.3, 0.55, 0.22)
	var glass := StandardMaterial3D.new()
	glass.resource_name = "glass"
	glass.albedo_color = Color(0.3, 0.55, 0.22)
	LowpolyMaterials.set_season(WorldMood.Season.SUMMER)
	var summer: Color = LowpolyMaterials.textured_for(leaf).albedo_color
	LowpolyMaterials.set_season(WorldMood.Season.AUTUMN)
	var autumn: Color = LowpolyMaterials.textured_for(leaf).albedo_color
	_expect(is_equal_approx(summer.g, 0.55 * LowpolyMaterials.DETAIL_GAIN), "Summer leaves keep the palette's green (got %s)" % summer)
	_expect(autumn.r > autumn.g and autumn.r > summer.r + 0.2, "Autumn leaves turn warm, red over green (got %s)" % autumn)
	_expect(LowpolyMaterials.seasonal_color("glass", glass.albedo_color) == glass.albedo_color, "Autumn leaves glass, paint and the rest alone")
	# Pines share the broadleaf trees' leaf palette, but keep their needles.
	var pine: Color = LowpolyMaterials.textured_for(leaf, false, true).albedo_color
	_expect(pine.is_equal_approx(summer), "A pine stays green in autumn (got %s)" % pine)
	_expect(LowpolyMaterials.is_evergreen("res://assets/models/environment/forest/sm_env_forest_pine_tall.glb")
		and LowpolyMaterials.is_evergreen("res://assets/models/environment/forest/sm_env_forest_pine_sapling.glb")
		and not LowpolyMaterials.is_evergreen("res://assets/models/environment/forest/sm_env_forest_oak.glb"),
		"Pines are evergreen, oaks aren't")

	# Whole route, forced to autumn: the trees that end up drawn (batched or
	# not) wear autumn leaves, and the terrain dries out.
	var network: Node = root.get_node(^"/root/NetworkManager")
	var autumn_seed: int = 0
	for seed_value: int in range(1, 200):
		if WorldMood.pick(seed_value).season == WorldMood.Season.AUTUMN:
			autumn_seed = seed_value
			break
	network.set(&"world_seed", autumn_seed)
	network.set(&"world_house_count", 1)
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate()
	root.add_child(route)
	await process_frame
	var warm_leaves: int = 0
	var green_leaves: int = 0
	var green_pines: int = 0
	# The batcher's merged pine meshes, to tell a pine's green from a
	# broadleaf tree that failed to turn.
	var pine_meshes: Array = []
	for key: String in DressingBatcher._model_cache:
		if LowpolyMaterials.is_evergreen(key.get_slice("|", 0)):
			pine_meshes.append(DressingBatcher._model_cache[key])
	for instance: Node in route.find_children("*", "GeometryInstance3D", true, false):
		var meshes: Array[Mesh] = []
		if instance is MeshInstance3D and (instance as MeshInstance3D).mesh != null:
			meshes.append((instance as MeshInstance3D).mesh)
		elif instance is MultiMeshInstance3D and (instance as MultiMeshInstance3D).multimesh != null:
			meshes.append((instance as MultiMeshInstance3D).multimesh.mesh)
		for mesh: Mesh in meshes:
			for surface: int in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface) as BaseMaterial3D
				if instance is MeshInstance3D and surface < (instance as MeshInstance3D).get_surface_override_material_count() and (instance as MeshInstance3D).get_surface_override_material(surface) != null:
					material = (instance as MeshInstance3D).get_surface_override_material(surface) as BaseMaterial3D
				if material == null or not material.resource_name.begins_with("leaf"):
					continue
				if material.albedo_color.r > material.albedo_color.g:
					warm_leaves += 1
				elif mesh in pine_meshes or _in_pine(instance):
					green_pines += 1
				else:
					green_leaves += 1
	_expect(warm_leaves > 0 and green_leaves == 0, "An autumn route's broadleaf trees are all warm (%d warm, %d still green)" % [warm_leaves, green_leaves])
	_expect(green_pines > 0, "...and its pines stay green (%d)" % green_pines)
	var dry: float = -1.0
	for body: Node in route.find_children("Terrain_*", "StaticBody3D", true, false):
		for mesh: Node in body.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).material_override is ShaderMaterial:
				dry = float(((mesh as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(&"autumn"))
		if dry >= 0.0:
			break
	_expect(is_equal_approx(dry, 1.0), "An autumn route dries the terrain's grass (autumn %.2f)" % dry)
	route.queue_free()
	await process_frame
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	LowpolyMaterials.set_season(WorldMood.Season.SUMMER)


func _in_pine(node: Node) -> bool:
	while node != null:
		if LowpolyMaterials.is_evergreen(node.scene_file_path):
			return true
		node = node.get_parent()
	return false


## #20: birds by day and at dusk, crickets at night, nothing but rain when it
## rains; the three loops are real audio and loop without a gap.
func _check_outdoor_sounds() -> void:
	var clear_day := WorldMood.new()
	var clear_night := WorldMood.new()
	clear_night.time_of_day = WorldMood.TimeOfDay.NIGHT
	var rainy_dusk := WorldMood.new()
	rainy_dusk.weather = WorldMood.Weather.RAIN
	rainy_dusk.time_of_day = WorldMood.TimeOfDay.DUSK
	_expect(clear_day.nature_bed() == &"birds", "Birds on a clear day")
	_expect(clear_night.nature_bed() == &"crickets", "Crickets at night")
	_expect(rainy_dusk.nature_bed().is_empty(), "No birds singing through the rain")
	for stream: AudioStreamWAV in [SynthAudio.ambient_birds(), SynthAudio.night_crickets(), SynthAudio.distant_road()]:
		var loud: int = 0
		for index: int in range(0, stream.data.size() - 1, 2):
			if absi(stream.data.decode_s16(index)) > 1500:
				loud += 1
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end * 2 == stream.data.size(), "Each outdoor loop covers its whole buffer")
		_expect(loud > 100, "Each outdoor loop actually makes sound (%d loud samples)" % loud)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
