extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_chaos_bot.gd
##
## S-803, the chaos bot: a bot player (fixed seed) mashes every verb of the
## delivery level at random for CHAOS_SECONDS of simulated time (physics
## ticks, not wall clock): walk and jump with the real input actions, grab and
## ring things through Player._try_interact() (the probe + closest-target path
## the E key uses), drop (Q) and open/close a lid (T), sit down and stand up,
## drive with the pedal actions, ping the crew, and work the phone camera.
## It teleports next to whatever it wants to use, which stands in for
## walking there.
## It fails on what no sequence of player actions should ever cause:
## - any engine or script error (push_error, a script runtime error) -- caught
##   with a Logger, so a null access in a rarely-taken branch shows up here
##   instead of in a player's log;
## - a NaN or infinite position or velocity on the player, the truck or a box;
## - a box outside the world (below the ground, or absurdly far from the map).
## If a run ends (the bot tipped the van or drove off the road) it starts a
## fresh delivery with the next seed and keeps going, so the simulated time
## is always spent playing.
## Speed: headless paces physics at wall-clock speed, so the test raises
## Engine.physics_ticks_per_second and Engine.time_scale together (ticks stay
## 1/60 s of game time, 30x as many per real second) and restores them at the
## end. About 35 s wall for 300 simulated seconds (over S-806's 20 s goal;
## the level load and the physics are the cost). Repeatable: same seeds, same
## bot; a failure prints its tick, seed and last actions to replay it.

const CHAOS_SECONDS: float = 300.0
const TICKS_PER_SECOND: int = 60
const TIME_SCALE: float = 30.0
const FIRST_SEED: int = 8030
## A box below or beyond these has left the world (terrain dips are far above).
const WORLD_FLOOR_Y: float = -40.0
const WORLD_CEILING_Y: float = 300.0
const WORLD_RADIUS: float = 3000.0
const NEAR_HOUSE: float = 60.0
const INTERACT_HEIGHT: float = 0.3

var _failures: int = 0
var _catcher: ErrorCatcher
var _rng := RandomNumberGenerator.new()
var _tick: int = 0
var _lives: int = 0
var _counts: Dictionary = {}
var _recent: Array[StringName] = []
var _level: Node
var _player: Node
var _phone: Node
var _van: VehicleBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	_rng.seed = FIRST_SEED
	# Headless paces physics at wall-clock speed (time_scale alone only makes each
	# tick longer). ticks/s x time_scale keeps every tick at 1/60 s of game time
	# but runs TIME_SCALE of them per real second.
	Engine.physics_ticks_per_second = int(TICKS_PER_SECOND * TIME_SCALE)
	Engine.time_scale = TIME_SCALE
	Engine.max_physics_steps_per_frame = 64
	OS.low_processor_usage_mode_sleep_usec = 0
	var network: Node = root.get_node(^"/root/NetworkManager")
	var manager: Node = root.get_node(^"/root/RunManager")
	var total_ticks: int = int(CHAOS_SECONDS * TICKS_PER_SECOND)
	var started_ms: int = Time.get_ticks_msec()

	while _tick < total_ticks and _failures == 0:
		network.set(&"world_seed", FIRST_SEED + _lives)
		network.set(&"world_house_count", 3)
		await _start_life()
		_lives += 1
		while _tick < total_ticks and _failures == 0:
			if not bool(manager.get(&"is_running")) and _tick_since_start() > 5:
				break
			await _do_random_action()
			_check_world()
			_check_logged_errors()
		await _end_life()

	_release_inputs()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = TICKS_PER_SECOND
	Engine.max_physics_steps_per_frame = 8
	OS.low_processor_usage_mode_sleep_usec = 6900
	OS.remove_logger(_catcher)
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)
	var verbs: Array = _counts.keys()
	verbs.sort()
	var summary: PackedStringArray = []
	for verb: Variant in verbs:
		summary.append("%s=%d" % [verb, _counts[verb]])
	print("chaos: %d ticks, %d deliveries, %.1f s wall, actions %s" % [
			_tick, _lives, (Time.get_ticks_msec() - started_ms) / 1000.0, ", ".join(summary)])
	if _failures == 0:
		print("PASS: %.0f s of random player actions raised no error, no NaN and lost no box" % CHAOS_SECONDS)
	quit(_failures)


var _life_start_tick: int = 0


func _tick_since_start() -> int:
	return _tick - _life_start_tick


func _start_life() -> void:
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(_level)
	current_scene = _level
	await process_frame
	await _step()
	_player = _level.get(&"local_player")
	_van = _level.get(&"vehicle")
	_phone = _level.get_node(^"PhoneCamera")
	_level.call(&"start_debug_delivery")
	_life_start_tick = _tick
	await _step()
	var running: bool = bool(root.get_node(^"/root/RunManager").get(&"is_running"))
	_expect(running, "The delivery starts with the bot at the wheel")


func _end_life() -> void:
	_release_inputs()
	if is_instance_valid(_level):
		_level.queue_free()
	await process_frame
	root.get_node(^"/root/RunManager").call(&"reset_run")
	await process_frame


## One physics frame of simulated time.
func _step(count: int = 1) -> void:
	for i: int in count:
		await physics_frame
		_tick += 1


func _do_random_action() -> void:
	var seated: bool = bool(_player.get(&"_seated"))
	var carrying: bool = _player.get(&"carried_package") != null
	var pool: Array[StringName] = [&"walk", &"walk", &"interact", &"interact", &"goto_use", &"goto_use", &"goto_use",
			&"open", &"ping", &"photo", &"idle", &"drop"]
	if seated:
		pool.append_array([&"stand", &"stand", &"drive", &"drive", &"drive", &"drive", &"drive", &"drive"])
	else:
		pool.append_array([&"sit", &"sit", &"sit", &"mount", &"mount"])
	if carrying:
		pool.append_array([&"deliver", &"deliver", &"mount", &"drop"])
	var verb: StringName = pool[_rng.randi() % pool.size()]
	_recent.append(verb)
	if _recent.size() > 6:
		_recent.pop_front()
	_counts[verb] = int(_counts.get(verb, 0)) + 1
	_release_inputs()
	match verb:
		&"walk":
			await _walk()
		&"interact":
			_player.call(&"_try_interact")
			await _step(4)
		&"goto_use":
			await _goto_and_use(_pick_interactable(false))
		&"sit":
			await _goto_and_use(_pick_interactable(true, "Seat"))
		&"mount":
			await _goto_and_use(_pick_interactable(true, "Mount"))
		&"deliver":
			await _deliver()
		&"open":
			_player.call(&"_toggle_package_lid")
			await _step(6)
		&"drop":
			_player.call(&"_drop_carried")
			await _step(6)
		&"ping":
			var options: Array = PingCatalog.OPTIONS
			_player.call(&"_send_ping", String(options[_rng.randi() % options.size()]["label"]))
			await _step(3)
		&"photo":
			if _rng.randf() < 0.5:
				_phone.call(&"toggle")
			await _phone.shoot()
			await _step(3)
		&"stand":
			_player.call(&"leave_seat")
			await _step(10)
		&"drive":
			await _drive()
		_:
			await _step(_rng.randi_range(5, 40))


func _walk() -> void:
	var actions: Array[StringName] = [&"walk_forward", &"walk_backward", &"drive_left", &"drive_right",
			&"look_left", &"look_right", &"look_up", &"look_down"]
	for i: int in _rng.randi_range(1, 3):
		Input.action_press(actions[_rng.randi() % actions.size()], _rng.randf_range(0.3, 1.0))
	if _rng.randf() < 0.4:
		Input.action_press(&"jump")
	await _step(_rng.randi_range(15, 90))


func _drive() -> void:
	var throttle: float = _rng.randf_range(-0.5, 1.0)
	var steer: float = _rng.randf_range(-1.0, 1.0)
	Input.action_press(&"drive_accelerate" if throttle >= 0.0 else &"drive_brake", absf(throttle))
	Input.action_press(&"drive_right" if steer >= 0.0 else &"drive_left", absf(steer))
	if _rng.randf() < 0.15:
		Input.action_press(&"drive_handbrake")
	await _step(_rng.randi_range(30, 150))


## The bot's stand-in for walking: appear next to the target facing it, give the
## probe a couple of physics frames to notice it, then press the use key.
func _goto_and_use(target: Node3D) -> void:
	if target == null or bool(_player.get(&"_seated")):
		await _step(2)
		return
	_teleport_beside(target.global_position)
	await _step(3)
	_player.call(&"_try_interact")
	await _step(_rng.randi_range(3, 12))


func _deliver() -> void:
	# Only doors the truck's own neighbourhood has built: the route streams in
	# around the van, so a house hundreds of metres down the road has no ground
	# yet and anything dropped there would fall forever (teleporting is the
	# bot's stand-in for walking, not for the drive).
	var houses: Array = (_level.get_node(^"World/Route").get(&"houses") as Array).filter(
			func(door: Node3D) -> bool: return door.global_position.distance_to(_van.global_position) < NEAR_HOUSE)
	if houses.is_empty() or bool(_player.get(&"_seated")):
		await _step(2)
		return
	var house: Node3D = houses[_rng.randi() % houses.size()]
	_teleport_beside(house.call(&"porch_position"))
	await _step(3)
	_player.call(&"_try_interact")
	await _step(5)
	await _phone.shoot()
	await _step(3)


func _pick_interactable(only_matching: bool, name_part: String = "") -> Node3D:
	var found: Array[Node3D] = []
	for node: Node in _level.find_children("*", "Interactable", true, false):
		var area := node as Node3D
		if area == null:
			continue
		var label: String = String(area.get_parent().name) + "/" + String(area.name)
		if not name_part.is_empty() and not name_part in label:
			continue
		# Mostly things that can be used right now; sometimes anything, so the
		# refusals get exercised too.
		if (only_matching or _rng.randf() < 0.8) and not bool(area.call(&"can_interact", _player)):
			continue
		found.append(area)
	if found.is_empty():
		return null
	return found[_rng.randi() % found.size()]


func _teleport_beside(point: Vector3) -> void:
	var angle: float = _rng.randf() * TAU
	var spot: Vector3 = point + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.6, 1.3)
	spot.y = point.y + INTERACT_HEIGHT
	_player.set(&"global_position", spot)
	_player.set(&"velocity", Vector3.ZERO)
	_player.look_at(Vector3(point.x, spot.y, point.z), Vector3.UP)
	_player.call(&"reset_physics_interpolation")


func _release_inputs() -> void:
	for action: StringName in [&"walk_forward", &"walk_backward", &"drive_left", &"drive_right", &"look_left",
			&"look_right", &"look_up", &"look_down", &"jump", &"drive_accelerate", &"drive_brake", &"drive_handbrake"]:
		Input.action_release(action)


func _check_world() -> void:
	if not is_instance_valid(_level):
		return
	var watched: Array[Node3D] = [_player as Node3D, _van as Node3D]
	# Untyped: a box handed over at a door is freed but stays in the level's
	# list, and a typed loop variable can't even hold a freed instance.
	for package: Variant in _level.get(&"packages"):
		if is_instance_valid(package):
			watched.append(package as Node3D)
	for body: Node3D in watched:
		if not is_instance_valid(body):
			continue
		var at: Vector3 = body.global_position
		_expect(_finite(at), "%s has a finite position at %s (got %s)" % [body.name, _where(), at])
		if body is RigidBody3D or body is CharacterBody3D or body is VehicleBody3D:
			var speed: Vector3 = body.get(&"linear_velocity") if body is RigidBody3D else body.get(&"velocity")
			_expect(_finite(speed), "%s has a finite velocity at %s (got %s)" % [body.name, _where(), speed])
	for package: Variant in _level.get(&"packages"):
		if not is_instance_valid(package):
			continue
		var at: Vector3 = (package as Node3D).global_position
		_expect(at.y > WORLD_FLOOR_Y and at.y < WORLD_CEILING_Y and Vector2(at.x, at.z).length() < WORLD_RADIUS,
				"Box %s stays inside the world at %s (got %s)" % [package.name, _where(), at])


func _check_logged_errors() -> void:
	for message: String in _catcher.take():
		_failures += 1
		printerr("ERROR: engine or script error at %s: %s" % [_where(), message])


func _where() -> String:
	return "tick %d (life %d, seed %d, last actions %s)" % [_tick, _lives, FIRST_SEED + _lives - 1, _recent]


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_catcher.ignoring = true
		push_error(description)
		_catcher.ignoring = false
		_failures += 1


## Collects everything the engine reports as an error while the bot plays.
class ErrorCatcher extends Logger:
	var ignoring: bool = false
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if ignoring or error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out
