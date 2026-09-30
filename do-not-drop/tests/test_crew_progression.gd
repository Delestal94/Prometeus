extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_crew_progression.gd
## The crew's campaign economy: shop money is shared, a delivery pays the team,
## merit (and rescue credit) stays personal, and a voted purchase spends the
## cooperative wallet.
##
## Two layers on purpose:
## - the wallet itself (crew_progression.gd), fed a results dictionary whose
##   values a real run can reach (time_bonus is 0 once a delivery outlasts
##   RunManager.PAR_SECONDS, which every real delivery does);
## - a real delivery through the RunManager autoload (run_manager.gd
##   finish_run -> CrewProgression.award_delivery): one box handed over at a
##   door, one still aboard and intact, a realistic 130 s run. The team wallet
##   has to rise by what the current payout formula reads from the results.
##   Which results fields SHOULD pay is decided in N-227.2 (docs/tareas-nacho.md);
##   this check follows whatever award_delivery pays, so it does not need to
##   change with that decision beyond its expected sum.

const REAL_RUN_SECONDS: float = 130.0

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var crew: Node = root.get_node(^"/root/CrewProgression")
	crew.call(&"reset_campaign")
	_expect(int(crew.get(&"team_money")) == 100, "Campaign starts with shared shop money")
	_expect(crew.call(&"award_action", 2, &"recover_box_1", 15), "A useful action grants merit")
	_expect(not crew.call(&"award_action", 2, &"recover_box_1", 15), "The same rescue is not farmable")
	_expect(int((crew.get(&"merit") as Dictionary)[2]) == 15, "Merit remains personal")
	crew.call(&"award_delivery", {"cargo_points": 100, "time_bonus": 0}, [1, 2])
	_expect(int(crew.get(&"team_money")) == 200,
			"Delivery payout belongs to the team (got %d)" % int(crew.get(&"team_money")))
	_expect(crew.call(&"spend", 50) and int(crew.get(&"team_money")) == 150,
			"A voted purchase spends cooperative money")
	_expect(not crew.call(&"spend", 151), "Cannot overspend team money")
	_check_real_delivery(crew)
	crew.call(&"reset_campaign")
	if failures == 0:
		print("PASS: shared money, personal merit and delivery rewards")
	quit(failures)


## A whole delivery-mode run through the real RunManager, not a hand-made
## results dictionary.
func _check_real_delivery(crew: Node) -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var bus: Node = root.get_node(^"/root/EventBus")
	var run_script: GDScript = load("res://scripts/core/run_manager.gd")
	root.get_node(^"/root/UnlockManager").call(&"reset_profile")
	crew.call(&"reset_campaign")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 1)
	manager.call(&"start_run")
	bus.emit_signal(&"cargo_registered", &"door", "HUD_TRAP_FRAGILE")
	bus.emit_signal(&"cargo_registered", &"aboard", "HUD_TRAP_BALANCE")
	manager.set(&"cargo", {
		&"door": {"integrity": 100.0, "maximum": 100.0, "state": 0},
		&"aboard": {"integrity": 100.0, "maximum": 100.0, "state": 0},
	})
	manager.call(&"register_delivery", 0, &"delivered_ok", &"door")
	manager.set(&"elapsed_seconds", REAL_RUN_SECONDS)
	var before: int = int(crew.get(&"team_money"))
	manager.call(&"finish_run", true)
	var results: Dictionary = manager.get(&"results")
	var gained: int = int(crew.get(&"team_money")) - before
	var expected: int = int(results.get("cargo_points", 0)) + int(results.get("time_bonus", 0))
	_expect(bool(results.get("delivered", false)),
			"The real run ends as a delivery (got %s)" % _got(results, "delivered"))
	_expect(int(results.get("houses_delivered", 0)) == 1,
			"The door counts as delivered (got %s)" % _got(results, "houses_delivered"))
	_expect(int(results.get("cargo_intact", 0)) == 1,
			"The box still aboard is intact (got %s)" % _got(results, "cargo_intact"))
	_expect(int(results.get("cargo_points", 0)) == int(run_script.POINTS_INTACT),
			"The aboard box scores its intact points (got %s)" % _got(results, "cargo_points"))
	_expect(int(results.get("delivery_points", 0)) > 0,
			"The handed-over door scores delivery points (got %s)" % _got(results, "delivery_points"))
	_expect(float(results.get("elapsed_seconds", 0.0)) >= REAL_RUN_SECONDS,
			"The run lasted a realistic time (got %s)" % _got(results, "elapsed_seconds"))
	_expect(gained > 0, "A real delivery raises the team wallet (got +%d)" % gained)
	_expect(gained == expected,
			"The wallet rises by the payout the results carry (got +%d, expected +%d)" % [gained, expected])
	manager.call(&"reset_run")


func _got(results: Dictionary, key: String) -> String:
	return str(results.get(key))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
