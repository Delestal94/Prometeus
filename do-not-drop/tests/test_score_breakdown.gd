extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_score_breakdown.gd
## The results screen's itemised score (docs/tareas-slatex.md #89): every
## line comes from RunManager's own sums, so together (times the chaos
## multiplier) they always make exactly the score shown -- including the
## penalties for a door nobody reached. There is no speed line: the time bonus
## was removed in N-227.2, so the lines are doors + cargo + deadlines + photos.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager: Node = root.get_node(^"/root/RunManager")
	var crew: Node = root.get_node(^"/root/CrewProgression")
	var unlocks: Node = root.get_node(^"/root/UnlockManager")
	crew.call(&"reset_campaign")
	unlocks.call(&"reset_profile")
	manager.call(&"reset_run")
	manager.set(&"expected_houses", 4)
	manager.call(&"start_run")
	root.get_node(^"/root/EventBus").emit_signal(&"houses_assigned", [
		[&"a", "HUD_TRAP_FRAGILE", "A1"],
		[&"b", "HUD_TRAP_BALANCE", "B2"],
		[&"c", "HUD_TRAP_NOISY", "C3"],
		[&"d", "HUD_TRAP_GROWING_WEIGHT", "D4"],
	])
	root.get_node(^"/root/EventBus").emit_signal(&"cargo_registered", &"a", "HUD_TRAP_FRAGILE")
	root.get_node(^"/root/EventBus").emit_signal(&"cargo_registered", &"b", "HUD_TRAP_BALANCE")
	manager.set(&"cargo", {
		&"a": {"integrity": 100.0, "maximum": 100.0, "state": 0},
		&"b": {"integrity": 60.0, "maximum": 100.0, "state": 1},
	})
	manager.call(&"register_delivery", 0, &"delivered_ok", &"a")
	manager.call(&"attach_delivery_photo", 0)
	manager.call(&"register_delivery", 1, &"delivered_ruined", &"b")
	manager.call(&"register_delivery", 2, &"missed", &"c")
	crew.call(&"award_milestone", 1, &"a", &"rescued", 1)
	crew.call(&"award_milestone", 1, &"a", &"leveled", 1)
	crew.call(&"award_milestone", 2, &"b", &"defused", 1)
	crew.call(&"award_milestone", 2, &"c", &"defused", 1)
	manager.set(&"_event_id", &"inspection")
	var route_events: Node = root.get_node(^"/root/RouteEventManager")
	route_events.set(&"active_event_id", &"")
	var resolved_events: Dictionary = route_events.get(&"resolved_events")
	resolved_events[&"inspection"] = true
	manager.call(&"finish_run", true)
	var results: Dictionary = manager.get(&"results")
	var lines: Array = results.get("breakdown", [])
	var sum: int = 0
	var labels: PackedStringArray = []
	for line: Dictionary in lines:
		sum += int(line["points"])
		labels.append(String(line["label"]))
	var expected: int = maxi(roundi(sum * float(results["chaos_multiplier"])), 0)
	_expect(expected == int(results["score"]), "The lines add up to the score (%d x %.1f vs %d)" % [sum, float(results["chaos_multiplier"]), int(results["score"])])
	_expect("HUD_SCORE_MISSED" in labels and int(lines[labels.find("HUD_SCORE_MISSED")].get("count", 0)) == 2,
			"Both the skipped door and the one never reached cost points (%s)" % ", ".join(labels))
	_expect(not "HUD_SCORE_SPEED" in labels and not results.has("time_bonus"), "No time-bonus line or field any more")
	_expect("HUD_SCORE_PHOTOS" in labels, "The photo shows as its own line")
	var deliveries: Array = results.get("deliveries", [])
	_expect(deliveries.size() == 4, "There is one result row per promised house")
	_expect(String(deliveries[0].get("trap", "")) == "HUD_TRAP_FRAGILE" and bool(deliveries[0].get("photo", false)),
			"A row identifies its trap (as a key each peer translates) and delivery photo")
	_expect(String(deliveries[3].get("trap", "")) == "HUD_TRAP_GROWING_WEIGHT",
			"A house never reached still names its ordered trap by key")
	_expect(StringName(deliveries[3].get("outcome", &"")) == &"missed",
			"An unreached house is represented as a missed delivery")
	var route_event: Dictionary = results.get("route_event", {})
	_expect(StringName(route_event.get("id", &"")) == &"inspection" and bool(route_event.get("success", false)),
			"The result records how the route event ended")
	var award_titles: PackedStringArray = []
	for award: Dictionary in results.get("awards", []):
		award_titles.append(String(award.get("title", "")))
	_expect("HUD_AWARD_MVP" in award_titles and "HUD_AWARD_RESCUER" in award_titles
			and "HUD_AWARD_DEFUSER" in award_titles and "HUD_AWARD_STEADY_HAND" in award_titles,
			"Merit produces all four result awards")
	var next_unlock: Dictionary = unlocks.call(&"next_unlock_progress")
	_expect(not next_unlock.is_empty() and float(next_unlock.get("progress", -1.0)) >= 0.0,
			"The results can show progress toward the next unlock")
	var text: String = load("res://scripts/ui/hud/hud.gd").score_breakdown_text(results, int(results["score"]))
	_expect(text.contains("Total") and text.contains(str(int(results["score"]))), "The results text ends on the total")
	manager.call(&"reset_run")
	if _failures == 0:
		print("PASS: the itemised results always add up to the score")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
