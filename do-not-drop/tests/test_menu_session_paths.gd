extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_menu_session_paths.gd
##
## How the main menu (main_menu.gd) reaches a level through a session, and what
## it does when the session breaks on the way (N-407/N-408). No level is loaded:
## the loader is cancelled right after it is created, or it swaps in a tiny scene.
## - Hosting over ENet picks level_base.tscn; "Crear sala Endless"
##   (_host_endless_session) sets NetworkManager.session_scene BEFORE host_session
##   so the room opens on level_endless.tscn; a session_ready with no scene falls
##   back to level_base. The loader's tape says which kind of room it is.
## - A start that fails on the spot (port taken) keeps the session's own reason
##   on screen: _show_failure() doesn't overwrite it with the generic "error %d".
## - A connection that fails when it is too late to cancel the loader
##   (_cancel_loading() == false): the loader is redirected to the menu, the menu
##   that is leaving doesn't swallow the failure message (the next menu shows it)
##   and a Steam invite is deferred (NetworkManager.defer_lobby) instead of
##   being thrown away or joined from a menu that is going away.

const DIR: String = "user://test_menu_session_paths"
const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

var _failures: int = 0
var _network: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_network = root.get_node(^"/root/NetworkManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	await _check_host_scenes()
	await _check_synchronous_failure()
	await _check_too_late()
	if _failures == 0:
		print("PASS: the menu picks the right level per room kind, keeps the session's failure reason and "
			+ "redirects a too-late loader back to the menu")
	quit(_failures)


func _new_menu() -> Control:
	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	current_scene = menu
	return menu


## Drops the loader a menu just started (it isn't in the tree yet) and the room.
func _abandon(menu: Control) -> void:
	_expect(bool(menu.call(&"_cancel_loading")), "A loader that is still loading can be cancelled")
	_network.call(&"leave_session")
	_network.set(&"transport", _network.Transport.AUTO)
	menu.set(&"_busy", false)


func _check_host_scenes() -> void:
	var menu: Control = _new_menu()
	await process_frame

	# session_ready with nothing chosen: the regular level, tagged as a hosted room.
	_network.set(&"session_scene", "")
	menu.call(&"_on_session_ready", true)
	var loader: LoadingScreen = menu.get(&"_loading")
	_expect(loader != null and loader.target_path == menu.LEVEL_SCENE,
		"session_ready with no session scene loads level_base (got %s)"
			% [loader.target_path if loader else "no loader"])
	_expect(loader != null and loader.mode_text == tr("UI_MENU_HOST"), "The loader's tape says it's a hosted room")
	_abandon(menu)

	# "Crear sala" over ENet (--host-lan): ready on the spot, level_base.
	menu.call(&"_host_session", _network.Transport.ENET)
	loader = menu.get(&"_loading")
	if loader == null:
		print("  (could not host on this machine, ENet scene check skipped)")
		_abandon_quietly(menu)
	else:
		_expect(loader.target_path == menu.LEVEL_SCENE,
			"Hosting over ENet loads level_base (got %s)" % loader.target_path)
		_expect(String(_network.get(&"session_scene")) == menu.LEVEL_SCENE,
			"The session remembers its level for friends who join (got %s)" % _network.get(&"session_scene"))
		_abandon(menu)

	# "Crear sala Endless": the scene is set before host_session() opens the room.
	menu.call(&"_host_endless_session")
	_expect(String(_network.get(&"session_scene")) == menu.ENDLESS_LEVEL_SCENE,
		"Hosting endless sets the session scene to level_endless (got %s)" % _network.get(&"session_scene"))
	loader = menu.get(&"_loading")
	if loader != null:
		# ENet answered at once (no Steam running); with Steam the room comes later.
		_expect(loader.target_path == menu.ENDLESS_LEVEL_SCENE,
			"The endless room loads level_endless (got %s)" % loader.target_path)
		_expect(loader.mode_text == tr("UI_MENU_HOST_ENDLESS"), "The loader's tape says it's an endless room")
		_abandon(menu)
	else:
		_abandon_quietly(menu)
	await process_frame
	await process_frame
	menu.queue_free()
	await process_frame


## The room didn't open (or Steam is answering later): nothing to cancel.
func _abandon_quietly(menu: Control) -> void:
	_network.call(&"leave_session")
	_network.set(&"transport", _network.Transport.AUTO)
	menu.set(&"_busy", false)


func _check_synchronous_failure() -> void:
	var menu: Control = _new_menu()
	await process_frame
	var taken := ENetMultiplayerPeer.new()
	# Whoever holds the port (this peer, or another test running in parallel) makes
	# hosting fail the same way.
	taken.create_server(_network.DEFAULT_PORT, 2)
	menu.call(&"_host_session", _network.Transport.ENET)
	var status: Label = menu.get(&"_status_label")
	if bool(_network.call(&"is_online")):
		print("  (the port was free after all, synchronous failure check skipped)")
		_network.call(&"leave_session")
		menu.call(&"_cancel_loading")
	else:
		var reason: String = tr("UI_NET_PORT_FAILED") % _network.DEFAULT_PORT
		_expect(status.visible and status.text == reason,
			"A port that is taken says so, not the generic error (got '%s', wanted '%s')" % [status.text, reason])
		_expect(not bool(menu.get(&"_busy")), "The menu is usable again after a failed start")
		# The other half: with no reason shown yet the generic text does appear.
		menu.set(&"_failure_shown", false)
		menu.call(&"_show_failure", "generic error 7")
		_expect(status.text == "generic error 7",
			"Without a reason of its own the generic text shows (got %s)" % status.text)
		menu.set(&"_failure_shown", true)
		menu.call(&"_show_failure", "another generic")
		_expect(status.text == "generic error 7", "With a reason already shown the generic one doesn't replace it")
	taken.close()
	_abandon_quietly(menu)
	menu.queue_free()
	await process_frame


func _check_too_late() -> void:
	var tiny_path: String = _save_scene("Tiny")
	var menu: Control = _new_menu()
	_network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))
	await process_frame
	var guard: Callable = func(node: Node) -> void:
		# No model prefetch: loading every .glb on threads crashes the headless renderer.
		if node is LoadingScreen:
			(node as LoadingScreen).prefetch_paths = PackedStringArray()
	root.child_entered_tree.connect(guard)
	menu.call(&"_go_to_level", tiny_path, "Unirse a la sala")
	var loader: LoadingScreen = menu.get(&"_loading")
	var start: int = Time.get_ticks_msec()
	while loader.stage == SceneLoader.Stage.LOADING and Time.get_ticks_msec() - start < 30000:
		await process_frame
	_expect(loader.stage == SceneLoader.Stage.BUILDING and current_scene == menu,
		"The loader is past loading but hasn't swapped yet (stage %s)" % loader.stage)

	_network.set(&"_failure_message", "timeout")
	_network.set(&"session_scene", "")
	menu.call(&"_on_session_failed", "timeout")
	_expect(String(loader.get(&"_redirect_path")) == MENU_SCENE,
		"Too late to cancel: the loader is told to come back to the menu (got '%s')" % loader.get(&"_redirect_path"))
	_expect(is_instance_valid(menu.get(&"_loading")), "The menu keeps the loader it couldn't cancel")
	_expect(not bool(menu.get(&"_failure_shown")), "The leaving menu doesn't claim it showed the failure")
	# A friend's invite arriving now is kept for the next menu.
	menu.call(&"join_steam_lobby", 424242)
	_expect(int(_network.call(&"take_pending_lobby")) == 424242,
		"A Steam invite that arrives while the level builds is deferred, not lost")
	_expect(String(_network.call(&"take_failure_message")) == "timeout",
		"The leaving menu left the failure message for the next one")
	_network.set(&"_failure_message", "timeout")  # Put back: the next menu is the one to take it.

	start = Time.get_ticks_msec()
	while is_instance_valid(loader) and Time.get_ticks_msec() - start < 60000:
		await process_frame
	_expect(not is_instance_valid(loader), "The loader finishes after the redirect")
	var again: Node = current_scene
	_expect(again != null and again.scene_file_path == MENU_SCENE, "The player lands back on the menu")
	if again != null and again.scene_file_path == MENU_SCENE:
		var status: Label = again.get(&"_status_label")
		_expect(status.visible and status.text == again.connection_error_text("timeout"),
			"The new menu says why (got '%s')" % status.text)
		_expect(String(_network.call(&"take_failure_message")).is_empty(), "The new menu took the message")
		again.queue_free()
	root.child_entered_tree.disconnect(guard)
	_network.call(&"take_pending_lobby")
	await process_frame


func _save_scene(scene_name: String) -> String:
	var node := Node3D.new()
	node.name = scene_name
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	var path: String = DIR + "/" + scene_name.to_lower() + ".tscn"
	ResourceSaver.save(packed, path)
	return path


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
