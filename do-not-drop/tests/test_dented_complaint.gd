extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dented_complaint.gd
## N-227.2: a box handed over dented ALWAYS draws a complaint (it used to be a
## 50 % roll, which made the results depend on luck). Only the delivery photo
## settles it. Forty real runs through RunManager.finish_run, every one the same,
## and the team is paid for the dented door (75) minus the unanswered complaint (40).

const RUNS: int = 40

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var bus: Node = root.get_node(^"/root/EventBus")
	var run_script: GDScript = load("res://scripts/core/run_manager.gd")
	root.get_node(^"/root/UnlockManager").call(&"reset_profile")
	var without_complaint: int = 0
	for _attempt: int in RUNS:
		crew.call(&"reset_campaign")
		manager.call(&"reset_run")
		manager.set(&"expected_houses", 1)
		manager.call(&"start_run")
		bus.emit_signal(&"cargo_registered", &"dented", "HUD_TRAP_FRAGILE")
		manager.set(&"cargo", {&"dented": {"integrity": 40.0, "maximum": 100.0, "state": 1}})
		manager.call(&"register_delivery", 0, &"delivered_at_risk", &"dented")
		manager.call(&"finish_run", true)
		var complaints: Array = (manager.get(&"results") as Dictionary).get("complaints", [])
		if complaints.size() != 1:
			without_complaint += 1
			continue
		var complaint: Dictionary = complaints[0]
		_expect(StringName(complaint["result"]) == &"at_risk" and not bool(complaint["dismissed"]),
				"The dented box's complaint is open and about a dented box (got %s)" % str(complaint))
	_expect(without_complaint == 0,
			"Every dented delivery complains, no dice (%d of %d had none)" % [without_complaint, RUNS])

	# The payout counts the door points net of the complaint it cost.
	var results: Dictionary = manager.get(&"results")
	var expected: int = int(run_script.POINTS_DELIVERED_AT_RISK) - int(run_script.COMPLAINT_PENALTY)
	_expect(int(results.get("delivery_points", 0)) == expected,
			"Dented door: 75 points minus the 40 of the open complaint (got %s)" % str(results.get("delivery_points")))
	_expect(int(crew.get(&"team_money")) == int(crew.get(&"STARTING_MONEY")) + expected,
			"The wallet got those points (got $%d)" % int(crew.get(&"team_money")))

	# With the photo, the complaint still exists but is settled and costs nothing.
	crew.call(&"reset_campaign")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 1)
	manager.call(&"start_run")
	manager.set(&"cargo", {&"dented": {"integrity": 40.0, "maximum": 100.0, "state": 1}})
	manager.call(&"register_delivery", 0, &"delivered_at_risk", &"dented")
	manager.call(&"attach_delivery_photo", 0)
	manager.call(&"finish_run", true)
	results = manager.get(&"results")
	var settled: Array = results.get("complaints", [])
	_expect(settled.size() == 1 and bool((settled[0] as Dictionary)["dismissed"]),
			"A photographed dented delivery keeps a settled complaint (got %s)" % str(settled))
	var settled_points: int = int(run_script.POINTS_DELIVERED_AT_RISK) + int(run_script.POINTS_PHOTO_BONUS)
	_expect(int(results.get("delivery_points", 0)) == settled_points,
			"The settled complaint costs nothing (got %s)" % str(results.get("delivery_points")))
	manager.call(&"reset_run")
	crew.call(&"reset_campaign")
	if _failures == 0:
		print("PASS: a dented delivery always draws a complaint; only the photo settles it")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
