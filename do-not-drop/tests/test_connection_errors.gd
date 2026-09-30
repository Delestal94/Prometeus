extends SceneTree
## Connection failures are protocol reasons internally and actionable Spanish
## messages at the menu boundary; a joiner's auth timeout ends the session a
## frame later, not inside SceneMultiplayer.poll() (that freed the peer mid-poll).
## The handshake and ENet peer timeouts outlast a blocking level load (18-34 s on
## CI): MIN equals MAX, or ENet cuts a settled joiner at MIN, mid-load.
## N-235: once a peer is in, NetworkManager drops a silent one within about
## 20 s (a single value, so MIN = MAX again), well under the load budget, and a
## session of one applies no ENet timeout at all. The 45 -> 20 s switch on
## admission and 20 -> 45 s on a restart run over a real link in
## modules/net_session/tests/test_net_session.gd. Here, over a real link too:
## restart_delivery() (level_common.gd) announces the restart before its fade,
## so both ends are on the 45 s budget while the host still polls and ENet can
## resend a lost notice -- not right before the reload blocks the host.

const RESTART_PORT: int = 7814

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu_script: Script = load("res://scripts/ui/main_menu.gd")

	var protocol_version := int(network.get(&"PROTOCOL_VERSION"))
	_expect(protocol_version >= 1, "The network protocol is versioned")
	var handshake_seconds := float(network.get(&"JOIN_HANDSHAKE_TIMEOUT"))
	var enet_min := int(network.get(&"ENET_PEER_TIMEOUT_MIN_MSEC"))
	var enet_max := int(network.get(&"ENET_PEER_TIMEOUT_MAX_MSEC"))
	_expect(handshake_seconds >= 40.0, "The join handshake outlasts the slowest CI level load")
	_expect(enet_min == enet_max, "ENet's peer timeout has no lower MIN that cuts a joiner mid-load")
	_expect(enet_min >= int(handshake_seconds * 1000.0), "ENet does not drop a joiner before the handshake times out")
	var enet_session := int(network.get(&"ENET_PEER_TIMEOUT_SESSION_MSEC"))
	_expect(enet_session >= 15000 and enet_session <= 25000,
		"In session a crashed peer is noticed in about 20 s, not 45 (got %d ms)" % enet_session)
	_expect(enet_session < enet_max, "The session timeout is shorter than the level-load budget")
	_expect(network.has_method(&"enet_timeout_msec") and int(network.call(&"enet_timeout_msec", 1)) == 0,
		"Offline, NetworkManager applies no ENet timeout to anyone")
	var valid_state: Dictionary = {
		"version": protocol_version,
		"seed": 42,
		"houses": 2,
		"locked": [],
		"runs": 3,
		"scene": "res://scenes/gameplay/level_base.tscn",
		"colors": {1: 0, 1_874_223_901: 1},
	}
	_expect(String(network.call(&"_handshake_error", valid_state)).is_empty(), "Matching handshake is accepted")
	var no_colors: Dictionary = valid_state.duplicate(true)
	no_colors.erase("colors")
	_expect(String(network.call(&"_handshake_error", no_colors)) == "connection",
		"A handshake without the colour slots (N-226) is refused")
	var old_state: Dictionary = valid_state.duplicate(true)
	old_state.version = protocol_version - 1
	_expect(String(network.call(&"_handshake_error", old_state)) == "version", "Old protocol is rejected as version")
	old_state.erase("version")
	_expect(String(network.call(&"_handshake_error", old_state)) == "version", "Missing protocol is rejected as version")
	_expect(String(network.call(&"_ready_reply_error", {"ready": true, "version": protocol_version})).is_empty(),
		"Host accepts a ready reply from its protocol")
	_expect(String(network.call(&"_ready_reply_error", {"ready": true, "version": protocol_version - 1})) == "version",
		"Host rejects a ready reply from an old client")

	# A joiner's auth timeout is reported from inside SceneMultiplayer.poll():
	# ending the session there freed the peer mid-poll (SIGSEGV), so it has to
	# wait for the next idle frame.
	var client := ENetMultiplayerPeer.new()
	_expect(client.create_client("127.0.0.1", 7799) == OK, "A client peer can be created for the auth check")
	network.multiplayer.multiplayer_peer = client
	var failures: Array[String] = []
	var on_failed: Callable = func(reason: String) -> void: failures.append(reason)
	network.session_failed.connect(on_failed)
	network.call(&"_auth_failed", 1)
	_expect(failures.is_empty() and network.multiplayer.multiplayer_peer == client,
		"An auth timeout leaves the peer alone while SceneMultiplayer is polling it")
	await process_frame
	_expect(failures == ["timeout"], "The auth timeout still fails the session, one frame later")
	_expect(network.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "The failed session goes back offline")
	# The host dropping a pending joiner fires the auth failure and then
	# server_disconnected in the same poll: the crew hears about it once.
	failures.clear()
	var dropped := ENetMultiplayerPeer.new()
	dropped.create_client("127.0.0.1", 7799)
	network.multiplayer.multiplayer_peer = dropped
	network.call(&"_auth_failed", 1)
	network.call(&"_on_server_disconnected")
	await process_frame
	_expect(failures.size() == 1, "An auth failure right before the host drop reports one failure, not two")
	# A deferred failure never ends a session that began after it was raised.
	failures.clear()
	var old_peer := ENetMultiplayerPeer.new()
	old_peer.create_client("127.0.0.1", 7799)
	network.multiplayer.multiplayer_peer = old_peer
	network.call(&"_auth_failed", 1)
	var fresh := ENetMultiplayerPeer.new()
	fresh.create_client("127.0.0.1", 7799)
	network.multiplayer.multiplayer_peer = fresh
	await process_frame
	_expect(failures.is_empty() and network.multiplayer.multiplayer_peer == fresh,
		"A stale auth failure leaves the next session alone")
	# The host's "failure" reply arrives through the auth callback, also inside poll().
	network.call(&"_receive_auth", 1, var_to_bytes({"failure": "version"}))
	_expect(failures.is_empty() and network.multiplayer.multiplayer_peer == fresh,
		"A version refusal leaves the peer alone while SceneMultiplayer is polling it")
	await process_frame
	_expect(failures == ["version"], "The version refusal still fails the session, one frame later")
	network.session_failed.disconnect(on_failed)
	network.call(&"take_failure_message")

	var expected: Dictionary = {
		"version": "El anfitrión tiene otra versión del juego: actualicen los dos.",
		"timeout": "No hubo respuesta en 8 s. Revisá la IP y que el firewall de Windows permita Take My Package.",
		"full": "La sala está llena.",
		"connection": "No se pudo completar la conexión. Revisá la dirección e intentá de nuevo.",
	}
	for reason: String in expected:
		_expect(String(menu_script.call(&"connection_error_text", reason)) == expected[reason],
			"Reason '%s' shows its actionable message" % reason)
	_expect(String(menu_script.call(&"connection_error_text", "Mensaje legado")) == "Mensaje legado",
		"Existing user-facing failures remain readable")

	# Exercise the actual menu boundary, not only its pure lookup helper.
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	for reason: String in expected:
		menu.call(&"_on_session_failed", reason)
		_expect((menu.get(&"_status_label") as Label).text == expected[reason],
			"Menu renders the '%s' message" % reason)
	menu.free()

	await _restart_announces_before_fade(network)

	if _failures == 0:
		print("PASS: protocol mismatch, timeout, full room and connection errors are actionable;"
			+ " auth timeout ends the session outside the poll")
	quit(_failures)


## NetworkManager hosts on localhost; a second copy of network_manager.gd joins,
## on its own SceneMultiplayer under a node standing in for /root (so its RPC
## paths match the host's). The level is level_common.gd set on a bare node
## already in the tree -- no scene, and its _ready never runs -- and is freed
## before its fade ends, so its restart and reload never run here. Whoever
## else listens to the host's roster (CrewProgression sends its campaign to a
## new peer) is unhooked meanwhile: that stand-in client has none of it.
func _restart_announces_before_fade(network: Node) -> void:
	var roster_listeners: Array[Dictionary] = network.get_signal_connection_list(&"roster_changed")
	for connection: Dictionary in roster_listeners:
		network.disconnect(&"roster_changed", connection.callable)
	var client_root := Node.new()
	client_root.name = "ClientRoot"
	root.add_child(client_root)
	set_multiplayer(SceneMultiplayer.new(), client_root.get_path())
	var client: Node = (load("res://scripts/core/network_manager.gd") as GDScript).new()
	client.name = "NetworkManager"
	client_root.add_child(client)
	network.set(&"transport", 2)  # NetSession.Transport.ENET
	client.set(&"transport", 2)
	var settle_delay: float = float(network.get(&"settle_delay_seconds"))
	network.set(&"settle_delay_seconds", 0.0)
	var handshakes: Array = []
	client.connect(&"session_ready", func(is_host: bool) -> void: handshakes.append(is_host))
	var up: bool = network.call(&"host_session", RESTART_PORT) == OK \
		and client.call(&"join_session", "127.0.0.1", RESTART_PORT) == OK
	_expect(up and await _wait_for(func() -> bool: return not handshakes.is_empty()),
		"A second NetworkManager joins the one hosting")
	client.call(&"level_ready")
	var joiner: int = client.multiplayer.get_unique_id()
	var session_msec := int(network.get(&"ENET_PEER_TIMEOUT_SESSION_MSEC"))
	var load_msec := int(network.get(&"ENET_PEER_TIMEOUT_MAX_MSEC"))
	var settled: Callable = func() -> bool:
		return int(network.call(&"enet_timeout_msec", joiner)) == session_msec \
			and int(client.call(&"enet_timeout_msec", 1)) == session_msec
	_expect(await _wait_for(settled), "Admitted, both NetworkManagers drop a silent peer within the session timeout")
	var level := Node3D.new()
	root.add_child(level)
	level.set_script(load("res://scripts/gameplay/level_common.gd"))
	level.call(&"restart_delivery")  # Returns at its fade's await.
	_expect(int(network.call(&"enet_timeout_msec", joiner)) == load_msec,
		"restart_delivery() puts the host on the load budget before its fade (got %d ms)"
		% int(network.call(&"enet_timeout_msec", joiner)))
	# The client is polled by hand: no frame passes, so the fade's timer can't
	# run out and the host doesn't poll.
	var told: bool = false
	for attempt: int in 100:
		OS.delay_msec(10)
		client.multiplayer.poll()
		if int(client.call(&"enet_timeout_msec", 1)) == load_msec:
			told = true
			break
	_expect(told, "The client is on the load budget before the host's fade ends")
	level.free()
	client.call(&"leave_session")
	network.call(&"leave_session")
	network.set(&"settle_delay_seconds", settle_delay)
	network.call(&"take_failure_message")
	await process_frame
	set_multiplayer(null, client_root.get_path())
	client_root.free()
	for connection: Dictionary in roster_listeners:
		network.connect(&"roster_changed", connection.callable, connection.flags)


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
