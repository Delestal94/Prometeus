extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_explosive_trap.gd
## Explosive trap, "Pedí el código" (N-117):
## - the right sequence defuses it, a wrong input costs time instead of drawing
##   a new code, and the timer reaching zero ruins it;
## - the code is drawn per box: the same roll seed gives the same code, other
##   seeds give other codes, it never repeats a direction twice in a row, and
##   two boxes made from the one shared definition never share a code;
## - a session seed and a box id give that box the same code every time, and
##   different boxes different ones (DeliveryPackage.initialize_trap());
## - the code reaches the driver, not the owner: the hint of a box read by the
##   driver never names an arrow, and the care state says who reads it
##   (PackageRescue.reader_for(), the sequence state's "reader");
## - the dashboard lists the codes the driver has to read out, the soonest
##   first, and leaves out boxes the owner reads themselves; its screen shows at
##   most two of them, with a "+N" for the rest, and hides the line with none.

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const ARROWS: Array[String] = ["↑", "↓", "←", "→"]
const EXPLOSIVE: Resource = preload("res://data/traps/explosive.tres")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_rules()
	_test_roll()
	_test_reader()
	await _test_package_roll()
	_test_dashboard()
	await _test_dashboard_screen()
	if _failures == 0:
		print("PASS: explosive code is drawn per box, defuses by sequence, and goes to the driver")
	quit(_failures)


func _new_bomb(config: Dictionary) -> ExplosiveTrapBehavior:
	var bomb := ExplosiveTrapBehavior.new()
	bomb.on_setup(null, config)
	return bomb


func _press(bomb: ExplosiveTrapBehavior, direction: StringName, extra: Dictionary = {}) -> void:
	var context: Dictionary = {"input": {"direction_pressed": direction}}
	context.merge(extra)
	bomb.on_physics_process(null, 0.1, context)


func _test_rules() -> void:
	var fixed := {"integrity_max": 100.0, "countdown_seconds": 8.0, "mistake_penalty": 2.0,
		"sequence": [&"up", &"left", &"down"]}
	var bomb: ExplosiveTrapBehavior = _new_bomb(fixed)
	_expect(bomb.sequence == [&"up", &"left", &"down"], "A configured sequence fixes the code")
	_press(bomb, &"up")
	_press(bomb, &"left")
	_press(bomb, &"down")
	_expect(bomb.get_hint() == tr("HUD_HINT_EXPLOSIVE_SAFE"), "The right sequence defuses the bomb")
	_expect(bomb.get_state() == ITrapBehavior.TrapState.OK and bomb.integrity == bomb.integrity_max,
		"A defused bomb is fully intact")
	_expect(bomb.take_milestones() == [&"defused"], "Defusing awards its milestone")

	var mistake: ExplosiveTrapBehavior = _new_bomb(fixed.merged({"countdown_seconds": 40.0}))
	var code_before: Array[StringName] = mistake.sequence.duplicate()
	var before: float = mistake.seconds_left
	_press(mistake, &"up")
	_press(mistake, &"right")
	_expect(mistake.seconds_left < before - 2.0 - 0.15, "A wrong input costs the penalty on top of the clock")
	_expect(mistake.sequence == code_before, "A mistake never draws a new code")
	_expect(mistake.sequence_index == 0, "A mistake starts the code over")
	_expect(mistake.sequence_state()["mistakes"] == 1, "The mistake is counted")
	# The wrong key that happens to be the first step still starts the code.
	_press(mistake, &"up")
	_press(mistake, &"down")
	_expect(mistake.sequence_index == 0, "A wrong key after the first step starts over")
	_press(mistake, &"left")
	_expect(mistake.sequence_index == 0, "Left is not the first step")
	_press(mistake, &"up")
	_press(mistake, &"up")
	_expect(mistake.sequence_index == 1, "The first key pressed again after a mistake counts as the first step")
	mistake.on_physics_process(null, 60.0, {"input": {}})
	_expect(mistake.get_state() == ITrapBehavior.TrapState.RUINED, "Reaching zero ruins the package")
	_expect(mistake.sequence_state().is_empty(), "A blown bomb publishes no code")
	_expect(mistake.next_direction() == &"", "A blown bomb asks for nothing")


func _test_roll() -> void:
	var seeded := {"countdown_seconds": 12.0, "code_length": 4, "roll_seed": 424242}
	var first: ExplosiveTrapBehavior = _new_bomb(seeded)
	var second: ExplosiveTrapBehavior = _new_bomb(seeded)
	_expect(first.sequence == second.sequence, "The same roll seed draws the same code")
	_expect(first.sequence.size() == 4, "The code has the configured length (got %d)" % first.sequence.size())
	var codes: Dictionary = {}
	var repeated: bool = false
	var valid: bool = true
	for roll_seed: int in range(1, 41):
		var bomb: ExplosiveTrapBehavior = _new_bomb({"roll_seed": roll_seed})
		codes[String(",".join(bomb.sequence))] = true
		_expect(bomb.sequence.size() == 3, "The default code is three steps (got %d)" % bomb.sequence.size())
		for index: int in range(bomb.sequence.size()):
			valid = valid and bomb.sequence[index] in ExplosiveTrapBehavior.DIRECTIONS
			if index > 0 and bomb.sequence[index] == bomb.sequence[index - 1]:
				repeated = true
	_expect(valid, "Every step is one of the four directions")
	_expect(not repeated, "No direction repeats twice in a row")
	_expect(codes.size() >= 12,
		"Forty seeds give a spread of codes, not one fixed sequence (%d distinct)" % codes.size())
	var clock_a: ExplosiveTrapBehavior = _new_bomb({})
	_expect(clock_a.sequence.size() == 3, "Without a seed the code is drawn from the clock")
	# Solved boxes can be drawn again from the same behavior instance (a fresh
	# setup), and a fresh setup is a fresh countdown with the code unsolved.
	var solved: ExplosiveTrapBehavior = _new_bomb({"roll_seed": 9})
	for direction: StringName in solved.sequence.duplicate():
		_press(solved, direction)
	_expect(solved.get_state() == ITrapBehavior.TrapState.OK and solved.sequence_index == 3,
		"The drawn code defuses it")
	solved.on_setup(null, {"roll_seed": 9})
	_expect(solved.sequence_index == 0 and solved.seconds_left > 0.0, "A new setup starts unsolved")
	var params: Dictionary = EXPLOSIVE.get(&"params")
	_expect(not params.has("sequence") and int(params.get("code_length", 0)) >= 2,
		"The data draws the code (no fixed sequence), with its length in the data")
	var one: Resource = EXPLOSIVE.call(&"create_behavior")
	var other: Resource = EXPLOSIVE.call(&"create_behavior")
	one.call(&"on_setup", null, params.duplicate(true).merged({"roll_seed": 1}))
	other.call(&"on_setup", null, params.duplicate(true).merged({"roll_seed": 2}))
	_expect(one != other, "Two behaviors from one definition are two instances")
	(one.get(&"sequence") as Array).clear()
	_expect((other.get(&"sequence") as Array).size() == 3, "One box's code is never another's array")


func _test_reader() -> void:
	var bomb: ExplosiveTrapBehavior = _new_bomb({"sequence": [&"up", &"left", &"down"], "countdown_seconds": 12.0})
	_expect(StringName(bomb.sequence_state()["reader"]) == &"driver", "By default the driver reads the code")
	var hint: String = bomb.get_hint()
	for arrow: String in ARROWS:
		_expect(not hint.contains(arrow), "The hint read by the driver names no arrow (%s in \"%s\")" % [arrow, hint])
	_expect(hint.contains("0/3"), "The hint counts the steps done instead (%s)" % hint)
	bomb.on_physics_process(null, 0.1, {"input": {}, "code_reader": &"owner"})
	_expect(StringName(bomb.sequence_state()["reader"]) == &"owner", "The package can hand the code to the owner")
	_expect(bomb.get_hint().contains("↑"), "The owner who reads it is told the next step")
	bomb.on_physics_process(null, 0.1, {"input": {}, "code_reader": &"stranger"})
	_expect(StringName(bomb.sequence_state()["reader"]) == &"owner", "An unknown reader changes nothing")
	# Who reads it: the driver unless the owner is the driver or nobody else drives.
	_expect(PackageRescue.reader_for(1, 2) == &"driver", "A driver who is not the owner reads it")
	_expect(PackageRescue.reader_for(2, 2) == &"owner", "An owner who drives reads it themselves")
	_expect(PackageRescue.reader_for(0, 2) == &"owner", "With nobody at the wheel the owner reads it")
	_expect(PackageRescue.reader_for(3, 0) == &"driver", "A box nobody tends goes to the driver")
	_expect(PackageRescue.reader_for(0, 0) == &"owner", "No driver and no owner falls back to owner")


func _test_package_roll() -> void:
	var network: Node = root.get_node(^"/root/NetworkManager")
	network.set(&"world_seed", 777)
	var definition: Resource = EXPLOSIVE
	var codes: Dictionary = {}
	for id: StringName in [&"box_a", &"box_b", &"box_c", &"box_d", &"box_e", &"box_f"]:
		var first: DeliveryPackage = _package(definition, id)
		var again: DeliveryPackage = _package(definition, id)
		_expect(first.trap_behavior.get(&"sequence") == again.trap_behavior.get(&"sequence"),
			"The same session and box always draw the same code (%s)" % id)
		codes[str(first.trap_behavior.get(&"sequence"))] = true
		first.free()
		again.free()
	_expect(codes.size() >= 3, "Each box gets its own code (%d distinct in six boxes)" % codes.size())
	network.set(&"world_seed", 778)
	var moved: DeliveryPackage = _package(definition, &"box_a")
	var original_seed: Array = moved.trap_behavior.get(&"sequence")
	network.set(&"world_seed", 777)
	var back: DeliveryPackage = _package(definition, &"box_a")
	_expect(back.trap_behavior.get(&"sequence") != null and original_seed.size() == 3,
		"Another session seed still draws a full code")
	moved.free()
	back.free()
	# Solo (no seed): drawn from the clock, still a full code.
	network.set(&"world_seed", 0)
	var solo: DeliveryPackage = _package(definition, &"box_a")
	_expect((solo.trap_behavior.get(&"sequence") as Array).size() == 3,
		"Without a session seed the code is still drawn")
	solo.free()
	await process_frame


func _package(definition: Resource, id: StringName) -> DeliveryPackage:
	var package: DeliveryPackage = PACKAGE_SCENE.instantiate()
	package.package_id = id
	package.trap_definition = definition
	package.freeze = true
	root.add_child(package)
	return package


func _test_dashboard() -> void:
	var soon: DeliveryPackage = PACKAGE_SCENE.instantiate()
	var later: DeliveryPackage = PACKAGE_SCENE.instantiate()
	var owned: DeliveryPackage = PACKAGE_SCENE.instantiate()
	var plain: DeliveryPackage = PACKAGE_SCENE.instantiate()
	soon.care_state = {"sequence": {"steps": [&"up", &"left", &"down"], "index": 1, "seconds": 4.0,
		"reader": &"driver"}}
	later.care_state = {"sequence": {"steps": [&"right", &"down"], "index": 0, "seconds": 9.0,
		"reader": &"driver"}}
	owned.care_state = {"sequence": {"steps": [&"up", &"left"], "index": 0, "seconds": 3.0, "reader": &"owner"}}
	var done: DeliveryPackage = PACKAGE_SCENE.instantiate()
	done.care_state = {"sequence": {"steps": [&"up"], "index": 1, "seconds": 7.0, "reader": &"driver"}}
	var blown: DeliveryPackage = PACKAGE_SCENE.instantiate()
	blown.care_state = {"sequence": {"steps": [&"up"], "index": 0, "seconds": 0.0, "reader": &"driver"}}
	var codes: Array[Dictionary] = DashboardGps.bomb_codes([later, owned, soon, plain, done, blown, null])
	_expect(codes.size() == 2, "Only the codes the driver reads are listed (got %d)" % codes.size())
	if codes.size() == 2:
		_expect(float(codes[0]["seconds"]) == 4.0 and float(codes[1]["seconds"]) == 9.0,
			"The soonest to go off comes first")
	_expect(DashboardGps.code_text([&"up", &"left", &"down"], 0) == "↑ ← ↓", "The code reads as arrows")
	_expect(DashboardGps.code_text([&"up", &"left", &"down"], 1) == "← ↓", "Steps already typed are no longer shown")
	_expect(DashboardGps.code_text([&"up"], 5) == "", "Past the end there is nothing left to say")
	for package: DeliveryPackage in [soon, later, owned, plain, done, blown]:
		package.free()


func _test_dashboard_screen() -> void:
	var truck := VehicleBody3D.new()
	root.add_child(truck)
	var gps := DashboardGps.new()
	truck.add_child(gps)
	await process_frame
	gps.refresh()
	_expect(not gps.code_label.visible, "With no bomb aboard the code line is hidden")
	var boxes: Array[DeliveryPackage] = []
	for seconds: float in [11.0, 5.0, 8.0]:
		var box: DeliveryPackage = PACKAGE_SCENE.instantiate()
		box.freeze = true
		root.add_child(box)
		box.add_to_group(&"cargo")
		box.care_state = {"sequence": {"steps": [&"up", &"left", &"down"], "index": 0, "seconds": seconds,
			"reader": &"driver"}}
		boxes.append(box)
	gps.refresh()
	_expect(gps.code_label.visible, "A bomb the driver reads shows its code")
	var lines: PackedStringArray = gps.code_label.text.split("\n")
	_expect(lines.size() == 2, "At most two codes at once (%d lines)" % lines.size())
	_expect(lines[0].contains("5") and lines[0].contains("↑ ← ↓"), "The soonest comes first (%s)" % gps.code_label.text)
	_expect(lines[1].contains("8") and lines[1].contains("+1"), "The rest is counted (%s)" % gps.code_label.text)
	_expect(gps.code_label.modulate == DashboardGps.ALERT, "Under six seconds it turns to the alert colour")
	for box: DeliveryPackage in boxes:
		box.care_state = {"sequence": {"steps": [&"up"], "index": 0, "seconds": 9.0, "reader": &"owner"}}
	gps.refresh()
	_expect(not gps.code_label.visible, "Once the owners read their own codes the dashboard lets go of them")
	for box: DeliveryPackage in boxes:
		box.free()
	truck.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
