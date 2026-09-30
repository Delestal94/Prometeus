extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_host_gone_tally.gd
##
## N-222: a client whose host drops mid-run keeps what it saw of the run.
## - RunTally.of() counts the doors that got their box, the boxes still intact
##   and the distance and time, from RunManager's own record.
## - RunTally.has_unfinished_run() is false before a run starts
##   (run_tally.gd).
## - In the real level, losing the host during a run puts the tally on the
##   disconnect screen (hud_pause.gd), in this peer's language; the level stops
##   its copy of the run (level_common.gd) and no results cover the screen.
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
	_expect(not RUN_TALLY.has_unfinished_run(run), "No run started: nothing to tally")

	# --- a run two doors in, one box broken ---
	run.start_run()
	run.set(&"expected_houses", 4)
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
		{"house": 3, "outcome": &"lost", "package_id": &"", "photo": false, "care": &""},
	] as Array[Dictionary])
	run.set(&"cargo", {
		&"a": {"state": ITrapBehavior.TrapState.OK, "delivered": true},
		&"b": {"state": ITrapBehavior.TrapState.AT_RISK, "delivered": true},
		&"c": {"state": ITrapBehavior.TrapState.RUINED},
		&"d": {"state": ITrapBehavior.TrapState.OK},
	})
	var tally: Dictionary = RUN_TALLY.of(run)
	var houses: String = "%d/%d" % [int(tally["houses_delivered"]), int(tally["houses_expected"])]
	_expect(houses == "2/4", "Two of four doors (one missed, one lost) got their box (got %s)" % houses)
	var boxes: String = "%d/%d" % [int(tally["cargo_intact"]), int(tally["cargo_total"])]
	_expect(boxes == "2/4", "Two of four boxes intact (got %s)" % boxes)
	_expect(RUN_TALLY.has_unfinished_run(run), "A started run without results is unfinished")
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
	var mode: String = String(hud.get(&"overlay_mode"))
	_expect(mode == "disconnected", "Losing the host opens the disconnect screen (got %s)" % mode)
	var stats: String = (hud.get(&"overlay_stats") as Label).text
	_expect(stats.contains(tr("HUD_HOST_GONE")) and stats.contains(spanish),
			"The disconnect screen keeps the tally (got '%s')" % stats)
	_expect(not bool(run.get(&"is_running")), "The level stops the local run with the session")
	network.session_failed.emit("host lost again")
	await process_frame
	stats = (hud.get(&"overlay_stats") as Label).text
	_expect(stats.contains(spanish), "A second loss notice keeps the tally (got '%s')" % stats)
	for i: int in 10:
		await physics_frame
	_expect(_ended == 0 and hud.get(&"overlay_mode") == "disconnected",
			"No results screen replaces it afterwards (ended %d, overlay %s)" % [_ended, hud.get(&"overlay_mode")])

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
