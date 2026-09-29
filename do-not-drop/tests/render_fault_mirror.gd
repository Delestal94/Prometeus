extends SceneTree
## Run without --headless: Godot --path do-not-drop --script res://tests/render_fault_mirror.gd
##
## N-214.3c: the broken driver's mirror on every truck variant and paint.
## For each one saves, under user://, a close-up from outside the driver's
## window with the mirror broken and a passenger's phone held up in its place,
## with the repair spot's position marked by a small orange sphere.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	var bus: Node = root.get_node(^"/root/EventBus")
	var constants: Dictionary = load("res://scripts/gameplay/vehicle/vehicle.gd").get_script_constant_map()
	var faults_script: Script = load("res://scripts/gameplay/vehicle/vehicle_faults.gd")
	for variant_id: StringName in constants["VARIANTS"]:
		for paint_id: StringName in constants["PAINTS"]:
			var world := Node3D.new()
			root.add_child(world)
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
			world.add_child(light)
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.background_mode = Environment.BG_COLOR
			environment.environment.background_color = Color("9fb8c9")
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
			world.add_child(environment)
			var van: VehicleBody3D = load("res://scenes/gameplay/vehicle/vehicle.tscn").instantiate()
			van.freeze = true
			world.add_child(van)
			van.variant_id = variant_id
			van.paint_id = paint_id
			var faults: Node = faults_script.new()
			faults.set(&"vehicle", van)
			world.add_child(faults)
			await process_frame
			var spot: Node3D = van.get_node_or_null(^"FaultRepair_mirror")
			if spot == null:
				push_error("No mirror repair spot on %s/%s" % [variant_id, paint_id])
				quit(1)
				return
			bus.relay(&"vehicle_fault_started", [&"mirror", Vector3.ZERO])
			faults.get(&"effects").call(&"show_phone_mirror", true, spot.position)
			var marker := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.05
			sphere.height = 0.1
			var marker_material := StandardMaterial3D.new()
			marker_material.albedo_color = Color("ff7a00")
			marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sphere.material = marker_material
			marker.mesh = sphere
			spot.add_child(marker)
			var camera := Camera3D.new()
			world.add_child(camera)
			camera.fov = 50.0
			camera.current = true
			# Outside the driver's window, and from above to see how far it
			# stands off the door.
			var views: Dictionary = {"side": Vector3(-2.2, 0.5, -1.8), "top": Vector3(-0.3, 2.5, 0.05)}
			for view: String in views:
				camera.global_position = van.to_global(spot.position + views[view])
				camera.look_at(spot.global_position)
				for _i: int in range(3):
					await process_frame
				await RenderingServer.frame_post_draw
				var output: String = "user://review_fault_mirror_%s_%s_%s.png" % [variant_id, paint_id, view]
				var result: Error = root.get_texture().get_image().save_png(output)
				if result != OK:
					push_error("Screenshot failed: %s" % output)
					quit(1)
					return
				print("RENDER: ", ProjectSettings.globalize_path(output))
			world.free()
			await process_frame
	quit(0)
