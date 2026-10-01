extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_salvage_orphans.gd
##
## Freeing a package must not leave orphan nodes behind (S-908). package_salvage.gd
## builds the repair tape and the replacement hen and attaches them with
## call_deferred; when the package (a level) was freed in the same frame the
## deferred call was dropped and those meshes stayed parentless forever.
## - Freed in the same frame it entered the tree (before the deferred calls run).
## - Freed after the deferred calls ran (tape and hen already children).
## - Several packages freed at once, as when a whole level goes away.
## - None of it logs an engine error (freeing must not touch already freed meshes).

var _failures: int = 0
var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(_catcher)
	await process_frame
	var baseline: int = _orphans()

	# Same frame: the salvage's deferred add_child never gets to run.
	var early: Node = _make_package(&"orphan_early")
	early.free()
	await process_frame
	await process_frame
	_expect_orphans(baseline, "Package freed before the deferred calls leaves no orphans")

	# After the deferred calls: tape and hen are children and go with the package.
	var late: Node = _make_package(&"orphan_late")
	await process_frame
	await process_frame
	_expect(late.get_node_or_null(^"RepairTape") != null and late.get_node_or_null(^"ReplacementHen") != null,
			"Tape and hen end up as children of the package once the deferred calls run")
	late.free()
	await process_frame
	_expect_orphans(baseline, "Package freed after the deferred calls leaves no orphans")

	# Many at once, all freed in the frame they were created.
	var batch: Array[Node] = []
	for index: int in 10:
		batch.append(_make_package(StringName("orphan_batch_%d" % index)))
	for package: Node in batch:
		package.free()
	await process_frame
	await process_frame
	_expect_orphans(baseline, "Ten packages freed in their first frame leave no orphans")

	var errors: Array[String] = _catcher.take()
	_expect(errors.is_empty(), "Freeing packages logs no engine errors: %s" % [errors])
	OS.remove_logger(_catcher)

	if _failures == 0:
		print("PASS: freeing a package, early or late, leaves no salvage orphans")
	quit(_failures)


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _expect_orphans(baseline: int, description: String) -> void:
	var now: int = _orphans()
	_expect(now == baseline, "%s (got %d, expected %d)" % [description, now, baseline])


func _make_package(id: StringName) -> Node:
	var package: Node = load("res://scenes/gameplay/package/package.tscn").instantiate()
	package.set(&"trap_definition", load("res://data/traps/fragile.tres"))
	package.set(&"package_id", id)
	root.add_child(package)
	return package


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out
