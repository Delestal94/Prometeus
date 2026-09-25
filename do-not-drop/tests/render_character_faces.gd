extends SceneTree
## GPU visual proof: the real customization panel, two combinations, and a
## close-up of the actual animated player head. Uses an isolated test profile.
const OUTPUT: String = "res://../art/rounded_character/review/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	var profile: Node = root.get_node("UnlockManager")
	profile.select_eyes(&"classic"); profile.select_mouth(&"smile")
	var panel: Control = load("res://scripts/ui/cosmetics_panel.gd").new()
	root.add_child(panel)
	await _save("customization_classic")
	panel.find_child("Eyes_wink", true, false).pressed.emit()
	panel.find_child("Mouth_tongue", true, false).pressed.emit()
	await _save("customization_wink")
	panel.hide()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("f7eddd")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -140, 0)
	root.add_child(light)
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_2"
	root.add_child(player)
	player.set_physics_process(false)
	player.face_eyes = &"classic"; player.face_mouth = &"grin"
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0.7, 1.55, -2.2)
	camera.look_at(Vector3(0, 1.36, 0))
	camera.fov = 36
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _save("face_ingame_closeup")
	player.anim_state = &"PickUpPackage"
	await create_timer(0.6).timeout
	await _save("face_on_animated_head")
	# Review the physical package at reach, contact and lift; this is the same
	# body and CarryPose overlay used in gameplay, viewed from the outside.
	player.set_process(false)
	player.rotation = Vector3.ZERO
	var package: Node3D = load("res://scenes/gameplay/package/package.tscn").instantiate()
	root.add_child(package)
	package.position = Vector3(0, 0.325, -0.56)
	package.take_by(player)
	var animation: AnimationPlayer = player.get("_anim_player")
	animation.play("PickUpPackage")
	animation.speed_scale = 0.0
	camera.position = Vector3(2.4, 1.6, -3.1)
	camera.look_at(Vector3(0, 0.85, -0.15))
	camera.fov = 40
	for sample: float in [0.25, 0.55, 1.0, 1.55]:
		player._pickup_elapsed = sample
		player._update_carried_package()
		animation.seek(sample, true)
		animation.advance(0)
		player._carry_pose.update_pose(package, sample, 0.2)
		await _save("pickup_%03d" % int(sample * 100))
	quit(0)

func _save(label: String) -> void:
	for i: int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(OUTPUT + label + ".png")
	root.get_texture().get_image().save_png(path)
	print("RENDER: ", path)
