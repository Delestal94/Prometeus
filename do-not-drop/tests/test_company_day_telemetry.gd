extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_day_telemetry.gd
##
## The company day in the local run log (D-0239, run_telemetry.gd +
## run_telemetry_format.gd), driven with real EventBus signals:
## - With "Guardar registro de partidas" off, a whole simulated day writes nothing.
## - With it on, company_day_started + business signals + company_day_summary
##   leave exactly one JSON under user://test_telemetry with "kind": "company_day",
##   the day, the plain summary, the events in order (with a time each) and the
##   count per event type; the file name carries the day.
## - describe_day() on the record read back from disk gives the readable lines
##   (income/costs/profit, orders, supplies, boxes, money by reason).
## - A day that never reaches its summary writes nothing.
## - The event list stops at the cap but the counts keep going.
## - A delivery run still writes its record, now with "kind": "run"; a record
##   without kind reads as a run.

var _failures: int = 0
var _dir: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var telemetry: Node = root.get_node(^"/root/RunTelemetry")
	var settings: Node = root.get_node(^"/root/GameSettings")
	var bus: Node = root.get_node(^"/root/EventBus")
	var format: GDScript = load("res://scripts/core/run_telemetry_format.gd")
	_dir = String(telemetry.get(&"directory"))
	_expect(_dir == "user://test_telemetry", "Under a test script the log goes to a throwaway folder (got %s)" % _dir)
	_clear()

	# --- pure helpers ---
	_expect(format.call(&"record_kind", {}) == "run", "A record without kind is a run")
	_expect(format.call(&"record_kind", {"kind": "company_day"}) == "company_day", "A company day record says so")
	var moment := {"year": 2026, "month": 9, "day": 30, "hour": 7, "minute": 5, "second": 3}
	_expect(format.call(&"day_file_stem", moment, 3) == "2026-09-30_07-05-03_day3", "Day stem is date_time_dayN")
	var counted: Dictionary = format.call(&"day_event_counts", [{"event": "a"}, {"event": "b"}, {"event": "a"}, {}])
	_expect(counted == {"a": 2, "b": 1}, "Events are counted by name (got %s)" % [counted])
	var plain: Dictionary = format.call(&"plain", {&"k": [&"v", 1]})
	_expect(plain.has("k") and plain["k"][0] is String, "StringName keys and values become strings")

	# --- off: a whole day leaves nothing behind ---
	settings.set(&"save_run_log", false)
	_simulate_day(bus, 1)
	_expect(_files().is_empty(), "With the option off, a finished day writes no file (got %s)" % [_files()])

	# --- on: one file with the day ---
	settings.set(&"save_run_log", true)
	_simulate_day(bus, 2)
	var files: Array = _files()
	_expect(files.size() == 1, "With the option on, a finished day writes one file (got %d)" % files.size())
	if files.size() == 1:
		_expect(String(files[0]).begins_with("20") and String(files[0]).ends_with("_day2.json"),
				"The file is <date>_day2.json (got %s)" % files[0])
		_check_day(_read(files[0]), format)

	# --- a day cut short writes nothing; the next one starts clean ---
	_clear()
	bus.emit_signal(&"company_day_started", 3)
	bus.emit_signal(&"order_added", &"order_9")
	_expect(_files().is_empty(), "A day left before its summary writes nothing")
	_simulate_day(bus, 4)
	files = _files()
	_expect(files.size() == 1, "The next day writes its own file (got %d)" % files.size())
	if files.size() == 1:
		var next: Dictionary = _read(files[0])
		var kept: int = (next.get("events", []) as Array).size()
		_expect(int(next.get("day", 0)) == 4 and kept == 9,
				"The abandoned day's events are not carried over (got %d events)" % kept)

	# --- events with no day open are ignored ---
	_clear()
	bus.emit_signal(&"order_added", &"stray")
	bus.emit_signal(&"company_day_summary", 5, {"day": 5})
	_expect(_files().is_empty(), "A summary with no day recording writes nothing")

	# --- the event list is capped, the counts are not ---
	_clear()
	var cap: int = int(telemetry.get(&"MAX_DAY_EVENTS"))
	bus.emit_signal(&"company_day_started", 6)
	for index: int in cap + 25:
		bus.emit_signal(&"order_added", StringName("o%d" % index))
	bus.emit_signal(&"company_day_summary", 6, {"day": 6})
	files = _files()
	_expect(files.size() == 1, "The long day is saved (got %d files)" % files.size())
	if files.size() == 1:
		var long_day: Dictionary = _read(files[0])
		_expect((long_day.get("events", []) as Array).size() == cap, "The event list stops at %d (got %d)" % [
				cap, (long_day.get("events", []) as Array).size()])
		_expect(int(long_day.get("events_dropped", 0)) == 25,
				"The overflow is counted (got %s)" % long_day.get("events_dropped"))
		_expect(int((long_day.get("counts", {}) as Dictionary).get("order_added", 0)) == cap + 25,
				"The counts include the events past the cap")
		var notes: PackedStringArray = format.call(&"describe_day", long_day)
		_expect(" ".join(notes).contains("25 events past the cap"), "describe_day mentions the dropped events")

	# --- a delivery run still writes, now with its kind ---
	_clear()
	_simulate_run(bus)
	files = _files()
	_expect(files.size() == 1, "A delivery run writes one file (got %d)" % files.size())
	if files.size() == 1:
		var run: Dictionary = _read(files[0])
		_expect(run.get("kind") == "run" and format.call(&"record_kind", run) == "run", "The run record says kind run")
		_expect(run.has("boxes") and run.has("totals")
				and int(run.get("format", 0)) == int(format.get("FORMAT_VERSION")),
				"The rest of the run record is unchanged")

	settings.set(&"save_run_log", false)
	_clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
	if _failures == 0:
		print("PASS: company day telemetry writes one readable company_day file, caps its events, leaves runs alone")
	quit(_failures)


## One day: 2 orders in, 1 packed and sealed, 1 delivered, a supply truck, a gate, a milestone
## and three wallet movements, then the summary. 9 events between the start and the summary.
func _simulate_day(bus: Node, day: int) -> void:
	bus.emit_signal(&"company_day_started", day)
	bus.emit_signal(&"order_added", &"order_1")
	bus.emit_signal(&"order_added", &"order_2")
	bus.emit_signal(&"supply_arrived", &"paper_co")
	bus.emit_signal(&"order_packed", &"order_1")
	bus.emit_signal(&"box_sealed", &"station_a", &"order_1")
	bus.emit_signal(&"order_delivered", &"order_1")
	bus.emit_signal(&"money_changed", 120, &"order_paid")
	bus.emit_signal(&"money_changed", -30, &"supplier")
	bus.emit_signal(&"company_day_closing", day)
	bus.emit_signal(&"company_day_summary", day, {
		"day": day, "income": 150, "costs": 40, "profit": 110, "opening": 200, "closing": 310,
		"income_by_reason": {&"order_paid": 120, &"tip": 30}, "cost_by_reason": {&"supplier": 30, &"rent": 10},
		"truncated": false,
	})


func _check_day(record: Dictionary, format: GDScript) -> void:
	_expect(not record.is_empty(), "The file parses as a JSON object")
	_expect(record.get("kind") == "company_day" and format.call(&"record_kind", record) == "company_day",
			"The record is a company_day")
	for key: String in ["format", "saved_at", "game_version", "role", "crew_size", "day", "duration_seconds",
			"summary", "events", "counts"]:
		_expect(record.has(key), "The record has '%s'" % key)
	_expect(int(record.get("day", 0)) == 2, "The day is 2")
	_expect(record.get("role") == "solo" and int(record.get("crew_size", 0)) == 1,
			"Role and crew are those of a solo game")
	var events: Array = record.get("events", [])
	var names: Array = []
	var last_t: float = -1.0
	var ordered: bool = true
	for entry: Dictionary in events:
		names.append(entry.get("event"))
		var t: float = float(entry.get("t", -1.0))
		ordered = ordered and t >= last_t
		last_t = t
	_expect(names == ["order_added", "order_added", "supply_arrived", "order_packed", "box_sealed", "order_delivered",
			"money_changed", "money_changed", "company_day_closing"],
			"Events are kept in the order they happened (got %s)" % [names])
	_expect(ordered and last_t >= 0.0, "Each event has a time and the times do not go back")
	if events.size() == 9:
		_expect(events[0].get("order") == "order_1" and events[2].get("supplier") == "paper_co"
				and events[4].get("station") == "station_a" and events[4].get("order") == "order_1",
				"Events carry their ids as strings (got %s)" % [events])
		_expect(int(events[6].get("amount", 0)) == 120 and events[7].get("reason") == "supplier"
				and int(events[7].get("amount", 0)) == -30, "Wallet movements keep amount and reason")
	var counts: Dictionary = record.get("counts", {})
	_expect(int(counts.get("order_added", 0)) == 2 and int(counts.get("money_changed", 0)) == 2
			and int(counts.get("order_packed", 0)) == 1 and int(counts.get("box_sealed", 0)) == 1,
			"Counts per event type are right (got %s)" % [counts])
	var recount: Dictionary = format.call(&"day_event_counts", events)
	var same: bool = recount.size() == counts.size()
	for name: String in recount:
		same = same and int(counts.get(name, -1)) == int(recount[name])  # JSON turns ints into floats
	_expect(same, "The stored counts match the event list")
	var summary: Dictionary = record.get("summary", {})
	_expect(int(summary.get("profit", 0)) == 110
			and (summary.get("income_by_reason", {}) as Dictionary).has("order_paid"),
			"The summary is stored as plain values (got %s)" % [summary])
	var lines: PackedStringArray = format.call(&"describe_day", record)
	var expected: PackedStringArray = [
		"Day 2 (solo, crew 1)",
		"Income 150, costs 40, profit 110",
		"Wallet 200 -> 310",
		"Orders: 2 added, 1 packed, 1 delivered",
		"Supplies arrived: 1, boxes sealed: 1",
		"Money in: order_paid 120, tip 30",
		"Money out: supplier 30, rent 10",
	]
	_expect(lines == expected, "describe_day reads the record back (got %s)" % [lines])


## The smallest delivery that ends: enough for the run record to be written.
func _simulate_run(bus: Node) -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	root.get_node(^"/root/CrewProgression").call(&"reset_campaign")
	root.get_node(^"/root/UnlockManager").call(&"reset_profile")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 1)
	bus.emit_signal(&"houses_assigned", [[&"box_a", "HUD_TRAP_FRAGILE", "A1"]])
	bus.emit_signal(&"cargo_registered", &"box_a", "HUD_TRAP_FRAGILE")
	manager.call(&"start_run")
	manager.set(&"elapsed_seconds", 20.0)
	manager.call(&"register_delivery", 0, &"delivered_ok", &"box_a")
	manager.call(&"finish_run", true)


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
