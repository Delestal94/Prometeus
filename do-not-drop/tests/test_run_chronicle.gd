extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_run_chronicle.gd
##
## RunChronicle (scripts/presentation/newspaper/run_chronicle.gd) keeps the facts
## of the run from EventBus for the next-day newspaper (N-606.2):
## - it notes a missed door, an order the crew kept, a ruined delivery, a
##   substituted or taped box, a box that fell and one that came back, deer and
##   sheep, the van's faults and their repair, ruined boxes and photos, each
##   with the kind of box it was (what the house ordered, which trap);
## - it ignores what happens outside a run, a route event that isn't an incident
##   and a photo that wasn't accepted; a new run starts from nothing;
## - the results add what only they know (a door the run never reached, the
##   complaints, how a failed or Endless run ended);
## - the host writes the paper from the decided results and relays it as
##   newspaper_ready before anyone hears run_ended, ids and slots without text,
##   and the next paper avoids the variants of this one.

## Loaded when it runs, not preloaded: it names autoloads, which don't exist yet while this script compiles.
var _chronicle_script: GDScript
const DESK = preload("res://scripts/presentation/newspaper/news_desk.gd")
var _failures: int = 0
var _relayed: Array = []
var _order: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _kinds(chronicle: Node) -> Array:
	return chronicle.facts.map(func(fact: Dictionary) -> String: return String(fact["kind"]))


func _last(chronicle: Node, kind: String) -> Dictionary:
	for index: int in range(chronicle.facts.size() - 1, -1, -1):
		if chronicle.facts[index]["kind"] == kind:
			return chronicle.facts[index]
	return {}


func _run() -> void:
	_chronicle_script = load("res://scripts/presentation/newspaper/run_chronicle.gd")
	var bus: Node = root.get_node(^"/root/EventBus")
	var manager: Node = root.get_node(^"/root/RunManager")
	manager.call(&"reset_run")
	_chronicle_script.set(&"last_variants", {})
	bus.newspaper_ready.connect(func(paper: Dictionary) -> void:
		_relayed.append(paper)
		_order.append("paper"))
	bus.run_ended.connect(func(_score: int, _results: Dictionary) -> void: _order.append("ended"))
	var chronicle: Node = _chronicle_script.new()
	root.add_child(chronicle)
	await process_frame

	# Before the run starts nothing counts (boxes get dropped around the depot).
	bus.package_ruined.emit(&"hen_box", "dropped")
	_expect(chronicle.facts.is_empty(), "Nothing is noted before the run starts")

	bus.houses_assigned.emit([
		[&"p_hen", "HUD_TRAP_NOISY", "A1", &"hen"],
		[&"p_cake", "HUD_TRAP_BALANCE", "B2", &"wedding_cake"],
		[&"p_vase", "HUD_TRAP_FRAGILE", "C3", &"porcelain_vase"],
		[&"p_milk", "HUD_TRAP_LIQUID", "D4", &"milk_canister"],
	])
	bus.cargo_registered.emit(&"p_hen", "HUD_TRAP_NOISY")
	bus.cargo_registered.emit(&"p_cake", "HUD_TRAP_BALANCE")
	bus.run_started.emit(&"test_route", [1])

	bus.house_delivery_recorded.emit(1, &"missed", &"p_cake")
	var missed: Dictionary = _last(chronicle, "missed")
	_expect(missed.get("house") == 1 and "cake" in missed["tags"] and "balance" in missed["tags"],
			"A missed door notes the house and what it ordered (got %s)" % str(missed))
	bus.house_delivery_recorded.emit(0, &"lost", &"p_hen")
	_expect(_last(chronicle, "abandoned").get("tags") == ["hen", "noisy"],
			"An order the crew kept notes a hen and its trap (got %s)" % str(_last(chronicle, "abandoned")))
	bus.house_delivery_recorded.emit(2, &"delivered_ruined", &"p_vase")
	var ruined_door: Dictionary = _last(chronicle, "delivered_ruined")
	_expect(not ruined_door.is_empty() and "vase" in ruined_door["tags"],
			"A ruined delivery is noted with its family")
	bus.house_delivery_recorded.emit(3, &"delivered_ok", &"p_milk")
	_expect(not _last(chronicle, "delivered_ok").is_empty(), "A good delivery is noted too")
	bus.delivery_care_noted.emit(0, &"substituted")
	bus.delivery_care_noted.emit(1, &"repaired")
	_expect(not _last(chronicle, "substituted").is_empty() and not _last(chronicle, "repaired_tape").is_empty(),
			"A substitute and a repair are noted (%s)" % str(_kinds(chronicle)))
	bus.delivery_care_noted.emit(2, &"none")
	_expect(_kinds(chronicle).count("substituted") == 1 and _kinds(chronicle).count("repaired_tape") == 1,
			"Other care notes are not stories")

	bus.cargo_overboard_ended.emit(&"p_hen", false)
	_expect(not _last(chronicle, "cargo_fell").is_empty() and "hen" in _last(chronicle, "cargo_fell")["tags"],
			"A box lost on the road is noted with its family")
	bus.cargo_overboard_ended.emit(&"p_cake", true)
	_expect(not _last(chronicle, "cargo_recovered").is_empty(), "A box that came back is noted")
	bus.route_event_started.emit(&"deer_hit", {"incident": true, "title": "x", "duration": 0})
	bus.route_event_started.emit(&"sheep_hit", {"incident": true})
	bus.route_event_started.emit(&"inspection", {"title": "x", "duration": 60.0})
	bus.route_event_started.emit(&"deer_hit", {"title": "no incident flag"})
	_expect(_kinds(chronicle).count("deer_hit") == 1 and _kinds(chronicle).count("sheep_hit") == 1,
			"Deer and sheep are noted once, a normal route event isn't")
	bus.vehicle_fault_started.emit(&"mirror", Vector3.ZERO)
	bus.vehicle_fault_repaired.emit(&"mirror", &"phone")
	_expect("phone" in _last(chronicle, "fault_mirror")["tags"] and not _last(chronicle, "fault_police").is_empty(),
			"A van fault is noted with how it was fixed (got %s)" % str(_last(chronicle, "fault_mirror")))
	bus.package_ruined.emit(&"p_hen", "hit")
	_expect("noisy" in _last(chronicle, "ruined_en_route")["tags"], "A ruined box is noted with its trap")
	bus.delivery_photo_taken.emit(2, false)
	_expect(_last(chronicle, "photo").is_empty(), "A photo that wasn't accepted is no story")
	bus.delivery_photo_taken.emit(2, true)
	_expect(_last(chronicle, "photo").get("house") == 2, "An accepted photo is noted")
	_expect(float(_last(chronicle, "photo").get("at", -1.0)) >= 0.0, "Each fact knows when in the run it happened")

	# The results add what only they know.
	var results: Dictionary = {
		"delivered": true, "elapsed_seconds": 200.0, "score": 100,
		"deliveries": [
			{"house": 0, "package_id": &"p_hen", "outcome": &"lost"},
			{"house": 1, "package_id": &"p_cake", "outcome": &"missed"},
			{"house": 3, "package_id": &"p_milk", "outcome": &"missed"},
		],
		"complaints": [{"house": 2, "dismissed": false}],
	}
	var crew: Array = [{"peer": 1, "nick": "Turbo"}, {"peer": 2, "nick": ""}]
	var paper: Dictionary = chronicle.compose(results, crew, 21)
	_expect(DESK.is_valid(paper) and chronicle.paper == paper, "The chronicle writes a paper that can be read")
	_expect(paper["town"] != "", "The paper has a town")
	var door_milk: Array = chronicle.facts.filter(func(fact: Dictionary) -> bool:
		return fact["house"] == 3 and fact["kind"] == "missed")
	_expect(door_milk.is_empty(), "compose() doesn't change the notes it read")
	var extra: Array = chronicle._facts_from_results(results, chronicle.facts)
	var extra_kinds: Array = extra.map(func(fact: Dictionary) -> String: return String(fact["kind"]))
	_expect(extra_kinds.count("missed") == 1 and extra[0]["house"] == 3 and "liquid" in extra[0]["tags"],
			"A door the run never reached is a missed fact, the ones already noted don't repeat (got %s)" % str(extra))
	_expect(extra_kinds.count("complaint") == 1, "A complaint in the results is a fact")
	var failed: Dictionary = chronicle.compose({"delivered": false, "elapsed_seconds": 90.0}, crew, 4)
	_expect(failed["front"]["id"] == "run_failed", "A failed delivery leads the paper (got %s)" % failed["front"]["id"])
	var endless: Dictionary = chronicle.compose({"distance_traveled": 3200.0, "elapsed_seconds": 240.0}, crew, 4)
	var endless_slots: Dictionary = endless["front"]["slots"]
	_expect(endless["front"]["id"] == "endless_end" and absf(float(endless_slots["km"]) - 3.2) < 0.01
			and int(endless_slots["minutes"]) == 4,

			"An Endless run is the truck last seen at its distance (got %s)" % str(endless["front"]))

	# The crew is who is in the level, with the nickname each one carries.
	var scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var second: Node3D = scene.instantiate()
	second.name = "Player_2"
	root.add_child(second)
	await process_frame
	second.set_physics_process(false)
	second.get_node("PlayerNickname").set(&"nickname", "Ana")
	var listed: Array = chronicle.current_crew()
	_expect(listed.any(func(member: Dictionary) -> bool: return member["peer"] == 2 and member["nick"] == "Ana"),
			"The crew is read from the players in the level, with their nicknames (got %s)" % str(listed))
	second.queue_free()

	# The host relays the paper before run_ended.
	_relayed.clear()
	_order.clear()
	manager.set(&"is_running", true)
	var spent: Dictionary = {"delivered": true, "elapsed_seconds": 120.0, "score": 10, "deliveries": [],
			"complaints": []}
	bus.run_results_decided.emit(spent)
	bus.run_ended.emit(10, spent)
	_expect(_relayed.size() == 1 and DESK.is_valid(_relayed[0]),
			"The host relays one readable paper when the results are decided")
	_expect(_order == ["paper", "ended"], "The paper arrives before run_ended (got %s)" % str(_order))
	_expect(chronicle.paper == _relayed[0], "The chronicle keeps the paper that went out")
	_expect(_chronicle_script.get(&"last_variants") == DESK.variants_used(_relayed[0]),
			"It remembers which variants went out")
	var line: String = str(_relayed[0])
	for entry: Dictionary in DESK.entries(_relayed[0]):
		var read: Dictionary = DESK.read(entry)
		_expect(not line.contains(String(read["headline"])),
				"What went out is ids and slots, not the headline of %s" % entry["id"])

	# After the run, nothing more is noted; a new run starts clean.
	bus.package_ruined.emit(&"p_hen", "late")
	_expect(_kinds(chronicle).count("ruined_en_route") == 1, "Nothing is noted after the run ended")
	bus.run_started.emit(&"test_route", [1])
	_expect(chronicle.facts.is_empty() and chronicle.paper.is_empty(), "A new run starts with no facts and no paper")

	chronicle.queue_free()
	manager.call(&"reset_run")
	await process_frame
	if _failures == 0:
		print("PASS: the chronicle notes the facts from EventBus and the host relays the paper before the results")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
