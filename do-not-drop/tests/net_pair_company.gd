extends SceneTree
## Two-process check of the company world online (D-0214). Run through `tools/run-net-pair.sh
## --company`, which starts both and reads their PAIR lines:
##   Godot --headless --path do-not-drop --script res://tests/net_pair_company.gd -- --host-company --slot=net_pair
##   Godot --headless --path do-not-drop --script res://tests/net_pair_company.gd -- --join=127.0.0.1
##
## Each process opens the real main menu with those command-line flags (main_menu.gd reads them
## itself): the host opens a company room over ENet (--host-company), the client joins it by
## address and the handshake sends it to company_root.tscn, both through the loading screen as a
## player gets there. Each waits for the company world with the same two players in company_crew;
## the client also for its own player (the loader's cover waits for it) and the host's snapshot.
## Then the client leaves the session and quits, and the host waits for its player to be gone from
## its world. Each prints one `PAIR role=<host|client> PASS|FAIL <why>` line; an engine error on the
## way (warnings aside) is a FAIL. The host's world saves in its own folder, never the game's slot.

const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const COMPANY_SCENE: String = "res://scenes/gameplay/company_root.tscn"
const SAVE_DIR: String = "user://net_pair_company"
## The host waits this long for the client to come and go, the client for the host's world.
const TIMEOUT_MSEC: int = 90000

var _host: bool = false
var _catcher := ErrorCatcher.new()


## Errors (not warnings) logged on either side, from any thread (the loader's too).
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)"
			% [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_host = "--host-company" in OS.get_cmdline_user_args()
	OS.add_logger(_catcher)
	root.child_entered_tree.connect(_aim_saves)
	_run.call_deferred()


func _run() -> void:
	# The menu takes the command line's flags itself, as the game does on start.
	change_scene_to_file(MENU_SCENE)
	var world: CompanyRoot = await _wait_for_world()
	if world == null:
		_finish(false, "never reached the company world (current scene %s)" % current_scene)
		return
	var session: NetSession = root.get_node(^"/root/NetworkManager") as NetSession
	if session.session_scene != COMPANY_SCENE:
		_finish(false, "the session plays %s, not the company world" % session.session_scene)
		return
	if _host:
		await _run_host(world)
	else:
		await _run_client(world, session)


func _run_host(world: CompanyRoot) -> void:
	if not await _wait_until(func() -> bool: return _crew(world) == 2):
		_finish(false, "the client's player never came (crew %d)" % _crew(world))
		return
	if not await _wait_until(func() -> bool: return _crew(world) == 1 and world.player != null):
		_finish(false, "the client's player stayed after it left (crew %d)" % _crew(world))
		return
	_finish(true, "crew 2 with the client, back to 1 when it left")


func _run_client(world: CompanyRoot, session: NetSession) -> void:
	var joined: bool = await _wait_until(func() -> bool:
		return (_crew(world) == 2 and world.player != null and world.player.is_multiplayer_authority()
			and not world.net.awaiting_snapshot()))
	if not joined:
		_finish(false, "crew %d, own player %s, waiting for a snapshot %s"
			% [_crew(world), world.player, world.net.awaiting_snapshot()])
		return
	# Read before leaving: the host's spawns go with the session.
	var detail: String = "crew 2, own player %s, snapshot at seq %d" % [world.player.name, world.net.seq]
	session.leave_session()
	for _frame: int in range(10):
		await process_frame
	_finish(true, detail)


## The company world once it is the current scene and the loader is done with it; null on timeout.
func _wait_for_world() -> CompanyRoot:
	var arrived: bool = await _wait_until(func() -> bool:
		return current_scene is CompanyRoot and root.get_node_or_null(^"SceneLoader") == null)
	return current_scene as CompanyRoot if arrived else null


func _crew(world: CompanyRoot) -> int:
	if not is_instance_valid(world):
		return 0
	var count: int = 0
	for node: Node in get_nodes_in_group(CompanyRoot.CREW_GROUP):
		if world.is_ancestor_of(node) and not node.is_queued_for_deletion():
			count += 1
	return count


func _wait_until(done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


## The host's world saves in SAVE_DIR, set as it enters the tree (before its _ready()).
func _aim_saves(node: Node) -> void:
	var world := node as CompanyRoot
	if world != null:
		world.save_dir = SAVE_DIR


func _finish(passed: bool, detail: String) -> void:
	var errors: Array[String] = _catcher.take()
	if passed and not errors.is_empty():
		passed = false
		detail = "engine errors: %s" % "; ".join(errors.slice(0, 3))
	print("PAIR role=%s %s %s" % ["host" if _host else "client", "PASS" if passed else "FAIL", detail])
	OS.remove_logger(_catcher)
	quit(0 if passed else 1)
