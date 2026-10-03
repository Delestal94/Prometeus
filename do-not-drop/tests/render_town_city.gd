extends SceneTree
## Run with a display (revisor-visual): Godot --path do-not-drop --script res://tests/render_town_city.gd
## Full six-district inspection: overall graph plus authored architecture and
## scenery of Industry, Country, Port and Sierra at street height. Two seeds.
## Images: user://town_city_<seed>_<view>.png. Waits for all route dressing.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Town city visual review needs a display")
		quit(2)
		return
	for seed_value: int in [4242, 90210]:
		var scene: PackedScene = load("res://scenes/gameplay/town/town_city.tscn")
		var town: Node3D = scene.instantiate()
		town.set(&"world_seed", seed_value)
		town.set(&"enable_camera", false)
		root.add_child(town)
		current_scene = town
		while not bool(town.get(&"is_built")):
			await process_frame
		var camera := Camera3D.new()
		camera.far = 2500
		camera.near = .2
		camera.current = true
		town.add_child(camera)
		var plan: Dictionary = town.get(&"plan")
		var center := Vector2.ZERO
		for district: Dictionary in plan.districts:
			center += district.center / 6
		var aim := Vector3(center.x, 0, center.y)
		await _shot(camera, aim + Vector3(180, 1000, 600), aim, seed_value, "overview")
		for id: int in [2, 3, 4, 5]:
			var at: Vector2 = plan.districts[id].center
			aim = Vector3(at.x, 0, at.y)
			await _shot(camera, aim + Vector3(35, 145, 90), aim, seed_value, "district_%d" % id)
			for lot: Dictionary in plan.lots:
				if lot.district != id or (id in [2, 4] and lot.role != &"shop"):
					continue
				var front := Vector3(lot.frontage.x, 2.5, lot.frontage.y)
				var target := Vector3(lot.position.x, 2.5, lot.position.y)
				await _shot(camera, front, target, seed_value, "front_%d" % id)
				break
		print(
			(
				"City seed %d: %d parcels, %d roads, %d green entries, dressing %s"
				% [
					seed_value,
					plan.lots.size(),
					plan.edges.size(),
					town.get(&"pedestrian_plan").green_paths.size(),
					town.get(&"dresser").get(&"placed_counts")
				]
			)
		)
		town.queue_free()
		await process_frame
	quit()


func _shot(camera: Camera3D, at: Vector3, aim: Vector3, seed_value: int, title: String) -> void:
	camera.position = at
	camera.look_at(aim)
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://town_city_%d_%s.png" % [seed_value, title]
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save city capture: %s" % path)
	print(ProjectSettings.globalize_path(path))
