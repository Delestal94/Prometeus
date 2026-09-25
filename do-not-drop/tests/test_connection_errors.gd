extends SceneTree
## Connection failures are protocol reasons internally and actionable Spanish
## messages at the menu boundary.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu_script: Script = load("res://scripts/ui/main_menu.gd")

	_expect(int(network.get(&"PROTOCOL_VERSION")) == 1, "The network protocol starts at version 1")
	var valid_state: Dictionary = {
		"version": 1,
		"seed": 42,
		"houses": 2,
		"locked": [],
		"scene": "res://scenes/gameplay/level_base.tscn",
	}
	_expect(String(network.call(&"_handshake_error", valid_state)).is_empty(), "Matching handshake is accepted")
	var old_state: Dictionary = valid_state.duplicate(true)
	old_state.version = 0
	_expect(String(network.call(&"_handshake_error", old_state)) == "version", "Old protocol is rejected as version")
	old_state.erase("version")
	_expect(String(network.call(&"_handshake_error", old_state)) == "version", "Missing protocol is rejected as version")
	_expect(String(network.call(&"_ready_reply_error", {"ready": true, "version": 1})).is_empty(),
		"Host accepts a ready reply from its protocol")
	_expect(String(network.call(&"_ready_reply_error", {"ready": true, "version": 0})) == "version",
		"Host rejects a ready reply from an old client")

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
		print("PASS: protocol mismatch, timeout, full room and connection errors are actionable")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
