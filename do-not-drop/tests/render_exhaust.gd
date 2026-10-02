extends SceneTree
## Run without --headless (revisor-visual). The exhaust smoke (N-324,
## vehicle_effects.gd) on an asphalt road, so no dust gets mixed into it. Three
## states of the truck, each from a fresh start:
##   idle    parked with the engine on, throttle 0
##   launch  throttle 1 from a standstill after an idle, shot 0.35 s later (under
##           10 km/h): the idling plume is still around the truck, just fed more
##   full    throttle 1 kept until ~40 km/h (the truck is on the move)
## and three shots per state, each from a camera that rides on the truck:
##   rear    behind the truck, a few metres off the ramp, looking at the pipe
##   cargo   from the rack seat nearest the rear, looking out of the open ramp
##   side    low, off the driver's side behind the truck, looking at the pipe
## Each shot is a fresh truck. Saves exhaust_{idle,launch,full}_{rear,cargo,side}.png and prints, per shot,
## the speed, the emitter's state (on/off, amount_ratio), the real position of the pipe
## (in the truck's space, against VehicleEffects.exhaust_anchor, and in the world), its
## height above the road by a ray down from the pipe (it must read 0.5-1.0 m), and
## its distance to each of the three cameras (the smoke stays quiet within 1.5 m of the
## viewer).
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_exhaust.gd \
##       -- --mood=day --seed=7 --out=D:/tmp/exhaust
## --mood=day|night are shortcuts for soleado_dia_verano and soleado_noche; any label of
## world_mood.gd works too: <soleado|nublado|lluvia|niebla>_<dia|atardecer|noche>[_<verano|otono>],
## e.g. lluvia_dia. --state=idle|launch|full does one state only. --out=<dir> is where
## the PNGs go (created if missing).
## --nosmoke hides the emitter (same truck, same cameras, same frames) to subtract the
## smoke pixel by pixel from the shots without it.
## --dry runs the drive and prints the lines without drawing or saving (works
## with --headless: a smoke test of the setup).

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")
## Loaded at run time, not preloaded: vehicle_effects.gd preloads vehicle.gd, which names autoloads that a
## --script does not have yet when it compiles (same as trailer_shot.gd in test_trailer_shots.gd).
const VEHICLE_EFFECTS_PATH: String = "res://scripts/presentation/vehicle_effects.gd"
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const VEHICLE_SCENE: String = "res://scenes/gameplay/vehicle/vehicle.tscn"
const DEFAULT_MOOD: String = "soleado_dia_verano"
const MOOD_SHORTCUTS: Dictionary = {
	"day": "soleado_dia_verano",
	"night": "soleado_noche",
}
const ROAD_LENGTH: float = 1200.0
const ROAD_START_Z: float = 100.0
const START_Z: float = 70.0
const FULL_KMH: float = 40.0
## Idle before the throttle goes down, longer than the smoke's life.
const PREROLL_SECONDS: float = 2.5
## Local camera poses on the truck (+Z is the rear): where, and what it looks at.
const VIEWS: Dictionary = {
	"rear": [Vector3(1.6, 1.9, 10.5), Vector3(-0.4, 0.5, 4.8)],
	"cargo": [Vector3(0.74, 1.24, 3.125), Vector3(0.2, 0.2, 9.0)],
	"side": [Vector3(-3.6, 0.9, 7.0), Vector3(-0.9, 0.5, 4.6)],
}
## state: [throttle, seconds of it before the shot (0: until FULL_KMH)]
const STATES: Dictionary = {
	"idle": [0.0, 0.0],
	"launch": [1.0, 0.35],
	"full": [1.0, 0.0],
}

var _world: Node3D
var _terrain: Node3D
var _camera: Camera3D
var _out_dir: String = "user://"
var _dry: bool = false
var _no_smoke: bool = false
var _mood_label: String = DEFAULT_MOOD


## A world that holds the mood the sky should dress itself with (RouteSky reads it).
class MoodWorld:
	extends Node3D
	var mood: WorldMood


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var seed_value: int = 7
	var only: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--mood="):
			_mood_label = MOOD_SHORTCUTS.get(arg.get_slice("=", 1), arg.get_slice("=", 1))
		elif arg.begins_with("--state="):
			only = arg.get_slice("=", 1)
		elif arg == "--nosmoke":
			_no_smoke = true
		elif arg == "--dry":
			_dry = true
	if DisplayServer.get_name() == "headless" and not _dry:
		push_error("Visual review needs a rendering display; omit --headless (or pass --dry).")
		quit(2)
		return
	if not _dry:
		DirAccess.make_dir_recursive_absolute(_out_dir)
	root.size = Vector2i(1280, 720)
	root.get_node(^"/root/NetworkManager").set(&"world_seed", seed_value)
	# The sky takes its mood from its parent's `mood` when it has one: handing it ours
	# keeps WorldMood.pick() (which reads --mood= off the command line, and finds no
	# time of day in "night") out of it.
	var holder := MoodWorld.new()
	holder.mood = _make_mood(_mood_label)
	_world = holder
	root.add_child(_world)
	_take_game_light()
	_terrain = RouteTerrain.new()
	_world.add_child(_terrain)
	# One asphalt road (false: not gravel), straight ahead of the truck.
	_terrain.add_span(Vector3(0.0, 0.0, ROAD_START_Z), Vector3(0.0, 0.0, ROAD_START_Z - ROAD_LENGTH), false, 6.0)
	_terrain.build()
	var sky := RouteSky.new()
	sky.name = "RouteSky"
	_world.add_child(sky)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 400.0
	_world.add_child(_camera)
	_camera.current = true
	root.get_node(^"/root/RunManager").set(&"is_running", true)
	for state: String in STATES:
		if only == "" or only == state:
			await _shoot_state(state)
	root.get_node(^"/root/RunManager").set(&"is_running", false)
	_world.queue_free()
	await process_frame
	quit(0)


func _shoot_state(state: String) -> void:
	for view: String in VIEWS:
		await _shoot_view(state, view)


## Each shot gets its own truck, so the launch is a launch every time (a truck
## kept under throttle across three views would be doing 30 km/h by the last).
func _shoot_view(state: String, view: String) -> void:
	var throttle: float = STATES[state][0]
	var seconds: float = STATES[state][1]
	var van := (load(VEHICLE_SCENE) as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(0.0, 1.2, START_Z)
	_world.add_child(van)
	van.controls_enabled = false
	van.get_node(^"VehiclePresentation").set(&"audio_enabled", false)
	# The camera rides on the truck from the start: GPUParticles only simulate while
	# a camera sees their visibility_aabb, so a preroll with the camera still at its old
	# pose left the emitter ~3 frames of life (1-2 puffs on screen).
	var pose: Array = VIEWS[view]
	_camera.reparent(van, false)
	var eye: Vector3 = pose[0]
	_camera.transform = Transform3D(Basis.looking_at((pose[1] as Vector3) - eye, Vector3.UP), eye)
	# Settled on its springs, the exhaust built and an idling plume already out
	# (it lives ~2 s) before the throttle goes down.
	for _i: int in range(int(PREROLL_SECONDS * Engine.physics_ticks_per_second)):
		_drive(van, 0.0)
		await physics_frame
	var elapsed: float = 0.0
	while throttle > 0.0 and elapsed < 40.0:
		if seconds > 0.0 and elapsed >= seconds:
			break
		if seconds <= 0.0 and van.speed_kmh >= FULL_KMH:
			break
		_drive(van, throttle)
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
	if _no_smoke:
		# Still simulated and driven as ever, just not drawn.
		(van.find_child("ExhaustSmoke", true, false) as GPUParticles3D).visible = false
	# Two more frames of the same throttle (and no more: the launch is fast).
	for _i: int in range(2):
		_drive(van, throttle)
		await physics_frame
	await process_frame
	if not _dry:
		await RenderingServer.frame_post_draw
	var smoke: GPUParticles3D = van.find_child("ExhaustSmoke", true, false) as GPUParticles3D
	if smoke == null:
		push_error("The truck has no ExhaustSmoke emitter")
	else:
		print("exhaust %s %s: speed %.1f km/h, mood %s, emitting %s (ratio %.2f), camera %.1f m from the pipe"
				% [state, view, van.speed_kmh, WorldMood.active.get("label", _mood_label), smoke.emitting,
				smoke.amount_ratio, _camera.global_position.distance_to(smoke.global_position)])
		_print_pipe(van, smoke)
	if not _dry:
		var path: String = "%s/exhaust_%s_%s.png" % [_out_dir.trim_suffix("/"), state, view]
		root.get_texture().get_image().save_png(path)
		print("Saved ", ProjectSettings.globalize_path(path))
	_camera.reparent(_world, false)
	van.queue_free()
	await process_frame


## The mood a label names (the words of world_mood.gd, as WorldMood.pick() reads
## them): what the label leaves out stays clear, day, summer.
func _make_mood(label: String) -> WorldMood:
	var mood := WorldMood.new()
	for key: int in WorldMood.WEATHER_NAMES:
		if label.contains(WorldMood.WEATHER_NAMES[key]):
			mood.weather = key
	for key: int in WorldMood.TIME_NAMES:
		if label.contains(WorldMood.TIME_NAMES[key]):
			mood.time_of_day = key
	for key: int in WorldMood.SEASON_NAMES:
		if label.contains(WorldMood.SEASON_NAMES[key]):
			mood.season = key
	mood._dress()
	print("mood: ", mood.label(), " (asked for ", label, ")")
	return mood


## The pipe where it really is (the truck's art, ramp and doors included, is built):
## in the truck's space next to what exhaust_anchor() says, in the world, and the
## distance from each of the three camera poses to it.
func _print_pipe(van: VehicleBody3D, smoke: GPUParticles3D) -> void:
	var local: Vector3 = van.to_local(smoke.global_position)
	var line: String = "  pipe: truck space (%.2f, %.2f, %.2f), anchor %s, world (%.2f, %.2f, %.2f)" % [
			local.x, local.y, local.z, load(VEHICLE_EFFECTS_PATH).exhaust_anchor(van),
			smoke.global_position.x, smoke.global_position.y, smoke.global_position.z]
	print(line)
	print("  pipe height above the road: %s" % _height_above_road(van, smoke.global_position))
	var distances: PackedStringArray = PackedStringArray()
	for name: String in VIEWS:
		var eye: Vector3 = (VIEWS[name] as Array)[0]
		distances.append("%s %.1f m" % [name, van.to_global(eye).distance_to(smoke.global_position)])
	print("  distance from the pipe to the cameras: ", ", ".join(distances))


## How high the point is over the road, by a ray straight down in the world (the
## terrain's collision, layer 1); the truck itself is left out.
func _height_above_road(van: VehicleBody3D, point: Vector3) -> String:
	var query := PhysicsRayQueryParameters3D.create(point, point + Vector3(0.0, -8.0, 0.0), 1)
	query.exclude = [van.get_rid()]
	var hit: Dictionary = van.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "no road under the pipe (ray found nothing)"
	return "%.2f m (road at y %.2f)" % [point.y - (hit["position"] as Vector3).y, (hit["position"] as Vector3).y]


## Holds the truck on the straight road at x = 0 (-Z is ahead) with this throttle.
func _drive(van: VehicleBody3D, throttle: float) -> void:
	var ahead: Vector3 = van.to_local(Vector3(0.0, van.global_position.y, van.global_position.z - 12.0))
	van.set_controls(throttle, clampf(atan2(ahead.x, -ahead.z) * 2.2, -1.0, 1.0), false)


func _take_game_light() -> void:
	var level_scene: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	var sun := level_scene.get_node(^"Sun") as DirectionalLight3D
	var environment := level_scene.get_node(^"WorldEnvironment") as WorldEnvironment
	level_scene.remove_child(sun)
	level_scene.remove_child(environment)
	level_scene.free()
	_world.add_child(environment)
	_world.add_child(sun)
