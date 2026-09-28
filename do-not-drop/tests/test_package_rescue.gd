extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_package_rescue.gd
##
## Cargo rescue (docs/jugabilidad-paquetes-rescate.md): the host-owned care
## model behind a box (crisis window, salvage, tape/repair/substitute, a
## quality cap no repair lifts), the crew's shared kit in RunManager, and how
## a rescued box is paid and told at the end of the run.

const Care = preload("res://scripts/gameplay/package/package_care.gd")

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	_check_crisis_and_repair()
	_check_crisis_window()
	_check_substitute()
	_check_supplies_and_scoring()
	_check_content_rescues()
	_check_lap_strap_and_filler()
	_check_disconnect_hold()
	_check_deadlines()
	quit(_failures)


func _work(care, tool: StringName, kind: StringName, seconds: float) -> bool:
	var done: bool = false
	var step: float = 1.0 / 60.0
	for _i: int in roundi(seconds / step):
		var input: Dictionary = {"work": true, "balance": care.work_direction()}
		if care.advance_work(step, tool, input, kind, 0.0, true):
			care.complete_tool(tool)
			done = true
			break
	return done


func _check_crisis_and_repair() -> void:
	var care = Care.new()
	_expect(care.observe(100.0, true, &"fragile"), "A broken vase starts a rescue")
	_expect(care.phase == &"crisis" and care.missing_parts == 3, "...with three pieces on the floor")
	_expect(not care.tool_blocker(&"repair", &"fragile", 0.0).is_empty(), "Repair waits for the pieces")
	for _i: int in 3:
		care.collect_part()
	_expect(care.missing_parts == 0, "All pieces collected")
	_expect(not care.tool_blocker(&"repair", &"fragile", 20.0).is_empty(), "No repairing at full speed")
	var idle: Dictionary = {"work": true, "balance": -care.work_direction()}
	_expect(not care.advance_work(0.5, &"repair", idle, &"fragile", 0.0, true) and is_zero_approx(care.work),
		"Working against the arrow makes no progress")
	_expect(_work(care, &"repair", &"fragile", 6.0), "Following the arrows completes the repair")
	_expect(care.phase == &"rescued" and not care.needs_restore, "The vase is rescued")
	_expect(care.quality_cap <= 85.0 and care.worst_quality <= 20.0,
		"...but its history stays: capped quality, worst kept")
	_expect(_work(care, &"tape", &"fragile", 4.0) and care.tape == 1, "Tape reinforces the box")
	_expect(care.impact_scale() < 1.0, "...and softens later hits")


func _check_crisis_window() -> void:
	var care = Care.new()
	care.begin_crisis(&"fragile")
	for _i: int in 60 * 16:
		care.advance(1.0 / 60.0, Vector3.ZERO, {})
	_expect(care.phase == &"lost", "An ignored rescue is lost after its window")
	_expect(not care.tool_blocker(&"repair", &"fragile", 0.0).is_empty(), "Nothing to repair once lost")


func _check_substitute() -> void:
	var vase = Care.new()
	vase.phase = &"lost"
	_expect(not vase.tool_blocker(&"substitute", &"fragile", 0.0).is_empty(), "The toy hen only replaces a hen")
	var hen = Care.new()
	hen.begin_crisis(&"noisy")
	_expect(not hen.tool_blocker(&"substitute", &"noisy", 0.0).is_empty(), "...and only once the real one is gone")
	hen.phase = &"lost"
	_expect(_work(hen, &"substitute", &"noisy", 6.0) and hen.substituted, "A lost hen can go out as a toy")
	_expect(hen.quality_cap <= 20.0, "A substitute never pays like the real thing")


func _check_content_rescues() -> void:
	var liquid = Care.new()
	liquid.begin_crisis(&"liquid", true)
	_expect(liquid.missing_parts == 0, "A leak leaves nothing to pick up")
	_expect(not liquid.tool_blocker(&"repair", &"liquid", 0.0).is_empty(), "A liquid can't be glued")
	_expect(_work(liquid, &"rag", &"liquid", 5.0) and liquid.phase == &"rescued", "The rag contains the leak")
	_expect(liquid.quality_cap <= 60.0, "...and it arrives partial")
	var heavy = Care.new()
	heavy.begin_crisis(&"growing_weight")
	_expect(not heavy.tool_blocker(&"repair", &"growing_weight", 0.0, false).is_empty(),
		"Moving the heavy box alone is refused")
	_expect(heavy.tool_blocker(&"repair", &"growing_weight", 0.0, true).is_empty(), "...with a helper it can be done")
	var cake = Care.new()
	cake.begin_crisis(&"balance")
	_expect(cake.missing_parts == 3 and cake.tool_name(&"repair", &"balance") == "Rearmar pisos",
		"A collapsed cake is restacked from its layers")
	var bomb = Care.new()
	bomb.begin_crisis(&"explosive")
	_expect(bomb.quality_cap <= 35.0 and bomb.missing_parts == 0, "A late bomb is scrap at best, nothing to collect")
	_expect(not bomb.tool_blocker(&"rag", &"explosive", 0.0).is_empty(), "The rag is only for leaks")


func _check_lap_strap_and_filler() -> void:
	var care = Care.new()
	care.in_lap = true
	care.advance(1.0 / 60.0, Vector3.ZERO, {})
	_expect(care.protection >= 0.4, "The lap cushions the box on its own")
	_expect(not care.tool_blocker(&"strap", &"fragile", 0.0).is_empty(), "...but ties up the hands for tools")
	care.in_lap = false
	_expect(_work(care, &"strap", &"fragile", 3.0) and care.strapped, "On the rack, the strap goes on")
	care.advance(1.0 / 60.0, Vector3.ZERO, {})
	_expect(care.protection >= 0.5, "A strapped box holds itself")
	care.on_hard_hit(8.0)
	_expect(not care.strapped, "A hard hit loosens the strap")
	var before: float = care.impact_scale()
	_expect(_work(care, &"filler", &"fragile", 4.0) and care.padded, "Filler goes in")
	_expect(care.impact_scale() < before, "...and fewer hits reach the contents")


func _check_disconnect_hold() -> void:
	var care = Care.new()
	care.begin_crisis(&"fragile")
	for _i: int in 60 * 12:
		care.advance(1.0 / 60.0, Vector3.ZERO, {})
	care.hold_crisis(Care.CRISIS_SECONDS)
	_expect(care.crisis_left >= Care.CRISIS_SECONDS - 0.01, "A player dropping out holds their box's rescue window")


func _check_deadlines() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	var planned: Array = run.plan_deadlines([300.0, 600.0, 900.0, 1200.0])
	_expect(planned.size() == 3, "At most three deadlines")
	_expect(float(planned[1]["seconds"]) > float(planned[0]["seconds"]), "Farther houses get later deadlines")
	var at_cruise: float = 600.0 / 12.8 + 25.0
	_expect(float(planned[1]["seconds"]) < at_cruise + 15.0 + 0.5 and float(planned[1]["seconds"]) > 600.0 / 20.0,
		"A deadline asks for a bit over cruise pace, with room for one short stop")
	run.reset_run()
	run.deadlines = planned
	run.elapsed_seconds = float(planned[0]["seconds"]) - 5.0
	run.register_delivery(0, &"delivered_ok", &"a")
	_expect(int(run.next_deadline().get("house", -1)) == 1, "The HUD moves on to the next open deadline")
	run.elapsed_seconds = float(planned[1]["seconds"]) + 5.0
	run.register_delivery(1, &"delivered_ok", &"b")
	var tally: Dictionary = run.deadline_tally()
	_expect(int(tally["met"]) == 1 and int(tally["missed"]) == 2, "On time counts, late and undelivered don't")
	var doors: Dictionary = run._resolve_deliveries()
	var labels: String = str(doors["breakdown"])
	_expect(labels.contains("Plazos cumplidos") and labels.contains("Plazos vencidos"),
		"Deadlines show in the breakdown")
	run.reset_run()
	_expect(run.deadlines.is_empty(), "A new run starts without deadlines")


func _check_supplies_and_scoring() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	run.reset_run()
	_expect(run.care_supply_count(&"tape") == 3, "The crew starts with three rolls of tape")
	for _i: int in 3:
		run.consume_care_supply(&"tape")
	_expect(not run.consume_care_supply(&"tape"), "The last roll can't be spent twice")
	run.record_care(&"vase", {"category": &"repaired", "kind": &"fragile", "repairs": 1, "substituted": false})
	run.record_care(&"hen", {"category": &"substituted", "kind": &"noisy", "repairs": 0, "substituted": true})
	run.register_delivery(0, &"delivered_at_risk", &"vase")
	run.register_delivery(1, &"delivered_ruined", &"hen")
	_expect(StringName(run.deliveries[0]["care"]) == &"repaired", "The door records what it inspected")
	var doors: Dictionary = run._resolve_deliveries()
	_expect(int(doors["delivery_points"]) == run.POINTS_DELIVERED_REPAIRED + run.POINTS_DELIVERED_SUBSTITUTED,
		"A convincing repair and a toy hen are paid by what the door saw")
	_expect((doors["complaints"] as Array).is_empty(), "...without a random complaint")
	var labels: String = str(doors["breakdown"])
	_expect(labels.contains("Reparaciones convincentes") and labels.contains("Sustitutos"),
		"Both show in the breakdown")
	var stories: String = str(run.rescue_stories())
	_expect(stories.contains("Jarrón") and stories.contains("juguete"), "The results tell the rescues")
	run.reset_run()
	_expect(run.care_supply_count(&"tape") == 3 and run.deliveries.is_empty(), "A new run gets a fresh kit")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
