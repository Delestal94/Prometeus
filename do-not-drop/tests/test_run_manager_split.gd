extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_run_manager_split.gd
##
## run_manager.gd was split by responsibility (N-225.5: run_scoring.gd, run_results.gd, run_deadlines.gd,
## run_deliveries.gd, run_leaderboard.gd and run_session.gd, next to deadline_cut.gd) and must stay split without
## changing what the rest of the project, or the network, sees of the autoload:
## - the RPC surface is exactly the table below (name, rpc mode, transfer mode, call_local, channel) and the
##   @rpc functions keep their order and annotations in the file, as before the split. Godot numbers RPCs by
##   name, so a renamed or re-moded one would make peers disagree on the wire; an @rpc has to stay in the
##   autoload's own script (which has no class_name: it would hide the singleton);
## - every var, constant (with its value: these are the score's numbers) and method that other scripts and
##   tests use still exists on the autoload, the private ones the tests call included;
## - the helpers load, are static, and name no autoload (they compile before the autoloads exist, which is why
##   the autoload hands them what they need), and run_manager.gd stays under MAX_LINES, far from the lint limit;
## - what the helpers compute is what the single-file version computed: three runs through the real
##   finish_run() (a delivery run with every kind of door, a failed one, an endless one), whose results were
##   worked out by hand from the original code (git show 6df932a:do-not-drop/scripts/core/run_manager.gd), plus
##   the pure helpers on small inputs.

const MANAGER_SCRIPT: String = "res://scripts/core/run_manager.gd"
const MAX_LINES: int = 700
const TEST_SAVE_PATH: String = "user://test_run_manager_split_leaderboard.json"
const HELPERS: Array[String] = [
	"run_scoring", "run_results", "run_deadlines", "run_deliveries", "run_leaderboard", "run_session",
]

## Order of the @rpc functions in run_manager.gd, with the annotation of each.
const RPC_ORDER: Array = [
	["_sync_care_supplies", "authority", "call_remote", "reliable"],
	["_remote_start_run", "authority", "call_remote", "reliable"],
	["_request_delivery_photo", "any_peer", "call_remote", "reliable"],
	["_receive_session_state", "authority", "call_remote", "reliable"],
	["_remote_finish_run", "authority", "call_remote", "reliable"],
]
## name -> [rpc_mode, call_local, transfer_mode, channel]. rpc_mode: 1 any_peer, 2 authority. transfer_mode:
## 2 reliable.
const RPCS: Dictionary = {
	"_sync_care_supplies": [2, false, 2, 0],
	"_remote_start_run": [2, false, 2, 0],
	"_request_delivery_photo": [1, false, 2, 0],
	"_receive_session_state": [2, false, 2, 0],
	"_remote_finish_run": [2, false, 2, 0],
}
const METHODS: Array[String] = [
	"reset_run", "set_deadlines", "shorten_next_deadline", "next_deadline", "deadline_tally", "care_supply_count",
	"consume_care_supply", "record_care", "care_category", "start_run", "register_delivery",
	"attach_delivery_photo", "submit_delivery_photo", "finish_run", "session_names", "send_session_state",
	"best_score", "rescue_stories", "world_stories", "worst_state",
	# Private, but the tests (and the nodes next to the autoload) call them.
	"_record_score", "_resolve_deliveries", "_load_leaderboard", "_mark_photo", "_remote_finish_run",
	"_remote_start_run", "_receive_session_state", "_delivered_at", "_publish_results", "_finish_endless_run",
	"_result_route_event", "_entry", "_attach_delivery_photo", "_on_package_ruined", "_on_state_changed",
	"_on_integrity_changed",
]
const STATIC_METHODS: Array[String] = ["plan_deadlines", "handed_over"]
const VARS: Array[String] = [
	"is_running", "elapsed_seconds", "results", "current_mode", "current_distance", "cargo", "deliveries",
	"cargo_names", "house_assignments", "refused_houses", "expected_houses", "delivery_photos",
	"last_photo_peer_id", "last_photo_package_id", "_event_id", "consumed_packages", "had_simultaneous_risk",
	"care_supplies", "deadlines", "_pending_care", "save_path", "leaderboard",
]
## The score's numbers, as before the split.
const CONSTANTS: Dictionary = {
	"POINTS_INTACT": 100, "POINTS_AT_RISK": 50, "CHAOS_MULTIPLIER": 1.2, "MAX_LEADERBOARD_ENTRIES": 10,
	"DISTANCE_POINTS_PER_METER": 1.0, "POINTS_DELIVERED_INTACT": 150, "POINTS_DELIVERED_AT_RISK": 75,
	"POINTS_DELIVERED_RUINED": 20, "PENALTY_MISSED_HOUSE": 60, "POINTS_PHOTO_BONUS": 25, "COMPLAINT_PENALTY": 40,
	"POINTS_DELIVERED_REPAIRED": 110, "POINTS_DELIVERED_UNCONVINCING": 35, "POINTS_DELIVERED_SUBSTITUTED": 10,
	"MAX_DEADLINES": 3, "DEADLINE_SPEED": 13.5, "DEADLINE_SLACK": 15.0, "DEADLINE_STOP_SECONDS": 25.0,
	"POINTS_DEADLINE_MET": 40, "PENALTY_DEADLINE_MISSED": 15, "PHOTO_REACH": 20.0,
	"MODE_DELIVERY": &"delivery", "MODE_ENDLESS": &"endless",
	"CARE_POINTS": {&"repaired": 110, &"unconvincing": 35, &"substituted": 10},
	"CARE_SUPPLIES_START": {&"tape": 3, &"repair": 2, &"filler": 2, &"rag": 2, &"strap": 2, &"substitute": 1},
	"DEADLINE_REASONS": ["HUD_DEADLINE_REASON_LEAVING", "HUD_DEADLINE_REASON_BIRTHDAY", "HUD_DEADLINE_REASON_SHOP"],
	"RESCUE_NAMES": {&"fragile": "HUD_RESCUE_VASE", &"balance": "HUD_RESCUE_CAKE", &"noisy": "HUD_RESCUE_HEN",
		&"growing_weight": "HUD_RESCUE_HEAVY", &"liquid": "HUD_RESCUE_LIQUID",
		&"explosive": "HUD_RESCUE_EXPLOSIVE", &"hostile": "HUD_RESCUE_CREATURE"},
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load(MANAGER_SCRIPT) as GDScript
	_expect(script != null, "run_manager.gd loads")
	var manager: Node = root.get_node_or_null(^"/root/RunManager")
	_expect(manager != null, "The RunManager autoload is loaded")
	if script == null or manager == null:
		quit(1)
		return
	_check_source()
	_check_rpcs(script)
	_check_api(manager, script)
	_check_helpers()
	_check_pure_helpers()
	_check_runs(manager)
	if _failures == 0:
		print("PASS: run_manager.gd keeps its RPCs, its API and its numbers, and stays under %d lines" % MAX_LINES)
	quit(_failures)


func _check_source() -> void:
	var source: String = FileAccess.get_file_as_string(MANAGER_SCRIPT)
	var lines: int = source.split("\n").size()
	_expect(lines <= MAX_LINES, "run_manager.gd has %d lines, at most %d: a new responsibility goes in its own file"
			% [lines, MAX_LINES])
	_expect(not source.contains("class_name"), "run_manager.gd has no class_name (it would hide the autoload)")
	var order: Array = []
	var all_lines: PackedStringArray = source.split("\n")
	for index: int in all_lines.size():
		if not all_lines[index].begins_with("@rpc("):
			continue
		var annotation: PackedStringArray = all_lines[index].trim_prefix("@rpc(").trim_suffix(")").replace("\"", "") \
				.replace(" ", "").split(",")
		var function_name: String = all_lines[index + 1].trim_prefix("func ").get_slice("(", 0)
		order.append([function_name] + Array(annotation))
	_expect(order == RPC_ORDER, "The @rpc functions keep their order and annotations (got %s)" % str(order))


func _check_rpcs(script: GDScript) -> void:
	var config: Dictionary = script.get_rpc_config()
	for rpc_name: String in RPCS:
		_expect(config.has(StringName(rpc_name)), "%s is still an @rpc of the autoload" % rpc_name)
		if not config.has(StringName(rpc_name)):
			continue
		var found: Dictionary = config[StringName(rpc_name)]
		var actual: Array = [int(found.get("rpc_mode", -1)), bool(found.get("call_local", false)),
				int(found.get("transfer_mode", -1)), int(found.get("channel", 0))]
		_expect(actual == RPCS[rpc_name], "%s has rpc_mode, call_local, transfer_mode, channel %s (got %s)"
				% [rpc_name, RPCS[rpc_name], actual])
	_expect(config.size() == RPCS.size(), "The autoload has exactly %d RPCs (got %d: %s)"
			% [RPCS.size(), config.size(), config.keys()])


func _check_api(manager: Node, script: GDScript) -> void:
	for method: String in METHODS:
		_expect(manager.has_method(StringName(method)), "The autoload still has %s()" % method)
	for method: String in STATIC_METHODS:
		var found: bool = false
		for entry: Dictionary in script.get_script_method_list():
			if entry.name == method and (int(entry.flags) & METHOD_FLAG_STATIC) != 0:
				found = true
		_expect(found, "The autoload still has the static %s()" % method)
	var properties: PackedStringArray = []
	for property: Dictionary in manager.get_property_list():
		properties.append(String(property.name))
	for variable: String in VARS:
		_expect(variable in properties, "The autoload still has the var %s" % variable)
	var constants: Dictionary = script.get_script_constant_map()
	for constant_name: String in CONSTANTS:
		_expect(constants.has(constant_name), "The autoload still has the constant %s" % constant_name)
		_expect(constants.get(constant_name) == CONSTANTS[constant_name], "%s keeps its value %s (got %s)"
				% [constant_name, str(CONSTANTS[constant_name]), str(constants.get(constant_name))])
	_expect(script.plan_deadlines([100.0]) == [{"house": 0, "seconds": 22.0, "reason": "HUD_DEADLINE_REASON_LEAVING"}],
			"plan_deadlines() still plans from the class")
	_expect(script.handed_over(&"delivered_ok") and not script.handed_over(&"missed")
			and not script.handed_over(&"lost"), "handed_over() still answers from the class")


func _check_helpers() -> void:
	_expect(_autoload_names().has("RunManager"), "project.godot autoloads are readable")
	for helper: String in HELPERS:
		var path: String = "res://scripts/core/%s.gd" % helper
		_expect(load(path) is GDScript, "%s loads" % path)
		var code: String = ""
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			code += line.get_slice("#", 0) + "\n"
		for autoload: String in _autoload_names():
			_expect(not code.contains(autoload), "%s names no autoload in code (found %s)" % [path, autoload])
		_expect(not code.contains("class_name"), "%s has no class_name: only run_manager.gd loads it" % path)


## The helpers on small inputs, worked out from the original code.
func _check_pure_helpers() -> void:
	var deadlines: GDScript = load("res://scripts/core/run_deadlines.gd")
	var planned: Array = deadlines.plan([100.0, 250.0, 400.0, 900.0])
	_expect(planned == [
		{"house": 0, "seconds": 22.0, "reason": "HUD_DEADLINE_REASON_LEAVING"},
		{"house": 1, "seconds": 59.0, "reason": "HUD_DEADLINE_REASON_BIRTHDAY"},
		{"house": 2, "seconds": 95.0, "reason": "HUD_DEADLINE_REASON_SHOP"},
	], "Three deadlines at most, 15 s + distance / 13.5 + 25 s per earlier stop (got %s)" % str(planned))
	var open_list: Array = [{"house": 0, "seconds": 40.0}, {"house": 1, "seconds": 60.0},
			{"house": 2, "seconds": 30.0}]
	var records: Array = [{"house": 2, "outcome": &"delivered_ok", "at": 20.0}]
	_expect(deadlines.next_open(open_list, records, 10.0) == open_list[0],
			"The next deadline skips the delivered house and takes the closest open one")
	_expect(deadlines.next_open(open_list, records, 100.0).is_empty(), "No deadline is next once all have passed")
	_expect(deadlines.tally(open_list, records) == {"met": 1, "missed": 2}, "Only the delivered-in-time one is met")

	var deliveries: GDScript = load("res://scripts/core/run_deliveries.gd")
	var door_records: Array = [
		{"house": 0, "outcome": &"delivered_at_risk", "package_id": &"a", "photo": false},
		{"house": 1, "outcome": &"missed", "package_id": &"b", "photo": false},
		{"house": 2, "outcome": &"delivered_ok", "package_id": &"c", "photo": false},
	]
	_expect(deliveries.delivered_at(door_records, 0) and not deliveries.delivered_at(door_records, 1)
			and not deliveries.delivered_at(door_records, 9), "A house counts as delivered unless missed or absent")
	_expect(deliveries.claim_package_at(door_records, 0) == &"a" and deliveries.claim_package_at(door_records, 2) == &""
			and deliveries.claim_package_at(door_records, 9) == &"", "Only a dented or ruined door has a box to claim")
	_expect(not deliveries.mark_photo(door_records, 1) and not deliveries.mark_photo(door_records, 9),
			"No photo is filed against a missed or absent house")
	_expect(deliveries.mark_photo(door_records, 0) and bool(door_records[0]["photo"]),
			"A delivered house takes the photo")
	_expect(not deliveries.mark_photo(door_records, 0), "...once")

	var results_script: GDScript = load("res://scripts/core/run_results.gd")
	_expect(results_script.route_event(&"", {}, true) == {}, "No route event, no row")
	_expect(results_script.route_event(&"x", {"title": "T"}, true) == {"id": &"x", "title": "T", "success": true}
			and results_script.route_event(&"y", {}, false) == {"id": &"y", "title": "y", "success": false},
			"The route event row has its id, title (or the id) and result")

	var leaderboard: GDScript = load("res://scripts/core/run_leaderboard.gd")
	var board: Array = []
	for score: int in 12:
		board = leaderboard.add(board, score, &"delivery", 2)
	board = leaderboard.add(board, 5, &"endless", 1)
	var by_mode: Dictionary = {}
	for entry: Dictionary in board:
		by_mode[entry["mode"]] = int(by_mode.get(entry["mode"], 0)) + 1
	_expect(by_mode == {&"delivery": 10, &"endless": 1}, "The cap is per mode (got %s)" % str(by_mode))
	var sorted_best_first: bool = true
	for index: int in range(1, board.size()):
		sorted_best_first = sorted_best_first and int(board[index - 1]["score"]) >= int(board[index]["score"])
	_expect(sorted_best_first and int(board[0]["score"]) == 11 and board.size() == 11,
			"Sorted best-first, 10 deliveries (11 down to 2) and the endless one")
	_expect(leaderboard.best_score(board, &"delivery") == 11 and leaderboard.best_score(board, &"endless") == 5
			and leaderboard.best_score([], &"delivery") == 0, "best_score() looks per mode")
	_expect(leaderboard.best_score([{"score": 7}], &"delivery") == 7,
			"An entry without a mode is a delivery score (old saves)")
	_expect(str(leaderboard.MODE_DELIVERY) == "delivery", "The board's delivery mode is the autoload's")


## Three runs through the real finish_run(), scored by hand from the original code.
func _check_runs(manager: Node) -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var bus: Node = root.get_node(^"/root/EventBus")
	var saved_path: Variant = manager.get(&"save_path")
	manager.set(&"save_path", TEST_SAVE_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	manager.set(&"leaderboard", [])
	crew.call(&"reset_campaign")
	root.get_node(^"/root/UnlockManager").call(&"reset_profile")
	var ended: Array = []
	bus.connect(&"run_ended", func(score: int, _results: Dictionary) -> void: ended.append(score))

	# 1. A delivery run with every kind of door: 6 promised, 5 recorded, one house the crew refused.
	manager.call(&"reset_run")
	manager.set(&"is_running", true)
	manager.set(&"elapsed_seconds", 123.5)
	manager.set(&"expected_houses", 6)
	manager.set(&"had_simultaneous_risk", true)
	manager.set(&"refused_houses", {5: true})
	manager.set(&"house_assignments", [[&"p0", "HUD_TRAP_FRAGILE"], [&"pkg_b", "HUD_TRAP_LIQUID"]])
	manager.set(&"cargo_names", {&"pkg_b": "HUD_NAMED_B"})
	manager.set(&"cargo", {
		&"a": {"integrity": 100.0, "maximum": 100.0, "state": 0, "care": {"kind": &"fragile", "repairs": 2}},
		&"b": {"integrity": 60.0, "maximum": 100.0, "state": 1},
		&"c": {"integrity": 0.0, "maximum": 100.0, "state": 2},
		&"d": {"integrity": 100.0, "maximum": 100.0, "state": 0, "delivered": true},
	})
	var records: Array = manager.get(&"deliveries")
	records.append({"house": 0, "outcome": &"delivered_ok", "package_id": &"p0", "photo": true, "care": &"",
			"opened": false, "at": 30.0})
	records.append({"house": 1, "outcome": &"delivered_at_risk", "package_id": &"pkg_b", "photo": false,
			"care": &"", "opened": false, "at": 70.0})
	records.append({"house": 2, "outcome": &"delivered_ruined", "package_id": &"p2", "photo": true, "care": &"",
			"opened": false, "at": 90.0})
	records.append({"house": 3, "outcome": &"delivered_ok", "package_id": &"p3", "photo": true,
			"care": &"repaired", "opened": false, "at": 95.0})
	records.append({"house": 4, "outcome": &"lost", "package_id": &"p4", "photo": false, "care": &"",
			"opened": false, "at": 100.0})
	manager.set(&"deadlines", [
		{"house": 0, "seconds": 40.0, "reason": "HUD_DEADLINE_REASON_LEAVING"},
		{"house": 1, "seconds": 60.0, "reason": "HUD_DEADLINE_REASON_BIRTHDAY"},
		{"house": 2, "seconds": 100.0, "reason": "HUD_DEADLINE_REASON_SHOP"},
		{"house": 4, "seconds": 200.0, "reason": "HUD_DEADLINE_REASON_LEAVING"},
	])
	manager.call(&"finish_run", true, "HUD_RUN_ARRIVED")
	var results: Dictionary = manager.get(&"results")
	_expect_fields(results, {
		"delivered": true, "reason": "HUD_RUN_ARRIVED", "elapsed_seconds": 123.5, "cargo_total": 3,
		"cargo_intact": 1, "cargo_ruined": 1, "cargo_points": 150, "chaos_multiplier": 1.2,
		"delivery_points": 320, "houses_delivered": 4, "houses_missed": 1, "houses_lost": 1, "photos": 3,
		"score": 564, "is_new_best": true, "best_score": 564,
	}, "Delivery run")
	_expect(results.get("breakdown") == [
		{"label": "HUD_SCORE_PERFECT", "count": 1, "points": 150},
		{"label": "HUD_SCORE_DENTED", "count": 1, "points": 75},
		{"label": "HUD_SCORE_RUINED", "count": 1, "points": 20},
		{"label": "HUD_SCORE_REPAIRED", "count": 1, "points": 110},
		{"label": "HUD_SCORE_DEADLINE_MET", "count": 2, "points": 80},
		{"label": "HUD_SCORE_DEADLINE_MISSED", "count": 2, "points": -30},
		{"label": "HUD_SCORE_PHOTOS", "count": 3, "points": 75},
		{"label": "HUD_SCORE_MISSED", "count": 1, "points": -60},
		{"label": "HUD_SCORE_LOST", "count": 1, "points": -60},
		{"label": "HUD_SCORE_COMPLAINTS", "count": 1, "points": -40},
		{"label": "HUD_SCORE_CARGO_BACK", "count": 2, "points": 150},
	], "Delivery run: the breakdown lines, in order (got %s)" % str(results.get("breakdown")))
	var complaints: Array = results.get("complaints", [])
	_expect(complaints.size() == 3,
			"Delivery run: a dented, a ruined and a wrong-box complaint (got %d)" % complaints.size())
	if complaints.size() == 3:
		_expect(int(complaints[0]["house"]) == 1 and StringName(complaints[0]["result"]) == &"at_risk"
				and not bool(complaints[0]["dismissed"]), "Delivery run: the dented door's complaint is open")
		_expect(int(complaints[1]["house"]) == 2 and StringName(complaints[1]["result"]) == &"ruined"
				and bool(complaints[1]["dismissed"]), "Delivery run: the ruined door's photo settles it")
		_expect(int(complaints[2]["house"]) == 5 and StringName(complaints[2]["result"]) == &"wrong"
				and bool(complaints[2]["dismissed"]), "Delivery run: the refused house keeps a settled note")
	var stories: Array = results.get("stories", [])
	var repaired_story: String = String(TranslationServer.translate("HUD_STORY_REPAIRED")) \
			% [String(TranslationServer.translate("HUD_RESCUE_VASE")), 2]
	_expect(stories == [repaired_story], "Delivery run: one story, the repaired vase (got %s)" % str(stories))
	_expect(results.get("route_event") == {}, "Delivery run: no route event was drawn")
	var rows: Array = results.get("deliveries", [])
	var fallback: String = "HUD_RESULT_PACKAGE_FALLBACK"
	_expect(rows == [
		{"house": 0, "package_id": &"p0", "trap": "HUD_TRAP_FRAGILE", "outcome": &"delivered_ok", "photo": true},
		{"house": 1, "package_id": &"pkg_b", "trap": "HUD_NAMED_B", "outcome": &"delivered_at_risk", "photo": false},
		{"house": 2, "package_id": &"p2", "trap": fallback, "outcome": &"delivered_ruined", "photo": true},
		{"house": 3, "package_id": &"p3", "trap": fallback, "outcome": &"delivered_ok", "photo": true},
		{"house": 4, "package_id": &"p4", "trap": fallback, "outcome": &"lost", "photo": false},
		{"house": 5, "package_id": &"", "trap": fallback, "outcome": &"missed", "photo": false},
	], "Delivery run: one row per promised stop (got %s)" % str(rows))

	# 2. A failed run: nothing delivered, two doors never reached, the cargo counts as lost.
	manager.call(&"reset_run")
	manager.set(&"is_running", true)
	manager.set(&"expected_houses", 2)
	manager.set(&"cargo", {
		&"x": {"integrity": 100.0, "maximum": 100.0, "state": 0},
		&"y": {"integrity": 60.0, "maximum": 100.0, "state": 1},
	})
	manager.call(&"finish_run", false, "HUD_RUN_TIPPED")
	results = manager.get(&"results")
	_expect_fields(results, {
		"delivered": false, "reason": "HUD_RUN_TIPPED", "cargo_total": 2, "cargo_intact": 0, "cargo_ruined": 2,
		"cargo_points": 0, "chaos_multiplier": 1.0, "delivery_points": -120, "houses_delivered": 0,
		"houses_missed": 2, "houses_lost": 0, "photos": 0, "score": 0, "is_new_best": false, "best_score": 564,
	}, "Failed run")
	_expect(results.get("breakdown") == [{"label": "HUD_SCORE_MISSED", "count": 2, "points": -120}],
			"Failed run: the two doors never reached are the only line (got %s)" % str(results.get("breakdown")))
	_expect((results.get("complaints") as Array).is_empty() and (results.get("stories") as Array).is_empty(),
			"Failed run: no complaints, no stories")
	_expect((results.get("deliveries") as Array).size() == 2, "Failed run: a row per promised stop")

	# 3. Endless: the meters each box survived, averaged: (100 + 40) / 2.
	manager.call(&"reset_run")
	manager.set(&"is_running", true)
	manager.set(&"current_mode", &"endless")
	manager.set(&"current_distance", 100.0)
	manager.set(&"cargo", {
		&"x": {"integrity": 100.0, "maximum": 100.0, "state": 0},
		&"y": {"integrity": 0.0, "maximum": 100.0, "state": 2, "ruined_at_m": 40.0},
	})
	manager.call(&"finish_run", false, "HUD_RUN_TIPPED")
	results = manager.get(&"results")
	_expect_fields(results, {
		"delivered": false, "reason": "HUD_RUN_TIPPED", "cargo_total": 2, "cargo_intact": 1, "cargo_ruined": 1,
		"distance_traveled": 100.0, "score": 70, "is_new_best": true, "best_score": 70,
	}, "Endless run")
	_expect(ended == [564, 0, 70], "run_ended told the score of each run (got %s)" % str(ended))

	# The board kept the three, best first, and saved them where the test said.
	var board: Array = manager.get(&"leaderboard")
	var scores: Array = []
	for entry: Dictionary in board:
		scores.append([int(entry["score"]), StringName(entry["mode"]), int(entry["crew_size"]) >= 1])
	_expect(scores == [[564, &"delivery", true], [70, &"endless", true], [0, &"delivery", true]],
			"The leaderboard has the three runs best first (got %s)" % str(scores))
	manager.set(&"leaderboard", [])
	manager.call(&"_load_leaderboard")
	_expect((manager.get(&"leaderboard") as Array).size() == 3, "...and they were saved to the board's file")

	manager.call(&"reset_run")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	manager.set(&"save_path", saved_path)
	manager.set(&"leaderboard", [])
	crew.call(&"reset_campaign")


func _expect_fields(results: Dictionary, expected: Dictionary, label: String) -> void:
	for key: String in expected:
		_expect(results.has(key), "%s: the results have %s" % [label, key])
		if results.has(key):
			var found: Variant = results[key]
			var matches: bool = is_equal_approx(float(found), float(expected[key])) \
					if (expected[key] is float) else (found == expected[key])
			_expect(matches, "%s: %s is %s (got %s)" % [label, key, str(expected[key]), str(found)])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


## Every autoload in project.godot: no helper may name one in code (comments aside).
func _autoload_names() -> Array[String]:
	var names: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var key: String = property.get("name", "")
		if key.begins_with("autoload/"):
			names.append(key.trim_prefix("autoload/"))
	return names
