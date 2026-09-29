extends SceneTree
## Run without --headless. Saves a narrow bridge's river (route_terrain.gd)
## under user:// -- terrain and water only, no bridge furniture -- from the
## road coming up to it, from beside the road looking along the water, and
## from above: to check the shoreline, the water's ends and the bridge's
## approach after the 2026-09-28 river rework -- and the rocky waterfalls at
## both ends of the water (route_river_falls.gd).

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")

const VIEWS: Array = [
	["river_approach", Vector3(0.0, 2.2, -34.0), Vector3(0.0, 0.5, 0.0)],
	["river_bank", Vector3(6.0, 2.0, -12.0), Vector3(40.0, -1.0, 6.0)],
	["river_far_end", Vector3(8.0, 3.0, 0.0), Vector3(60.0, 2.0, 0.0)],
	["river_above", Vector3(-30.0, 45.0, -40.0), Vector3(10.0, -1.0, 0.0)],
	# The waterfalls at both ends of the water (route_river_falls.gd).
	["river_fall_west", Vector3(-22.0, 3.5, 6.0), Vector3(-44.0, 1.0, 0.0)],
	["river_fall_east", Vector3(28.0, 3.5, -5.0), Vector3(44.0, 1.0, 0.0)],
	["river_fall_above", Vector3(-30.0, 16.0, 16.0), Vector3(-44.0, 0.0, 0.0)],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("9fc7d8")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c9d6dd")
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var terrain: Node3D = RouteTerrain.new()
	world.add_child(terrain)
	terrain.add_span(Vector3(0, 0, -120), Vector3(0, 0, 120))
	terrain.rivers.append({"a": Vector2(0, -18), "b": Vector2(0, 18), "depth": 1.8, "full_width": 18.0,
		"bank_width": 60.0})
	terrain.build()
	var camera := Camera3D.new()
	camera.fov = 70.0
	world.add_child(camera)
	camera.current = true
	for view: Array in VIEWS:
		camera.position = view[1]
		camera.look_at(view[2])
		for _i: int in 4:
			await process_frame
		await _shot("render_%s.png" % view[0])
	# Freed a frame before quitting: freeing the terrain's meshes and
	# trimesh colliders in the same frame as quit() crashed on exit.
	world.queue_free()
	await process_frame
	await process_frame
	quit(0)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
