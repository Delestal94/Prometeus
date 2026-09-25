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
## of a kind, a deer crossing or a house), how fast the autopilot drives it,
## where it stops, what happens (a train, a roll), how many boxes ride along,
## and the camera's rail (TrailerCamera). The HUD and the floating in-world
## labels are hidden, and the truck's doors shut: these are for the store
## page and the trailer.
##
## Start options ("start"):
##   at        depot | segment | crossing | house
##   segment   the segment kind (at: segment); the seed, unless the shot fixes
##             one, is the first whose route has that kind at least lead +
##             RUN_UP_MARGIN metres out -- not the depot's own doorstep
##   lead      metres of run-up before the segment / crossing / house stop
##   stop      (segment) stop this many metres before the segment's middle
##   train     (segment, RailCrossingSegment) the barriers do come down
##
## The anchor space of the rail: the segment (at: segment), the crossing
## turned so the deer waits at +x (crossing), or the truck's stop on the road
## facing along it with the house at +x (house).

const SHOTS_PATH: String = "res://data/trailer_shots.json"
const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
const TrailerCameraScript = preload("res://scripts/tools/trailer_camera.gd")
const RouteScript = preload("res://scripts/gameplay/route/route.gd")
const LOOKAHEAD: float = 14.0
## A shot's segment is at least its lead plus this far from the depot.
const RUN_UP_MARGIN: float = 60.0
## How hard the autopilot can brake, to start slowing in time (m/s^2).
const BRAKING: float = 2.5
const CARGO_MOUNTS: Array[String] = [
	"CargoBay/LeftSeat1PackageMount", "CargoBay/RightSeat1PackageMount", "CargoBay/LeftSeat2PackageMount",
	"CargoBay/RightSeat2PackageMount", "CargoBay/LeftShelfPackageMount", "CargoBay/RightShelfPackageMount",
]

var shot: Dictionary = {}
## Off in tests: they call setup() themselves.
var autoplay: bool = true
var level: Node
var route: Node3D
var van: VehicleBody3D
var camera: Camera3D
## What the shot is about: its segment, deer crossing or house (null at the depot).
var focus: Node3D
var _time: float = 0.0
var _path: Array[Vector3] = []
var _path_index: int = 0
## Where the autopilot stops (world space) and the road's heading there;
## `_stopping` false when the shot doesn't stop.
var _stopping: bool = false
var stop_point: Vector3 = Vector3.ZERO
var _stop_heading: Vector3 = Vector3.FORWARD
var _rolled: bool = false
var _landed: bool = false
var _still_at: float = -1.0
var _out_path: String = ""
var _frames_dir: String = ""
var _frame_step: float = 0.0
var _next_frame: float = 0.0
var _frame_count: int = 0


static func load_shots() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOTS_PATH))
	return parsed if parsed is Dictionary else {}


static func find_seed(kind: String, houses: int, first_seed: int = 1, min_start: float = 0.0) -> int:
	# The first seed whose route has a `kind` segment at least `min_start`
	# metres down the road (plan only, no build).
	for seed_value: int in range(first_seed, first_seed + 400):
		var plan: Dictionary = RouteScript.plan_spine(seed_value, houses, true)
		for entry: Dictionary in plan.segments:
			if (entry.script as Script).get_global_name() == kind and float(entry.get("start", 0.0)) >= min_start:
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
		seed_value = find_seed(String(start.get("segment", "StraightSegment")), houses, 1, float(start.get("lead", 60.0)) + RUN_UP_MARGIN)
	var network: Node = get_node(^"/root/NetworkManager")
	network.set(&"world_seed", seed_value)
	network.set(&"world_house_count", houses)
	WorldMood.forced_label = String(shot.get("mood", "soleado_dia"))
	level = load(LEVEL).instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	_hide_overlays()
	van = level.get(&"vehicle")
	route = level.get_node(^"World/Route")
	_path.assign(route.get(&"_path_points"))
	_load_cargo(int(shot.get("cargo", 1)))
	level.call(&"start_debug_delivery")
	await get_tree().physics_frame
	# Boarding opened the cab door and the load left the back open (ramp
	# down): shut for a driving shot.
	for door: StringName in [&"rear", &"cab_left", &"cab_right"]:
		van.call(&"set_door_open", door, false)
	var anchor := Transform3D.IDENTITY
	match String(start.get("at", "depot")):
		"segment":
			var segment: Node3D = _first_segment(String(start.segment), float(start.get("lead", 60.0)) + 20.0)
			if segment != null:
				focus = segment
				anchor = segment.global_transform
				var segment_start: float = float(segment.get_meta(&"route_distance", 0.0))
				_place_before(segment_start - float(start.get("lead", 60.0)))
				if start.has("stop"):
					_set_stop(segment_start + float(segment.get(&"length")) * 0.5 - float(start.stop))
				if bool(start.get("train", false)) and &"will_close" in segment:
					segment.set(&"will_close", true)
		"crossing":
			# A deer crossing (RouteDresser._dress_crossings), mid-straight:
			# the run-up is measured to the crossing itself, so nothing else
			# (a level crossing's barrier) comes between.
			var crossing := route.find_child("DeerCrossing", true, false) as Node3D
			if crossing != null:
				focus = crossing
				anchor = _mirrored_toward(crossing.global_transform, crossing.global_transform * Vector3(float(crossing.get(&"side")), 0.0, 0.0))
				_place_before(float(route.call(&"road_distance", crossing.global_position)) - float(start.get("lead", 60.0)))
		"house":
			var house: Node3D = (route.get(&"houses") as Array)[int(start.get("index", 0))]
			focus = house
			var stop: float = float(route.call(&"stop_road_distance", int(start.get("index", 0))))
			_place_before(stop - float(start.get("lead", 90.0)))
			_set_stop(stop)
			anchor = _mirrored_toward(Transform3D(Basis.looking_at(_stop_heading, Vector3.UP), stop_point), house.global_position)
		_:
			anchor = level.get(&"depot").global_transform
	camera = TrailerCameraScript.new()
	camera.name = "TrailerCamera"
	camera.set(&"target", van)
	add_child(camera)
	camera.call(&"play", shot.get("rail", []), anchor)


## `frame`, with its x axis flipped if need be so `point` lies on its +x side:
## a rail written for "the house on the right" works on either side.
func _mirrored_toward(frame: Transform3D, point: Vector3) -> Transform3D:
	if (frame.affine_inverse() * point).x < 0.0:
		frame.basis.x = -frame.basis.x
	return frame


## `count` boxes aboard (the debug start loads one): more to fly in a roll.
func _load_cargo(count: int) -> void:
	var player: Node = level.get(&"local_player")
	var packages: Array = level.get(&"packages")
	if player == null:
		return
	var loaded: int = 0
	for package: RigidBody3D in packages:
		if loaded >= count or loaded >= CARGO_MOUNTS.size():
			break
		var mount: Node = van.get_node_or_null(NodePath(CARGO_MOUNTS[loaded] + "/InteractionArea"))
		if mount == null or not is_instance_valid(package):
			continue
		player.call(&"pick_up", package.get_path())
		mount.call(&"interact", player)
		loaded += 1


## HUD, menus and the floating in-world labels (a house's "CASA 1" tag):
## game UI, not scenery. Run every frame -- the run's banners come later.
func _hide_overlays() -> void:
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	if level == null:
		return
	for label: Node in level.find_children("*", "Label3D", true, false):
		if (label as Label3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			(label as Label3D).visible = false


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


## The stop at exactly `distance` metres along the road: interpolated between
## path points, which are 10 m apart -- rounding to the next one stopped the
## truck up to 10 m late, on the level crossing's tracks.
func _set_stop(distance: float) -> void:
	var cumulative: PackedFloat32Array = route.call(&"_path_cumulative")
	var index: int = clampi(_index_at(distance), 1, _path.size() - 1)
	var span: float = maxf(cumulative[index] - cumulative[index - 1], 0.001)
	var weight: float = clampf((distance - cumulative[index - 1]) / span, 0.0, 1.0)
	var from: Vector3 = route.to_global(_path[index - 1])
	var to: Vector3 = route.to_global(_path[index])
	stop_point = from.lerp(to, weight)
	var heading: Vector3 = to - from
	heading.y = 0.0
	_stop_heading = heading.normalized() if heading.length() > 0.001 else Vector3.FORWARD
	_stopping = true


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
	if _rolled and not _landed and van.global_basis.y.dot(Vector3.UP) < 0.15:
		# On its side: most of the spin goes, so it doesn't carry on over onto
		# its roof.
		_landed = true
		van.angular_velocity *= 0.25
	var roll: Dictionary = shot.get("roll", {})
	if not roll.is_empty() and not _rolled and _time >= float(roll.get("t", 2.0)):
		# Clip the kerb too fast: a spin about the roll axis and a hop, at
		# speed (`strength` in radians a second). Set, not pushed: the truck's
		# low centre of mass shrugged off an impulse.
		_rolled = true
		van.freeze = false
		# The truck's centre of mass sits under its floor (vehicle.tscn), so
		# on its side gravity rolled it straight back onto its wheels: for
		# the shot, lift it to mid-body so the truck comes to rest lying there.
		van.center_of_mass = Vector3(0.0, 0.8, 0.1)
		van.angular_velocity = van.global_basis.z * float(roll.get("strength", 5.0))
		van.linear_velocity += Vector3.UP * 4.0 + van.global_basis.x * 3.0
		# The boxes come loose and carry on with the truck's speed, tossed up
		# and out the way it's going over.
		var rng := RandomNumberGenerator.new()
		rng.seed = 906
		for package: RigidBody3D in level.call(&"_release_loaded_cargo"):
			package.linear_velocity = van.linear_velocity * 0.8 + Vector3.UP * rng.randf_range(3.0, 6.0) + van.global_basis.x * rng.randf_range(2.0, 5.0)
			package.angular_velocity = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))


## Pure pursuit along the road at the shot's speed, braking to a stop at the
## house for an arrival shot. The truck drives itself; nobody's at the wheel.
func _drive() -> void:
	if _rolled:
		# Nobody drives a truck that's going over: it doesn't get righted and
		# driven off.
		van.set_controls(0.0, 0.0, false)
		return
	if _path_index >= _path.size() - 1:
		van.set_controls(0.0, 0.0, true)
		return
	var here: Vector3 = route.to_local(van.global_position)
	while _path_index < _path.size() - 1 and Vector2(_path[_path_index].x - here.x, _path[_path_index].z - here.z).length() < LOOKAHEAD:
		_path_index += 1
	var local: Vector3 = van.global_transform.affine_inverse() * route.to_global(_path[_path_index])
	var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	var target_kmh: float = float(shot.get("speed_kmh", 40.0))
	var speed: float = float(van.get(&"speed_kmh"))
	if _stopping:
		# Brake in time to stand still at the stop, not a lookahead past it.
		var to_stop: float = van.global_position.distance_to(stop_point)
		var metres_per_second: float = speed / 3.6
		if to_stop < metres_per_second * metres_per_second / (2.0 * BRAKING) + 1.5 or _passed_stop():
			target_kmh = 0.0
	var throttle: float = 0.35
	if target_kmh <= 0.0:
		throttle = -1.0 if speed > 1.0 else 0.0
	elif speed < target_kmh - 2.0:
		throttle = 1.0
	elif speed > target_kmh + 3.0:
		throttle = -0.6
	van.set_controls(throttle, steer, target_kmh <= 0.0 and speed < 1.0)


## Whether the truck is already beyond the stop along the road.
func _passed_stop() -> bool:
	return (van.global_position - stop_point).dot(_stop_heading) > 0.0


func _process(delta: float) -> void:
	if van == null:
		return
	_hide_overlays()
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
	# Only when running on its own: a test drives the shot and quits itself.
	if autoplay and _time > float(shot.get("duration", 8.0)) and _still_at < 0.0:
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
