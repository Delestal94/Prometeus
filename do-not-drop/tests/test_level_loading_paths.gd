extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_level_loading_paths.gd
##
## The level side of the loading screen (N-408), on the real level_base.tscn:
## - restart_delivery() (level_common.gd), host offline: reloads through a
##   LoadingScreen (a SceneLoader under the root with the "restart" tape), not
##   a bare reload that froze the window; the old level goes, the new route
##   builds itself and the run is reset. Protects against going back to a frozen
##   window on every "play again".
## - The crew grew before the run (level_base.gd _crew_outgrew_route()): true only
##   for the host, with the run not started and more crew than houses; the
##   notice HUD_NOTICE_CREW_GREW says how many houses; the restart that follows
##   after CREW_RESTART_DELAY is skipped if the crew shrank again and goes through
##   the loader (with a bigger route) if it didn't. The decision is tested on the
##   roster (NetworkManager.peer_ids) with no sockets.
## - HUD (hud.gd _on_started): a late joiner looking at the start card gets the
##   mouse back when the run starts (it stayed free and the player couldn't look
##   or move). Needs a display to capture the mouse: headless only checks that
##   the card closes and the overlay mode becomes "run".

const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
const TIMEOUT_MSEC: int = 100_000

var _failures: int = 0
var _network: Node
var _run_manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_network = root.get_node(^"/root/NetworkManager")
	_run_manager = root.get_node(^"/root/RunManager")
	# Every loader that appears skips the model prefetch: loading every .glb on
	# threads crashes the headless dummy renderer.
	root.child_entered_tree.connect(func(node: Node) -> void:
		if node is LoadingScreen:
			(node as LoadingScreen).prefetch_paths = PackedStringArray())
	var level: Node = await _load_level()
	_check_hud_late_joiner(level)
	_check_crew_decision(level)
	await _check_restart(level)
	level = current_scene
	await _check_crew_notice_and_restart(level)
	if _failures == 0:
		print("PASS: restart goes through the loader, crew-grew decision and notice, late joiner recaptures the mouse")
	quit(_failures)


func _load_level() -> Node:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await process_frame
	return level


func _check_hud_late_joiner(level: Node) -> void:
	var hud: Node = level.get_node(^"HUD")
	_expect(String(hud.get("overlay_mode")) == "start",
		"A fresh level shows the start card (got %s)" % hud.get("overlay_mode"))
	var overlay: Control = hud.get("overlay")
	_expect(overlay.visible, "The start card is on screen")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.call(&"_on_started", &"test_route", [1])
	_expect(not overlay.visible and String(hud.get("overlay_mode")) == "run",
		"The run starting closes the start card (mode %s)" % hud.get("overlay_mode"))
	# Only a real window captures the mouse; the dummy display keeps whatever it was.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var can_capture: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not can_capture:
		print("  (this display cannot capture the mouse: recapture check skipped)")
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set(&"overlay_mode", "start")
	overlay.show()
	hud.call(&"_on_started", &"test_route", [1])
	_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"The run starting under the start card gives the mouse back to the game (got %s)" % Input.mouse_mode)
	# A pause is not a reason to take the cursor away.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set(&"overlay_mode", "start")
	overlay.show()
	paused = true
	hud.call(&"_on_started", &"test_route", [1])
	paused = false
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"A paused tree keeps the cursor free (got %s)" % Input.mouse_mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _check_crew_decision(level: Node) -> void:
	_set_crew([1])
	_expect(not bool(level.call(&"_crew_outgrew_route")), "A solo crew doesn't outgrow the route")
	_set_crew([1, 22, 33, 44])
	var houses: int = int(level.call(&"_wanted_houses"))
	var route: Node = level.get_node(^"World/Route")
	_expect(houses > int(route.get("house_count")),
		"Four players want more houses (%d) than the solo route has (%s)" % [houses, route.get("house_count")])
	_expect(bool(level.call(&"_crew_outgrew_route")), "A fourth player before the run outgrows the route")
	_run_manager.set(&"is_running", true)
	_expect(not bool(level.call(&"_crew_outgrew_route")), "Once the run started the route is left alone")
	_run_manager.set(&"is_running", false)
	_run_manager.set(&"results", {"stub": 1})
	_expect(not bool(level.call(&"_crew_outgrew_route")), "After the results the route is left alone too")
	_run_manager.call(&"reset_run")
	_expect(bool(level.call(&"_crew_outgrew_route")), "Back to preparation it outgrows the route again")
	_set_crew([1])


## restart_delivery(): fade, then the level is reloaded behind the loading screen.
func _check_restart(level: Node) -> void:
	var level_id: int = level.get_instance_id()
	level.call(&"restart_delivery")
	var loader: LoadingScreen = await _wait_for_loader()
	_expect(loader != null, "restart_delivery() puts a loading screen over the old level")
	if loader == null:
		return
	_expect(loader.target_path == LEVEL, "The restart loads the same level (got %s)" % loader.target_path)
	_expect(loader.mode_text == tr("UI_LOADING_TAG_RESTART"), "The loading screen's tape says it's a restart")
	_expect(not _run_manager.is_running, "The run is reset for the restart")
	var start: int = Time.get_ticks_msec()
	while is_instance_valid(loader) and Time.get_ticks_msec() - start < TIMEOUT_MSEC:
		await process_frame
	_expect(not is_instance_valid(loader), "The loader frees itself after the restart")
	var fresh: Node = current_scene
	_expect(fresh != null and fresh.get_instance_id() != level_id and fresh.scene_file_path == LEVEL,
		"A new copy of the level replaced the old one")
	_expect(not is_instance_valid(instance_from_id(level_id)), "The old level is gone")
	if fresh != null:
		var route: Node = fresh.get_node_or_null(^"World/Route")
		_expect(route != null and bool(route.get("is_built")), "The rebuilt route is complete when the cover lifts")
		_expect(fresh.get_node_or_null(^"World/Player_1") != null, "The player is in the restarted level")
	_expect(not _run_manager.is_running and _run_manager.results.is_empty(), "Nothing is running after the restart")


func _check_crew_notice_and_restart(level: Node) -> void:
	var notices: Array[String] = []
	var catch: Callable = func(text: String) -> void: notices.append(text)
	var bus: Node = root.get_node(^"/root/EventBus")
	bus.connect(&"depot_notice", catch)
	var route: Node = level.get_node(^"World/Route")
	var before: int = int(route.get("house_count"))

	# The crew shrinks again before the delay is over: no restart.
	_set_crew([1, 22, 33, 44])
	level.call(&"_on_peer_level_ready", 44)
	var wanted: int = int(level.call(&"_wanted_houses"))
	_expect(notices.has(tr("HUD_NOTICE_CREW_GREW") % wanted),
		"Someone joining before the run announces the bigger route (got %s)" % [notices])
	_expect(bool(level.get(&"_crew_restart_pending")),
		"The restart waits a moment, so friends joining together cost one reload")
	_set_crew([1])
	await create_timer(float(level.CREW_RESTART_DELAY) + 0.4).timeout
	_expect(not bool(level.get(&"_crew_restart_pending")), "The wait is over")
	_expect(_find_loader() == null and current_scene == level, "A crew that shrank back doesn't restart the level")

	# The crew stays: the level reloads behind the loader, with the bigger route.
	_set_crew([1, 22, 33, 44])
	level.call(&"_on_peer_level_ready", 44)
	var loader: LoadingScreen = await _wait_for_loader(float(level.CREW_RESTART_DELAY) + 3.0)
	_expect(loader != null, "A crew that stays gets the level rebuilt behind the loading screen")
	if loader != null:
		var start: int = Time.get_ticks_msec()
		while is_instance_valid(loader) and Time.get_ticks_msec() - start < TIMEOUT_MSEC:
			await process_frame
		var fresh: Node = current_scene
		var rebuilt: Node = fresh.get_node_or_null(^"World/Route") if fresh != null else null
		_expect(rebuilt != null and int(rebuilt.get("house_count")) == wanted and wanted > before,
			"The rebuilt route has a house per passenger (wanted %d, was %d, got %s)"
			% [wanted, before, rebuilt.get("house_count") if rebuilt != null else "no route"])
	bus.disconnect(&"depot_notice", catch)
	_set_crew([1])
	_run_manager.call(&"reset_run")


## peer_ids is a typed Array[int]: set() refuses a plain Array.
func _set_crew(ids: Array[int]) -> void:
	_network.set(&"peer_ids", ids)


func _find_loader() -> LoadingScreen:
	for child: Node in root.get_children():
		if child is LoadingScreen and not child.is_queued_for_deletion():
			return child as LoadingScreen
	return null


func _wait_for_loader(seconds: float = 5.0) -> LoadingScreen:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		var found: LoadingScreen = _find_loader()
		if found != null:
			return found
		await process_frame
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
