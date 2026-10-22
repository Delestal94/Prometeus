extends RunLog
## Local run log for playtesting (S-805) on the run_log module's RunLog
## (docs/modulos.md): the module writes, names and prunes the files; this
## is what Take My Package records. Off unless the player turns on "Guardar
## registro de partidas" (GameSettings.save_run_log).
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
##
## Company days (D-0239) go to the same folder under the same option: from
## company_day_started to company_day_summary it keeps the day's business events
## (orders, supplies, boxes, gates, milestones, every wallet movement) with the
## seconds since the day opened, and the summary writes one file with
## `"kind": "company_day"` (delivery runs say `"kind": "run"`; an older file with
## no kind is a run). Read one with describe_day() in run_telemetry_format.gd. A day
## abandoned before its summary (leaving mid-day) writes nothing, and a peer that
## joins mid-day sees no company_day_started, so it writes nothing either.

const TelemetryFormat = preload("res://scripts/core/run_telemetry_format.gd")

## ITrapBehavior.TrapState AT_RISK / RUINED: numbers kept here so this file
## compiles on its own in the headless runner, where the class cache is cold.
const STATE_AT_RISK: int = 1
const STATE_RUINED: int = 2
const MAX_FILES: int = 300
## A day's event list stops growing here (counts keep going), so a very long
## day can't grow the buffer or the file without bound.
const MAX_DAY_EVENTS: int = 2000

var _recording: bool = false
## package_id -> {trap, risk_seconds, risk_episodes, risk_since, damage, ruined, ...}
var _boxes: Dictionary = {}
var _route_events: Array[Dictionary] = []
var _deliveries: Array[Dictionary] = []
var _impact_count: int = 0
var _impact_peak: float = 0.0
var _day_recording: bool = false
var _day: int = 0
var _day_events: Array[Dictionary] = []
var _day_counts: Dictionary = {}
var _day_dropped: int = 0
var _day_started_msec: int = 0


func _init() -> void:
	directory = "user://telemetry"
	max_files = MAX_FILES


func _ready() -> void:
	super()
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
	EventBus.company_day_started.connect(_on_day_started)
	EventBus.company_day_closing.connect(func(day: int) -> void: _log_day_event("company_day_closing", {"day": day}))
	EventBus.company_day_summary.connect(_on_day_summary)
	EventBus.order_added.connect(_log_id_event.bind("order_added", "order"))
	EventBus.order_packed.connect(_log_id_event.bind("order_packed", "order"))
	EventBus.order_delivered.connect(_log_id_event.bind("order_delivered", "order"))
	EventBus.supply_arrived.connect(_log_id_event.bind("supply_arrived", "supplier"))
	EventBus.box_sealed.connect(func(station: StringName, order: StringName) -> void:
			_log_day_event("box_sealed", {"station": String(station), "order": String(order)}))
	EventBus.gate_opened.connect(_log_id_event.bind("gate_opened", "gate"))
	EventBus.milestone_reached.connect(_log_id_event.bind("milestone_reached", "milestone"))
	EventBus.money_changed.connect(func(amount: int, reason: StringName) -> void:
			_log_day_event("money_changed", {"amount": amount, "reason": String(reason)}))


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


## Seconds since the company day opened: a monotonic clock that needs neither
## the day cycle nor the world clock (neither is reachable from an autoload).
func _day_seconds() -> float:
	return float(Time.get_ticks_msec() - _day_started_msec) / 1000.0


func _on_day_started(day: int) -> void:
	_day = day
	_day_events.clear()
	_day_counts.clear()
	_day_dropped = 0
	_day_started_msec = Time.get_ticks_msec()
	_day_recording = GameSettings.save_run_log


## The business signals that carry a single id; `event` and `key` come from bind().
func _log_id_event(id: StringName, event: String, key: String) -> void:
	_log_day_event(event, {key: String(id)})


## Appends one business event; the count is always kept, the list stops at the cap.
func _log_day_event(event: String, args: Dictionary) -> void:
	if not _day_recording:
		return
	_day_counts[event] = int(_day_counts.get(event, 0)) + 1
	if _day_events.size() >= MAX_DAY_EVENTS:
		_day_dropped += 1
		return
	var entry: Dictionary = {"t": _round(_day_seconds()), "event": event}
	entry.merge(args)
	_day_events.append(entry)


func _on_day_summary(day: int, summary: Dictionary) -> void:
	if not _day_recording:
		return
	_day_recording = false
	var record: Dictionary = {
		"format": TelemetryFormat.FORMAT_VERSION,
		"kind": TelemetryFormat.KIND_COMPANY_DAY,
		"saved_at": Time.get_datetime_string_from_system(),
		"game_version": String(ProjectSettings.get_setting("application/config/version", "")),
		"role": _role(),
		"crew_size": maxi(NetworkManager.peer_ids.size(), 1),
		"day": day,
		"duration_seconds": _round(_day_seconds()),
		"summary": TelemetryFormat.plain(summary),
		"events": _day_events.duplicate(true),
		"events_dropped": _day_dropped,
		"counts": _day_counts.duplicate(),
	}
	save_record(record, TelemetryFormat.day_file_stem(Time.get_datetime_dict_from_system(), day))


func _role() -> String:
	if NetworkManager.is_online():
		return "host" if NetworkManager.is_host() else "client"
	return "solo"


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
	save_record(record, TelemetryFormat.file_stem(Time.get_datetime_dict_from_system()))


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
	var role: String = _role()
	return {
		"format": TelemetryFormat.FORMAT_VERSION,
		"kind": TelemetryFormat.KIND_RUN,
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


static func _round(value: float) -> float:
	return snappedf(value, 0.1)
