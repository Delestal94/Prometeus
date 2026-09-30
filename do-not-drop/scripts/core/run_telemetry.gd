extends Node
## Local run log for playtesting (S-805). Off unless the player turns on
## "Guardar registro de partidas" (GameSettings.save_run_log).
##
## It only listens: every fact it records already travels on EventBus, so it
## adds no RPC, no replication and no state a run depends on. Each peer writes
## what it saw locally (the host has the whole picture, a client sees the same
## relayed events), and nothing is ever sent anywhere: one small JSON file per
## run in user://telemetry/, named by date and time, for
## tools/telemetry-summary.py to fold into a table.
##
## What a file holds: duration, the traps on the order, seconds each box spent
## at risk, what ruined each box, the route event and how it ended, the doors
## and the score. The ruin cause is the text the package reported, which is
## already translated on that peer, so it reads well but is not a stable key:
## group by `trap` when comparing files from different languages.

const SAFE_JSON = preload("res://modules/persistence/safe_json.gd")
const TelemetryFormat = preload("res://scripts/core/run_telemetry_format.gd")

## ITrapBehavior.TrapState AT_RISK / RUINED: numbers kept here so this file
## compiles on its own in the headless runner, where the class cache is cold.
const STATE_AT_RISK: int = 1
const STATE_RUINED: int = 2

## Oldest files go first past this many, so leaving the option on for months
## can't slowly fill the disk.
const MAX_FILES: int = 300

## Where the files go. Tests point it at a throwaway folder.
var directory: String = "user://telemetry"
## Path of the last file written ("" until one is), for tests and the UI.
var last_file: String = ""

var _recording: bool = false
## package_id -> {trap, risk_seconds, risk_episodes, risk_since, damage, ruined, ...}
var _boxes: Dictionary = {}
var _route_events: Array[Dictionary] = []
var _deliveries: Array[Dictionary] = []
var _impact_count: int = 0
var _impact_peak: float = 0.0


func _ready() -> void:
	# Under a test script (--script) keep away from the player's real log.
	if Engine.get_main_loop().get_script() != null:
		directory = "user://test_telemetry"
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.cargo_registered.connect(_on_cargo_registered)
	EventBus.package_state_changed.connect(_on_state_changed)
	EventBus.package_damaged.connect(_on_damaged)
	EventBus.package_ruined.connect(_on_ruined)
	EventBus.vehicle_impact.connect(_on_vehicle_impact)
	EventBus.route_event_started.connect(_on_route_event_started)
	EventBus.route_event_resolved.connect(_on_route_event_resolved)
	EventBus.house_delivery_recorded.connect(_on_delivery)


func is_recording() -> bool:
	return _recording


## Run clock: the same seconds the results screen shows, and the only clock a
## simulated run in a test can set.
func _now() -> float:
	return RunManager.elapsed_seconds


func _on_run_started(_route_id: StringName, _players: Array) -> void:
	_boxes.clear()
	_route_events.clear()
	_deliveries.clear()
	_impact_count = 0
	_impact_peak = 0.0
	_recording = GameSettings.save_run_log


func _on_cargo_registered(id: StringName, name_key: String) -> void:
	if _recording:
		_box(id)["trap"] = TelemetryFormat.trap_id(name_key)


func _on_state_changed(id: StringName, state: int) -> void:
	if not _recording:
		return
	var box: Dictionary = _box(id)
	var at_risk: bool = state == STATE_AT_RISK
	if at_risk and float(box["risk_since"]) < 0.0:
		box["risk_since"] = _now()
		box["risk_episodes"] = int(box["risk_episodes"]) + 1
	elif not at_risk:
		_close_risk(box)
	box["state"] = state


func _on_damaged(id: StringName, damage: float) -> void:
	if _recording:
		var box: Dictionary = _box(id)
		box["damage"] = float(box["damage"]) + damage


func _on_ruined(id: StringName, cause: String) -> void:
	if not _recording:
		return
	var box: Dictionary = _box(id)
	box["ruined"] = true
	box["ruin_cause"] = cause
	box["ruined_at_seconds"] = _round(_now())


func _on_vehicle_impact(strength: float, _position: Vector3) -> void:
	if _recording:
		_impact_count += 1
		_impact_peak = maxf(_impact_peak, strength)


func _on_route_event_started(event_id: StringName, _event: Dictionary) -> void:
	if _recording:
		_route_events.append({"id": String(event_id), "started_at_seconds": _round(_now()),
				"resolved": false, "success": false})


func _on_route_event_resolved(event_id: StringName, success: bool, peer_id: int) -> void:
	if not _recording:
		return
	for entry: Dictionary in _route_events:
		if entry["id"] == String(event_id) and not bool(entry["resolved"]):
			entry["resolved"] = true
			entry["success"] = success
			entry["resolved_at_seconds"] = _round(_now())
			entry["peer_id"] = peer_id
			return


func _on_delivery(house_index: int, outcome: StringName, package_id: StringName) -> void:
	if _recording:
		_deliveries.append({"house": house_index, "outcome": String(outcome),
				"package_id": String(package_id), "at_seconds": _round(_now())})


func _on_run_ended(score: int, results: Dictionary) -> void:
	if not _recording:
		return
	_recording = false
	# A box still at risk when the run stopped counts up to that moment.
	for box: Dictionary in _boxes.values():
		_close_risk(box)
	var record: Dictionary = _build_record(score, results)
	save_record(record)


func _box(id: StringName) -> Dictionary:
	if not _boxes.has(id):
		_boxes[id] = {"risk_seconds": 0.0, "risk_episodes": 0, "risk_since": -1.0, "damage": 0.0,
				"ruined": false, "ruin_cause": "", "state": 0, "trap": ""}
	return _boxes[id]


func _close_risk(box: Dictionary) -> void:
	if float(box["risk_since"]) >= 0.0:
		box["risk_seconds"] = float(box["risk_seconds"]) + maxf(_now() - float(box["risk_since"]), 0.0)
		box["risk_since"] = -1.0


## The file's content: a plain Dictionary of numbers, strings and arrays, so
## the summary script (or anyone with a text editor) can read it.
func _build_record(score: int, results: Dictionary) -> Dictionary:
	var orders: Array = []
	for house: int in RunManager.house_assignments.size():
		var assignment: Array = RunManager.house_assignments[house]
		if assignment.size() < 2:
			continue
		orders.append({"house": house, "package_id": String(assignment[0]),
				"trap": TelemetryFormat.trap_id(String(assignment[1]))})
	var boxes: Array = []
	var ids: Array = _boxes.keys()
	for id: StringName in RunManager.cargo:
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	for id: StringName in ids:
		var box: Dictionary = _box(id)
		var trap: String = String(box["trap"])
		if trap.is_empty():
			trap = TelemetryFormat.trap_id(String(RunManager.cargo_names.get(id, "")))
		var final_state: int = int((RunManager.cargo.get(id, {}) as Dictionary).get("state", box["state"]))
		boxes.append({
			"package_id": String(id),
			"trap": trap,
			"risk_seconds": _round(float(box["risk_seconds"])),
			"risk_episodes": int(box["risk_episodes"]),
			"damage": _round(float(box["damage"])),
			"ruined": bool(box["ruined"]) or final_state == STATE_RUINED,
			"ruin_cause": String(box["ruin_cause"]),
			"ruined_at_seconds": float(box.get("ruined_at_seconds", -1.0)),
		})
	var route_event: Dictionary = results.get("route_event", {})
	var role: String = "solo"
	if NetworkManager.is_online():
		role = "host" if NetworkManager.is_host() else "client"
	return {
		"format": TelemetryFormat.FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"game_version": String(ProjectSettings.get_setting("application/config/version", "")),
		"role": role,
		"crew_size": maxi(NetworkManager.peer_ids.size(), 1),
		"mode": String(RunManager.current_mode),
		"duration_seconds": _round(float(results.get("elapsed_seconds", _now()))),
		"delivered": bool(results.get("delivered", false)),
		"reason": String(results.get("reason", "")),
		"score": score,
		"orders": orders,
		"boxes": boxes,
		"route_event": String(route_event.get("id", "")),
		"route_events": _route_events.duplicate(true),
		"deliveries": _deliveries.duplicate(true),
		"vehicle_impacts": {"count": _impact_count, "peak": _round(_impact_peak)},
		"totals": {
			"cargo_total": int(results.get("cargo_total", 0)),
			"cargo_intact": int(results.get("cargo_intact", 0)),
			"cargo_ruined": int(results.get("cargo_ruined", 0)),
			"houses_delivered": int(results.get("houses_delivered", 0)),
			"houses_missed": int(results.get("houses_missed", 0)),
			"houses_lost": int(results.get("houses_lost", 0)),
			"photos": int(results.get("photos", 0)),
			"complaints": (results.get("complaints", []) as Array).size(),
			"chaos_multiplier": float(results.get("chaos_multiplier", 1.0)),
			"distance_traveled": _round(float(results.get("distance_traveled", 0.0))),
		},
	}


## Writes the record as a new file under `directory`. Returns the path, or ""
## if the disk said no (a warning, never a crash: a playtest log must not
## be able to break the results screen).
func save_record(record: Dictionary) -> String:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK \
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		push_warning("[Telemetry] No se pudo crear la carpeta: " + directory)
		return ""
	var path: String = _free_path(TelemetryFormat.file_stem(Time.get_datetime_dict_from_system()))
	if not SAFE_JSON.write(path, record):
		push_warning("[Telemetry] No se pudo guardar el registro: " + path)
		return ""
	last_file = path
	_prune()
	return path


func _free_path(stem: String) -> String:
	var path: String = "%s/%s.json" % [directory, stem]
	var copy: int = 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.json" % [directory, stem, copy]
		copy += 1
	return path


func _prune() -> void:
	var names: PackedStringArray = []
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".json"):
			names.append(file_name)
	if names.size() <= MAX_FILES:
		return
	names.sort()
	for index: int in names.size() - MAX_FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [directory, names[index]]))


static func _round(value: float) -> float:
	return snappedf(value, 0.1)
