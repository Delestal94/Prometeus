extends SceneTree

var failures := 0

func _initialize() -> void:
	var crew: Node = load("res://scripts/core/crew_progression.gd").new()
	crew.name = "CrewProgression"
	get_root().add_child(crew)
	crew.reset_campaign()
	_expect(int(crew.team_money) == 100, "Campaign starts with shared shop money")
	_expect(crew.award_action(2, &"recover_box_1", 15), "A useful action grants merit")
	_expect(not crew.award_action(2, &"recover_box_1", 15), "The same rescue is not farmable")
	_expect(int(crew.merit[2]) == 15, "Merit remains personal")
	crew.award_delivery({"cargo_points": 100, "time_bonus": 20}, [1, 2])
	_expect(int(crew.team_money) == 220, "Delivery payout belongs to the team")
	_expect(crew.spend(50) and int(crew.team_money) == 170, "A voted purchase spends cooperative money")
	_expect(not crew.spend(171), "Cannot overspend team money")
	if failures == 0:
		print("PASS: shared money, personal merit and delivery rewards")
	quit(failures)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
