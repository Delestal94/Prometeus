extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_menu_to_level.gd
##
## The whole trip "¡JUGAR!" -> LoadingScreen -> the REAL level (N-407/N-408), not a
## tiny stand-in scene (test_loading_screen.gd does that one). Protects against:
## the cover lifting while the road still builds over frames (the player saw an
## empty world or fell through it), the local player not being in when it lifts,
## the depot/route drawn all in one frame because nobody hid them, and the menu
## theme dying at the swap instead of playing on under the loader.
## - Solo (main_menu.gd _play_solo -> level_base.tscn): at the swap the cover is
##   fully up (alpha 1) and the depot and route are hidden while route.is_built is
##   false; the loader never leaves BUILDING before the route is built (the
##   BUSY_GROUP gate of scene_loader.gd); when it settles the route is built,
##   Player_1 exists with authority, depot and route are visible; MenuMusic was
##   reparented under the loader (alive at the swap), and both are gone at the end;
##   the run is not running and the HUD shows the "start" card.
## - Endless (_play_endless -> level_endless.tscn): same, smaller (player, depot
##   visible, music carried, start card).

const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
const ENDLESS: String = "res://scenes/gameplay/level_endless.tscn"
const TIMEOUT_MSEC: int = 100_000

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _trip("_play_solo", LEVEL, true)
	await _trip("_play_endless", ENDLESS, false)
	if _failures == 0:
		print("PASS: menu -> loader -> real level: cover up while building, player in, music carried, loader gone")
	quit(_failures)


func _trip(method: String, path: String, has_route: bool) -> void:
	var tag: String = method
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	# A Steam lobby callback must not send this menu somewhere on its own.
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.disconnect(&"session_ready", Callable(menu, "_on_session_ready"))
	await process_frame
	var music: AudioStreamPlayer = menu.get_node_or_null(^"MenuMusic") as AudioStreamPlayer
	_expect(music != null, "%s: the menu has its music" % tag)

	menu.call(method)
	var loader: LoadingScreen = menu.get("_loading")
	_expect(loader != null and loader.target_path == path, "%s: the loader targets %s" % [tag, path])
	if loader == null:
		menu.queue_free()
		return
	# The loader enters the tree deferred, so this still takes effect. Prefetching
	# every .glb on threads crashes the headless dummy renderer (exit 139 on
	# Windows), so the test skips the prefetch and checks everything else.
	loader.prefetch_paths = PackedStringArray()
	var seen: Dictionary = {"swap": false, "unbuilt_frames": 0, "premature": false, "music_carried": false}
	var at_settling: Dictionary = {}
	var at_done: Dictionary = {}
	loader.stage_changed.connect(func(stage: SceneLoader.Stage) -> void:
		if stage == SceneLoader.Stage.SETTLING:
			at_settling.merge(_snapshot(has_route), true)
		elif stage == SceneLoader.Stage.DONE:
			at_done.merge(_snapshot(has_route), true))

	var start: int = Time.get_ticks_msec()
	while is_instance_valid(loader) and Time.get_ticks_msec() - start < TIMEOUT_MSEC:
		await process_frame
		var level: Node = current_scene
		if level == null or level == menu or not is_instance_valid(level) or level.scene_file_path != path:
			continue
		if not seen["swap"]:
			seen["swap"] = true
			_expect(is_instance_valid(music) and music.get_parent() == loader,
				"%s: the menu music was carried under the loader at the swap, not freed" % tag)
			seen["music_carried"] = is_instance_valid(music) and music.get_parent() == loader
		var route: Node = level.get_node_or_null(^"World/Route")
		if has_route and route != null and not bool(route.get("is_built")):
			seen["unbuilt_frames"] = int(seen["unbuilt_frames"]) + 1
			var cover: Control = loader.get("_cover")
			_expect(cover.modulate.a >= 0.999, "%s: cover fully up while the route builds (got alpha %s)"
				% [tag, cover.modulate.a])
			_expect(not (route as Node3D).visible, "%s: route hidden while it builds" % tag)
			if loader.stage != SceneLoader.Stage.BUILDING:
				seen["premature"] = true
	_expect(not is_instance_valid(loader), "%s: the loader frees itself (stage %s)" % [tag, "n/a"])
	_expect(bool(seen["swap"]), "%s: the level replaced the menu" % tag)
	if has_route:
		_expect(int(seen["unbuilt_frames"]) > 0,
			"%s: the swap happens before the route is built (build is spread over frames)" % tag)
		_expect(not bool(seen["premature"]), "%s: the loader stays in BUILDING until route.is_built" % tag)
		_expect(bool(at_settling.get("route_built", false)), "%s: route is built when the loader starts settling" % tag)
	for label: String in ["settling", "done"]:
		var snap: Dictionary = at_settling if label == "settling" else at_done
		_expect(bool(snap.get("player", false)), "%s: Player_1 exists when %s starts" % [tag, label])
		_expect(bool(snap.get("authority", false)), "%s: Player_1 is the local authority at %s" % [tag, label])
	_expect(bool(at_done.get("depot_visible", false)), "%s: depot visible after the reveal" % tag)
	if has_route:
		_expect(bool(at_done.get("route_visible", false)), "%s: route visible after the reveal" % tag)
	_expect(not bool(at_done.get("running", true)), "%s: nothing is running behind the loader" % tag)
	_expect(String(at_done.get("overlay", "")) == "start", "%s: the HUD shows the start card (got %s)"
		% [tag, at_done.get("overlay", "")])
	_expect(not is_instance_valid(music), "%s: the carried music is gone once the loader is" % tag)

	var level_node: Node = current_scene
	if level_node != null and level_node != menu and is_instance_valid(level_node):
		level_node.queue_free()
	if is_instance_valid(menu):
		menu.queue_free()
	root.get_node(^"/root/RunManager").call(&"reset_run")
	await process_frame
	await process_frame


## What the new scene looks like right now.
func _snapshot(has_route: bool) -> Dictionary:
	var level: Node = current_scene
	var snap: Dictionary = {}
	if level == null:
		return snap
	var player: Node = level.get_node_or_null(^"World/Player_1")
	snap["player"] = player != null
	snap["authority"] = player != null and player.is_multiplayer_authority()
	var depot: Node = level.get_node_or_null(^"World/Depot")
	snap["depot_visible"] = depot is Node3D and (depot as Node3D).visible
	var route: Node = level.get_node_or_null(^"World/Route")
	if has_route:
		snap["route_built"] = route != null and bool(route.get("is_built"))
		snap["route_visible"] = route is Node3D and (route as Node3D).visible
	snap["running"] = bool(root.get_node(^"/root/RunManager").get("is_running"))
	var hud: Node = level.get_node_or_null(^"HUD")
	snap["overlay"] = String(hud.get("overlay_mode")) if hud != null else ""
	return snap


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
