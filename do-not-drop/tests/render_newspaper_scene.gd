extends SceneTree
## Run without --headless. Saves the next-day newspaper scene (N-606.3) under
## user://render_newspaper_scene/ (or --out=<absolute dir>): one image per shot
## of a busy run in Spanish (office, approach, spread, each story's close-up,
## spread again, reaction), the results that follow, a skip hint, and the
## front close-up of the same paper in English and of a clean run.
## The busy run's front story has its photo (N-606.5): a real PressPhoto
## capture, framed by NewsPhotographer, of the truck and a stag staged on a
## patch of road; the raw capture is saved too (00_raw_photo.png).
## Window size: pass --resolution WxH to see other shapes.

const DESK: GDScript = preload("res://scripts/presentation/newspaper/news_desk.gd")

var out_dir: String = "user://render_newspaper_scene"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual review needs a rendering display; omit --headless.")
		quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bus: Node = root.get_node("EventBus")
	var settings: Node = root.get_node("GameSettings")
	settings.set(&"newspaper_mode", 0)
	var hud: CanvasLayer = load("res://scripts/ui/hud/hud.gd").new()
	root.add_child(hud)
	for _i in range(4):
		await process_frame
	hud.pause.primary_action()
	var crew: Array = [{"peer": 1, "nick": "Turbo"}, {"peer": 2, "nick": ""}, {"peer": 3, "nick": "Manos de Manteca"}]
	var busy: Array = [
		_fact("deer_hit", -1, [], 1), _fact("missed", 1, ["cake"]), _fact("abandoned", 0, ["hen", "noisy"]),
		_fact("fault_mirror"), _fact("delivered_ruined", 2, ["vase"]), _fact("photo", 2),
	]
	var context: Dictionary = {"seed": 12, "town": "San Ceferino del Bache", "km": 1.5, "minutes": 3, "crew": crew}
	var results: Dictionary = {"delivered": true, "elapsed_seconds": 100.0, "score": 120, "best_score": 500,
			"cargo_total": 5, "cargo_intact": 3, "houses_delivered": 3, "houses_missed": 2, "breakdown": [],
			"deliveries": []}
	var paper: Dictionary = DESK.compose(busy, context)
	var photographer: Node = await _stage_photo(String(paper["front"]["id"]))

	# Every shot of the busy run, in Spanish.
	settings.call(&"set_language", "es")
	var director: Control = await _open(bus, hud, paper, results)
	var timeline: Array = director.get("timeline")
	var duration: float = director.get("duration")
	for index: int in timeline.size():
		var shot: Dictionary = timeline[index]
		# Mid-move for the travelling shots, else just before the cut.
		var share: float = 0.5 if shot["id"] in ["office", "approach"] else 0.97
		var at: float = float(shot["start"]) + float(shot["seconds"]) * share
		await _seek(director, at)
		await _shot("%02d_%s" % [index + 1, shot["id"]])
		if shot["id"] == "spread":
			director.call(&"_input", _action(&"interact", true))
			await _seek(director, float(director.get("time")) + 0.3)
			await _shot("%02d_skip_hint" % (timeline.size() + 1))
			director.call(&"_input", _action(&"interact", false))
	await _seek(director, duration + 0.2)
	for _i in range(6):
		await process_frame
	await _shot("%02d_results" % (timeline.size() + 2))
	_close_results(hud)

	# The same paper in English, and a clean run: the front close-up.
	for case: Array in [["en", paper, "front_en"], ["es", DESK.compose([], context), "front_clean"]]:
		settings.call(&"set_language", case[0])
		director = await _open(bus, hud, case[1], results)
		for shot: Dictionary in director.get("timeline"):
			if shot["id"] == "front":
				await _seek(director, float(shot["start"]) + float(shot["seconds"]) - 0.1)
		await _shot(case[2])
		hud.newspaper.dismiss()
		_close_results(hud)
	settings.call(&"set_language", "es")
	photographer.queue_free()
	print("Saved to ", ProjectSettings.globalize_path(out_dir))
	quit()


## The truck on a patch of road with a stag at its nose, shot the way the
## photographer shoots a deer hit; the photo is kept for `story`.
func _stage_photo(story: String) -> Node:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a9c4d6")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("6f8a4a")
	ground.material_override = grass
	stage.add_child(ground)
	var road := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(7, 80)
	road.mesh = strip
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("55524d")
	road.material_override = asphalt
	road.position.y = 0.01
	stage.add_child(road)
	var van := Node3D.new()
	van.add_to_group(&"vehicle")
	stage.add_child(van)
	var truck: Node3D = (load("res://assets/models/truck_reference_lowpoly.glb") as PackedScene).instantiate()
	van.add_child(truck)
	var stag_model: PackedScene = load("res://assets/models/environment/wildlife/sm_env_animal_stag_rigged.glb")
	var stag: Node3D = stag_model.instantiate()
	stage.add_child(stag)
	stag.position = Vector3(0.6, 0.0, -4.6)
	stag.rotation_degrees = Vector3(0, 70, 12)
	var photographer: Node = (load("res://scripts/presentation/newspaper/news_photographer.gd") as GDScript).new()
	root.add_child(photographer)
	for _i in range(3):
		await process_frame
	var photo: Texture2D = await PressPhoto.capture(photographer, photographer.call(&"pose_for", &"deer_hit"))
	if photo != null:
		photo.get_image().save_png(out_dir.path_join("00_raw_photo.png"))
		photographer.get("photos")[story] = photo
	stage.queue_free()
	return photographer


func _open(bus: Node, hud: CanvasLayer, paper: Dictionary, results: Dictionary) -> Control:
	bus.newspaper_ready.emit(paper)
	bus.run_ended.emit(120, results)
	for _i in range(8):
		await process_frame
	return hud.newspaper.director


## Jumps the scene's clock to `at` seconds as if it had played up to there.
func _seek(director: Control, at: float) -> void:
	# Driven by hand only: the captures take real frames, which mustn't move the clock.
	if is_instance_valid(director):
		director.set_process(false)
	while is_instance_valid(director) and not bool(director.get("done")) and float(director.get("time")) < at:
		director.call(&"_process", minf(0.1, at - float(director.get("time"))))
	await process_frame


func _shot(file_name: String) -> void:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = out_dir.path_join(file_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))


func _fact(kind: String, house: int = -1, tags: Array = [], peer: int = 0) -> Dictionary:
	return {"kind": kind, "house": house, "tags": tags, "peer": peer}


func _action(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _close_results(hud: CanvasLayer) -> void:
	hud.overlay.hide()
	hud.overlay_mode = "run"
