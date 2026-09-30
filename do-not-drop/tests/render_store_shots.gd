extends SceneTree
## Generates the five deterministic 1920x1080 store-page stills (S-902, N-316):
## one per trailer plane (data/trailer_shots.json), each with the crew on
## screen, boxes in their hands or in the cargo bay, and most of them with
## something going wrong. Run with a rendering window (never --headless):
##   <godot> --path do-not-drop --resolution 1920x1080 --script res://tests/render_store_shots.gd
##   ... -- --only=cruce_tren          (just one plane, to iterate on a framing)
## Output: user://store_shots/<plano>.png
##
## The crew are ordinary teammates (Player_<peer>, peer 2 and up: their
## bodies render on the WORLD layer, like anyone else's for you), used as they
## are: the character model, its clips and its looks are Slatex's (S-311).
## A pose is one of the character's own clips frozen at a fixed time, and a box
## "in the hands" is a real pick_up() -- the carry pose's IK puts the hands on
## it -- with the box set where the carrier would hold it. Everything is then
## frozen (truck, boxes, crew, the train): every run gives the same framing,
## poses and placements (only rain and swaying foliage differ, by a few pixels).

const OUTPUT_SIZE := Vector2i(1920, 1080)
const OUTPUT_DIR := "user://store_shots"
const ShotScript = preload("res://scripts/tools/trailer_shot.gd")
## Loaded when the shots run, not preloaded: the headless metadata test
## preloads this script before the autoloads exist, and the player's and the
## box's scripts name them.
const PACKAGE_SCENE_PATH: String = "res://scenes/gameplay/package/package.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/gameplay/player/player.tscn"
const TRAPS_DIR: String = "res://data/traps/"
## Where a standing carrier holds a box, in their own space (chest height,
## a forearm ahead): what player_carry.gd's carry_position() works out.
const HOLD_OFFSET := Vector3(0.0, 1.0, -0.46)
## Frames for the carry pose's hands to reach their box (it eases in).
const SETTLE_FRAMES: int = 30

## Public metadata lets the headless regression test prove the promised set
## without pretending that a dummy renderer can judge the resulting images.
## `crew`: people on screen besides the driver; `held`: boxes in someone's
## hands; `mishap`: what goes wrong in the frame ("" when nothing does).
const STORE_SHOTS: Array[Dictionary] = [
	{"file": "salida_deposito.png", "scene": "salida_deposito", "label": "depósito cargando",
		"crew": 3, "held": 2, "mishap": "una caja se le escapa de las manos a uno en la rampa"},
	{"file": "curva_bosque.png", "scene": "curva_bosque", "label": "manejo con cajas en riesgo",
		"crew": 2, "held": 1, "mishap": "en la curva, una caja sale volando por la puerta de atrás"},
	{"file": "cruce_tren.png", "scene": "cruce_tren", "label": "corriendo tras una caja caída",
		"crew": 2, "held": 1, "mishap": "una caja cayó en las vías y uno corre a buscarla con el tren encima"},
	{"file": "puente_lluvia.png", "scene": "puente_lluvia", "label": "pasajero sosteniendo una caja en la lluvia",
		"crew": 2, "held": 1, "mishap": "una caja se cae del puente y el pasajero se estira para agarrarla"},
	{"file": "casa_noche.png", "scene": "casa_noche", "label": "entrega en una casa",
		"crew": 3, "held": 2, "mishap": ""},
]

var _runner: Node
var _only: String = ""
var _next_peer: int = 2
var _next_box: int = 0
## Players to freeze once their pose has settled: [player, clip, time].
var _poses: Array[Array] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Store shots need a rendering window; omit --headless.")
		quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.get_slice("=", 1)
	DisplayServer.window_set_size(OUTPUT_SIZE)
	root.size = OUTPUT_SIZE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for _i in range(4):
		await process_frame

	var saved: int = 0
	for shot: Dictionary in STORE_SHOTS:
		if not _only.is_empty() and _only != String(shot.scene):
			continue
		match String(shot.scene):
			"salida_deposito":
				await _depot_loading()
			"curva_bosque":
				await _forest_bend()
			"cruce_tren":
				await _rail_crossing()
			"puente_lluvia":
				await _rainy_bridge()
			"casa_noche":
				await _house_at_night()
		await _save(String(shot.file))
		await _clear_runner()
		saved += 1
	print("RENDER: %d store shots saved at 1920x1080 under %s" % [saved, ProjectSettings.globalize_path(OUTPUT_DIR)])
	quit(0)


# --- The five planes -----------------------------------------------------------


## Depot: loading up at the open back. One stands in the bay with a box, one
## walks over with another, and the third's box has just got away from him --
## in the air over his head, him reaching after it.
func _depot_loading() -> void:
	var runner: Node = await _new_runner(&"salida_deposito", 3)
	var van := runner.get(&"van") as VehicleBody3D
	van.call(&"set_door_open", &"rear", true)
	var floor_y: float = _bay_floor(van)
	var inside := _crew_at(van.to_global(Vector3(0.35, floor_y, 4.2)), van.to_global(Vector3(-1.0, 0.0, 9.0)),
		&"Idle", 0.4)
	_hold(inside, _box(&"fragile"))
	# From the shelves (the truck's left, -x) to the ramp: they come toward
	# the camera's side, faces in view.
	var walker := _crew_at(_ground(van.to_global(Vector3(-2.2, 0.0, 7.6))), van.to_global(Vector3(0.3, 0.0, 5.4)),
		&"Walk", 0.25)
	_hold(walker, _box(&"noisy"))
	var clumsy := _crew_at(_ground(van.to_global(Vector3(-3.2, 0.0, 10.6))), van.to_global(Vector3(0.4, 0.0, 8.4)),
		&"PickUpHigh", 0.55)
	var loose := _box(&"explosive")
	loose.global_transform = Transform3D(Basis.from_euler(Vector3(0.6, 0.4, -0.5)),
		clumsy.to_global(Vector3(0.05, 2.05, -0.75)))
	_set_camera(runner, van.to_global(Vector3(5.4, 2.0, 12.6)), van.to_global(Vector3(-0.8, 1.2, 7.0)))
	await _settle()


## Forest bend: the back doors swing open in the curve, a box flies out onto
## the road, and the passenger at the doors hugs the explosive one.
func _forest_bend() -> void:
	var runner: Node = await _new_runner(&"curva_bosque", 4)
	var van := runner.get(&"van") as VehicleBody3D
	var segment := runner.get(&"focus") as Node3D
	if segment != null:
		var into_bend: float = float(segment.get(&"length")) * 0.45
		runner.call(&"_place_before", float(segment.get_meta(&"route_distance", 0.0)) + into_bend)
	_freeze_world(runner)
	_rest_van_on_road(runner)
	van.call(&"set_door_open", &"rear", true)
	var floor_y: float = _bay_floor(van)
	var passenger := _crew_at(van.to_global(Vector3(-0.35, floor_y, 4.3)), van.to_global(Vector3(-2.0, 0.0, 9.0)),
		&"Idle", 0.2)
	var hugged := _box(&"explosive")
	_hold(passenger, hugged)
	_at_risk(hugged)
	# The other one at the doors, reaching after the box that just flew out.
	var reacher := _crew_at(van.to_global(Vector3(0.45, floor_y, 4.45)), van.to_global(Vector3(1.6, 0.0, 7.5)),
		&"PickUpHigh", 0.55)
	var flying := _box(&"fragile")
	flying.global_transform = Transform3D(Basis.from_euler(Vector3(0.7, 0.3, 0.9)),
		reacher.to_global(Vector3(0.1, 2.3, -1.25)))
	_at_risk(flying)
	var landed := _box(&"liquid")
	landed.global_transform = Transform3D(Basis.from_euler(Vector3(0.0, 0.8, 1.45)),
		_ground(van.to_global(Vector3(1.2, 0.0, 10.0))) + Vector3.UP * 0.3)
	_set_camera(runner, van.to_global(Vector3(-3.0, 2.3, 11.2)), van.to_global(Vector3(0.3, 1.6, 5.2)))
	await _settle()


## Rail crossing: the truck braked hard at the barrier, a box went flying
## onto the tracks, and one of the crew ducks under the arm to get it back
## while the train comes out of the tunnel.
func _rail_crossing() -> void:
	var runner: Node = await _new_runner(&"cruce_tren", 3)
	var van := runner.get(&"van") as VehicleBody3D
	var segment := runner.get(&"focus") as Node3D
	_move_van_to_stop(runner)
	_freeze_world(runner)
	var track_z: float = float(segment.get(&"track_z"))
	# The train out of its bore and on its way (State.TRAIN), stopped there.
	segment.call(&"_apply_state", 3, 0.0, -14.0)
	segment.set_physics_process(false)
	var lamps: Array = segment.get(&"_lamps")
	for index: int in range(lamps.size()):
		(lamps[index] as StandardMaterial3D).emission_energy_multiplier = 2.2 if index % 2 == 0 else 0.0
	van.call(&"set_door_open", &"cab_right", true)
	var box := _box(&"fragile")
	box.global_transform = Transform3D(segment.global_basis * Basis.from_euler(Vector3(0.0, 0.6, 0.0)),
		_ground(segment.to_global(Vector3(-0.5, 0.0, track_z - 0.6))) + Vector3.UP * 0.33)
	_at_risk(box)
	# Past the barrier and onto the tracks, coming at the camera.
	var runner_guy := _crew_at(_ground(segment.to_global(Vector3(0.7, 0.0, track_z + 1.6))), box.global_position,
		&"Run", 0.2)
	var holder := _crew_at(_ground(van.to_global(Vector3(1.9, 0.0, -3.4))), runner_guy.global_position, &"Idle", 0.5)
	_hold(holder, _box(&"noisy"))
	# Beyond the tracks, looking back at the truck (as the trailer's rail does).
	# High enough to see the box over the near barrier arm.
	_set_camera(runner, segment.to_global(Vector3(4.6, 2.9, track_z - 8.5)), segment.to_global(Vector3(-0.8, 0.8,
		track_z + 2.5)))
	await _settle()


## Narrow bridge in the rain: a box goes over the rail and the passenger at
## the open back leans out after it, another box clutched to his chest.
func _rainy_bridge() -> void:
	var runner: Node = await _new_runner(&"puente_lluvia", 4)
	var van := runner.get(&"van") as VehicleBody3D
	var segment := runner.get(&"focus") as Node3D
	if segment != null:
		var onto_bridge: float = float(segment.get(&"length")) * 0.35
		runner.call(&"_place_before", float(segment.get_meta(&"route_distance", 0.0)) + onto_bridge)
	_freeze_world(runner)
	_rest_van_on_road(runner)
	van.call(&"set_door_open", &"rear", true)
	var floor_y: float = _bay_floor(van)
	var passenger := _crew_at(van.to_global(Vector3(-0.4, floor_y, 4.3)), van.to_global(Vector3(1.5, 0.0, 9.0)),
		&"Idle", 0.2)
	var clutched := _box(&"liquid")
	_hold(passenger, clutched)
	_at_risk(clutched)
	var leaner := _crew_at(van.to_global(Vector3(0.55, floor_y, 4.5)), van.to_global(Vector3(3.0, 0.0, 6.0)),
		&"PickUpHigh", 0.55)
	# Going over the bridge's rail, beside the truck's back.
	var falling := _box(&"fragile")
	var rail_side: Vector3 = _ground(van.to_global(Vector3(2.2, 0.0, 6.4)))
	falling.global_transform = Transform3D(Basis.from_euler(Vector3(0.9, 0.2, -0.6)), rail_side + Vector3.UP * 1.25)
	_at_risk(falling)
	# Over the lane, between the rails, chasing the truck.
	_set_camera(runner, van.to_global(Vector3(-2.3, 3.3, 10.2)), van.to_global(Vector3(0.9, 1.4, 3.2)))
	await _settle()


## A house at night: the truck at the door, the back open; one runs the box to
## the porch, one hands another down from the bay to the third.
func _house_at_night() -> void:
	var runner: Node = await _new_runner(&"casa_noche", 3)
	var van := runner.get(&"van") as VehicleBody3D
	_move_van_to_stop(runner)
	_freeze_world(runner)
	van.call(&"set_door_open", &"rear", true)
	var house := runner.get(&"focus") as Node3D
	var floor_y: float = _bay_floor(van)
	# The house's side of the road, in the truck's space.
	var side: float = signf(van.to_local(house.global_position).x)
	var porch: Vector3 = house.global_position
	var rear: Vector3 = _ground(van.to_global(Vector3(side * 1.2, 0.0, 6.2)))
	var courier := _crew_at(_ground(rear.lerp(porch, 0.4)), porch, &"Run", 0.3)
	_hold(courier, _box(&"fragile"))
	var inside := _crew_at(van.to_global(Vector3(side * 0.3, floor_y, 4.3)),
		van.to_global(Vector3(side * 1.4, 0.0, 6.4)), &"Idle", 0.4)
	_hold(inside, _box(&"growing_weight"))
	_crew_at(rear, van.to_global(Vector3(side * 0.3, 0.0, 4.0)), &"PickUpHigh", 0.6)
	# The bay's work light: the crew at the back aren't lost in the night.
	var work_light := OmniLight3D.new()
	work_light.light_color = Color("ffe2b0")
	work_light.light_energy = 1.6
	work_light.omni_range = 7.0
	(runner.get(&"level") as Node).add_child(work_light)
	work_light.global_position = van.to_global(Vector3(side * -0.6, 2.8, 7.2))
	var middle: Vector3 = rear.lerp(porch, 0.35)
	_set_camera(runner, van.to_global(Vector3(side * -3.0, 2.6, 13.0)), middle + Vector3.UP * 1.1)
	await _settle()


# --- Crew and boxes -------------------------------------------------------------


## A teammate standing at `at`, facing `toward`, in `clip` frozen `clip_time`
## seconds in.
func _crew_at(at: Vector3, toward: Vector3, clip: StringName, clip_time: float) -> CharacterBody3D:
	var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as CharacterBody3D
	player.name = "Player_%d" % _next_peer
	_next_peer += 1
	(_runner.get(&"level") as Node).add_child(player)
	player.global_position = at
	player.set(&"net_position", at)
	var facing: Vector3 = toward - at
	facing.y = 0.0
	if facing.length() > 0.01:
		player.global_basis = Basis.looking_at(facing.normalized(), Vector3.UP)
	player.set(&"anim_state", clip)
	player.set(&"locomotion_speed", 5.5 if clip == &"Run" else (3.6 if clip == &"Walk" else 0.0))
	_poses.append([player, clip, clip_time])
	return player


## A box out of nowhere (not part of the run's cargo), frozen where it's put.
func _box(trap: StringName) -> RigidBody3D:
	var package := (load(PACKAGE_SCENE_PATH) as PackedScene).instantiate() as RigidBody3D
	package.set(&"package_id", StringName("store_%s_%d" % [trap, _next_box]))
	_next_box += 1
	package.set(&"trap_definition", load(TRAPS_DIR + String(trap) + ".tres"))
	package.freeze = true
	(_runner.get(&"level") as Node).add_child(package)
	return package


## `package` in `player`'s hands: a real pick-up, so the carry pose puts the
## hands on it, and the box where a carrier holds one.
func _hold(player: CharacterBody3D, package: RigidBody3D) -> void:
	package.freeze = true
	package.global_transform = Transform3D(player.global_basis, player.to_global(HOLD_OFFSET))
	player.call(&"pick_up", package.get_path())
	# Already lifted: the pick-up's reach-and-lift is over.
	player.set(&"_pickup_elapsed", 2.0)


## The box's at-risk look, as the HUD and its feedback show it in play.
func _at_risk(package: RigidBody3D) -> void:
	var event_bus: Node = root.get_node(^"/root/EventBus")
	event_bus.emit_signal(&"package_integrity_changed", package.get(&"package_id"), 24.0, 100.0)
	event_bus.emit_signal(&"package_state_changed", package.get(&"package_id"), ITrapBehavior.TrapState.AT_RISK)


## Lets the hands reach their boxes, then freezes every pose on its clip.
func _settle() -> void:
	for _i in range(SETTLE_FRAMES):
		await process_frame
	for pose: Array in _poses:
		var player: CharacterBody3D = pose[0]
		player.set_process(false)
		player.set_physics_process(false)
		var animator: Object = player.get(&"animator")
		var anim: AnimationPlayer = animator.get(&"anim_player") if animator != null else null
		if anim == null:
			continue
		if anim.current_animation != String(pose[1]) and anim.has_animation(pose[1]):
			anim.play(String(pose[1]), 0.0)
		anim.seek(float(pose[2]), true)
		anim.speed_scale = 0.0
	_poses.clear()
	_hide_floating_labels()


## Floating in-world labels (a box's countdown, "PEDÍ EL CÓDIGO", a house's
## tag): game UI, not scenery. Taken off every render layer rather than
## hidden -- the box's feedback shows its countdown again every frame. What is
## printed on a box (its shipping label) doesn't billboard and stays.
func _hide_floating_labels() -> void:
	_runner.call(&"_hide_overlays")
	for label: Node in (_runner.get(&"level") as Node).find_children("*", "Label3D", true, false):
		if (label as Label3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			(label as Label3D).visible = false
			(label as Label3D).layers = 0


# --- World ----------------------------------------------------------------------


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


## The truck, with the boxes aboard, on whatever it's over: _place_before()
## puts it at the route's path height, and a bridge's deck is above that (the
## truck sank into it up to the cargo box).
func _rest_van_on_road(runner: Node) -> void:
	var van := runner.get(&"van") as VehicleBody3D
	var query := PhysicsRayQueryParameters3D.create(van.global_position + Vector3.UP * 6.0,
		van.global_position + Vector3.DOWN * 6.0, 1)
	var hit: Dictionary = van.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var lift := Vector3.UP * ((hit.position as Vector3).y + 0.9 - van.global_position.y)
	van.global_position += lift
	for package: Node in (runner.get(&"level") as Node).get(&"packages"):
		if is_instance_valid(package) and bool(package.get(&"is_loaded")):
			(package as Node3D).global_position += lift


## The cargo bay's floor height, in the truck's own space.
func _bay_floor(van: VehicleBody3D) -> float:
	var from: Vector3 = van.to_global(Vector3(0.0, 1.6, 4.0))
	var query := PhysicsRayQueryParameters3D.create(from, van.to_global(Vector3(0.0, -1.0, 4.0)), 1 | 2 | 64)
	var hit: Dictionary = van.get_world_3d().direct_space_state.intersect_ray(query)
	return van.to_local(hit.position).y if not hit.is_empty() else 0.55


## The ground (or road) right under `point`.
func _ground(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point + Vector3.DOWN * 12.0, 1)
	var hit: Dictionary = (_runner as Node).get_viewport().world_3d.direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else point


func _set_camera(runner: Node, position: Vector3, target: Vector3) -> void:
	var camera := runner.get(&"camera") as Camera3D
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	camera.make_current()


func _save(file_name: String) -> void:
	for _i in range(4):
		await process_frame
	if is_instance_valid(_runner):
		_hide_floating_labels()
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
	_next_peer = 2
