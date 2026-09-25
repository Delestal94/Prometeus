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

	# Layout (2026-09-25): the home page is one hero button plus a few quiet
	# ones -- it used to be ten equal buttons with the IP field among them.
	var pages: Dictionary = menu.get(&"_pages")
	var home: Control = pages[0]
	var play: Control = pages[1]
	var join: Control = pages[2]
	var address_field: LineEdit = menu.get(&"_address_field")
	_expect(home.visible and not play.visible and not join.visible, "The menu opens on its home page")
	_expect(_visible_buttons(home) <= 5, "The home page shows at most five buttons (had %d)" % _visible_buttons(home))
	_expect(not address_field.is_visible_in_tree(), "The LAN address field isn't on the home page")
	(menu.get(&"_play_button") as Button).pressed.emit()
	_expect(play.visible and not home.visible, "¡JUGAR! opens the game modes")
	menu.call(&"_show_page", 2)
	_expect(address_field.is_visible_in_tree(), "The address field lives on the join page")
	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	menu.call(&"_unhandled_input", back)
	_expect(play.visible, "Esc on the join page goes back to the modes, one level up")
	menu.call(&"_unhandled_input", back)
	_expect(home.visible, "Esc on the modes goes back to the home page")

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
	_expect(join.visible, "Joining by address (or --join=) shows the join page, where its status belongs")
	network.call(&"leave_session")

	# Accepting a friend's Steam invite (or "Unirse a la partida") while in
	# the menu joins that lobby over Steam, even right after a LAN attempt.
	current_scene = menu
	menu.set(&"_busy", false)
	network.call(&"_on_join_requested", 90210, 0)
	_expect(network.get(&"transport") == NetworkManager.Transport.STEAM,
		"An accepted Steam invite joins over Steam")
	# Whether the join then stays in flight depends on Steam actually running:
	# without it (CI, headless) _join_steam() fails synchronously and the menu
	# must drop _busy and say so, not sit on "Entrando…" forever.
	if bool(network.get(&"_steam_ready")):
		_expect(bool(menu.get(&"_busy")), "The menu takes the invite over (shows it's joining)")
	else:
		_expect(not bool(menu.get(&"_busy"))
				and (menu.get(&"_status_label") as Label).text.begins_with("No se pudo entrar"),
			"Without Steam the menu takes the invite over and reports it couldn't join")
	network.call(&"leave_session")
	network.set(&"transport", NetworkManager.Transport.AUTO)
	# An invite accepted before the menu existed waits for it, once.
	network.set(&"_pending_lobby", 4242)
	_expect(int(network.call(&"take_pending_lobby")) == 4242 and int(network.call(&"take_pending_lobby")) == 0,
		"A pending invite is handed to the menu exactly once")

	menu.free()
	if _failures == 0:
		print("PASS: the menu loads and every entry point resolves to the transport it promises")
	quit(_failures)


func _visible_buttons(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is Button and (child as Button).visible:
			count += 1
		count += _visible_buttons(child)
	return count


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
