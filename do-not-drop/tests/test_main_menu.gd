extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_main_menu.gd
## Covers the menu's pure logic: it loads without error, and each entry
## point picks the transport it's supposed to. The actual two-process
## connection is verified separately (net_smoke.gd, and manually via
## --host-lan / --join=<ip>) -- this is about not regressing the choice
## of transport, which is what silently broke the first manual test of
## this feature (host went Steam via AUTO, --join= forces ENet, and the
## two were never going to find each other).

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var network: Node = root.get_node(^"/root/NetworkManager")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame

	_expect(is_instance_valid(menu), "The menu scene instantiates without error")
	_expect(network.get(&"transport") == NetworkManager.Transport.AUTO,
		"Starts on AUTO, same as everywhere else in the project")

	# This test only checks which transport each entry point picks, not
	# what happens once a session is actually ready -- and Steam really is
	# running on a dev machine that has it open, so _host_session() below
	# kicks off a genuine, asynchronous Steam lobby creation. Left connected,
	# session_ready firing whenever that callback lands (possibly after this
	# script has already quit) would send the menu into _go_to_level() and
	# load the real level with no multiplayer peer assigned. The transport
	# choice itself is synchronous and already checked by the time this
	# matters, so disconnecting is safe, not a gap in coverage.
	network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))

	# _busy normally clears when session_ready/session_failed fires; real
	# Steam lobby creation is async and won't resolve synchronously here, so
	# each check below resets it by hand first -- same as a fresh menu.

	# "Crear sala" (and --host) go through AUTO -- Steam when it's actually
	# usable, ENet otherwise.
	menu.set(&"_busy", false)
	menu.call(&"_host_session")
	_expect(network.get(&"transport") == NetworkManager.Transport.AUTO,
		"_host_session()'s default leaves the transport on AUTO")
	network.call(&"leave_session")

	# --host-lan explicitly overrides AUTO -- the whole reason it exists is
	# to guarantee it lands on the same transport --join= forces below.
	menu.set(&"_busy", false)
	menu.call(&"_host_session", NetworkManager.Transport.ENET)
	_expect(network.get(&"transport") == NetworkManager.Transport.ENET,
		"_host_session(ENET) actually forces ENet, not AUTO")
	network.call(&"leave_session")

	# "Unirse por IP" / --join= always force ENet: a Steam lobby is joined by
	# id, not by typing an address, so AUTO would be misleading here even
	# with Steam running. The address field is built procedurally in
	# _build_ui(), not laid out in the .tscn -- reaching it through the
	# script's own reference avoids guessing at generated node paths.
	menu.set(&"_busy", false)
	(menu.get(&"_address_field") as LineEdit).text = "203.0.113.1"
	menu.call(&"_join_by_address")
	_expect(network.get(&"transport") == NetworkManager.Transport.ENET,
		"Joining by address forces ENet regardless of what AUTO would pick")
	network.call(&"leave_session")

	menu.free()
	if _failures == 0:
		print("PASS: the menu loads and every entry point resolves to the transport it promises")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
