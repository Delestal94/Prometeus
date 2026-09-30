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
## - If the run already ended and the host's results are up when the host
##   drops, they stay (hud_pause.gd, HudResults.show_host_gone()): same title,
##   score and rows; the guest's "only the host can restart" note gives way to
##   one saying the host left (once, however many loss notices come); the
##   retry shows greyed out with its reason, and neither it nor R restarts
##   (HudPrompts.can_restart(): offline now, a restart would reload a solo
##   world); "back to the menu" gets there, with the run cleared.

const RUN_TALLY = preload("res://scripts/core/run_tally.gd")
const LEVEL: String = "res://scenes/gameplay/level_base.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"

var _failures: int = 0
var _ended: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var level: Node = load(LEVEL).instantiate()
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
	await _results_stay_when_the_host_leaves()
	if _failures == 0:
		print("PASS: a client left without a host keeps the run's tally on the disconnect screen,"
				+ " or the results if the run had ended")
	quit(_failures)


## The run is over and the host's results are on screen when the host drops.
func _results_stay_when_the_host_leaves() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	var network: Node = root.get_node(^"/root/NetworkManager")
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	var hud: Node = level.get_node(^"HUD")
	var restarts: Array[int] = [0]
	root.get_node(^"/root/EventBus").restart_requested.connect(func() -> void: restarts[0] += 1)

	# The host's results, as the relay leaves them (RunManager._remote_finish_run()).
	var results: Dictionary = {
		"score": 240, "delivered": true, "reason": "", "elapsed_seconds": 95.0,
		"cargo_total": 2, "cargo_intact": 1, "cargo_ruined": 1, "cargo_points": 100,
		"houses_delivered": 2, "houses_missed": 0, "houses_lost": 0,
		"breakdown": [{"label": "Doors", "points": 150, "count": 2}],
		"best_score": 240, "complaints": [],
		"deliveries": [
			{"house": 0, "outcome": &"delivered_ok", "photo": false},
			{"house": 1, "outcome": &"delivered_ruined", "photo": false},
		],
	}
	run.set(&"elapsed_seconds", 95.0)
	run.set(&"results", results.duplicate(true))
	hud.get(&"results").call(&"_on_ended", 240, results)
	# What a guest's card has on top (can_restart() is false online, which a
	# single process can't be): no retry, and the "only the host" note.
	var stats_label: Label = hud.get(&"overlay_stats")
	stats_label.text += tr("HUD_RESULT_GUEST_NOTE")
	hud.get(&"results").call(&"set_buttons", "", false, false, true)
	await process_frame
	var title: String = (hud.get(&"overlay_title") as Label).text
	var score: String = (hud.get(&"score_label") as Label).text
	var rows_box: Node = hud.get(&"result_rows_box")
	_expect(hud.get(&"overlay_mode") == "results" and rows_box.get_child_count() == 2,
			"The results screen is up with a row per door (rows %d)" % rows_box.get_child_count())

	# --- the host drops ---
	network.call(&"_fail", tr("UI_NET_HOST_LOST"))
	await process_frame
	var mode: String = String(hud.get(&"overlay_mode"))
	_expect(mode == "results" and (hud.get(&"overlay") as Control).visible,
			"Losing the host with the results up keeps them (got %s)" % mode)
	_expect((hud.get(&"overlay_title") as Label).text == title and (hud.get(&"score_label") as Label).text == score
			and rows_box.get_child_count() == 2,
			"Title, score and rows are the host's, untouched (got '%s', '%s', %d rows)" % [
				(hud.get(&"overlay_title") as Label).text, (hud.get(&"score_label") as Label).text,
				rows_box.get_child_count()])
	var note: String = tr("HUD_RESULT_HOST_GONE_NOTE").strip_edges()
	var guest_note: String = tr("HUD_RESULT_GUEST_NOTE").strip_edges()
	_expect(stats_label.text.contains(note) and not stats_label.text.contains(guest_note)
			and not stats_label.text.contains(tr("HUD_HOST_GONE")),
			"The guest note gives way to 'the host left' (got '%s')" % stats_label.text)
	var retry: Button = hud.get(&"action_button")
	_expect(retry.visible and retry.disabled and retry.text == tr("HUD_RETRY")
			and retry.tooltip_text == tr("HUD_RETRY_NEEDS_HOST"),
			"The retry shows greyed out with its reason (visible %s, disabled %s, '%s', '%s')" % [
				retry.visible, retry.disabled, retry.text, retry.tooltip_text])
	var menu: Button = hud.get(&"menu_button")
	_expect(menu.visible and not menu.disabled and menu.has_focus(),
			"Back to the menu is there, enabled and focused (visible %s, disabled %s, focus %s)" % [
				menu.visible, menu.disabled, menu.has_focus()])
	network.call(&"_fail", tr("UI_NET_HOST_LOST"))
	await process_frame
	_expect(hud.get(&"overlay_mode") == "results" and stats_label.text.count(note) == 1,
			"A second loss notice keeps the results and says it once (got '%s')" % stats_label.text)

	# --- no restart into a world that isn't the crew's ---
	var pause: Node = hud.get(&"pause")
	pause.call(&"primary_action")
	pause.call(&"request_restart")
	var press := InputEventAction.new()
	press.action = &"run_restart"
	press.pressed = true
	pause.call(&"_unhandled_input", press)
	for i: int in 5:
		await physics_frame
	var still_up: bool = is_instance_valid(level) and current_scene == level
	_expect(restarts[0] == 0 and still_up and not (run.get(&"results") as Dictionary).is_empty(),
			"Neither the greyed retry nor R restarts or leaves (restart requests %d, level up %s)" % [
				restarts[0], still_up])
	if not still_up:
		if current_scene != null:
			current_scene.queue_free()
		run.reset_run()
		await process_frame
		return

	# --- back to the menu ---
	menu.pressed.emit()
	for i: int in 10:
		if current_scene != null and current_scene != level:
			break
		await process_frame
	var landed: Node = current_scene
	_expect(landed != null and landed.scene_file_path == MAIN_MENU,
			"Back to the menu lands there (got %s)" % (landed.scene_file_path if landed != null else "nothing"))
	_expect((run.get(&"results") as Dictionary).is_empty(), "Leaving clears the run")
	if landed != null and landed.scene_file_path == MAIN_MENU:
		var status: Label = landed.get(&"_status_label")
		_expect(status.text == tr("UI_NET_HOST_LOST"), "The menu says why the room closed (got '%s')" % status.text)
		landed.queue_free()
	run.reset_run()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
