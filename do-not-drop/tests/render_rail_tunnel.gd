extends SceneTree
## Run without --headless. Saves a level crossing's tunnels (rail_crossing_
## segment.gd, route_terrain.gd tunnels) under user://: the train coming out
## of the near portal, the far portal, both from the road as the driver sees
## them, and from above and beside to check the hill over the bore and the
## hole the terrain leaves for it. Terrain set up the way route.gd does it.

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")

const VIEWS: Array = [
	["tunnel_near_front", Vector3(-22.0, 4.0, -7.0), Vector3(-42.0, 3.0, -16.0)],
	["tunnel_far_front", Vector3(22.0, 3.5, -24.0), Vector3(42.0, 3.5, -16.0)],
	["tunnel_from_road", Vector3(1.5, 2.6, 6.0), Vector3(-42.0, 3.0, -16.0)],
	["tunnel_above", Vector3(-22.0, 32.0, 8.0), Vector3(-48.0, 3.0, -16.0)],
	["tunnel_side", Vector3(-38.0, 20.0, 16.0), Vector3(-47.0, 5.0, -16.0)],
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
	terrain.add_span(Vector3(0, 0, 120), Vector3(0, 0, -120))
	var crossing := RailCrossingSegment.new()
	crossing.continuous_terrain = true
	world.add_child(crossing)
	var level: float = terrain.base_height(Vector2(0.0, crossing.track_z))
	for pad: Vector3 in crossing.track_pads():
		terrain.pads.append(Vector3(pad.x, level, pad.z))
	for mouth: Dictionary in crossing.tunnel_mouths():
		mouth["level"] = level
		terrain.tunnels.append(mouth)
	terrain.build()
	terrain.conform_geometry(crossing)
	crossing.set_meta(&"track_height", terrain.height_at(Vector3(0.0, 0.0, crossing.track_z)))
	# The train halfway out of the near tunnel, frozen there.
	crossing.set_physics_process(false)
	crossing.state = RailCrossingSegment.State.TRAIN
	crossing.set(&"_train_x", -RailCrossingSegment.PORTAL_X + 5.0)
	crossing.call(&"_place_train")
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
	world.queue_free()
	await process_frame
	await process_frame
	quit(0)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://" + file_name
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
