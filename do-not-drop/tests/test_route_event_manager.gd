extends SceneTree

var failures := 0

func _initialize() -> void:
	var crew: Node = load("res://scripts/core/crew_progression.gd").new()
	crew.name = "CrewProgression"
	get_root().add_child(crew)
	var events: Node = load("res://scripts/core/route_event_manager.gd").new()
	events.name = "RouteEventManager"
	events.crew_progression = crew
	get_root().add_child(events)
	crew.reset_campaign()
	_expect(events.begin_event(&"rear_door_jam") == &"rear_door_jam", "A named route event starts")
	_expect(not events.resolve_active(2, &"wrong_action"), "Wrong action cannot resolve an event")
	_expect(events.resolve_active(2, &"free_rear_door"), "Correct cooperative action resolves an event")
	_expect(int(crew.merit.get(2, 0)) == 20, "Route rescue awards individual merit")
	_expect(int(crew.team_money) == 115, "Route rescue rewards shared money")
	_expect(events.active_event_id.is_empty(), "Resolved event is cleared")
	if failures == 0:
		print("PASS: route events reward the team and the helpful player")
	quit(failures)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
