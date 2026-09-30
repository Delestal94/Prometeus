extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_trap_gestures.gd
## Balance's "Contrapesá" and Liquid's "Fregá" (N-117.3) through the package on
## the host and to the screen, where test_traps.gd and test_liquid_trap.gd look
## at the behaviors alone:
## - the lean axis travels like steady/calm: it counts only from someone holding
##   the primary (the assistant at half), a client's value is clamped and a
##   non-number is zero;
## - the box's side comes from the truck's own right, so a truck turned around
##   flips which key is which; the published gesture names it;
## - the keys are the ones the passenger's screen shows: a seat on the truck's
##   side (LeftSeat looks to the truck's right, RackSeat to its left) has its
##   "left" forward or back on the road, so the same tilt asks for S there, W on
##   the other side and A in the cab; the right key straightens the box and the
##   other three do nothing, and the card lights that key;
## - the seated body's head goes toward the truck's right times the push, in
##   every seat;
## - a scrub swing is a key press edge: it counts once however many host ticks
##   pass, and holding the primary (or calm) dries nothing;
## - the care card asks for the verb ("¡CONTRAPESÁ!" with A/D, "¡FREGÁ!"),
##   only while the box needs hands, and names the controls of the device;
## - the passenger's body leans with what their box says (every peer reads it
##   from the box's care state), and the tutorial cards show the new controls.

const CargoCare = preload("res://scripts/gameplay/player/player_cargo_care.gd")
const CareGuide = preload("res://scripts/ui/hud/care_guide.gd")
const CarePromptView = preload("res://scripts/ui/hud/care_prompt_view.gd")
const SeatPose = preload("res://scripts/gameplay/player/player_seat_pose.gd")
const VEHICLE_SOURCE: String = "extends Node3D\nvar driver_peer_id: int = 0\nvar velocity := Vector3.ZERO\n" \
	+ "func carries(_p: Vector3, _m: float = 0.0) -> bool:\n\treturn true\n" \
	+ "func point_velocity(_p: Vector3) -> Vector3:\n\treturn velocity\n" \
	+ "func needs_sweep(_p: Node, _m: float = 0.0) -> bool:\n\treturn false\n"
const TICK: float = 1.0 / 60.0

var _failures: int = 0
var _serial: int = 0
var _vehicle: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_vehicle = _make_vehicle()
	root.get_node(^"/root/RunManager").set(&"is_running", true)
	await process_frame
	_test_lean_axis()
	_test_balance_side()
	_test_seats()
	_test_body_lean()
	_test_scrub()
	_test_card()
	await _test_body()
	_test_tutorial()
	root.get_node(^"/root/RunManager").set(&"is_running", false)
	if _failures == 0:
		print("PASS: the lean and the scrub travel to the host, drive their traps and reach the card and the body")
	quit(_failures)


func _make_vehicle() -> Node3D:
	var script := GDScript.new()
	script.source_code = VEHICLE_SOURCE
	script.reload()
	var vehicle := Node3D.new()
	vehicle.set_script(script)
	vehicle.add_to_group(&"vehicle")
	root.add_child(vehicle)
	return vehicle


func _package(definition_path: String) -> DeliveryPackage:
	_serial += 1
	var package := DeliveryPackage.new()
	package.package_id = StringName("gesture_%d" % _serial)
	package.trap_definition = load(definition_path)
	package.freeze = true
	root.add_child(package)
	package.set_tender(1)
	return package


func _test_lean_axis() -> void:
	var package: DeliveryPackage = _package("res://data/traps/balance.tres")
	package._accept_tender_input(1, {"steady": true, "lean": -1.0})
	_expect(is_equal_approx(float(package.player_input.get("lean", 9.0)), -1.0), "A tender's lean arrives")
	package._accept_tender_input(1, {"steady": false, "lean": -1.0})
	_expect(package.player_input.is_empty() or is_zero_approx(float(package.player_input.get("lean", 0.0))),
		"Leaning without holding the primary is nothing")
	package.set_assistant(2)
	package._accept_tender_input(1, {"steady": true, "lean": -1.0})
	package._accept_tender_input(2, {"steady": true, "lean": -1.0})
	_expect(is_equal_approx(float(package.player_input["lean"]), -1.5), "The assistant's lean is half of a tender's")
	package._accept_tender_input(2, {"steady": true, "lean": 1.0})
	_expect(is_equal_approx(float(package.player_input["lean"]), -0.5), "Two players leaning opposite ways cancel out")
	# What a client can send.
	_expect(PackageRescue.clean_axis(5.0) == 1.0 and PackageRescue.clean_axis(-5.0) == -1.0, "A lean is clamped")
	_expect(PackageRescue.clean_axis("left") == 0.0 and PackageRescue.clean_axis(null) == 0.0, "A non-number is zero")
	_expect(PackageRescue.clean_axis(NAN) == 0.0 and PackageRescue.clean_axis(INF) == 0.0, "So are NaN and infinity")
	_expect(is_equal_approx(PackageRescue.clean_axis(0.4), 0.4), "A half-pushed stick keeps its value")
	var operator := Node3D.new()
	operator.add_to_group(&"player")
	root.add_child(operator)
	package.set_assistant(0)
	package.submit_care_input({"steady": true, "lean": 7.0, "balance": Vector2.ZERO})
	_expect(is_equal_approx(float(package.player_input.get("lean", 0.0)), 1.0),
		"The care input's lean is clamped on the host")
	package.submit_care_input({"steady": true, "work": true, "lean": 1.0, "balance": Vector2.ZERO})
	_expect(is_zero_approx(float(package.player_input.get("lean", 0.0))), "Working a tool takes both hands: no lean")
	operator.free()
	package.free()


## The truck's own right decides which key is which, all the way from the
## published state.
func _test_balance_side() -> void:
	var package: DeliveryPackage = _package("res://data/traps/balance.tres")
	package.global_position = Vector3.ZERO
	var trap: BalanceTrapBehavior = package.trap_behavior
	package.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(15.0)), Vector3.ZERO)
	_vehicle.rotation.y = 0.0
	PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.tilt_side == 1.0, "Box leaning to +X, truck facing forward: it leans right")
	PackageRescue.publish_care(package)
	var gesture: Dictionary = package.care_state.get("gesture", {})
	_expect(gesture.get("kind") == &"lean" and float(gesture.get("side", 0.0)) == 1.0,
		"The published gesture says the box leans right (%s)" % str(gesture))
	_expect(StringName(package.care_state.get("action", &"")) == &"lean", "and the card's action is the lean")
	_vehicle.rotation.y = PI
	PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.tilt_side == -1.0, "The truck turned around: the same tilt is on its left")
	# Holding and leaning the right way through the package, on that turned truck.
	package.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(15.0)), Vector3.ZERO)
	var start: float = trap.tilt_degrees
	for tick: int in 30:
		package._accept_tender_input(1, {"steady": true, "lean": 1.0, "balance": Vector2.ZERO})
		PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.tilt_degrees < start - 1.0, "Leaning right on the turned truck pushes back (%.1f)" % trap.tilt_degrees)
	package.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(15.0)), Vector3.ZERO)
	start = 15.0
	for tick: int in 30:
		package._accept_tender_input(1, {"steady": true, "lean": -1.0, "balance": Vector2.ZERO})
		PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.tilt_degrees > start - 0.5, "and leaning left there does nothing (%.1f)" % trap.tilt_degrees)
	_vehicle.rotation.y = 0.0
	package.free()


## Fake players in seats like vehicle.tscn's: LeftSeatN looks to the truck's
## right (+X), RackSeatN to its left, the cab forward. For each, the key the
## screen shows for "against the tilt" straightens a box leaning to the truck's
## right, and no other key does.
func _test_seats() -> void:
	_vehicle.rotation.y = 0.0
	var seats: Array[Dictionary] = [
		{"name": "LeftSeatT", "facing": Vector3.RIGHT, "key": &"S", "axes": {"lean": 0.0, "lean_fwd": -1.0}},
		{"name": "RackSeatT", "facing": Vector3.LEFT, "key": &"W", "axes": {"lean": 0.0, "lean_fwd": 1.0}},
		{"name": "CabSeatT", "facing": Vector3.FORWARD, "key": &"A", "axes": {"lean": -1.0, "lean_fwd": 0.0}},
	]
	var all_keys: Dictionary = {&"W": {"lean": 0.0, "lean_fwd": 1.0}, &"S": {"lean": 0.0, "lean_fwd": -1.0},
		&"A": {"lean": -1.0, "lean_fwd": 0.0}, &"D": {"lean": 1.0, "lean_fwd": 0.0}}
	var script := GDScript.new()
	script.source_code = "extends Node3D
var seat_node_path := NodePath()
"
	script.reload()
	for seat_info: Dictionary in seats:
		var seat := Node3D.new()
		seat.name = seat_info["name"]
		root.add_child(seat)
		seat.global_basis = Basis.looking_at(seat_info["facing"], Vector3.UP)
		var player := Node3D.new()
		player.set_script(script)
		player.set(&"seat_node_path", seat.get_path())
		player.add_to_group(&"player")
		root.add_child(player)
		var package: DeliveryPackage = _package("res://data/traps/balance.tres")
		var trap: BalanceTrapBehavior = package.trap_behavior
		for key: StringName in all_keys:
			package.initialize_trap()
			trap = package.trap_behavior
			package.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(15.0)), Vector3.ZERO)
			var start: float = 15.0
			for tick: int in 30:
				var input: Dictionary = {"steady": true, "balance": Vector2.ZERO}
				input.merge(all_keys[key])
				package._accept_tender_input(1, input)
				PackageRescue.simulate_cargo(package, TICK)
			if key == seat_info["key"]:
				_expect(trap.tilt_degrees < start - 1.0,
					"%s: %s, the key its screen shows, straightens the box (%.1f)" % [seat_info["name"], key, trap.tilt_degrees])
			else:
				_expect(trap.tilt_degrees > start - 0.3,
					"%s: %s does nothing (%.1f)" % [seat_info["name"], key, trap.tilt_degrees])
		# The card lights the same key: the tilt on this player's screen.
		var screen: Vector2 = CargoCare.screen_frame(Vector2(1.0, 0.0), _vehicle.global_basis,
			PackageRescue.view_basis_of(player))
		var view: CarePromptView = CarePromptView.new()
		root.add_child(view)
		view.show_step(&"lean", {"screen_tilt": screen, "gesture": {"kind": &"lean"}})
		_expect(view.lean_key() == seat_info["key"],
			"%s: the card lights %s (it says %s, tilt %s)" % [seat_info["name"], seat_info["key"], view.lean_key(), screen])
		view.free()
		package.free()
		player.free()
		seat.free()
	var upright: CarePromptView = CarePromptView.new()
	root.add_child(upright)
	upright.show_step(&"lean", {"screen_tilt": Vector2.ZERO})
	_expect(upright.lean_key() == &"", "Upright, every key asks")
	upright.free()


## The head goes toward the truck's right times the push, whichever way the
## seat looks, and however the truck sits.
func _test_body_lean() -> void:
	var facings: Dictionary = {"left seat": Vector3.RIGHT, "rack seat": Vector3.LEFT, "cab": Vector3.FORWARD}
	for label: String in facings:
		for yaw: float in [0.0, PI * 0.5]:
			var truck_right: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, yaw)
			for push: float in [1.0, -1.0]:
				var body := Node3D.new()
				root.add_child(body)
				body.global_basis = Basis.looking_at(facings[label], Vector3.UP)
				body.rotation.x = 0.18
				var resting: float = body.global_basis.y.dot(truck_right)
				SeatPose.lean_body(body, truck_right, push)
				var moved: float = body.global_basis.y.dot(truck_right) - resting
				_expect(moved * push > 0.15, "%s, truck yawed %.0f: the head moves to %s (%.2f)" % [
					label, rad_to_deg(yaw), "the truck's right" if push > 0.0 else "its left", moved])
				_expect(absf(body.global_basis.y.dot(Vector3.UP)) > 0.9, "%s: it leans, it does not fall over" % label)
				body.free()
	var still := Node3D.new()
	root.add_child(still)
	var before: Basis = still.global_basis
	SeatPose.lean_body(still, Vector3.RIGHT, 0.0)
	_expect(still.global_basis.is_equal_approx(before), "No push, no lean")
	still.free()


func _test_scrub() -> void:
	var package: DeliveryPackage = _package("res://data/traps/liquid.tres")
	var trap: LiquidTrapBehavior = package.trap_behavior
	trap.spill_amount = 40.0
	var swings: Array[StringName] = [&"left", &"right", &"left", &"right"]
	for swing: StringName in swings:
		package._accept_tender_input(1, {"direction_pressed": swing, "balance": Vector2.ZERO})
		# The host may tick more than once before the next sample: one press.
		for tick: int in 6:
			PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.scrubs == 3, "Four alternating presses are three scrubs, however many ticks (%d)" % trap.scrubs)
	_expect(is_equal_approx(40.0 - trap.spill_amount, 6.0), "Each dries two (%.1f left)" % trap.spill_amount)
	var wet: float = trap.spill_amount
	for tick: int in 30:
		package._accept_tender_input(1, {"steady": true, "calm": true, "steady_strength": 1.0, "balance": Vector2.ZERO})
		PackageRescue.simulate_cargo(package, TICK)
	_expect(trap.spill_amount >= wet - 0.001, "Holding the primary dries nothing through the package either")
	PackageRescue.publish_care(package)
	var gesture: Dictionary = package.care_state.get("gesture", {})
	_expect(gesture.get("kind") == &"scrub" and StringName(package.care_state.get("action", &"")) == &"scrub",
		"The scrub is published with its action (%s)" % str(gesture))
	package.free()


func _test_card() -> void:
	var keys: Dictionary = {"primary": "Clic izq.", "sides": "WASD", "swing": "A / D"}
	var state: Dictionary = {"phase": &"intact", "action": &"lean", "need_hands": true}
	var step: Dictionary = CareGuide.next_step(state, &"balance", &"", "", keys)
	_expect(step["step"] == &"lean" and step["title"] == tr("HUD_CARE_LEAN"), "Balance asks to lean")
	_expect(String(step["detail"]).contains("Clic izq.") and String(step["detail"]).contains("WASD"),
		"and names the button and the keys (%s)" % step["detail"])
	state["need_hands"] = false
	_expect(CareGuide.next_step(state, &"balance", &"", "", keys)["step"] == &"idle",
		"A box that needs nothing says so")
	state = {"phase": &"intact", "action": &"scrub", "need_hands": true}
	step = CareGuide.next_step(state, &"liquid", &"", "", keys)
	_expect(step["step"] == &"scrub" and step["title"] == tr("HUD_CARE_SCRUB"), "Liquid asks to scrub")
	_expect(String(step["detail"]).contains("A / D") and not String(step["detail"]).contains("Clic"),
		"Seated it asks for no button (%s)" % step["detail"])
	state["on_foot"] = true
	_expect(String(CareGuide.next_step(state, &"liquid", &"", "", keys)["detail"]).contains("Clic izq."),
		"On foot the primary is held to stop the walk")
	var pad: Dictionary = CargoCare.control_names(true, "A")
	var pc: Dictionary = CargoCare.control_names(false, "E")
	_expect(pc["sides"] == "WASD" and pad["sides"] == tr("HUD_CARE_KEY_STICK"), "Each device names its own keys")
	var view: CarePromptView = CarePromptView.new()
	root.add_child(view)
	view.show_step(&"lean", {"gesture": {"kind": &"lean", "side": 1.0}, "axis": 0.0, "primary": true})
	view.show_step(&"scrub", {"axis": 0.0})
	view.played.clear()
	view.show_step(&"scrub", {"axis": 1.0})
	_expect(view.played.has(&"tick"), "A swing of the stick clicks")
	view.played.clear()
	view.show_step(&"scrub", {"axis": 1.0})
	_expect(not view.played.has(&"tick"), "Holding the stick over does not click again")
	view.show_step(&"scrub", {"axis": -1.0})
	_expect(view.played.has(&"tick"), "The swing back does")
	view.free()


## The body follows what the box says, for every peer.
func _test_body() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var package: DeliveryPackage = _package("res://data/traps/balance.tres")
	package.add_to_group(&"cargo")
	var me: int = player.get_multiplayer_authority()
	package.set_tender(me)
	_expect(is_zero_approx(float(SeatPose.push_for_peer(self, me))), "A box with no gesture leaves the body still")
	package.care_state = {"gesture": {"kind": &"lean", "side": 1.0, "push": -1.0}}
	_expect(is_equal_approx(float(SeatPose.push_for_peer(self, me)), -1.0), "The body leans as the box's state says")
	package.set_tender(0)
	_expect(is_zero_approx(float(SeatPose.push_for_peer(self, me))), "Someone else's box does not move this body")
	player.free()
	package.free()
	await process_frame


func _test_tutorial() -> void:
	var catalog: Script = load("res://scripts/ui/tutorial_catalog.gd")
	var balance: Dictionary = catalog.call(&"card", &"balance")
	var liquid: Dictionary = catalog.call(&"card", &"liquid")
	_expect(String(balance["keyboard"]).contains("WASD") and String(balance["action"]).contains("WASD"),
		"Balance's tutorial card shows the push (%s / %s)" % [balance["keyboard"], balance["action"]])
	_expect(String(liquid["keyboard"]) == "A/D" and not String(liquid["action"]).contains("Mantené"),
		"Liquid's shows the scrub, not the hold (%s)" % liquid["action"])
	_expect(String(liquid["gamepad"]).contains("stick") or String(liquid["gamepad"]).contains("Stick"),
		"and the stick on a gamepad")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
