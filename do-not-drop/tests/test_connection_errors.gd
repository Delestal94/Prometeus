extends SceneTree
## Connection failures are protocol reasons internally and actionable Spanish
## messages at the menu boundary; a joiner's auth timeout ends the session a
## frame later, not inside SceneMultiplayer.poll() (that freed the peer mid-poll).

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu_script: Script = load("res://scripts/ui/main_menu.gd")

	var protocol_version := int(network.get(&"PROTOCOL_VERSION"))
	_expect(protocol_version >= 1, "The network protocol is versioned")
	var valid_state: Dictionary = {
		"version": protocol_version,
		"seed": 42,
		"houses": 2,
		"locked": [],
		"runs": 3,
		"scene": "res://scenes/gameplay/level_base.tscn",
	}
	_expect(String(network.call(&"_handshake_error", valid_state)).is_empty(), "Matching handshake is accepted")
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

	if _failures == 0:
		print("PASS: protocol mismatch, timeout, full room and connection errors are actionable;"
			+ " auth timeout ends the session outside the poll")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
