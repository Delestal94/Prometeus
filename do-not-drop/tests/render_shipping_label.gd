extends SceneTree
## Run (not headless): Godot --path do-not-drop --script res://tests/render_shipping_label.gd
## Close-ups of the courier label on the -Z face of three boxes (fragile, noisy,
## growing weight), in es and en, at ~0.8 m with the game's sun. Env SHIP_OUT
## overrides the output dir (default user://). Saves shipping_label_<locale>_<trap>.png.

const CASES: Array[Dictionary] = [
	{"trap": "fragile", "content": "porcelain_vase"},
	{"trap": "noisy", "content": "hen"},
	{"trap": "growing_weight", "content": "sourdough"},
]
const DISTANCES: Array[float] = [0.8, 1.0]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_environment("SHIP_OUT")
	if out == "":
		out = "user://"
	DirAccess.make_dir_recursive_absolute(out)
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
	# Sun from the -Z side so the label face is lit like in game.
	light.rotation_degrees = Vector3(-40.0, 180.0 - 32.0, 0.0)
	light.light_color = Color(0.92, 0.91, 0.85)
	light.light_energy = 0.65
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 55.0
	world.add_child(camera)
	camera.current = true
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		for i: int in CASES.size():
			var item: Dictionary = CASES[i]
			var package: RigidBody3D = (load("res://scenes/gameplay/package/package.tscn") as PackedScene).instantiate()
			package.set(&"trap_definition", load("res://data/traps/%s.tres" % item["trap"]))
			package.set(&"content", load("res://data/contents/%s.tres" % item["content"]))
			package.set(&"package_id", StringName("ship_%s_%d" % [locale, i]))
			package.freeze = true
			world.add_child(package)
			package.position = Vector3(0.0, 1.0, 0.0)
			await process_frame
			await process_frame
			var label: Node3D = package.find_child("ShippingLabel", true, false)
			if label == null:
				push_error("no ShippingLabel on %s" % item["trap"])
				package.queue_free()
				continue
			var center: Vector3 = label.global_position
			for d: float in DISTANCES:
				camera.global_position = center + Vector3(0.0, 0.0, -d)
				camera.look_at(center, Vector3.UP)
				await process_frame
				await process_frame
				await process_frame
				var image: Image = root.get_viewport().get_texture().get_image()
				image.save_png("%s/shipping_label_%s_%s_%dcm.png" % [out, locale, item["trap"], int(d * 100.0)])
			package.queue_free()
			await process_frame
	quit()
