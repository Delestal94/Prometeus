extends SceneTree
## Run (not headless): Godot --path do-not-drop --script res://tests/render_packages.gd
## Captures the four delivery boxes, closed in the back row and open in the
## front row (one of them at each trap state), to review the box print,
## the flaps and the contents. Saves user://packages_review.png.

const TRAPS: Array[String] = ["fragile", "noisy", "balance", "growing_weight"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("48757a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.51, 0.60, 0.64)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	# Same sun as level_base.tscn, so colours read as they will in game.
	light.light_color = Color(0.92, 0.91, 0.85)
	light.light_energy = 0.65
	light.shadow_enabled = true
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("63736f")
	ground.material_override = ground_material
	world.add_child(ground)

	var packages: Array[RigidBody3D] = []
	for row: int in 2:
		for i: int in TRAPS.size():
			var package: RigidBody3D = (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate()
			package.set(&"trap_definition", load("res://data/traps/%s.tres" % TRAPS[i]))
			package.set(&"package_id", StringName("render_%d_%d" % [row, i]))
			package.freeze = true
			world.add_child(package)
			var size: Vector3 = (package.call(&"content_definition") as Resource).get(&"box_size")
			package.position = Vector3(-2.1 + i * 1.4, size.y * 0.5, -1.2 + row * 1.5)
			package.rotation.y = 0.35 if row == 0 else -0.25
			packages.append(package)
	await process_frame
	await process_frame
	# Front row open; the fragile one cracked, the hen agitated, the cake ruined.
	var bus: Node = root.get_node("EventBus")
	for i: int in TRAPS.size():
		packages[4 + i].call(&"set_open", true)
	bus.emit_signal(&"package_state_changed", &"render_1_0", 1)
	bus.emit_signal(&"package_state_changed", &"render_1_2", 2)
	var camera := Camera3D.new()
	camera.fov = 55.0
	world.add_child(camera)
	camera.position = Vector3(0.0, 3.0, 3.6)
	camera.look_at(Vector3(0.0, 0.35, -0.3))
	camera.make_current()
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png("user://packages_review.png")
	print("RENDER: ", ProjectSettings.globalize_path("user://packages_review.png"))
	# Looking down into the open row, where the contents actually are.
	camera.position = Vector3(0.0, 3.4, 1.9)
	camera.look_at(Vector3(0.0, 0.0, 0.25))
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_root().get_viewport().get_texture().get_image().save_png("user://packages_review_inside.png")
	print("RENDER: ", ProjectSettings.globalize_path("user://packages_review_inside.png"))
	quit(0)
