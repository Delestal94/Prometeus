extends SceneTree
## Visual review for S-311.36. Run with a rendering display:
## Godot --path do-not-drop --resolution 1280x720 \
##   --script res://tests/render_gel_contexts.gd
##
## Saves eight in-game contexts and a 4x2 contact sheet under
## art/gel_character/review_bloque_d/s311_36_contexts/. Pass
## `-- --only=<name>` to iterate on one context, or `-- --sheet-only` to
## rebuild the contact sheet from the existing eight PNG files.

const OUTPUT: String = "res://../art/gel_character/review_bloque_d/s311_36_contexts"
const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const CONTEXTS: PackedStringArray = [
	"day",
	"sunset",
	"night_flashlights",
	"rain",
	"fog",
	"truck_interior",
	"depot",
	"results",
]

var _camera: Camera3D
var _gel: Node3D
var _level: Node3D
var _only: String = ""
var _sheet_only: bool = false
var _frames: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gel context review needs a rendering display; omit --headless")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			_only = argument.get_slice("=", 1)
		elif argument == "--sheet-only":
			_sheet_only = true
	if not _only.is_empty() and not _only in CONTEXTS:
		push_error("Unknown context '%s'; expected one of %s" % [_only, CONTEXTS])
		quit(2)
		return
	var output_path: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path)
	if not _sheet_only:
		for context: String in CONTEXTS:
			if _only.is_empty() or _only == context:
				await _render_context(context, output_path)
	if _only.is_empty():
		_save_contact_sheet(output_path)
	print("PASS: S-311.36 gel contexts at %s" % output_path)
	quit(0)


func _render_context(context: String, output_path: String) -> void:
	var mood: String = {
		"day": "soleado_dia_verano",
		"sunset": "nublado_atardecer",
		"night_flashlights": "soleado_noche",
		"rain": "lluvia_dia",
		"fog": "niebla_dia_otono",
		"truck_interior": "soleado_dia_verano",
		"depot": "soleado_dia_verano",
		"results": "nublado_atardecer",
	}[context]
	await _build_level(mood)
	match context:
		"day", "sunset", "rain", "fog":
			_setup_courtyard(context)
		"night_flashlights":
			_setup_night_flashlights()
		"truck_interior":
			_setup_truck_interior()
		"depot":
			_setup_depot()
		"results":
			_setup_results()
	for _frame: int in range(12):
		await process_frame
	if context == "results":
		_emit_results()
		for _frame: int in range(8):
			await process_frame
	var frame: Image = await _capture()
	var path: String = output_path.path_join("s311_36_%s.png" % context)
	var error: Error = frame.save_png(path)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [path, error])
		quit(1)
		return
	_frames[context] = frame
	print("Saved ", path)
	await _free_level()


func _build_level(mood: String) -> void:
	root.get_node(^"/root/NetworkManager").set(&"world_seed", 4242)
	root.get_node(^"/root/NetworkManager").set(&"world_house_count", 2)
	WorldMood.forced_label = mood
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	_level.get_node(^"World/Route").set(&"batch_dressing", true)
	root.add_child(_level)
	current_scene = _level
	for layer: Node in _level.find_children("*", "CanvasLayer", false, false):
		(layer as CanvasLayer).hide()
	for child: Node in _level.get_node(^"World").get_children():
		if child.is_in_group(&"player"):
			(child as Node3D).hide()
	_camera = Camera3D.new()
	_camera.far = 600.0
	_camera.fov = 48.0
	_level.add_child(_camera)
	_camera.make_current()
	for _frame: int in range(90):
		await process_frame


func _spawn_gel(at: Vector3, facing: Vector3, color: Color = Color("70d8ee")) -> void:
	_gel = GEL_SCENE.instantiate() as Node3D
	_level.add_child(_gel)
	_gel.global_position = at
	_gel.look_at(facing, Vector3.UP, true)
	PlayerAppearance.set_gel_material(_gel, false)
	PlayerAppearance.set_gel_look(_gel, color, 0.86, 1.08)
	PlayerAppearance.enable_shadows(_gel)
	var animation: AnimationPlayer = PlayerAppearance.find_animation_player(_gel)
	if animation != null and animation.has_animation(&"Idle"):
		animation.play(&"Idle")
		animation.advance(0.32)
		animation.pause()


func _setup_courtyard(context: String) -> void:
	var framing: Dictionary = _route_framing(18)
	var at: Vector3 = framing.at
	var camera_at: Vector3 = framing.camera
	_spawn_gel(at, camera_at)
	_aim(camera_at, at + Vector3.UP * 0.82)
	if context == "rain":
		_add_rain_key_light(at)
	elif context == "fog":
		_camera.fov = 42.0


func _setup_night_flashlights() -> void:
	var framing: Dictionary = _route_framing(18)
	var at: Vector3 = framing.at
	var camera_at: Vector3 = framing.camera
	_spawn_gel(at, camera_at, Color("78d9f0"))
	_add_spot(camera_at + Vector3.UP * 0.7, at + Vector3.UP * 0.8, Color("cce8ff"), 2.2)
	_add_spot(at + Vector3(2.4, 1.5, 1.8), at + Vector3.UP * 0.7, Color("ffd6a0"), 1.2)
	_aim(camera_at, at + Vector3.UP * 0.82)


func _setup_truck_interior() -> void:
	var van: VehicleBody3D = _level.get(&"vehicle")
	van.call(&"set_door_open", &"rear", true)
	var floor_y: float = _bay_floor(van)
	var at: Vector3 = van.to_global(Vector3(0.0, floor_y + 0.02, 1.65))
	var camera_at: Vector3 = van.to_global(Vector3(0.0, 1.45, 4.15))
	_spawn_gel(at, camera_at, Color("76d9ee"))
	_add_spot(camera_at + Vector3.UP * 0.2, at + Vector3.UP, Color("e8f3ff"), 0.7)
	_camera.fov = 50.0
	_aim(camera_at, at + Vector3.UP * 0.78)


func _setup_depot() -> void:
	var depot: Node3D = _level.get(&"depot")
	var at: Vector3 = depot.to_global(Vector3(-2.5, 0.02, 17.0))
	var camera_at: Vector3 = depot.to_global(Vector3(2.2, 1.65, 20.6))
	_spawn_gel(at, camera_at, Color("72d7ec"))
	_add_spot(camera_at + Vector3(0.0, 1.2, -1.0), at + Vector3.UP, Color("fff0d0"), 2.0)
	_camera.fov = 50.0
	_aim(camera_at, at + Vector3.UP * 0.85)


func _setup_results() -> void:
	var depot: Node3D = _level.get(&"depot")
	var at: Vector3 = depot.to_global(Vector3(-5.0, 0.02, 10.5))
	var camera_at: Vector3 = depot.to_global(Vector3(-8.0, 1.6, 7.0))
	_spawn_gel(at, camera_at, Color("72d7ec"))
	_aim(camera_at, at + Vector3.UP * 0.82)
	var screen_right: Vector3 = _camera.global_basis.x
	_camera.look_at(at + Vector3.UP * 0.82 + screen_right * 2.4, Vector3.UP)
	_level.get_node(^"HUD").show()


func _emit_results() -> void:
	root.get_node(^"/root/EventBus").run_ended.emit(378, {
		"delivered": true,
		"reason": "",
		"elapsed_seconds": 212.4,
		"cargo_points": 100,
		"delivery_points": 215,
		"payout": 315,
		"chaos_multiplier": 1.2,
		"houses_delivered": 2,
		"houses_missed": 1,
		"cargo_total": 1,
		"cargo_intact": 1,
		"cargo_ruined": 0,
		"is_new_best": true,
		"best_score": 378,
		"complaints": [{"house": 1, "dismissed": true}],
		"deliveries": [
			{"house": 0, "trap": "FRÁGIL", "outcome": &"delivered_ok", "photo": true},
			{"house": 1, "trap": "EQUILIBRIO", "outcome": &"delivered_at_risk", "photo": true},
			{"house": 2, "trap": "RUIDOSO", "outcome": &"missed", "photo": false},
		],
		"awards": [
			{"title": "MVP", "peer": 1},
			{"title": "Rescatista", "peer": 2},
			{"title": "Mano firme", "peer": 1},
		],
		"route_event": {"title": "Inspección sorpresa", "success": true},
	})


func _add_spot(at: Vector3, target: Vector3, color: Color, energy: float) -> void:
	var light := SpotLight3D.new()
	_level.add_child(light)
	light.global_position = at
	light.light_color = color
	light.light_energy = energy
	light.spot_range = 12.0
	light.spot_angle = 34.0
	light.shadow_enabled = true
	light.look_at(target, Vector3.UP)


func _add_rain_key_light(at: Vector3) -> void:
	_add_spot(at + Vector3(-2.5, 4.0, -2.0), at + Vector3.UP, Color("b9ddff"), 1.2)


func _route_framing(index: int) -> Dictionary:
	var route: Node3D = _level.get_node(^"World/Route")
	var path: Array = route.get(&"_path_points")
	var safe_index: int = clampi(index, 2, path.size() - 3)
	var centre: Vector3 = path[safe_index]
	var tangent: Vector3 = (path[safe_index + 2] as Vector3) - (path[safe_index - 2] as Vector3)
	tangent.y = 0.0
	tangent = tangent.normalized()
	var side := Vector3(-tangent.z, 0.0, tangent.x)
	var gel_local: Vector3 = centre + side * 1.9
	var camera_local: Vector3 = centre - side * 2.6 - tangent * 0.8
	gel_local.y = float(route.get(&"terrain").call(&"height_at", gel_local)) + 0.03
	camera_local.y = float(route.get(&"terrain").call(&"height_at", camera_local)) + 1.48
	return {
		"at": route.to_global(gel_local),
		"camera": route.to_global(camera_local),
	}


func _bay_floor(van: VehicleBody3D) -> float:
	var from: Vector3 = van.to_global(Vector3(0.0, 1.6, 4.0))
	var to: Vector3 = van.to_global(Vector3(0.0, -1.0, 4.0))
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 64)
	var hit: Dictionary = van.get_world_3d().direct_space_state.intersect_ray(query)
	return van.to_local(hit.position).y if not hit.is_empty() else 0.55


func _aim(at: Vector3, target: Vector3) -> void:
	_camera.global_position = at
	_camera.look_at(target, Vector3.UP)
	_camera.make_current()


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save_contact_sheet(output_path: String) -> void:
	var sheet := Image.create_empty(1920, 540, false, Image.FORMAT_RGBA8)
	for index: int in CONTEXTS.size():
		var context: String = CONTEXTS[index]
		var frame: Image
		if _frames.has(context):
			frame = (_frames[context] as Image).duplicate()
		else:
			frame = Image.load_from_file(output_path.path_join("s311_36_%s.png" % context))
		if frame == null or frame.is_empty():
			push_error("Missing source PNG for contact-sheet context: %s" % context)
			return
		frame.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i((index % 4) * 480, (index / 4) * 270)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), destination)
	var path: String = output_path.path_join("s311_36_contact_sheet.png")
	var error: Error = sheet.save_png(path)
	if error != OK:
		push_error("Cannot save %s (got %d)" % [path, error])


func _free_level() -> void:
	_level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	WorldMood.forced_label = ""
	_level = null
	_gel = null
	_camera = null
