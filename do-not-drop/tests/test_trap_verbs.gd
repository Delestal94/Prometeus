extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trap_verbs.gd
## N-117.4, the verb of each trap in the world and in the first-time tip:
## - PackageVerb says what a box asks of its crew (Amortiguá, Contrapesá, Fregá,
##   Abrazalo, Leelo, Asegurá) from the replicated state alone, only while it is
##   asking: nothing when it is fine, ruined, in a rescue or outside a run, and
##   nothing for the bomb (it has its own sign);
## - Hostile's mood reads as different shapes, ">:(" angry and ":)" calm, not
##   only as colours, and Asegurá lists the arrows still to tap;
## - the label really floats over the box on every trap but the bomb, shown and
##   hidden with the box's state;
## - Asegurá is a two-person sequence: the tender's helper advances the same
##   step, both pressing the same key at once is one step and not a mistake, and
##   a wrong key from either starts it over;
## - each first-time tip names its verb and the control that does it (Fragile
##   and the bomb no longer show the old keys), the bomb's sign says to ask.

const PACKAGE_PATH: String = "res://scenes/gameplay/package/package.tscn"
const VEHICLE_SOURCE: String = "extends Node3D\nvar driver_peer_id: int = 0\nvar velocity := Vector3.ZERO\n" \
	+ "func carries(_p: Vector3, _m: float = 0.0) -> bool:\n\treturn true\n" \
	+ "func point_velocity(_p: Vector3) -> Vector3:\n\treturn velocity\n" \
	+ "func needs_sweep(_p: Node, _m: float = 0.0) -> bool:\n\treturn false\n"
const TICK: float = 1.0 / 60.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_asks()
	await _test_label()
	await _test_assistant()
	_test_tips()
	if _failures == 0:
		print("PASS: every trap says its verb in the world, the sequence takes two, and the tips name the keys")
	quit(_failures)


func _test_asks() -> void:
	var fine: int = 0
	var risky: int = 1
	var ruined: int = 2
	var cushion: Dictionary = {"cushion": {"eta": 0.4, "ready": true}}
	_expect(not PackageVerb.ask(&"fragile", fine, cushion, true).is_empty(), "A bump close, a tap ready: Amortiguá")
	_expect(PackageVerb.ask(&"fragile", fine, {"cushion": {"eta": -1.0, "ready": true}}, true).is_empty(),
		"A quiet road asks nothing")
	_expect(PackageVerb.ask(&"fragile", fine, {"cushion": {"eta": 0.4, "ready": false}}, true).is_empty(),
		"Nor does a tap that would not count")
	var names: Dictionary = {&"balance": "HUD_VERB_BALANCE", &"liquid": "HUD_VERB_LIQUID", &"noisy": "HUD_VERB_NOISY"}
	for trap_id: StringName in names:
		_expect(PackageVerb.ask(trap_id, fine, {}, true).is_empty(), "%s asks nothing while fine" % trap_id)
		var ask: Dictionary = PackageVerb.ask(trap_id, risky, {}, true)
		_expect(ask.get("text") == tr(names[trap_id]), "%s asks its verb at risk" % trap_id)
		_expect(PackageVerb.ask(trap_id, ruined, {}, true).is_empty(), "%s asks nothing once ruined" % trap_id)
		_expect(PackageVerb.ask(trap_id, risky, {}, false).is_empty(), "%s asks nothing outside a run" % trap_id)
		_expect(PackageVerb.ask(trap_id, risky, {"phase": &"crisis"}, true).is_empty(),
			"%s asks nothing in a rescue" % trap_id)
	_expect(PackageVerb.ask(&"explosive", risky, {"action": &"hold"}, true).is_empty(), "The bomb has its own sign")
	# Hostile: angry the moment its order is to let go; calm only once at risk.
	var angry: Dictionary = PackageVerb.ask(&"hostile", fine, {"action": &"release"}, true)
	var calm: Dictionary = PackageVerb.ask(&"hostile", risky, {"action": &"hold"}, true)
	_expect(PackageVerb.ask(&"hostile", fine, {"action": &"hold"}, true).is_empty(), "A calm, safe creature is quiet")
	_expect(String(angry["text"]).contains(">:(") and not String(angry["text"]).contains(":)"),
		"Angry: >:( (%s)" % angry)
	_expect(String(calm["text"]).contains(":)") and not String(calm["text"]).contains(">:("), "Calm: :) (%s)" % calm)
	_expect(angry["text"] != calm["text"] and angry["color"] != calm["color"], "The moods differ in text and colour")
	# Asegurá: the arrows still to tap.
	var sequence: Dictionary = {"sequence": {"steps": [&"up", &"left", &"down"], "index": 1, "pending": true}}
	var weight: Dictionary = PackageVerb.ask(&"growing_weight", fine, sequence, true)
	_expect(String(weight["text"]).contains("← ↓") and not String(weight["text"]).contains("↑"),
		"Asegurá lists the arrows still to tap (%s)" % weight)
	sequence["sequence"]["pending"] = false
	_expect(PackageVerb.ask(&"growing_weight", fine, sequence, true).is_empty(), "A secured load asks nothing")
	sequence["sequence"]["pending"] = true
	sequence["sequence"]["index"] = 3
	_expect(PackageVerb.ask(&"growing_weight", fine, sequence, true).is_empty(), "A finished sequence asks nothing")


func _test_label() -> void:
	var run: Node = root.get_node(^"/root/RunManager")
	run.set(&"is_running", true)
	var ids: Array[StringName] = [&"fragile", &"balance", &"liquid", &"noisy", &"hostile", &"growing_weight"]
	for trap_id: StringName in ids:
		var package := (load(PACKAGE_PATH) as PackedScene).instantiate() as Node3D
		package.set(&"trap_definition", load("res://data/traps/%s.tres" % trap_id))
		package.set(&"freeze", true)
		root.add_child(package)
		await process_frame
		await process_frame
		var feedback: Node = package.get_node("PackageFeedbackComponent")
		var label := feedback.get_node_or_null("../Box/VerbIcon") as Label3D
		_expect(label != null, "%s has a verb label over the box" % trap_id)
		if label == null:
			package.free()
			continue
		_expect(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and label.no_depth_test,
			"%s: it faces the camera and is drawn over the box" % trap_id)
		_expect(not label.visible, "%s: a box that asks nothing keeps the world clean" % trap_id)
		feedback.call(&"_set_state", 1)
		var state: Dictionary = {}
		if trap_id == &"fragile":
			state = {"cushion": {"eta": 0.3, "ready": true}}
		elif trap_id == &"hostile":
			state = {"action": &"release"}
		elif trap_id == &"growing_weight":
			state = {"sequence": {"steps": [&"up", &"down"], "index": 0, "pending": true}}
		package.set(&"care_state", state)
		await process_frame
		_expect(label.visible and not label.text.is_empty(), "%s: at risk the verb shows (%s)" % [trap_id, label.text])
		feedback.call(&"_set_state", 2)
		await process_frame
		_expect(not label.visible, "%s: ruined, it goes" % trap_id)
		package.free()
	var bomb := (load(PACKAGE_PATH) as PackedScene).instantiate() as Node3D
	bomb.set(&"trap_definition", load("res://data/traps/explosive.tres"))
	root.add_child(bomb)
	await process_frame
	await process_frame
	_expect(bomb.get_node("PackageFeedbackComponent").get_node_or_null("../Box/VerbIcon") == null,
		"The bomb keeps its own sign only")
	var sign_label := bomb.get_node("PackageFeedbackComponent").get_node_or_null("../Box/ExplosiveCountdown") as Label3D
	_expect(sign_label != null and sign_label.text.contains(tr("HUD_EXPLOSIVE_CODE_SIGN").split(" ")[0]),
		"The bomb's sign says to ask for the code")
	bomb.free()
	run.set(&"is_running", false)


## Asegurá through the package: the tender and their helper take turns, press
## together, and err.
func _test_assistant() -> void:
	var script := GDScript.new()
	script.source_code = VEHICLE_SOURCE
	script.reload()
	var vehicle := Node3D.new()
	vehicle.set_script(script)
	vehicle.add_to_group(&"vehicle")
	root.add_child(vehicle)
	var run: Node = root.get_node(^"/root/RunManager")
	run.set(&"is_running", true)
	var package := DeliveryPackage.new()
	package.package_id = &"weight_assist"
	package.trap_definition = load("res://data/traps/growing_weight.tres")
	package.freeze = true
	root.add_child(package)
	package.set_tender(1)
	_expect(package.set_assistant(2), "A second peer can help")
	var trap: GrowingWeightTrapBehavior = package.trap_behavior
	trap.set(&"_time_since_solved", 6.0)
	var code: Array[StringName] = trap.sequence.duplicate()
	_expect(code.size() >= 3, "There is a sequence to tap")
	# Turn by turn: the tender, the helper, the tender...
	for step: int in range(code.size() - 1):
		var who: int = 1 if step % 2 == 0 else 2
		package._accept_tender_input(who, {"direction_pressed": code[step], "balance": Vector2.ZERO})
		PackageRescue.simulate_cargo(package, TICK)
		_expect(trap.sequence_index == step + 1, "Step %d advanced by peer %d" % [step + 1, who])
	# Both press the final key at once: one step, no mistake, solved.
	package._accept_tender_input(1, {"direction_pressed": code[-1], "balance": Vector2.ZERO})
	package._accept_tender_input(2, {"direction_pressed": code[-1], "balance": Vector2.ZERO})
	PackageRescue.simulate_cargo(package, TICK)
	var state: Dictionary = trap.sequence_state()
	_expect(int(state.get("solved", 0)) == 1 and int(state.get("mistakes", -1)) == 0,
		"Both pressing the last key at once solves it with no mistake (%s)" % str(state))
	# A mistake by the helper costs what the tender's would.
	trap.set(&"_time_since_solved", 6.0)
	var next: Array[StringName] = trap.sequence.duplicate()
	package._accept_tender_input(1, {"direction_pressed": next[0], "balance": Vector2.ZERO})
	PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.sequence_index == 1, "The tender starts the new sequence")
	var wrong: StringName = &"left" if next[1] != &"left" else &"right"
	package._accept_tender_input(2, {"direction_pressed": wrong, "balance": Vector2.ZERO})
	PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.sequence_index == 0 and int(trap.sequence_state()["mistakes"]) == 1,
		"The helper's wrong key starts it over, the same as the tender's would")
	# The key sent twice in a row across ticks (an edge already spent) is not re-read.
	package._accept_tender_input(2, {"direction_pressed": next[0], "balance": Vector2.ZERO})
	for tick: int in 4:
		PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.sequence_index == 1, "One press is one step however many ticks the host makes")
	package.free()
	vehicle.free()
	run.set(&"is_running", false)
	await process_frame


func _test_tips() -> void:
	var catalog: Script = load("res://scripts/ui/tutorial_catalog.gd")
	var expected: Dictionary = {
		&"fragile": ["Amortiguá", "Click izq."], &"balance": ["Contrapesá", "WASD"],
		&"growing_weight": ["Asegurá", "WASD"], &"liquid": ["Fregá", "A/D"], &"noisy": ["Abrazalo", "Click izq."],
		&"hostile": ["Leelo", "Click izq."], &"explosive": ["Pedí el código", "WASD"],
	}
	for trap_id: StringName in expected:
		var tip: String = catalog.call(&"tip_text", trap_id)
		_expect(tip.contains(expected[trap_id][0]), "%s's tip names its verb (%s)" % [trap_id, tip])
		_expect(tip.contains(expected[trap_id][1]), "%s's tip names its control (%s)" % [trap_id, tip])
		_expect(not tip.contains("W/S"), "%s's tip does not show the old keys" % trap_id)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
