extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_host_gone_tally.gd
##
## N-222: a client whose host drops mid-run keeps what it saw of the run.
## - RunTally.of() counts the doors that got their box, the boxes still intact
##   and the distance and time, from RunManager's own record.
## - RunTally.interrupt() stops the local run once and returns that tally; with
##   no run going it returns {} (run_tally.gd).
## - In the real level, losing the host during a run puts the tally on the
##   disconnect screen (hud_pause.gd), in this peer's language, and the level
##   doesn't end the run on its own afterwards (no results over it).
## - level_base.gd keeps RunManager.current_distance at the furthest point
##   reached in a delivery run, not only in Endless.

const RUN_TALLY = preload("res://scripts/core/run_tally.gd")

var _failures: int = 0
var _ended: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var hud: Node = level.get_node(^"HUD")
	root.get_node(^"/root/EventBus").run_ended.connect(func(_score: int, _results: Dictionary) -> void: _ended += 1)

	# --- nothing to keep without a run ---
	run.reset_run()
	_expect(RUN_TALLY.interrupt().is_empty(), "No run going: interrupt() returns nothing")

	# --- a run two doors in, one box broken ---
	run.start_run()
	run.set(&"expected_houses", 3)
	run.set(&"current_distance", 250.0)
	await physics_frame
	await physics_frame
	_expect(float(run.get(&"current_distance")) >= 250.0,
			"The level only raises the distance, never drops it (got %.1f)" % float(run.get(&"current_distance")))
	run.set(&"current_distance", 250.0)
	run.set(&"elapsed_seconds", 83.0)
	run.set(&"deliveries", [
		{"house": 0, "outcome": &"delivered_ok", "package_id": &"a", "photo": false, "care": &""},
		{"house": 1, "outcome": &"missed", "package_id": &"", "photo": false, "care": &""},
		{"house": 2, "outcome": &"delivered_at_risk", "package_id": &"b", "photo": false, "care": &""},
	] as Array[Dictionary])
	run.set(&"cargo", {
		&"a": {"state": ITrapBehavior.TrapState.OK, "delivered": true},
		&"b": {"state": ITrapBehavior.TrapState.AT_RISK, "delivered": true},
		&"c": {"state": ITrapBehavior.TrapState.RUINED},
		&"d": {"state": ITrapBehavior.TrapState.OK},
	})
	var tally: Dictionary = RUN_TALLY.of(run)
	_expect(int(tally["houses_delivered"]) == 2 and int(tally["houses_expected"]) == 3,
			"Two of three doors got their box (got %d/%d)" % [int(tally["houses_delivered"]), int(tally["houses_expected"])])
	_expect(int(tally["cargo_intact"]) == 2 and int(tally["cargo_total"]) == 4,
			"Two of four boxes intact (got %d/%d)" % [int(tally["cargo_intact"]), int(tally["cargo_total"])])
	_expect(not bool(tally["endless"]), "A delivery run isn't tallied as Endless")

	TranslationServer.set_locale("en")
	var english: String = RUN_TALLY.describe(tally)
	TranslationServer.set_locale("es")
	var spanish: String = RUN_TALLY.describe(tally)
	_expect(english != spanish and english.contains("2") and english.contains("250") and english.contains("1:23"),
			"The line is translated and carries houses, meters and time (got '%s' / '%s')" % [english, spanish])

	# --- the host drops ---
	network.session_failed.emit("host lost")
	await process_frame
	_expect(hud.get(&"overlay_mode") == "disconnected", "Losing the host opens the disconnect screen (got %s)" % hud.get(&"overlay_mode"))
	var stats: String = (hud.get(&"overlay_stats") as Label).text
	_expect(stats.contains(tr("HUD_HOST_GONE")) and stats.contains(spanish),
			"The disconnect screen keeps the tally (got '%s')" % stats)
	_expect(not bool(run.get(&"is_running")), "The local run stops with the session")
	for i: int in 10:
		await physics_frame
	_expect(_ended == 0 and hud.get(&"overlay_mode") == "disconnected",
			"No results screen replaces it afterwards (ended %d, overlay %s)" % [_ended, hud.get(&"overlay_mode")])
	_expect(RUN_TALLY.interrupt().is_empty(), "A second loss doesn't tally the same run twice")

	# --- Endless reads in meters ---
	run.set(&"current_mode", &"endless")
	var endless: String = RUN_TALLY.describe(RUN_TALLY.of(run))
	_expect(endless.contains("250") and endless != spanish, "Endless has its own line, in meters (got '%s')" % endless)

	run.reset_run()
	level.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: a client left without a host keeps the run's tally on the disconnect screen")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
