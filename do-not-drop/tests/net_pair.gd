extends Node
## Two-process gameplay race check. Run through tools/run-net-pair.sh.

const PORT: int = 17992
const TIMEOUT_SECONDS: float = 40.0
const CLIENT_COSMETIC: StringName = &"mint_uniform"

var _network: Node
var _level: Node
var _host: bool = false
var _failed: bool = false
var _finished: bool = false
var _client_peer_id: int = 0
var _pickup_sent: bool = false
var _race_sent: bool = false
var _reports: Dictionary = {}


func _ready() -> void:
	_network = get_node(^"/root/NetworkManager")
	_network.set(&"transport", 2)  # NetworkManager.Transport.ENET
	_host = "--host" in OS.get_cmdline_user_args()
	if not _host:
		# Starter cosmetic, but deliberately not the automatic team colour.
		get_node(^"/root/UnlockManager").set(&"selected_cosmetic", CLIENT_COSMETIC)
	_network.connect(&"session_ready", func(_is_host: bool) -> void: _load_level.call_deferred())
	var error: Error = _network.call(&"host_session", PORT) if _host else _network.call(&"join_session", "127.0.0.1", PORT)
	if error != OK:
		print("PAIR role=%s FAIL could not %s (error %d)" % [_role(), "host" if _host else "join", error])
		get_tree().quit(1)
		return
	if _host:
		_run_host.call_deferred()
	else:
		_watch_client.call_deferred()


func _load_level() -> void:
	if _level != null:
		return
	_level = load("res://scenes/gameplay/level_base.tscn").instantiate()
	get_tree().root.add_child(_level)


func _run_host() -> void:
	if not await _wait_until(func() -> bool:
		return _level != null and get_tree().get_nodes_in_group(&"player").size() >= 2):
		await _finish(false, "timed out waiting for both spawned players")
		return
	_client_peer_id = int(get_tree().root.multiplayer.get_peers()[0])
	var host_player: Player = _player(1)
	var client_player: Player = _player(_client_peer_id)
	if host_player == null or client_player == null:
		await _finish(false, "spawned player paths are missing")
		return

	# The client owns this property. The host must see the selected uniform.
	var cosmetic_arrived: bool = await _wait_until(func() -> bool:
		return client_player.cosmetic_id == CLIENT_COSMETIC)
	_expect(cosmetic_arrived, "host sees the client's selected uniform")

	# The client sends its pickup request and a sibling notification in one
	# frame. Whichever request the host processes first may win; only one may.
	var package: DeliveryPackage = _level.packages[0]
	var pickup: Node = package.get_node(^"InteractionArea")
	rpc_id(_client_peer_id, &"_client_attempt_pickup", package.get_path(), pickup.get_path())
	if not await _wait_until(func() -> bool: return _pickup_sent):
		await _finish(false, "client never sent the pickup race")
		return
	pickup.call(&"interact", host_player)
	await _pump(1.0)
	var carriers: Array[Player] = _players_holding(package)
	_expect(carriers.size() == 1, "simultaneous pickup leaves exactly one player holding the package")
	_expect(package.carrier == carriers[0] if carriers.size() == 1 else false,
		"host authority agrees with the one visible carrier")
	rpc_id(_client_peer_id, &"_client_check_pickup", package.get_path())
	await _wait_for_report(&"pickup")

	# Reset through the real host-authoritative drop path before the seat race.
	if package.is_held:
		package.call(&"request_drop", Transform3D(Basis.IDENTITY, package.global_position), false)
	await _pump(0.7)

	var seat: Node = _level.get_node(^"World/Vehicle/CargoBay/CenterSeatEyePoint/InteractionArea")
	seat.call(&"interact", host_player)
	await _pump(0.4)
	rpc_id(_client_peer_id, &"_client_attempt_occupied_seat", seat.get_path())
	await _pump(1.0)
	_expect(seat.get(&"occupant") == host_player, "occupied seat keeps its first occupant")
	_expect(client_player.seat_node_path.is_empty(), "client is rejected from the occupied seat")
	rpc_id(_client_peer_id, &"_client_check_seat", host_player.get_path(), client_player.get_path(), seat.get_parent().get_path())
	await _wait_for_report(&"seat")
	host_player.call(&"leave_seat")
	await _pump(0.6)

	# Put the package in the client's hands, then have that client request a
	# handoff and a drop in the same frame. Dropping cancels the in-flight
	# handoff: nobody may retain a second copy in their hands.
	package.call(&"take_by", client_player)
	await _pump(0.8)
	_expect(client_player.carried_package == package, "client holds the package before the transfer/drop race")
	rpc_id(_client_peer_id, &"_client_transfer_then_drop", package.get_path(), host_player.get_path())
	if not await _wait_until(func() -> bool: return _race_sent):
		await _finish(false, "client never sent the transfer/drop race")
		return
	await _pump(1.5)
	_expect(not package.is_held and package.carrier == null, "package ends loose on the floor after transfer/drop")
	_expect(host_player.carried_package == null and client_player.carried_package == null,
		"neither host nor client keeps the dropped package in hand")
	rpc_id(_client_peer_id, &"_client_check_drop", package.get_path())
	await _wait_for_report(&"drop")

	# The disconnect cleanup is the last check because the client process
	# intentionally leaves. Its carried box must become loose on the host.
	package.call(&"take_by", client_player)
	await _pump(0.8)
	_expect(client_player.carried_package == package and package.carrier == client_player,
		"client holds the package before disconnecting")
	rpc_id(_client_peer_id, &"_client_disconnect_while_carrying", package.get_path())
	var disconnected: bool = await _wait_until(func() -> bool:
		return get_tree().root.multiplayer.get_peers().is_empty())
	_expect(disconnected, "host observes the client disconnect")
	await _pump(0.8)
	_expect(is_instance_valid(package) and package.is_inside_tree(), "disconnected client's package remains in the world")
	_expect(not package.is_held and package.carrier == null and package.collision_layer == 4,
		"disconnected client's package is loose on the host")
	_client_peer_id = 0  # It already printed its own result and left cleanly.

	await _finish(not _failed, "all pair checks passed")


func _watch_client() -> void:
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while not _finished and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _finished:
		print("PAIR role=client FAIL timed out waiting for host commands")
		_network.call(&"leave_session")
		get_tree().quit(1)


@rpc("authority", "call_remote", "reliable")
func _client_attempt_pickup(_package_path: NodePath, pickup_path: NodePath) -> void:
	var pickup: Node = get_node_or_null(pickup_path)
	if pickup != null:
		pickup.rpc_id(1, &"request_interact")
	rpc_id(1, &"_client_pickup_sent")


@rpc("any_peer", "call_remote", "reliable")
func _client_pickup_sent() -> void:
	if _host and get_tree().root.multiplayer.get_remote_sender_id() == _client_peer_id:
		_pickup_sent = true


@rpc("authority", "call_remote", "reliable")
func _client_check_pickup(package_path: NodePath) -> void:
	await _pump(0.4)
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var ok: bool = package != null and _players_holding(package).size() == 1 and package.is_held
	_report(&"pickup", ok, "client sees exactly one carrier")


@rpc("authority", "call_remote", "reliable")
func _client_attempt_occupied_seat(seat_path: NodePath) -> void:
	var seat: Node = get_node_or_null(seat_path)
	if seat != null:
		seat.rpc_id(1, &"request_interact")


@rpc("authority", "call_remote", "reliable")
func _client_check_seat(host_path: NodePath, client_path: NodePath, seat_path: NodePath) -> void:
	await _pump(0.4)
	var host_player: Player = get_node_or_null(host_path) as Player
	var client_player: Player = get_node_or_null(client_path) as Player
	var ok: bool = host_player != null and client_player != null \
		and host_player.seat_node_path == seat_path and client_player.seat_node_path.is_empty()
	_report(&"seat", ok, "client sees the first occupant and remains standing")


@rpc("authority", "call_remote", "reliable")
func _client_transfer_then_drop(package_path: NodePath, recipient_path: NodePath) -> void:
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var player: Player = _player(get_tree().root.multiplayer.get_unique_id())
	if package != null and player != null:
		package.rpc_id(1, &"request_transfer", recipient_path)
		player.call(&"_drop_carried")
	rpc_id(1, &"_client_race_sent")


@rpc("any_peer", "call_remote", "reliable")
func _client_race_sent() -> void:
	if _host and get_tree().root.multiplayer.get_remote_sender_id() == _client_peer_id:
		_race_sent = true


@rpc("authority", "call_remote", "reliable")
func _client_check_drop(package_path: NodePath) -> void:
	await _pump(0.4)
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var ok: bool = package != null and not package.is_held and _players_holding(package).is_empty() \
		and package.collision_layer == 4
	_report(&"drop", ok, "client sees the loose package on the floor")


@rpc("authority", "call_remote", "reliable")
func _client_disconnect_while_carrying(package_path: NodePath) -> void:
	var package: DeliveryPackage = get_node_or_null(package_path) as DeliveryPackage
	var player: Player = _player(get_tree().root.multiplayer.get_unique_id())
	var ok: bool = package != null and player != null and player.carried_package == package
	_finished = true
	print("PAIR role=client %s: disconnect while carrying" % ("PASS" if ok else "FAIL"))
	await _pump(0.2)
	_network.call(&"leave_session")
	get_tree().quit(0 if ok else 1)


func _report(stage: StringName, ok: bool, detail: String) -> void:
	rpc_id(1, &"_receive_report", stage, ok, detail)


@rpc("any_peer", "call_remote", "reliable")
func _receive_report(stage: StringName, ok: bool, detail: String) -> void:
	if not _host or get_tree().root.multiplayer.get_remote_sender_id() != _client_peer_id:
		return
	_reports[stage] = ok
	_expect(ok, detail)


@rpc("authority", "call_remote", "reliable")
func _finish_client(ok: bool) -> void:
	_finished = true
	print("PAIR role=client %s" % ("PASS" if ok else "FAIL"))
	await _pump(0.3)
	_network.call(&"leave_session")
	get_tree().quit(0 if ok else 1)


func _finish(ok: bool, detail: String) -> void:
	if not ok:
		_failed = true
		push_error(detail)
	var passed: bool = not _failed
	if _client_peer_id > 0:
		rpc_id(_client_peer_id, &"_finish_client", passed)
	print("PAIR role=host %s: %s" % ["PASS" if passed else "FAIL", detail])
	await _pump(0.8)
	_network.call(&"leave_session")
	get_tree().quit(0 if passed else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error(description)


func _wait_for_report(stage: StringName) -> bool:
	var arrived: bool = await _wait_until(func() -> bool: return _reports.has(stage))
	_expect(arrived, "client did not report stage %s" % stage)
	return arrived and bool(_reports.get(stage, false))


func _wait_until(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _pump(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _player(peer_id: int) -> Player:
	if _level == null:
		return null
	return _level.get_node_or_null(NodePath("World/Player_%d" % peer_id)) as Player


func _players_holding(package: DeliveryPackage) -> Array[Player]:
	var holders: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and player.carried_package == package:
			holders.append(player)
	return holders


func _role() -> String:
	return "host" if _host else "client"
