extends SceneTree
## Run (from tools/export/smoke-company.sh, D-2019):
##   <editor> --headless --main-pack <build>/TakeMyPackage.pck --script <abs>/probe_company.gd -- --autostart-company
##
## Looks inside an exported build's .pck: a release template ignores --script, so the same engine version's
## editor binary mounts the pack. It proves what a quiet log cannot: the menu takes --autostart-company as the exe
## does, the company world really comes up (crew, shed, day open) and the registries that use DirAccess are
## full. A listing is what breaks in an export (x.tres.remap instead of x.tres), and an empty one only shows
## as a shed with nothing to buy. Prints "COMPANY_PROBE OK" and exits 0, or names what failed and exits 1.
## The editor binary has no GodotSteam library for the pack: that one error happens before this runs, and the
## exe's own boot is what covers the extension.

const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const WORLD_CLASS: StringName = &"CompanyRoot"
const LOAD_TIMEOUT_MSEC: int = 90000
const SETTLE_FRAMES: int = 120
## Under this many, a registry lost files on the way to the build (a folder in the source has at least these).
const MIN_ZONES: int = 9
## Left out by the presets: seen here, the exclude_filter stopped working. A script in a pack is x.gdc plus
## x.gd.remap, so FileAccess.file_exists() says false for every script: only ResourceLoader can tell.
const MUST_NOT_SHIP: String = "res://tests/test_release_build.gd"
## The control of that look: a script that does ship has to be seen by it.
const MUST_SHIP: String = "res://scripts/core/company/company_save.gd"

var _failures: int = 0
var _catcher := ErrorCatcher.new()


## Errors (not warnings) logged from the moment the probe starts, from any thread (the loader's too).
class ErrorCatcher extends Logger:
	var messages: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		messages.append("%s:%d %s %s" % [file, line, code, rationale])
		_mutex.unlock()


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	_expect(ResourceLoader.exists(MUST_SHIP), "A compiled script of the pack can be seen (%s)" % MUST_SHIP)
	_expect(not ResourceLoader.exists(MUST_NOT_SHIP), "tests/ is left out of the pack (%s)" % MUST_NOT_SHIP)
	_expect(change_scene_to_file(MENU_SCENE) == OK, "The menu loads from the pack")
	var level: Node = await _wait_for_world()
	_expect(level != null, "--autostart-company reaches the company world (at %s)" % current_scene)
	if level != null:
		for _frame: int in SETTLE_FRAMES:
			await physics_frame
		_check_world(level)
	_check_registries()
	_expect(tr("UI_MENU_COMPANY") != "UI_MENU_COMPANY", "The translations are in the pack")
	OS.remove_logger(_catcher)
	_expect(_catcher.messages.is_empty(), "No ERROR is logged on the way (got %s)" % [_catcher.messages])
	if _failures == 0:
		print("COMPANY_PROBE OK")
	quit(1 if _failures > 0 else 0)


func _wait_for_world() -> Node:
	var deadline: int = Time.get_ticks_msec() + LOAD_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var scene: Node = current_scene
		if scene != null and scene.get_script() != null and scene.get_script().get_global_name() == WORLD_CLASS:
			return scene
		await process_frame
	return null


func _check_world(level: Node) -> void:
	_expect(bool(root.get_node(^"/root/CompanyState").call(&"is_active")), "The company is switched on")
	_expect(level.get(&"zones").size() >= MIN_ZONES, "The world has its zones (%d)" % level.get(&"zones").size())
	_expect(level.get(&"player") != null, "The local player stands in the world")
	var shed: Node = level.get(&"shed")
	_expect(shed != null and shed.get_child_count() > 0, "The shed is furnished")
	_expect(level.get(&"day_cycle") != null, "The day's cycle is up")


## The registries that use DirAccess on res://data: a name lost to the export comes back empty, not as an error.
func _check_registries() -> void:
	var catalog: RefCounted = _global(&"CompanyCatalog").call(&"load_all")
	_expect(catalog.get(&"errors").is_empty(), "The catalog reads clean (got %s)" % [catalog.get(&"errors")])
	for kind: StringName in _global(&"CompanyCatalog").get(&"KINDS"):
		_expect(not catalog.call(&"all", kind).is_empty(), "The catalog has %s" % kind)
	_expect(not _global(&"CompanyShop").call(&"items").is_empty(), "The company shop has items")
	_expect(not _global(&"EmployeeLevels").call(&"levels").is_empty(), "There are employee levels")
	_expect(not _global(&"OrderTemplateCheck").call(&"load_sets").is_empty(), "There are order templates")
	_expect(not _global(&"BuildCursor").call(&"all_definitions").is_empty(), "There are placeable objects")


## This file is compiled against whatever pack is mounted: the game's classes by name, not as types.
func _global(class_id: StringName) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == class_id:
			return load(entry["path"]) as Script
	_expect(false, "The class %s is in the pack" % class_id)
	return GDScript.new()


func _expect(condition: bool, description: String) -> void:
	if not condition:
		printerr("COMPANY_PROBE FAIL: ", description)
		_failures += 1
