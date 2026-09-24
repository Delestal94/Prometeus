extends SceneTree
## Run two processes with --host / --client. Exercises the real level spawner.
var network: Node
var level: Node
var host_mode: bool
var failed: bool = false
var saw_peer: bool = false

func _initialize() -> void:
	await process_frame
	network = root.get_node("NetworkManager")
	host_mode = "--host" in OS.get_cmdline_user_args()
	network.transport = 2
	network.session_ready.connect(_session_ready)
	var error: Error = network.host_session(17889) if host_mode else network.join_session("127.0.0.1", 17889)
	if error != OK:
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		root.multiplayer.poll()
		await process_frame
		if level == null:
			continue
		if host_mode and saw_peer and root.multiplayer.get_peers().is_empty():
			await _settle()
			_expect(level.vehicle.driver_peer_id == 0, "Disconnected driver releases the wheel")
			_expect(not level.vehicle.controls_enabled, "Disconnected driver cannot leave throttle enabled")
			print("PASS: host disconnect cleanup" if not failed else "FAIL: host cleanup")
			level.free()
			quit(1 if failed else 0)
			return
		var players: Array[Node] = get_nodes_in_group("player")
		if players.size() < 2:
			continue
		saw_peer = true
		if not host_mode:
			await _check_client()
			return
	push_error("Multiplayer gameplay timed out")
	quit(1)

func _session_ready(_host: bool) -> void:
	_load_level.call_deferred()

func _load_level() -> void:
	level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level

func _check_client() -> void:
	var player: Player = level.get_node("World/Player_%d" % network.local_id())
	_expect(player.is_local(), "Client owns its character")
	_expect(level.local_player == player, "Level tracks the spawned local player")
	_expect(player.global_position.distance_to(level.depot.spawn_position(1)) < 0.5,
		"Client spawns at the depot, not at the origin: %s" % player.global_position)
	_expect(player.get_node("Head/Camera3D").current, "Client camera is active")
	var start: Vector3 = player.position
	level.get_node("HUD")._primary_action()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("walk_backward")
	for i in range(60):
		root.multiplayer.poll()
		await physics_frame
	Input.action_release("walk_backward")
	print("Movement: ", start, " -> ", player.position, " mouse=", Input.mouse_mode)
	_expect(player.position.distance_to(start) > 1.0, "Client can walk")
	var package: Node = level.packages[0]
	package.get_node("InteractionArea").rpc_id(1, "request_interact")
	await _settle()
	_expect(player.carried_package == package, "Client can pick up cargo through host")
	var seat: Node = level.get_node("World/Vehicle/CargoBay/LeftSeat1EyePoint")
	seat.get_node("InteractionArea").rpc_id(1, "request_interact")
	await _settle()
	_expect(player._seated, "Client can board passenger seat")
	_expect(player.carried_package == null and player.tended_package == package, "Cargo is mounted and can be tended")
	player.leave_seat()
	await _settle()
	_expect(not player._seated and player.get_node("Head/Camera3D").current, "Client can exit and recover camera")
	_expect(player.get_node("BodyVisual").position.length() < 0.1, "Standing body has no stale seat offset")
	var driver: Node = level.get_node("World/Vehicle/CabinInterior/DriverEyePoint/InteractionArea")
	# Open the cab through the same host request used by door interactions.
	level.vehicle.rpc_id(1, "request_toggle_door", &"cab_left")
	await _settle()
	_expect(driver.can_interact(player), "Client sees mounted cargo and can use driver seat")
	driver.rpc_id(1, "request_interact")
	await _settle()
	_expect(player._seated and level.vehicle.driver_peer_id == network.local_id(), "Client takes the wheel")
	Input.action_press("drive_accelerate")
	await _settle()
	Input.action_release("drive_accelerate")
	_expect(level.vehicle.linear_velocity.length() > 0.2, "Client input drives host vehicle")
	print("PASS: client spawn, movement, pickup, boarding, exit and driving" if not failed else "FAIL: client gameplay")
	level.free()
	level = null
	network.leave_session()
	quit(1 if failed else 0)

func _settle() -> void:
	for i in range(45):
		root.multiplayer.poll()
		await physics_frame

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error(description)
