extends SceneTree
## Run without --headless (revisor-visual). The truck drives at ~40 km/h down a
## gravel road and down an asphalt one (N-320): the dust behind the rear wheels
## (wheel_dust.gd) is on gravel and not on asphalt, and rain puts it out. Three
## shots per road, each from a camera that rides on the truck:
##   mirror  outside the driver's door, looking back along the side
##   cargo   from the rack seat nearest the rear, looking out of the open ramp
##   rear    behind the truck, a few metres off the ramp, looking at it
## Saves wheel_dust_{gravel,asphalt}_{mirror,cargo,rear}.png and prints, per shot,
## the speed, the ground's roughness under the rear wheels and the mood.
##   <godot> --path do-not-drop --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1280x720 --script res://tests/render_wheel_dust.gd \
##       -- --mood=soleado_dia_verano --seed=7 --out=D:/tmp/wheel_dust
## Moods (world_mood.gd): <soleado|nublado|lluvia|niebla>_<dia|atardecer|noche>[_<verano|otono>],
## e.g. soleado_noche, lluvia_dia. --ground=gravel|asphalt does one road only.
## --dry runs the drive and prints the lines without drawing or saving (works
## with --headless: a smoke test of the setup).

const RouteTerrain = preload("res://scripts/gameplay/route/route_terrain.gd")
const RouteScript = preload("res://scripts/gameplay/route/route.gd")
const LEVEL_SCENE: String = "res://scenes/gameplay/level_base.tscn"
const VEHICLE_SCENE: String = "res://scenes/gameplay/vehicle/vehicle.tscn"
const DEFAULT_MOOD: String = "soleado_dia_verano"
const CRUISE_KMH: float = 40.0
## Seconds at cruise speed before the first shot: longer than the dust's life.
const SETTLE_SECONDS: float = 3.0
const ROAD_LENGTH: float = 1200.0
const ROAD_START_Z: float = 100.0
const START_Z: float = 70.0
## Local camera poses on the truck (+Z is the rear): where, and what it looks at.
const VIEWS: Dictionary = {
	"mirror": [Vector3(-1.45, 1.55, -1.0), Vector3(-1.9, 0.5, 9.0)],
	"cargo": [Vector3(0.74, 1.24, 3.125), Vector3(0.2, 0.2, 9.0)],
	"rear": [Vector3(2.4, 1.9, 8.5), Vector3(0.0, 0.3, 3.8)],
}

var _world: Node3D
var _terrain: Node3D
var _camera: Camera3D
var _out_dir: String = "user://"
var _dry: bool = false
var _mood_label: String = DEFAULT_MOOD


## What Route.ground_roughness() answers, for a terrain built here (the game's
## Route is the whole level): the same rule, on the same TerrainField.
class GroundProbe:
	extends Node
	var terrain: Node3D

	func ground_roughness(world_point: Vector3) -> float:
		var point := Vector2(world_point.x, world_point.z)
		for zone: Rect2 in terrain.flat_zones:
			if zone.has_point(point):
				return 0.0
		var road: Vector3 = terrain.nearest(point)
		if road.x <= road.z * 0.5 + 0.5:
			return 1.0 if road.y > 0.5 else 0.0
		return RouteScript.VERGE_ROUGHNESS


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
			_mood_label = arg.get_slice("=", 1)
		elif arg.begins_with("--ground="):
			only = arg.get_slice("=", 1)
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
	WorldMood.forced_label = _mood_label
	_world = Node3D.new()
	root.add_child(_world)
	_take_game_light()
	_terrain = RouteTerrain.new()
	_world.add_child(_terrain)
	# Two parallel roads, far enough apart not to share a verge.
	_terrain.add_span(Vector3(0.0, 0.0, ROAD_START_Z), Vector3(0.0, 0.0, ROAD_START_Z - ROAD_LENGTH), true, 6.0)
	_terrain.add_span(Vector3(160.0, 0.0, ROAD_START_Z), Vector3(160.0, 0.0, ROAD_START_Z - ROAD_LENGTH), false, 6.0)
	_terrain.build()
	var ground := GroundProbe.new()
	ground.terrain = _terrain
	ground.add_to_group(&"route")
	_world.add_child(ground)
	var sky := RouteSky.new()
	sky.name = "RouteSky"
	_world.add_child(sky)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 400.0
	_world.add_child(_camera)
	_camera.current = true
	root.get_node(^"/root/RunManager").set(&"is_running", true)
	for surface: String in ["gravel", "asphalt"]:
		if only == "" or only == surface:
			await _drive_and_shoot(surface, 0.0 if surface == "gravel" else 160.0)
	root.get_node(^"/root/RunManager").set(&"is_running", false)
	_world.queue_free()
	await process_frame
	quit(0)


func _drive_and_shoot(surface: String, road_x: float) -> void:
	var van := (load(VEHICLE_SCENE) as PackedScene).instantiate() as VehicleBody3D
	van.position = Vector3(road_x, 1.2, START_Z)
	_world.add_child(van)
	van.controls_enabled = false
	van.get_node(^"VehiclePresentation").set(&"audio_enabled", false)
	# Up to speed, then a few seconds at it so a trail is already behind the truck.
	var at_speed: float = 0.0
	var waited: float = 0.0
	while at_speed < SETTLE_SECONDS and waited < 40.0:
		_cruise(van, road_x)
		await physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		at_speed = at_speed + 1.0 / Engine.physics_ticks_per_second if absf(van.speed_kmh - CRUISE_KMH) < 3.0 else 0.0
	for view: String in VIEWS:
		var pose: Array = VIEWS[view]
		_camera.reparent(van, false)
		var eye: Vector3 = pose[0]
		_camera.transform = Transform3D(Basis.looking_at((pose[1] as Vector3) - eye, Vector3.UP), eye)
		# A few frames of the same cruise, so the cloud in view is a settled one.
		for _i: int in range(30):
			_cruise(van, road_x)
			await physics_frame
		await process_frame
		if not _dry:
			await RenderingServer.frame_post_draw
		var roughness: float = float(root.get_tree().get_first_node_in_group(&"route").call(&"ground_roughness",
				van.get_node(^"RearLeftWheel").global_position))
		var emitting: int = 0
		for particles: GPUParticles3D in van.get_node(^"VehiclePresentation/WheelDust").get(&"emitters"):
			emitting += 1 if particles.emitting else 0
		print("wheel_dust %s %s: speed %.1f km/h, ground roughness %.2f, mood %s, %d of 2 emitters on"
				% [surface, view, van.speed_kmh, roughness, WorldMood.active.get("label", _mood_label), emitting])
		if not _dry:
			var path: String = "%s/wheel_dust_%s_%s.png" % [_out_dir.trim_suffix("/"), surface, view]
			root.get_texture().get_image().save_png(path)
			print("Saved ", ProjectSettings.globalize_path(path))
	_camera.reparent(_world, false)
	van.queue_free()
	await process_frame


## Holds the truck at CRUISE_KMH on the straight road at road_x (-Z is ahead).
func _cruise(van: VehicleBody3D, road_x: float) -> void:
	var speed: float = van.speed_kmh
	var throttle: float = 1.0 if speed < CRUISE_KMH - 3.0 else (-0.5 if speed > CRUISE_KMH + 3.0 else 0.35)
	var ahead: Vector3 = van.to_local(Vector3(road_x, van.global_position.y, van.global_position.z - 12.0))
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
