extends SceneTree
## Generates the five deterministic 1920x1080 store-page stills from S-902.
## Run with a rendering window (never --headless):
##   <godot> --path do-not-drop --resolution 1920x1080 --script res://tests/render_store_shots.gd
## Output: user://store_shots/*.png

const OUTPUT_SIZE := Vector2i(1920, 1080)
const OUTPUT_DIR := "user://store_shots"
const ShotScript = preload("res://scripts/tools/trailer_shot.gd")
const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const EXPLOSIVE_TRAP: Resource = preload("res://data/traps/explosive.tres")

## Public metadata lets the headless regression test prove the promised set
## without pretending that a dummy renderer can judge the resulting images.
const STORE_SHOTS: Array[Dictionary] = [
	{"file": "01_depot_loading.png", "scene": "salida_deposito", "label": "depósito cargando"},
	{"file": "02_driving_at_risk.png", "scene": "curva_bosque", "label": "manejo con cajas en riesgo"},
	{"file": "03_house_delivery.png", "scene": "casa_noche", "label": "entrega en una casa"},
	{"file": "04_exploding_box.png", "scene": "salida_deposito", "label": "caja explotando"},
	{"file": "05_results.png", "scene": "casa_noche", "label": "resultados"},
]

var _runner: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Store shots need a rendering window; omit --headless.")
		quit(2)
		return
	DisplayServer.window_set_size(OUTPUT_SIZE)
	root.size = OUTPUT_SIZE
	for _i in range(4):
		await process_frame

	await _depot_loading()
	await _driving_at_risk()
	await _house_delivery()
	await _exploding_box()
	await _results()
	print("RENDER: 5 store shots saved at 1920x1080 under ", ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _depot_loading() -> void:
	var runner: Node = await _new_runner(&"salida_deposito", 4)
	var van := runner.get(&"van") as VehicleBody3D
	van.call(&"set_door_open", &"rear", true)
	var camera := runner.get(&"camera") as Camera3D
	_set_camera(camera, van.to_global(Vector3(4.8, 2.8, 9.5)),
		van.to_global(Vector3(0.0, 1.25, 1.4)))
	await _save(STORE_SHOTS[0].file)
	await _clear_runner()


func _driving_at_risk() -> void:
	var runner: Node = await _new_runner(&"curva_bosque", 4)
	var van := runner.get(&"van") as VehicleBody3D
	van.call(&"set_door_open", &"rear", true)
	var event_bus: Node = root.get_node(^"/root/EventBus")
	for package: Node in (runner.get(&"level") as Node).get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			event_bus.emit_signal(&"package_integrity_changed", package.get(&"package_id"), 28.0, 100.0)
			event_bus.emit_signal(&"package_state_changed", package.get(&"package_id"), ITrapBehavior.TrapState.AT_RISK)
	var camera := runner.get(&"camera") as Camera3D
	_set_camera(camera, van.to_global(Vector3(5.6, 3.1, 10.5)),
		van.to_global(Vector3(0.0, 1.15, 1.0)))
	await _save(STORE_SHOTS[1].file)
	await _clear_runner()


func _house_delivery() -> void:
	var runner: Node = await _new_runner(&"casa_noche", 2)
	_move_van_to_stop(runner)
	_set_rail_pose(runner, float(runner.get(&"shot").get("duration", 11.0)))
	await _save(STORE_SHOTS[2].file)
	await _clear_runner()


func _exploding_box() -> void:
	var runner: Node = await _new_runner(&"salida_deposito", 1)
	var van := runner.get(&"van") as VehicleBody3D
	van.call(&"set_door_open", &"rear", true)
	var package := PACKAGE_SCENE.instantiate() as DeliveryPackage
	package.package_id = &"store_explosive"
	package.trap_definition = EXPLOSIVE_TRAP
	package.freeze = true
	(runner.get(&"level") as Node).add_child(package)
	package.global_position = van.to_global(Vector3(0.0, 1.05, 6.8))
	await process_frame
	await process_frame
	# Store art should show the physical gag, not debug-like floating status
	# labels. The second full-speed burst catches the confetti opened around
	# the box instead of still hidden inside it during the ruin hold.
	for label: Node in package.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	var camera := runner.get(&"camera") as Camera3D
	_set_camera(camera, van.to_global(Vector3(3.2, 2.0, 10.0)),
		package.global_position + Vector3.UP * 0.15)
	var before_integrity: float = package.integrity
	var before_state: int = package.trap_state
	package.trap_behavior.set(&"seconds_left", 0.0)
	package.trap_behavior.set(&"integrity", 0.0)
	package.call(&"_report_change", before_integrity, before_state, "Store capture")
	var feedback: Node = package.get_node(^"PackageFeedbackComponent")
	feedback.call(&"_burst_confetti", false)
	feedback.set_process(false)
	for label: Node in package.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	var flash := OmniLight3D.new()
	flash.light_color = Color("ffb347")
	flash.light_energy = 7.0
	flash.omni_range = 5.0
	package.add_child(flash)
	await create_timer(0.16).timeout
	await _save(STORE_SHOTS[3].file)
	await _clear_runner()


func _results() -> void:
	var runner: Node = await _new_runner(&"casa_noche", 2)
	_move_van_to_stop(runner)
	_set_rail_pose(runner, float(runner.get(&"shot").get("duration", 11.0)))
	var hud := (runner.get(&"level") as Node).get_node(^"HUD") as CanvasLayer
	hud.visible = true
	var event_bus: Node = root.get_node(^"/root/EventBus")
	var network: Node = root.get_node(^"/root/NetworkManager")
	event_bus.emit_signal(&"run_ended", 510, {
		"delivered": true,
		"reason": "",
		"elapsed_seconds": 212.4,
		"cargo_points": 150,
		"delivery_points": 275,
		"chaos_multiplier": 1.2,
		"houses_delivered": 2,
		"houses_missed": 0,
		"cargo_total": 2,
		"cargo_intact": 1,
		"cargo_ruined": 0,
		"is_new_best": true,
		"best_score": 510,
		"breakdown": [
			{"label": "Carga entregada", "points": 150},
			{"label": "Dos casas", "points": 275},
		],
		"complaints": [],
		"deliveries": [
			{"house": 0, "trap": "FRÁGIL", "outcome": &"delivered_ok", "photo": true},
			{"house": 1, "trap": "EXPLOSIVO", "outcome": &"delivered_at_risk", "photo": true},
		],
		"awards": [{"title": "MVP", "peer": network.call(&"local_id")}],
		"route_event": {"title": "Inspección sorpresa", "success": true},
	})
	for _i in range(6):
		await process_frame
	await _save(STORE_SHOTS[4].file)
	await _clear_runner()


func _new_runner(shot_name: StringName, cargo_count: int) -> Node:
	var definitions: Dictionary = ShotScript.load_shots()
	var definition: Dictionary = (definitions[String(shot_name)] as Dictionary).duplicate(true)
	definition["cargo"] = cargo_count
	_runner = ShotScript.new()
	_runner.set(&"autoplay", false)
	root.add_child(_runner)
	await _runner.call(&"setup", definition)
	_runner.set_process(false)
	_runner.set_physics_process(false)
	var camera := _runner.get(&"camera") as Camera3D
	camera.set_process(false)
	_freeze_world(_runner)
	return _runner


func _freeze_world(runner: Node) -> void:
	var van := runner.get(&"van") as VehicleBody3D
	van.freeze = true
	van.linear_velocity = Vector3.ZERO
	van.angular_velocity = Vector3.ZERO
	for package: Node in (runner.get(&"level") as Node).get(&"packages"):
		if package is RigidBody3D:
			(package as RigidBody3D).freeze = true


func _move_van_to_stop(runner: Node) -> void:
	var van := runner.get(&"van") as VehicleBody3D
	var aboard: Dictionary = {}
	for package: Node in (runner.get(&"level") as Node).get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			aboard[package] = van.global_transform.affine_inverse() * (package as Node3D).global_transform
	var heading: Vector3 = runner.get(&"_stop_heading")
	van.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP),
		(runner.get(&"stop_point") as Vector3) + Vector3.UP * 0.9)
	for package: Node in aboard:
		(package as Node3D).global_transform = van.global_transform * (aboard[package] as Transform3D)


func _set_rail_pose(runner: Node, seconds: float) -> void:
	var camera := runner.get(&"camera") as Camera3D
	var pose: Array = camera.call(&"pose_at", seconds)
	_set_camera(camera, pose[0], pose[1])


func _set_camera(camera: Camera3D, position: Vector3, target: Vector3) -> void:
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	camera.make_current()


func _save(file_name: String) -> void:
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.get_size() != OUTPUT_SIZE:
		image.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path: String = OUTPUT_DIR.path_join(file_name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Could not save %s (error %d)" % [path, error])
		quit(1)
		return
	print("RENDER: ", ProjectSettings.globalize_path(path), " ", image.get_size())


func _clear_runner() -> void:
	if is_instance_valid(_runner):
		_runner.queue_free()
	await process_frame
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	WorldMood.forced_label = ""
	_runner = null
