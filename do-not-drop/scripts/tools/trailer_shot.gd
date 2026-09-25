extends Node
## Plays one of the trailer's shots (tareas de Nacho N-902, N-905, N-906),
## debug tool, never exported (tools/export presets leave scripts/tools and
## scenes/tools out). Needs a display:
##
##   godot --path do-not-drop res://scenes/tools/trailer_shot.tscn -- --shot=cruce_tren
##   ... --write-movie ../art/devlog/cruce.avi        (Godot's movie maker: the whole shot)
##   ... -- --shot=casa_noche --still=4.5 --out=../art/marketing/capturas/casa_noche.png
##   ... -- --shot=vuelco --frames=/tmp/vuelco --fps=12   (PNG frames, for a GIF)
##
## The shots are in data/trailer_shots.json: which world (seed, weather),
## where the truck starts (the depot, or some metres before the first segment
## of a kind, or before a house), how fast the autopilot drives it, what
## happens (a roll), and the camera's rail (TrailerCamera). The HUD is hidden:
## these are for the store page and the trailer.

const SHOTS_PATH: String = "res://data/trailer_shots.json"
const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
const TrailerCameraScript = preload("res://scripts/tools/trailer_camera.gd")
const RouteScript = preload("res://scripts/gameplay/route/route.gd")
const LOOKAHEAD: float = 14.0

var shot: Dictionary = {}
## Off in tests: they call setup() themselves.
var autoplay: bool = true
var level: Node
var route: Node3D
var van: VehicleBody3D
var camera: Camera3D
var _time: float = 0.0
var _path: Array[Vector3] = []
var _path_index: int = 0
var _stop_at: int = -1
var _rolled: bool = false
var _still_at: float = -1.0
var _out_path: String = ""
var _frames_dir: String = ""
var _frame_step: float = 0.0
var _next_frame: float = 0.0
var _frame_count: int = 0


static func load_shots() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOTS_PATH))
	return parsed if parsed is Dictionary else {}


static func find_seed(kind: String, houses: int, first_seed: int = 1) -> int:
	# The first seed whose route has a `kind` segment (plan only, no build).
	for seed_value: int in range(first_seed, first_seed + 400):
		var plan: Dictionary = RouteScript.plan_spine(seed_value, houses, true)
		for entry: Dictionary in plan.segments:
			if (entry.script as Script).get_global_name() == kind:
				return seed_value
	return first_seed


func _ready() -> void:
	if not autoplay:
		return
	var name: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			name = arg.get_slice("=", 1)
		elif arg.begins_with("--still="):
			_still_at = float(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out_path = arg.get_slice("=", 1)
		elif arg.begins_with("--frames="):
			_frames_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--fps="):
			_frame_step = 1.0 / maxf(float(arg.get_slice("=", 1)), 1.0)
	var shots: Dictionary = load_shots()
	if name.is_empty() or not shots.has(name):
		print("Shots: ", ", ".join(PackedStringArray(shots.keys())))
		name = shots.keys()[0] if not shots.is_empty() else ""
	shot = shots.get(name, {})
	if shot.is_empty():
		push_error("No trailer shots in %s" % SHOTS_PATH)
		get_tree().quit(1)
		return
	if not _frames_dir.is_empty() and _frame_step <= 0.0:
		_frame_step = 1.0 / 12.0
	await setup(shot)


## Builds the shot's world and puts everything in place. Public so a test
## can run the setup headless.
func setup(definition: Dictionary) -> void:
	shot = definition
	var houses: int = int(shot.get("houses", 2))
	var seed_value: int = int(shot.get("seed", 0))
	var start: Dictionary = shot.get("start", {})
	if seed_value == 0:
		seed_value = find_seed(String(start.get("segment", "StraightSegment")), houses)
	var network: Node = get_node(^"/root/NetworkManager")
	network.set(&"world_seed", seed_value)
	network.set(&"world_house_count", houses)
	WorldMood.forced_label = String(shot.get("mood", "soleado_dia"))
	level = load(LEVEL).instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	for layer: Node in level.find_children("*", "CanvasLayer", false, false):
		(layer as CanvasLayer).visible = false
	van = level.get(&"vehicle")
	route = level.get_node(^"World/Route")
	_path.assign(route.get(&"_path_points"))
	level.call(&"start_debug_delivery")
	await get_tree().physics_frame
	var anchor := Transform3D.IDENTITY
	match String(start.get("at", "depot")):
		"segment":
			var segment: Node3D = _first_segment(String(start.segment), float(start.get("lead", 60.0)) + 20.0)
			if segment != null:
				anchor = segment.global_transform
				_place_before(float(segment.get_meta(&"route_distance", 0.0)) - float(start.get("lead", 60.0)))
		"house":
			var house: Node3D = (route.get(&"houses") as Array)[int(start.get("index", 0))]
			anchor = house.global_transform
			var stop: float = float(route.call(&"stop_road_distance", int(start.get("index", 0))))
			_place_before(stop - float(start.get("lead", 90.0)))
			_stop_at = _index_at(stop)
		_:
			anchor = level.get(&"depot").global_transform
	camera = TrailerCameraScript.new()
	camera.name = "TrailerCamera"
	camera.set(&"target", van)
	add_child(camera)
	camera.call(&"play", shot.get("rail", []), anchor)


## The first `kind` segment at least `from` metres down the road (room for
## the run-up), or the first of that kind at all.
func _first_segment(kind: String, from: float = 0.0) -> Node3D:
	var fallback: Node3D = null
	for child: Node in route.get_children():
		if child is RouteSegment and (child.get_script() as Script).get_global_name() == kind:
			if float(child.get_meta(&"route_distance", 0.0)) >= from:
				return child
			if fallback == null:
				fallback = child
	return fallback


func _index_at(distance: float) -> int:
	var cumulative: PackedFloat32Array = route.call(&"_path_cumulative")
	for index: int in range(cumulative.size()):
		if cumulative[index] >= distance:
			return index
	return cumulative.size() - 1


## The truck, with its boxes aboard, at `distance` metres along the road,
## facing along it and already at the shot's speed.
func _place_before(distance: float) -> void:
	var index: int = clampi(_index_at(maxf(distance, 0.0)), 0, _path.size() - 2)
	var at: Vector3 = route.to_global(_path[index])
	var ahead: Vector3 = route.to_global(_path[index + 1])
	var aboard: Dictionary = {}
	for package: RigidBody3D in level.get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			aboard[package] = van.global_transform.affine_inverse() * package.global_transform
	var direction: Vector3 = (ahead - at).normalized()
	van.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), at + Vector3.UP * 0.9)
	van.linear_velocity = direction * float(shot.get("speed_kmh", 40.0)) / 3.6
	van.angular_velocity = Vector3.ZERO
	for package: RigidBody3D in aboard:
		package.global_transform = van.global_transform * (aboard[package] as Transform3D)
		package.linear_velocity = van.linear_velocity
	_path_index = index + 1


func _physics_process(_delta: float) -> void:
	if van == null:
		return
	_drive()
	var roll: Dictionary = shot.get("roll", {})
	if not roll.is_empty() and not _rolled and _time >= float(roll.get("t", 2.0)):
		# Clip the kerb too fast: a spin about the roll axis and a hop, at
		# speed (`strength` in radians a second). Set, not pushed: the truck's
		# low centre of mass shrugged off an impulse.
		_rolled = true
		van.freeze = false
		van.angular_velocity = van.global_basis.z * float(roll.get("strength", 5.0))
		van.linear_velocity += Vector3.UP * 4.0 + van.global_basis.x * 3.0


## Pure pursuit along the road at the shot's speed, braking to a stop at the
## house for an arrival shot. The truck drives itself; nobody's at the wheel.
func _drive() -> void:
	if _path_index >= _path.size() - 1:
		van.set_controls(0.0, 0.0, true)
		return
	var here: Vector3 = route.to_local(van.global_position)
	while _path_index < _path.size() - 1 and Vector2(_path[_path_index].x - here.x, _path[_path_index].z - here.z).length() < LOOKAHEAD:
		_path_index += 1
	var local: Vector3 = van.global_transform.affine_inverse() * route.to_global(_path[_path_index])
	var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	var target_kmh: float = float(shot.get("speed_kmh", 40.0))
	if _stop_at >= 0 and _path_index >= _stop_at - 2:
		target_kmh = 0.0
	var speed: float = float(van.get(&"speed_kmh"))
	var throttle: float = 0.35
	if target_kmh <= 0.0:
		throttle = -1.0 if speed > 1.0 else 0.0
	elif speed < target_kmh - 2.0:
		throttle = 1.0
	elif speed > target_kmh + 3.0:
		throttle = -0.6
	van.set_controls(throttle, steer, target_kmh <= 0.0 and speed < 1.0)


func _process(delta: float) -> void:
	if van == null:
		return
	_time += delta
	if _frame_step > 0.0 and _time >= _next_frame:
		_next_frame += _frame_step
		_save_frame(_frames_dir.path_join("frame_%04d.png" % _frame_count))
		_frame_count += 1
	if _still_at >= 0.0 and _time >= _still_at:
		_still_at = -1.0
		await RenderingServer.frame_post_draw
		_save_frame(_out_path if not _out_path.is_empty() else "user://trailer_still.png")
		get_tree().quit()
		return
	if _time > float(shot.get("duration", 8.0)) and _still_at < 0.0:
		get_tree().quit()


func _save_frame(path: String) -> void:
	var texture: ViewportTexture = get_viewport().get_texture()
	if texture == null:
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)
