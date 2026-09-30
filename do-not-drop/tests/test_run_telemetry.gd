extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_run_telemetry.gd
##
## The local run log (S-805, run_telemetry.gd + run_telemetry_format.gd):
## - With "Guardar registro de partidas" off (the default) a finished run
##   writes nothing at all.
## - With it on, a simulated run (real RunManager, real EventBus signals)
##   leaves one valid JSON under user://test_telemetry with duration, the
##   traps on the order, seconds at risk per box, what ruined each box, the
##   route event and the score.
## - The file name is date and time with no character Windows rejects, a
##   second run in the same second does not overwrite the first, and a full
##   folder drops its oldest files.
## - The option is persisted and reset by GameSettings.

var _failures: int = 0
var _dir: String = ""
var _event_name: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var telemetry: Node = root.get_node(^"/root/RunTelemetry")
	var settings: Node = root.get_node(^"/root/GameSettings")
	_dir = String(telemetry.get(&"directory"))
	_expect(_dir == "user://test_telemetry", "Under a test script the log goes to a throwaway folder (got %s)" % _dir)
	_clear()

	# --- defaults and persistence ---
	_expect(not bool(settings.get(&"save_run_log")), "The run log is off by default")
	settings.set(&"save_run_log", true)
	var config := ConfigFile.new()
	config.load(String(settings.get(&"save_path")))
	_expect(bool(config.get_value("player", "save_run_log", false)), "Turning the run log on is saved")
	settings.call(&"reset_to_defaults")
	_expect(not bool(settings.get(&"save_run_log")), "Reset to defaults turns the run log off again")

	# --- format helpers ---
	var format: GDScript = load("res://scripts/core/run_telemetry_format.gd")
	_expect(format.call(&"trap_id", "HUD_TRAP_GROWING_WEIGHT") == "growing_weight", "A trap name key becomes its id")
	var moment := {"year": 2026, "month": 9, "day": 30, "hour": 7, "minute": 5, "second": 3}
	var stem: String = format.call(&"file_stem", moment)
	_expect(stem == "2026-09-30_07-05-03", "File name stem is date_time (got %s)" % stem)
	for bad: String in [":", "/", "\\", "*", "?", "\"", "<", ">", "|"]:
		_expect(not stem.contains(bad), "The file name has no '%s', which Windows rejects" % bad)

	# --- off: a whole run leaves nothing behind ---
	settings.set(&"save_run_log", false)
	_simulate_run()
	_expect(_files().is_empty(), "With the option off, a finished run writes no file (got %s)" % [_files()])

	# --- on: one file, with the fields ---
	settings.set(&"save_run_log", true)
	_simulate_run()
	var files: Array = _files()
	_expect(files.size() == 1, "With the option on, a finished run writes one file (got %d)" % files.size())
	if files.size() == 1:
		_check_record(_read(files[0]))
		_expect(String(files[0]).ends_with(".json") and String(files[0]).begins_with("20"),
				"The file is <date>.json (got %s)" % files[0])

	# --- a second run right away does not overwrite the first ---
	_simulate_run()
	_expect(_files().size() == 2, "Two runs in the same second leave two files (got %d)" % _files().size())

	# --- an old folder is pruned, oldest first ---
	_clear()
	var limit: int = int(telemetry.get(&"MAX_FILES"))
	for index: int in limit + 2:
		var handle := FileAccess.open("%s/2000-01-01_00-00-%03d.json" % [_dir, index], FileAccess.WRITE)
		handle.store_string("{}")
		handle.close()
	telemetry.call(&"save_record", {"format": 1})
	var kept: Array = _files()
	_expect(kept.size() == limit, "The folder is trimmed to %d files (got %d)" % [limit, kept.size()])
	_expect(not kept.has("2000-01-01_00-00-000.json"), "The oldest file is the one removed")

	settings.set(&"save_run_log", false)
	_clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
	if _failures == 0:
		print("PASS: run log is off by default, writes one valid JSON per run when on, and prunes itself")
	quit(_failures)


## A delivery with two boxes: a fragile one that goes at risk for 12.5 s and
## survives, and a noisy one that goes at risk and is ruined; one route event.
func _simulate_run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	root.get_node(^"/root/CrewProgression").call(&"reset_campaign")
	root.get_node(^"/root/UnlockManager").call(&"reset_profile")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 2)
	bus.emit_signal(&"houses_assigned", [[&"box_a", "HUD_TRAP_FRAGILE", "A1"], [&"box_b", "HUD_TRAP_NOISY", "B2"]])
	bus.emit_signal(&"cargo_registered", &"box_a", "HUD_TRAP_FRAGILE")
	bus.emit_signal(&"cargo_registered", &"box_b", "HUD_TRAP_NOISY")
	manager.call(&"start_run")
	manager.set(&"elapsed_seconds", 10.0)
	bus.emit_signal(&"package_state_changed", &"box_a", 1)
	manager.set(&"elapsed_seconds", 22.5)
	bus.emit_signal(&"package_state_changed", &"box_a", 0)
	manager.set(&"elapsed_seconds", 30.0)
	bus.emit_signal(&"package_state_changed", &"box_b", 1)
	bus.emit_signal(&"package_damaged", &"box_b", 40.0)
	manager.set(&"elapsed_seconds", 34.0)
	bus.emit_signal(&"package_state_changed", &"box_b", 2)
	bus.emit_signal(&"package_ruined", &"box_b", "Se cayó de la caja")
	bus.emit_signal(&"vehicle_impact", 6.5, Vector3.ZERO)
	# start_run() drew a route event at random (whichever is playable with no
	# cargo in the scene); if none was, start one by hand.
	var event_id: StringName = root.get_node(^"/root/RouteEventManager").get(&"active_event_id")
	if event_id.is_empty():
		event_id = &"inspection"
		bus.emit_signal(&"route_event_started", event_id, {})
		manager.set(&"_event_id", event_id)
	_event_name = String(event_id)
	manager.set(&"elapsed_seconds", 40.0)
	bus.emit_signal(&"route_event_resolved", event_id, true, 1)
	manager.call(&"register_delivery", 0, &"delivered_ok", &"box_a")
	manager.set(&"elapsed_seconds", 50.0)
	manager.call(&"finish_run", true)


func _check_record(record: Dictionary) -> void:
	_expect(not record.is_empty(), "The file parses as a JSON object")
	for key: String in ["format", "saved_at", "role", "crew_size", "mode", "duration_seconds", "delivered", "score",
			"orders", "boxes", "route_event", "route_events", "deliveries", "totals"]:
		_expect(record.has(key), "The record has '%s'" % key)
	var duration: float = float(record.get("duration_seconds", 0.0))
	_expect(is_equal_approx(duration, 50.0), "Duration is the run's elapsed seconds (got %s)" % duration)
	var shown_score: int = int(root.get_node(^"/root/RunManager").get(&"results")["score"])
	_expect(int(record.get("score", -1)) == shown_score, "The score is the one the results show")
	var orders: Array = record.get("orders", [])
	_expect(orders.size() == 2 and orders[0].get("trap") == "fragile" and orders[1].get("trap") == "noisy",
			"Orders name the traps by id (got %s)" % [orders])
	var boxes: Dictionary = {}
	for box: Dictionary in record.get("boxes", []):
		boxes[box["package_id"]] = box
	_expect(boxes.size() == 2, "Both boxes are in the record (got %d)" % boxes.size())
	if boxes.size() == 2:
		var fragile: Dictionary = boxes["box_a"]
		var noisy: Dictionary = boxes["box_b"]
		_expect(is_equal_approx(float(fragile["risk_seconds"]), 12.5) and int(fragile["risk_episodes"]) == 1,
				"The fragile box spent 12.5 s at risk once (got %s)" % [fragile])
		_expect(not bool(fragile["ruined"]) and fragile["trap"] == "fragile", "The fragile box survived")
		_expect(is_equal_approx(float(noisy["risk_seconds"]), 4.0),
				"The noisy box spent 4 s at risk before it broke (got %s)" % noisy["risk_seconds"])
		_expect(bool(noisy["ruined"]) and noisy["ruin_cause"] == "Se cayó de la caja"
				and is_equal_approx(float(noisy["ruined_at_seconds"]), 34.0),
				"The ruined box records what broke it and when (got %s)" % [noisy])
		_expect(is_equal_approx(float(noisy["damage"]), 40.0), "The damage the box took is recorded")
	_expect(record.get("route_event") == _event_name and not _event_name.is_empty(),
			"The route event is named (got %s)" % record.get("route_event"))
	var events: Array = record.get("route_events", [])
	_expect(events.size() == 1 and events[0].get("id") == _event_name and bool(events[0].get("success", false))
			and is_equal_approx(float(events[0].get("resolved_at_seconds", 0.0)), 40.0),
			"The route event's outcome and time are kept (got %s)" % [events])
	_expect((record.get("deliveries", []) as Array).size() == 1, "The door that resolved is listed")
	_expect(int((record.get("vehicle_impacts", {}) as Dictionary).get("count", 0)) == 1, "Van impacts are counted")


func _files() -> Array:
	var names: Array = []
	for file_name: String in DirAccess.get_files_at(_dir):
		names.append(file_name)
	names.sort()
	return names


func _read(file_name: String) -> Dictionary:
	var handle := FileAccess.open("%s/%s" % [_dir, file_name], FileAccess.READ)
	if handle == null:
		return {}
	var json := JSON.new()
	var ok: bool = json.parse(handle.get_as_text()) == OK
	handle.close()
	return json.data if ok and json.data is Dictionary else {}


func _clear() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [_dir, file_name]))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
