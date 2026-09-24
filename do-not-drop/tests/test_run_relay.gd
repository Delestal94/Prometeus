extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_run_relay.gd
##
## Online, a run starts and ends on the host (interactions resolve there), and
## a client used to hear neither: no results screen, and its own profile never
## counted the delivery. The host now hands both over (RunManager
## _remote_start_run / _remote_finish_run). This covers the client's half:
##   - the start arrives with the route event the host drew, not a new draw;
##   - the results are the host's, as they are, while the leaderboard entry
##     and the new-best flag are this player's own;
##   - the client's profile counts the run (UnlockManager hears run_ended),
##     and the team's money isn't paid out a second time.

const TEST_SAVE_PATH: String = "user://test_run_relay_leaderboard.json"

var _failures: int = 0
var _started: int = 0
var _ended: Array = []
var _events: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var route_events: Node = root.get_node(^"/root/RouteEventManager")
	manager.set(&"save_path", TEST_SAVE_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	manager.set(&"leaderboard", [])
	manager.call(&"reset_run")
	unlocks.call(&"reset_profile")
	bus.connect(&"run_started", func(_route: StringName, _players: Array) -> void: _started += 1)
	bus.connect(&"run_ended", func(score: int, results: Dictionary) -> void: _ended.append([score, results]))
	bus.connect(&"route_event_started", func(event_id: StringName, _event: Dictionary) -> void: _events.append(event_id))

	# The host's start, as a client receives it.
	manager.call(&"_remote_start_run", &"delivery", &"rear_door_jam")
	_expect(bool(manager.get(&"is_running")) and _started == 1, "The host's start runs the client's run too")
	_expect(_events == [&"rear_door_jam"] and route_events.get(&"active_event_id") == &"rear_door_jam",
		"The client plays the route event the host drew, not one of its own (got %s)" % str(_events))
	manager.call(&"_remote_start_run", &"delivery", &"inspection")
	_expect(_started == 1, "A repeated start doesn't start the run twice")

	# The host's results, as a client receives them.
	var money_before: int = int(crew.get(&"team_money"))
	var runs_before: int = int(unlocks.get(&"completed_runs"))
	var host_results: Dictionary = {
		"delivered": true, "reason": "", "score": 240, "cargo_points": 100, "time_bonus": 20,
		"breakdown": [{"label": "Casa 1 — intacto", "points": 150}, {"label": "Rapidez", "points": 20}],
		"houses_delivered": 1, "is_new_best": false, "best_score": 900,
	}
	manager.call(&"_remote_finish_run", &"delivery", host_results)
	_expect(not bool(manager.get(&"is_running")), "The client's run is over")
	_expect(_ended.size() == 1 and int(_ended[0][0]) == 240, "run_ended reaches the client with the host's score")
	var results: Dictionary = manager.get(&"results")
	_expect((results.get("breakdown") as Array).size() == 2 and bool(results.get("delivered")), "Same breakdown and outcome as the host's")
	_expect(bool(results.get("is_new_best")) and int(results.get("best_score")) == 240,
		"New best and best score are the client's own leaderboard's, not the host's (%s / %d)" % [str(results.get("is_new_best")), int(results.get("best_score"))])
	_expect((manager.get(&"leaderboard") as Array).size() == 1, "The run lands in the client's own leaderboard")
	_expect(int(unlocks.get(&"completed_runs")) == runs_before + 1, "The client's profile counts the run")
	_expect(int(crew.get(&"team_money")) == money_before, "The team's money isn't paid out again on the client")
	manager.call(&"_remote_finish_run", &"delivery", host_results)
	_expect(_ended.size() == 1, "A repeated finish doesn't end the run twice")

	manager.call(&"reset_run")
	unlocks.call(&"reset_profile")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	if _failures == 0:
		print("PASS: a client follows the host's run start to finish, with its own leaderboard and profile")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
