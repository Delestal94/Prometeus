extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_endless_cargo_score.gd
## Endless scores the cargo, not only the distance (N-118): the score is the
## meters each box survived, averaged over the boxes. All intact scores the
## plain distance, so records from before N-118 stay comparable.

const TEST_SAVE_PATH: String = "user://test_endless_cargo_score.json"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	manager.set(&"save_path", TEST_SAVE_PATH)
	_cleanup()

	# Four boxes; two are lost on the way, at 100 m and 300 m.
	_start(manager, [&"a", &"b", &"c", &"d"])
	manager.set(&"current_distance", 100.0)
	bus.emit_signal(&"package_ruined", &"a", "test")
	manager.set(&"current_distance", 300.0)
	bus.emit_signal(&"package_ruined", &"b", "test")
	_expect(bool(manager.get(&"is_running")), "Losing two of four boxes doesn't end the run")
	manager.set(&"current_distance", 1000.0)
	manager.call(&"finish_run", false, "HUD_RUN_ALL_CARGO_RUINED")
	var results: Dictionary = manager.get(&"results")
	var expected: int = roundi((100.0 + 300.0 + 1000.0 + 1000.0) / 4.0)
	_expect(int(results.get("score", -1)) == expected,
		"Score is the meters each box survived, averaged (%d, got %d)" % [expected, int(results.get("score", -1))])
	_expect(int(results.get("cargo_ruined", -1)) == 2 and int(results.get("cargo_intact", -1)) == 2,
		"The results still count intact and ruined boxes")
	var careless: int = int(results.get("score", 0))

	# Same distance, every box intact: the plain distance, as before N-118.
	_start(manager, [&"a", &"b", &"c", &"d"])
	manager.set(&"current_distance", 1000.0)
	manager.call(&"finish_run", false, "HUD_RUN_ALL_CARGO_RUINED")
	var careful: int = int((manager.get(&"results") as Dictionary).get("score", -1))
	_expect(careful == 1000, "All boxes intact scores exactly the distance (got %d)" % careful)
	_expect(careful > careless, "Keeping the cargo beats losing it over the same distance")

	# No cargo at all (a solo warm-up): still the distance.
	_start(manager, [])
	manager.set(&"current_distance", 250.0)
	manager.call(&"finish_run", false, "HUD_RUN_ALL_CARGO_RUINED")
	_expect(int((manager.get(&"results") as Dictionary).get("score", -1)) == 250,
		"With no cargo the score is the distance")

	manager.call(&"reset_run")
	_cleanup()
	if _failures == 0:
		print("PASS: Endless scores the meters each box survived")
	quit(_failures)


func _start(manager: Node, ids: Array) -> void:
	manager.call(&"reset_run")
	manager.call(&"start_run", &"endless")
	var cargo: Dictionary = {}
	for id: StringName in ids:
		cargo[id] = {"integrity": 100.0, "maximum": 100.0, "state": 0}
	manager.set(&"cargo", cargo)


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
