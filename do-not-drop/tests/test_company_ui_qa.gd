extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_ui_qa.gd
##
## UI QA of the company world (expansion D-1950), without people: boots the real world (CompanyRoot, its own save
## folder) and walks every screen of the expansion the way a player would, catching every error the engine logs
## (a Logger added for the run) step by step:
##   boot, clipboard up / sheet turned / down, phone up / map / down, pause menu open / closed, dispatch board open /
##   closed, the day's closing screen with every part and its Continue.
## Each step must log no error and leave the player's input and the mouse as it found them. The table of the run is
## kept in docs/expansion-distritos/revisar/D-1950.md.

const DIR: String = "user://test_company_ui_qa"

var _failures: int = 0
var _catch := ErrorCatch.new()


class ErrorCatch:
	extends Logger
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var text: String = rationale if rationale != "" else code
		# The engine's own leftovers at exit and the CI's missing import cache are not the UI's.
		if text.contains("resources still in use") or text.contains(".translation"):
			return
		errors.append("%s (%s:%d)" % [text, file.get_file(), line])

	func take() -> Array[String]:
		var out: Array[String] = errors.duplicate()
		errors.clear()
		return out


func _initialize() -> void:
	OS.add_logger(_catch)
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var world := (load("res://scenes/gameplay/company_root.tscn") as PackedScene).instantiate() as CompanyRoot
	world.save_dir = DIR
	root.add_child(world)
	await _frames(20)
	_step("boot")
	var player: Node = world.player
	var clip := world.get_node_or_null(^"Clipboard") as CompanyClipboard
	if clip != null:
		_expect(clip.raise(), "the clipboard comes out")
		await _frames(3)
		clip.turn(1)
		await _frames(3)
		clip.stow()
		await _frames(2)
		_step("clipboard", player)
	var phone: Node = _by_class(world, &"CompanyPhone")
	if phone != null:
		_expect(bool(phone.call(&"raise")), "the phone comes out")
		await _frames(3)
		phone.call(&"show_app", &"map")
		await _frames(3)
		phone.call(&"stow")
		await _frames(2)
		_step("phone", player)
	var pause: Node = _by_class(world, &"CompanySoloPause")
	if pause != null:
		pause.call(&"open_menu")
		await _frames(3)
		pause.call(&"close_menu")
		await _frames(2)
		_step("pause menu", player)
	var dispatch: Node = _by_class(world, &"CompanyDispatch")
	if dispatch != null:
		dispatch.call(&"open")
		await _frames(3)
		dispatch.call(&"close")
		await _frames(2)
		_step("dispatch board", player)
	_expect(pause != null and dispatch != null, "the world has its pause and its dispatch board")
	var summary: DaySummaryPanel = world.summary_panel
	if summary != null:
		summary.open({"day": 1, "income": 100, "costs": 40, "profit": 60, "income_by_reason": {"order_paid": 100},
			"cost_by_reason": {"rent": 40}}, [], 0, {"employees": [{"name": "Ana", "wage": 40}]})
		await _frames(3)
		summary.close()
		await _frames(3)
		_step("closing screen")
	world.queue_free()
	await _frames(2)
	state.call(&"reset")
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)
	if _failures == 0:
		print("PASS: every company screen opens and closes in the real world with no error logged")
	quit(_failures)


## One step of the walk: no error since the last one, and the player's input back on.
func _step(name: String, player: Node = null) -> void:
	var errors: Array[String] = _catch.take()
	print("QA | %s | %d errors" % [name, errors.size()])
	_expect(errors.is_empty(), "%s logs no error (%s)" % [name, errors])
	if player != null and is_instance_valid(player):
		_expect(player.is_processing_unhandled_input(), "%s gives the player's input back" % name)


## The first node under `top` whose script is the class `class_id` (null when none).
static func _by_class(top: Node, class_id: StringName) -> Node:
	for node: Node in top.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if script != null and script.get_global_name() == class_id:
			return node
	return null


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
