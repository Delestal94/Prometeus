extends SceneTree
## Performance probe. Run WITHOUT --headless (it measures real rendering):
##   <godot> --path do-not-drop --script res://tests/bench_drive.gd
## Builds the real level, seats the driver, and lets an autopilot drive the
## generated route at full throttle while it records every frame: frame time,
## script/physics time, draw calls and objects. Prints a summary plus every
## hitch (frame > HITCH_MS) with what was going on, so a stutter can be traced
## to rendering, physics or a script instead of guessed at.
## Optional user args: -- --seconds=60 --seed=1234 --hitch=33
## --endless drives Endless instead (level_endless.tscn), following the
## streamed road's own centre line (RouteStreamer.point_at()).
## --mood=lluvia_noche (world_mood.gd) forces the weather and time of day.
## --quality=low|medium|high (or 0|1|2) forces the graphics preset (WorldQuality,
## N-205) for this run only, without touching the saved setting; without it the
## bench runs with whatever GameSettings loaded (the default, High).
## --render-scale=2.0 overrides the 3D render scale (0.25..2.0): 2.0 shades four
## times the pixels, a stand-in for a GPU a fraction of this one's speed.
## With --headless and -- --cpu-only it measures scripts + physics alone.
## --experiment=noshadow|shadow2|noplants|nodress|nohouses|nosegvis|notruck|
## noparticles|nolights|notransp|nobatch switches one cost off to measure what
## it's worth (several at once: --experiment=noparticles,nolights).
## --players=5 --cargo=full is the full-crew scenario (N-220): the other
## players are fake remote ones (the same Player_<peer> nodes a spawner would
## replicate) seated in passenger seats, and every package mount of the truck
## carries a box. The report adds Jolt's own monitors (they read 0), the rigid bodies awake
## and (--contacts) their reported contacts, and the object census.
## --via-loader builds the level the way the game does (LoadingScreen: every
## model prefetched, synth sounds warmed, road built over frames, depot and road
## revealed one per frame) instead of instantiating it cold: the first-use
## hitches of a cold build mostly vanish under the game's own loader.

## Last node of the tree to run its _physics_process: it stamps when every
## script of the tick has run, so the tick splits into scripts (before the
## stamp) and Jolt's step (after it).
class PhysicsEnd extends Node:
	var stamp_usec: int = 0

	func _physics_process(_delta: float) -> void:
		stamp_usec = Time.get_ticks_usec()


var HITCH_MS: float = 33.0
var _physics_end: PhysicsEnd = null
## What joined the tree, by process frame (the first few nodes and the count): a
## hitch line names what was being built in it.
var _added: Dictionary = {}
var _endless: bool = false
var _endless_best: float = -INF
const LOOKAHEAD: float = 14.0

var _level: Node3D
var _route: Node3D
var _van: VehicleBody3D
var _frames: Array[Dictionary] = []
var _last_usec: int = 0
var _path: Array[Vector3] = []
var _path_index: int = 0
var _done: bool = false
var _stuck_seconds: float = 0.0
var _rescues: int = 0
var _last_progress_index: int = -1
## Wall-clock physics cost: from the first physics_frame of an iteration to
## the process_frame that follows it (Performance's physics monitor is an
## average that lags behind, useless for spotting a single slow tick).
var _physics_start_usec: int = -1
## Motion smoothness: how evenly the rendered camera advances frame to frame
## at cruising speed. Without interpolation it only moves on physics ticks,
## so at high frame rates most frames repeat a pose and the next one jumps.
var _last_camera_origin: Vector3 = Vector3.INF
var _smooth_samples: Array[float] = []
## How far the seated driver's body drifts from its seat as drawn (should
## stay ~0: both must be interpolated the same way).
var _seat_drift_peak: float = 0.0
## Jolt's monitors, one sample per physics tick (_drive).
var _phys_active: Array[float] = []
var _phys_pairs: Array[float] = []
var _phys_islands: Array[float] = []
var _phys_time_ms: Array[float] = []
## Jolt's PHYSICS_3D_* monitors read 0 (not implemented by the Jolt server), so
## the physics load is read from the bodies themselves once a second: how many
## rigid bodies are awake and, with --contacts, how many contacts they report.
var _tick: int = 0
var _rigid: Array[RigidBody3D] = []
var _bodies_awake: Array[float] = []
var _bodies_total: Array[float] = []
var _contacts: Array[float] = []


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	if DisplayServer.get_name() == "headless" and not "--cpu-only" in OS.get_cmdline_user_args():
		push_error("bench_drive needs a rendering display; omit --headless.")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", int(_arg("seed", "4242")))
	var seconds: float = float(_arg("seconds", "60"))
	HITCH_MS = float(_arg("hitch", "33"))
	if _arg("experiment", "").contains("fti"):
		physics_interpolation = true
	var quality_arg: String = _arg("quality", "")
	if quality_arg != "":
		var names: Array[String] = ["low", "medium", "high"]
		var wanted: int = names.find(quality_arg.to_lower())
		WorldQuality.apply(self, wanted if wanted >= 0 else int(quality_arg))
	if _arg("render-scale", "") != "":
		# Over the preset's own: 2.0 draws 4x the pixels of the window (a GPU
		# stress: what a much weaker card would have to shade at 1080p).
		root.scaling_3d_scale = clampf(float(_arg("render-scale", "1.0")), 0.25, 2.0)
	var build_start: int = Time.get_ticks_usec()
	_endless = "--endless" in OS.get_cmdline_user_args()
	var full_cargo: bool = _arg("cargo", "") == "full"
	if full_cargo:
		# Locked traps stay off the depot's shelves; a full truck needs seven boxes.
		var unlocks: Node = root.get_node(^"/root/UnlockManager")
		for unlock_id: StringName in (unlocks.get(&"TRAP_UNLOCKS") as Dictionary).values():
			unlocks.unlocked[unlock_id] = true
	var scene_path: String = "res://scenes/gameplay/level_base.tscn"
	if _endless:
		scene_path = "res://scenes/gameplay/level_endless.tscn"
	if "--via-loader" in OS.get_cmdline_user_args():
		# The way the game gets there: prefetch of every model, warm synth sounds,
		# road built over frames, depot and road revealed one per frame.
		var screen: LoadingScreen = LoadingScreen.go(self, scene_path, "bench")
		await screen.finished
		_level = current_scene
	else:
		_level = load(scene_path).instantiate()
		if _endless and _arg("experiment", "").contains("nobatch"):
			(_level.get_node(^"World/RouteStreamer") as Node).set(&"batch_geometry", false)
		root.add_child(_level)
		current_scene = _level
	var build_ms: float = (Time.get_ticks_usec() - build_start) / 1000.0
	# Endless has no Route: the experiments below that need one skip it.
	_route = _level.get_node_or_null(^"World/Route")
	_van = _level.vehicle
	for _i: int in range(3):
		await process_frame
	var experiment: String = _arg("experiment", "")
	if experiment.contains("shadow2"):
		for light: Node in _level.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if experiment.contains("noshadow"):
		for light: Node in _level.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = false
	if _route != null and (experiment.contains("noplants") or experiment.contains("nodress")):
		for group: Node in _route.find_children("*Dressing", "Node3D", true, false):
			if experiment.contains("nodress") or group.name == "ForestDressing":
				group.queue_free()
	if _route != null and experiment.contains("nohouses"):
		for house: Node in _route.get(&"houses"):
			(house as Node3D).visible = false
	if _route != null and experiment.contains("nosegvis"):
		for segment: Node in _route.get(&"_segments"):
			for mesh: Node in segment.find_children("*", "MeshInstance3D", true, false):
				(mesh as Node3D).visible = false
	if experiment.contains("notruck"):
		(_van.get_node(^"BodyVisuals") as Node3D).visible = false
	if experiment.contains("noparticles"):
		for node: Node in _level.find_children("*", "GPUParticles3D", true, false):
			(node as GPUParticles3D).emitting = false
			(node as GPUParticles3D).visible = false
		for node: Node in _level.find_children("*", "CPUParticles3D", true, false):
			(node as CPUParticles3D).emitting = false
			(node as CPUParticles3D).visible = false
	if experiment.contains("nolights"):
		for node: Node in _level.find_children("*", "Light3D", true, false):
			if not node is DirectionalLight3D:
				(node as Light3D).visible = false
	if experiment.contains("notransp"):
		for node: Node in _level.find_children("*", "GeometryInstance3D", true, false):
			if _is_blended(node as GeometryInstance3D):
				(node as GeometryInstance3D).visible = false
	var crew: int = int(_arg("players", "1"))
	if crew > 1 or full_cargo:
		await _setup_crew(crew, full_cargo)
	_level.call(&"start_debug_delivery")
	if experiment.contains("camoff"):
		for camera: Node in _level.find_children("*", "Camera3D", true, false):
			camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_van.get_node(^"VehicleInputComponent").set_physics_process(false)
	# The autopilot crashes into chicanes; a box lost there would end the run
	# (and the level) halfway. This measures frames, not driving, so keep going.
	var ruined: Callable = Callable(root.get_node(^"/root/RunManager"), &"_on_package_ruined")
	var bus: Node = root.get_node(^"/root/EventBus")
	if bus.is_connected(&"package_ruined", ruined):
		bus.disconnect(&"package_ruined", ruined)
	if _route != null:
		_path.assign(_route.get(&"_path_points"))
	print("BENCH quality=%s resolution=%s render_scale=%.2f" % [
		WorldQuality.NAMES[WorldQuality.level], str(DisplayServer.window_get_size()), root.scaling_3d_scale])
	print("BENCH mode=%s mood=%s build_ms=%.0f nodes=%d path_points=%d route_length=%.0f" % ["endless" if _endless else "delivery", str(WorldMood.active.get("label", "")), build_ms, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _path.size(), float(_route.get(&"route_length")) if _route != null else 0.0])
	_physics_end = PhysicsEnd.new()
	_physics_end.process_physics_priority = 1_000_000
	root.add_child(_physics_end)
	node_added.connect(_on_node_added)
	_census()
	physics_frame.connect(_drive)
	var first_frame_start: int = Time.get_ticks_usec()
	var first_ms: float = 0.0
	await process_frame
	first_ms = (Time.get_ticks_usec() - first_frame_start) / 1000.0
	_last_usec = Time.get_ticks_usec()
	var elapsed: float = 0.0
	while elapsed < seconds and not _done:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var physics_wall: float = (now - _physics_start_usec) / 1000.0 if _physics_start_usec >= 0 else 0.0
		var scripts_ms: float = 0.0
		if _physics_start_usec >= 0 and _physics_end.stamp_usec >= _physics_start_usec:
			scripts_ms = (_physics_end.stamp_usec - _physics_start_usec) / 1000.0
		_physics_start_usec = -1
		var ms: float = (now - _last_usec) / 1000.0
		_last_usec = now
		elapsed += ms / 1000.0
		var camera: Camera3D = root.get_viewport().get_camera_3d()
		if camera != null:
			var origin: Vector3 = camera.get_global_transform_interpolated().origin
			var speed: float = _van.linear_velocity.length()
			if _last_camera_origin != Vector3.INF and speed > 15.0 and ms > 0.0:
				_smooth_samples.append(origin.distance_to(_last_camera_origin) / (ms / 1000.0) / speed)
			_last_camera_origin = origin
		var player: Node = _level.get(&"local_player")
		if player != null and _van.linear_velocity.length() > 15.0:
			var body_visual: Node3D = player.get(&"_body_visual")
			var seat: Node3D = player.get_node_or_null(player.get(&"seat_node_path")) as Node3D
			if body_visual != null and seat != null:
				var expected: Vector3 = seat.get_global_transform_interpolated().translated_local(Vector3(0.0, -0.55, 0.0)).origin
				_seat_drift_peak = maxf(_seat_drift_peak, body_visual.get_global_transform_interpolated().origin.distance_to(expected))
		_frames.append({
			"ms": ms,
			"t": elapsed,
			"process": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics": physics_wall,
			"phys_scripts": scripts_ms,
			"frame": Engine.get_process_frames(),
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"memory_video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"kmh": _van.linear_velocity.length() * 3.6,
			"progress": float(_path_index) / maxf(1.0, float(_path.size())),
			"rescues": _rescues,
		})
	_report(first_ms)
	quit()


## Pure-pursuit autopilot along the route's own path points.
func _drive() -> void:
	if _physics_start_usec < 0:
		_physics_start_usec = Time.get_ticks_usec()
	_phys_active.append(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	_phys_pairs.append(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	_phys_islands.append(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
	_phys_time_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_sample_bodies()
	if _endless:
		_drive_endless()
		return
	if _path.is_empty():
		return
	var here: Vector3 = _route.to_local(_van.global_position)
	while _path_index < _path.size() - 1 and Vector2(_path[_path_index].x - here.x, _path[_path_index].z - here.z).length() < LOOKAHEAD:
		_path_index += 1
	if _path_index >= _path.size() - 1:
		_done = true
	# The autopilot only follows the centreline and can't weave through a
	# chicane or roadworks: when it's pinned against one, put it back on the
	# road a little further on, so one run still covers the whole route.
	_stuck_seconds += 1.0 / Engine.physics_ticks_per_second
	if _path_index != _last_progress_index:
		_last_progress_index = _path_index
		_stuck_seconds = 0.0
	if _stuck_seconds > 2.0 and _path_index < _path.size() - 3:
		_stuck_seconds = 0.0
		_rescues += 1
		_path_index += 2
		var at: Vector3 = _route.to_global(_path[_path_index])
		var ahead: Vector3 = _route.to_global(_path[_path_index + 1])
		_van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
		_van.linear_velocity = (ahead - at).normalized() * 12.0
		_van.angular_velocity = Vector3.ZERO
		_van.reset_physics_interpolation()
	var target: Vector3 = _route.to_global(_path[_path_index])
	var local: Vector3 = _van.global_transform.affine_inverse() * target
	# Front is -Z; positive steer input turns right (+X).
	var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	_van.call(&"set_controls", 1.0, steer, false)


## Endless: follow the streamed road's centre line, and past a chicane it
## can't weave, hop the truck 20 m on.
func _drive_endless() -> void:
	var streamer: RouteStreamer = _level.get_node(^"World/RouteStreamer")
	var along: float = streamer.distance_along(_van.global_position)
	_stuck_seconds += 1.0 / Engine.physics_ticks_per_second
	if along > _endless_best + 1.0:
		_endless_best = along
		_stuck_seconds = 0.0
	if _stuck_seconds > 2.0:
		_stuck_seconds = 0.0
		_rescues += 1
		var at: Vector3 = streamer.point_at(along + 20.0)
		var ahead: Vector3 = streamer.point_at(along + 25.0)
		_van.global_transform = Transform3D(Basis.looking_at(ahead - at, Vector3.UP), at + Vector3.UP * 1.2)
		_van.linear_velocity = (ahead - at).normalized() * 12.0
		_van.angular_velocity = Vector3.ZERO
		_van.reset_physics_interpolation()
	var local: Vector3 = _van.global_transform.affine_inverse() * streamer.point_at(along + LOOKAHEAD)
	var steer: float = clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	_van.call(&"set_controls", 1.0, steer, false)


func _sample_bodies() -> void:
	_tick += 1
	if _tick % 600 == 1:
		_rigid.clear()
		for node: Node in _level.find_children("*", "RigidBody3D", true, false):
			_rigid.append(node as RigidBody3D)
			if "--contacts" in OS.get_cmdline_user_args():
				PhysicsServer3D.body_set_max_contacts_reported((node as RigidBody3D).get_rid(), 16)
	if _tick % 60 != 0:
		return
	var awake: int = 0
	var contacts: int = 0
	for body: RigidBody3D in _rigid:
		if not is_instance_valid(body):
			continue
		if not body.sleeping and not body.freeze:
			awake += 1
		if "--contacts" in OS.get_cmdline_user_args():
			contacts += PhysicsServer3D.body_get_direct_state(body.get_rid()).get_contact_count()
	_bodies_awake.append(awake)
	_bodies_total.append(_rigid.size())
	_contacts.append(contacts)


func _on_node_added(node: Node) -> void:
	var frame: int = Engine.get_process_frames()
	var entry: Dictionary = _added.get_or_add(frame, {"count": 0, "names": []})
	entry.count += 1
	if entry.names.size() < 5:
		entry.names.append("%s(%s)" % [node.name, node.get_class()])


func _added_text(frame: int) -> String:
	var parts: Array[String] = []
	for key: int in [frame - 1, frame]:
		if _added.has(key) and int(_added[key].count) > 1:
			parts.append("+%d nodes %s" % [_added[key].count, ", ".join(_added[key].names)])
	return " | ".join(parts)


## The crew of the full-truck scenario: fake remote players seated in the
## passenger seats that look after a package mount, a box in every mount (loaded
## by the local player, as the tests do) before the driver takes the wheel.
func _setup_crew(players: int, full_cargo: bool) -> void:
	var world: Node = _level.get_node(^"World")
	var local: Node = _level.get(&"local_player")
	var remotes: Array[Node3D] = []
	for peer: int in range(2, players + 1):
		var remote: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
		remote.name = "Player_%d" % peer
		remote.position = Vector3(float(peer) * 1.2 - 4.0, 1.0, 10.0)
		world.add_child(remote)
		remote.set(&"net_position", remote.position)
		remotes.append(remote)
	await process_frame
	await physics_frame
	var loaded: int = 0
	if full_cargo:
		var boxes: Array[Node] = []
		boxes.assign(get_nodes_in_group(&"cargo"))
		var mounts: Array[Node] = []
		mounts.assign(get_nodes_in_group(&"package_mount"))
		for index: int in range(mini(boxes.size(), mounts.size())):
			local.call(&"pick_up", boxes[index].get_path())
			mounts[index].call(&"interact", local)
			if bool(boxes[index].get(&"is_loaded")):
				loaded += 1
		await physics_frame
	var seated: int = 0
	var taken: int = 0
	for seat: Node in get_nodes_in_group(&"cargo_seat"):
		if taken >= remotes.size():
			break
		if seat.get(&"role") != &"passenger" or (seat.get(&"required_mount_path") as NodePath).is_empty():
			continue
		# The host side (occupant, the box they tend). Its RPCs to a peer that does
		# not exist log "unknown peer" errors: expected, nothing is lost by them.
		seat.call(&"interact", remotes[taken])
		# What the replicated state gives every other peer's copy of a seated
		# player: the seat path (board_seat() would also switch this window's
		# camera to the seat's) and "riding in the truck".
		remotes[taken].set(&"seat_node_path", seat.get_parent().get_path())
		remotes[taken].set(&"net_in_vehicle", true)
		taken += 1
		if seat.get(&"occupant") == remotes[taken - 1]:
			seated += 1
	# The seated pose blends in over ~0.15 s.
	for _i: int in range(40):
		await process_frame
	var away: float = 0.0
	for remote: Node3D in remotes:
		var seat_node: Node3D = remote.get_node_or_null(remote.get(&"seat_node_path")) as Node3D
		if seat_node != null:
			away = maxf(away, remote.get(&"_body_visual").global_position.distance_to(seat_node.global_position))
	print("BENCH crew players=%d (fake remote=%d, seated=%d, farthest body from its seat %.2f m) boxes_loaded=%d" % [
		get_nodes_in_group(&"player").size(), remotes.size(), seated, away, loaded])


## Whether a node is drawn in the blended (transparent) pass, as well as it can
## be told from its resources: a BaseMaterial3D with alpha blending or a shader
## that writes ALPHA / asks for a blend mode.
func _is_blended(node: GeometryInstance3D) -> bool:
	if not node.visible:
		return false
	var materials: Array[Material] = []
	if node.material_override != null:
		materials.append(node.material_override)
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		for surface: int in range((node as MeshInstance3D).mesh.get_surface_count()):
			materials.append((node as MeshInstance3D).get_active_material(surface))
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var mesh: Mesh = (node as MultiMeshInstance3D).multimesh.mesh
		for surface: int in range(mesh.get_surface_count() if mesh != null else 0):
			materials.append(mesh.surface_get_material(surface))
	elif node is GPUParticles3D:
		return true
	for material: Material in materials:
		if material is BaseMaterial3D:
			var base: BaseMaterial3D = material
			var alpha: bool = base.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,
					BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]
			if alpha or base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
				return true
		elif material is ShaderMaterial and (material as ShaderMaterial).shader != null:
			var code: String = (material as ShaderMaterial).shader.code
			if code.contains("blend_") or code.contains("ALPHA ="):
				return true
	return false


## What is in the scene, once, after the setup: nodes by kind, and the sources
## the experiments switch off (particles, lights, shadow casters, blended).
func _census() -> void:
	var meshes: int = 0
	var multimeshes: int = 0
	var instances: int = 0
	var casters: int = 0
	var blended: int = 0
	var gpu_particles: int = 0
	var emitting: int = 0
	var particle_amount: int = 0
	var lights: Dictionary = {}
	var shadowed: int = 0
	var bodies: int = 0
	for node: Node in _level.find_children("*", "", true, false):
		if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree():
			meshes += 1
		elif node is MultiMeshInstance3D:
			multimeshes += 1
			var batch: MultiMesh = (node as MultiMeshInstance3D).multimesh
			instances += batch.instance_count if batch != null else 0
		if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree():
			if (node as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += 1
			if not node is GPUParticles3D and _is_blended(node as GeometryInstance3D):
				blended += 1
		if node is GPUParticles3D:
			gpu_particles += 1
			particle_amount += (node as GPUParticles3D).amount
			if (node as GPUParticles3D).emitting and (node as GPUParticles3D).is_visible_in_tree():
				emitting += 1
		if node is Light3D and (node as Light3D).is_visible_in_tree():
			lights[node.get_class()] = int(lights.get(node.get_class(), 0)) + 1
			if (node as Light3D).shadow_enabled:
				shadowed += 1
		if node is PhysicsBody3D:
			bodies += 1
	print("BENCH census meshes=%d multimesh=%d(%d instances) shadow_casters=%d blended_meshes=%d " % [
		meshes, multimeshes, instances, casters, blended]
		+ "gpu_particles=%d(%d emitting, amount %d) lights=%s shadowed_lights=%d physics_bodies=%d" % [
		gpu_particles, emitting, particle_amount, str(lights), shadowed, bodies])


func _stats(values: Array[float]) -> String:
	if values.is_empty():
		return "n/a"
	var sum: float = 0.0
	var peak: float = 0.0
	for value: float in values:
		sum += value
		peak = maxf(peak, value)
	return "avg=%.1f max=%.1f" % [sum / values.size(), peak]


func _report(first_ms: float) -> void:
	if _frames.is_empty():
		print("BENCH no frames")
		return
	var times: Array[float] = []
	var total: float = 0.0
	var draws: float = 0.0
	var objects: float = 0.0
	var prims: float = 0.0
	var process_ms: float = 0.0
	var physics_ms: float = 0.0
	var physics_peak: float = 0.0
	var memory_static_peak: float = 0.0
	var memory_video_peak: float = 0.0
	var physics_ticks: int = 0
	for f: Dictionary in _frames:
		times.append(f.ms)
		total += f.ms
		draws += f.draws
		objects += f.objects
		prims += f.prims
		memory_static_peak = maxf(memory_static_peak, f.memory_static)
		memory_video_peak = maxf(memory_video_peak, f.memory_video)
		process_ms += f.process
		if f.physics > 0.0:
			physics_ms += f.physics
			physics_ticks += 1
			physics_peak = maxf(physics_peak, f.physics)
	var n: float = float(_frames.size())
	times.sort()
	var p: Callable = func(q: float) -> float: return times[clampi(int(q * n), 0, times.size() - 1)]
	print("BENCH first_frame_ms=%.0f frames=%d avg_ms=%.2f fps=%.0f p50=%.2f p95=%.2f p99=%.2f max=%.1f" % [first_ms, _frames.size(), total / n, 1000.0 * n / total, p.call(0.5), p.call(0.95), p.call(0.99), times[-1]])
	print("BENCH avg draws=%.0f objects=%.0f prims=%.0f progress=%.2f" % [draws / n, objects / n, prims / n, _frames[-1].progress])
	print("BENCH physics per tick: avg=%.2fms peak=%.2fms (%d ticks)" % [physics_ms / maxf(1.0, physics_ticks), physics_peak, physics_ticks])
	var scripts_total: float = 0.0
	var scripts_peak: float = 0.0
	var step_peak: float = 0.0
	for f: Dictionary in _frames:
		if f.physics > 0.0:
			scripts_total += f.phys_scripts
			scripts_peak = maxf(scripts_peak, f.phys_scripts)
			step_peak = maxf(step_peak, f.physics - f.phys_scripts)
	var ticks: float = maxf(1.0, physics_ticks)
	print("BENCH physics split: _physics_process scripts avg=%.2fms peak=%.2fms | " % [
		scripts_total / ticks, scripts_peak]
		+ "the rest of the tick (Jolt step and what follows) avg=%.2fms peak=%.2fms" % [
		(physics_ms - scripts_total) / ticks, step_peak])
	print("BENCH memory_static_peak_mib=%.1f memory_video_peak_mib=%.1f" % [
		memory_static_peak / 1048576.0,
		memory_video_peak / 1048576.0,
	])
	var monitors: String = "PHYSICS_3D_* monitors: active %s, pairs %s, islands %s" % [
		_stats(_phys_active), _stats(_phys_pairs), _stats(_phys_islands)]
	if _phys_active.max() == 0.0 and _phys_pairs.max() == 0.0 and _phys_islands.max() == 0.0:
		monitors = "PHYSICS_3D_* monitors are all 0 under Jolt"
	print("BENCH physics3d: %s | TIME_PHYSICS_PROCESS ms %s" % [monitors, _stats(_phys_time_ms)])
	print("BENCH rigid bodies (sampled 1/s): total %s | awake %s | contacts reported %s (only with --contacts)" % [
		_stats(_bodies_total), _stats(_bodies_awake), _stats(_contacts)])
	print("BENCH objects=%d nodes=%d resources=%d orphans=%d texture_mem_mib=%.1f buffer_mem_mib=%.1f" % [
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	if _smooth_samples.size() > 10:
		var mean: float = 0.0
		for v: float in _smooth_samples:
			mean += v
		mean /= _smooth_samples.size()
		var variance: float = 0.0
		var frozen: int = 0
		for v: float in _smooth_samples:
			variance += (v - mean) * (v - mean)
			if v < 0.2:
				frozen += 1
		print("BENCH motion judder=%.2f (0 = perfectly even; std/mean of camera speed vs truck speed) frozen_frames=%.0f%%" % [sqrt(variance / _smooth_samples.size()) / maxf(mean, 0.001), 100.0 * frozen / _smooth_samples.size()])
	print("BENCH seated body drift from its seat, peak=%.3fm" % _seat_drift_peak)
	var hitches: int = 0
	for f: Dictionary in _frames:
		if f.ms > HITCH_MS:
			hitches += 1
			if hitches <= 40:
				print("HITCH rescue=%d t=%.2fs ms=%.1f process_monitor=%.1f physics=%.1f(scripts %.1f) " % [
					f.rescues, f.t, f.ms, f.process, f.physics, f.phys_scripts]
					+ "draws=%d objects=%d kmh=%.0f progress=%.2f %s" % [
					f.draws, f.objects, f.kmh, f.progress, _added_text(f.frame)])
	print("BENCH hitches(>%.0fms)=%d rescues=%d" % [HITCH_MS, hitches, _rescues])
