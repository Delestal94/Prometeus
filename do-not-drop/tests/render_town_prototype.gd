extends SceneTree
## Run with a display (revisor-visual): Godot --path do-not-drop --script res://tests/render_town_prototype.gd
## Captures district overhead and its plaza at street height for seed 4242,
## then another seed overhead and two connected districts with center street
## views. Images: user://town_<seed>_<view>.png.

const SCENE := preload("res://scenes/gameplay/town/town_prototype.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Town visual review needs a display")
		quit(2)
		return
	for seed_value: int in [4242, 90210]:
		var town: Node3D = SCENE.instantiate()
		town.set(&"world_seed", seed_value)
		town.set(&"enable_camera", false)
		root.add_child(town)
		current_scene = town
		var camera := Camera3D.new()
		camera.far = 1000
		camera.near = 1
		camera.current = true
		town.add_child(camera)
		var plan: Dictionary = town.get(&"plan")
		var center: Vector2 = plan.districts[0].center
		var aim := Vector3(center.x, 0, center.y)
		await _shot(camera, aim + Vector3(60, 185, 125), aim, seed_value, "overhead")
		if seed_value == 4242:
			for green: Dictionary in plan.green_areas:
				if green.district == 0 and green.kind == &"plaza":
					var plaza := Vector3(green.position.x, 2.3, green.position.y)
					await _shot(
						camera,
						plaza + Vector3(10, 0, 10),
						plaza + Vector3(0, 1.5, 0),
						seed_value,
						"plaza"
					)
		town.queue_free()
		await process_frame
	await _center_shots()
	quit()


func _center_shots() -> void:
	for seed_value: int in [4242, 90210]:
		var town: Node3D = SCENE.instantiate()
		town.set(&"world_seed", seed_value)
		town.set(&"enable_camera", false)
		town.set(&"built_districts", PackedInt32Array([0, 1]))
		root.add_child(town)
		current_scene = town
		var camera := Camera3D.new()
		camera.far = 2000
		camera.near = .2
		camera.current = true
		town.add_child(camera)
		var plan: Dictionary = town.get(&"plan")
		var center: Vector2 = (plan.districts[0].center + plan.districts[1].center) * .5
		var aim := Vector3(center.x, 0, center.y)
		await _shot(camera, aim + Vector3(100, 430, 290), aim, seed_value, "connected")
		center = plan.districts[1].center
		aim = Vector3(center.x, 0, center.y)
		await _shot(camera, aim + Vector3(60, 185, 125), aim, seed_value, "center")
		if seed_value == 4242:
			for lot: Dictionary in plan.lots:
				if lot.district == 1 and lot.role == &"shop":
					var from := Vector3(lot.frontage.x, 3, lot.frontage.y)
					var to := Vector3(lot.position.x, 3, lot.position.y)
					await _shot(camera, from, to, seed_value, "center_shop")
					break
		town.queue_free()
		await process_frame


func _shot(camera: Camera3D, at: Vector3, aim: Vector3, seed_value: int, title: String) -> void:
	camera.position = at
	camera.look_at(aim)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://town_%d_%s.png" % [seed_value, title]
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save town capture: %s" % path)
	print(ProjectSettings.globalize_path(path))
