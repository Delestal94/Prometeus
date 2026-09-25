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
	_expect(events.ROUTE_POOL.size() == 5, "Drawable pool has five events (got %s)" % [events.ROUTE_POOL])
	_expect(not events.ROUTE_POOL.has(&"rear_door_jam") and not events.ROUTE_POOL.has(&"confusing_shop"), "Unplayable events stay out of draw (got %s)" % [events.ROUTE_POOL])
	_expect(events.begin_event(&"rear_door_jam") == &"rear_door_jam", "Named event remains available (got %s)" % events.active_event_id)
	_expect(not events.resolve_active(2, &"wrong_action"), "Wrong action cannot resolve event (got %s)" % events.active_event_id)
	_expect(events.resolve_active(2, &"free_rear_door"), "Correct action resolves event (got %s)" % events.active_event_id)
	_expect(int(crew.merit.get(2, 0)) == 20, "Helper earns individual merit (got %s)" % crew.merit)
	_expect(int(crew.team_money) == 115, "Team earns shared reward (got %s)" % crew.team_money)
	_expect(events.active_snapshot().is_empty(), "Resolved event has no late-join snapshot (got %s)" % events.active_snapshot())
	events.reset_route()
	_expect(events.begin_event(&"inspection") == &"inspection", "Inspection starts after reset (got %s)" % events.active_event_id)
	var snapshot: Dictionary = events.active_snapshot()
	_expect(snapshot.get("id") == &"inspection", "Snapshot carries live event (got %s)" % snapshot)
	events.load_snapshot({})
	_expect(events.active_event_id.is_empty(), "Empty snapshot cannot revive stale event (got %s)" % events.active_event_id)
	if failures == 0:
		print("PASS: route events reward the team and the helpful player")
	quit(failures)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
