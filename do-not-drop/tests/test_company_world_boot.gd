extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_world_boot.gd
##
## The company world as the command line boots it (D-0214; main_menu.gd, company_root.gd,
## docs/decisiones/2026-10-04-flag-modo-empresa.md):
## - the menu takes --autostart-company with --slot=<n> (_handle_cmdline_args(), what it runs on the
##   command line's own arguments): the loading screen swaps company_root.tscn in as the current
##   scene, CompanyState.is_active() is true, its DayCycle is in OPENING of the company's day, the
##   world plays slot <n> (CompanyRoot.launch_slot, taken once), it has its World/PlayerSpawner and
##   its player is one of the crew at SPAWN; no ERROR is logged on the way (a Logger counts them,
##   as N-917's test does); leaving saves the day as interrupted in slot <n> of the test's own
##   folder (save_dir, set as the root enters the tree), and the game's own slot is never touched;
## - --mode=company, the older alias, takes the same way in (the loader heads for the company world
##   and is cancelled there), with no slot;
## - the company world is one of NetworkManager.LEVEL_SCENES, so a host in it sends joiners to it.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
## The autoload's script, for its constants (this compiles before the autoloads exist).
const NETWORK_MANAGER := preload("res://scripts/core/network_manager.gd")
## The world saves here, never in the game's slot.
const DIR: String = "user://test_company_world_boot"
const SLOT: String = "boot_test"
const LOAD_TIMEOUT_MSEC: int = 60000

var _failures: int = 0
var _catcher := ErrorCatcher.new()


## Errors (not warnings) logged while the world boots, from any thread (the loader's too).
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
	_run.call_deferred()


func _run() -> void:
	_clean()
	var real_slot: String = _real_slot()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	CompanyRoot.launch_slot = ""
	root.child_entered_tree.connect(_aim_saves)
	OS.add_logger(_catcher)
	_catcher.take()

	await _check_autostart(state)
	await _check_alias()
	_expect(NETWORK_MANAGER.LEVEL_SCENES.has(SCENE),
		"The company world is one of NetworkManager.LEVEL_SCENES (got %s)" % [NETWORK_MANAGER.LEVEL_SCENES])

	var errors: Array[String] = _catcher.take()
	OS.remove_logger(_catcher)
	_expect(errors.is_empty(), "No ERROR is logged while the company world boots (got %s)" % [errors])
	root.child_entered_tree.disconnect(_aim_saves)
	state.call(&"reset")
	_expect(_real_slot() == real_slot, "The game's own company slot is never touched")
	_clean()
	if _failures == 0:
		print("PASS: --autostart-company (and --mode=company) boot the company world through the loader:"
			+ " company on, day OPENING, slot from --slot, crew of one, no ERROR")
	quit(_failures)


## --autostart-company --slot=<SLOT>: through the loading screen into the company world.
func _check_autostart(state: Node) -> void:
	var menu: Control = _new_menu()
	await process_frame
	menu.call(&"_handle_cmdline_args", PackedStringArray(["--autostart-company", "--slot=" + SLOT]))
	var loader: LoadingScreen = menu.get(&"_loading")
	_expect(loader != null and loader.target_path == SCENE,
		"--autostart-company sends the loader to the company world (got %s)"
		% [loader.target_path if loader != null else "no loader"])
	_expect(CompanyRoot.launch_slot == SLOT, "--slot=%s is handed to the next company world (got '%s')"
		% [SLOT, CompanyRoot.launch_slot])
	var level: CompanyRoot = await _wait_for_level(loader)
	_expect(level != null, "The loader swaps the company world in as the current scene (got %s)" % current_scene)
	if level == null:
		return
	# The day opens deferred, once the world is up (CompanyRoot._open_company_day()).
	await process_frame
	await physics_frame
	_expect(bool(state.call(&"is_active")), "CompanyState.is_active() is true in the booted world")
	var cycle: DayCycle = level.day_cycle
	_expect(cycle != null and cycle.phase() == DayCycle.Phase.OPENING
		and cycle.current_day() == int(state.get(&"day")),
		"Its DayCycle is in OPENING of the company's day %s (got %s)"
		% [state.get(&"day"), cycle.phase_name() if cycle != null else "no DayCycle"])
	_expect(level.save_slot == SLOT and CompanyRoot.launch_slot.is_empty(),
		"The world plays slot %s and the launch slot is taken once (save_slot '%s', left '%s')"
		% [SLOT, level.save_slot, CompanyRoot.launch_slot])
	_expect(level.get_node_or_null(^"World/PlayerSpawner") is MultiplayerSpawner,
		"The world has its World/PlayerSpawner, where the loader waits for a client's own player")
	var crew: Array[Node] = get_nodes_in_group(CompanyRoot.CREW_GROUP)
	var player: Node3D = level.player
	_expect(crew.size() == 1 and player != null and crew[0] == player
		and absf(player.global_position.x - CompanyRoot.SPAWN.x) < 0.05
		and absf(player.global_position.z - CompanyRoot.SPAWN.z) < 0.05,
		"Solo, the crew is its own player at SPAWN (crew %d, at %s)"
		% [crew.size(), player.global_position if player != null else Vector3.INF])
	level.queue_free()
	current_scene = null
	await process_frame
	_expect(CompanySave.was_interrupted(SLOT, DIR),
		"Leaving saves the day as interrupted in slot %s of the test's folder" % SLOT)


## --mode=company, the older alias: the same way in, no slot.
func _check_alias() -> void:
	var menu: Control = _new_menu()
	await process_frame
	menu.call(&"_handle_cmdline_args", PackedStringArray(["--mode=company"]))
	var loader: LoadingScreen = menu.get(&"_loading")
	_expect(loader != null and loader.target_path == SCENE,
		"--mode=company sends the loader to the company world too (got %s)"
		% [loader.target_path if loader != null else "no loader"])
	_expect(CompanyRoot.launch_slot.is_empty(), "...with no slot of its own (got '%s')" % CompanyRoot.launch_slot)
	_expect(bool(menu.call(&"_cancel_loading")), "...and that loader can still be cancelled")
	menu.queue_free()
	current_scene = null
	await process_frame


func _new_menu() -> Control:
	var menu: Control = (load(MENU_SCENE) as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	return menu


## The company world the loader brought in, once the loader is done with it; null if it never came.
func _wait_for_level(loader: LoadingScreen) -> CompanyRoot:
	var deadline: int = Time.get_ticks_msec() + LOAD_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if current_scene is CompanyRoot and not is_instance_valid(loader):
			return current_scene as CompanyRoot
		await process_frame
	return current_scene as CompanyRoot


## Points the company world at the test's folder as it enters the tree, before its _ready().
func _aim_saves(node: Node) -> void:
	var level := node as CompanyRoot
	if level != null:
		level.save_dir = DIR


## What the game's slot holds now, its file, .bak and .tmp ("" for each one missing).
static func _real_slot() -> String:
	var path: String = CompanySave.path_for()
	var parts: PackedStringArray = []
	for file: String in [path, path + ".bak", path + ".tmp"]:
		parts.append(FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else "")
	return "|".join(parts)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
