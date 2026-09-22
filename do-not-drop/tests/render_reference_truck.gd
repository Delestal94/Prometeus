extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.22, 0.30)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.82, 1.0)
	env.ambient_light_energy = 0.7
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.8
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	world.add_child(ground)
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	van.freeze = true
	van.position.y = 0.16
	world.add_child(van)
	var camera := Camera3D.new()
	camera.position = Vector3(5.6, 3.1, 6.4)
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.15, 1.1))
	await process_frame
	await process_frame
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png("user://reference_truck_review.png")
	print("RENDER: ", ProjectSettings.globalize_path("user://reference_truck_review.png"))
	quit(0)
