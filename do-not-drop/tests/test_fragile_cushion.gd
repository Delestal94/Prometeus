extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fragile_cushion.gd
## Fragile's "Amortiguá" and the bomb's "Pedí el código" through the package on
## the host (N-117), where test_fragile.gd and test_explosive_trap.gd look at
## the behaviors alone:
## - a speed bump announces itself (RoadImpacts): found ahead along the truck's
##   heading and inside the lookahead, not behind, not off to the side, not
##   when barely moving;
## - a box riding over a bump at speed takes the jolt once, a slow one takes
##   none, and a tap inside the window before it softens it (a tenth of the
##   damage) while a tap held down, one that comes too early, or none does not;
## - the tap arrives like any other input (the care input's sample, and the
##   assistant's), counts once however many ticks the host makes before the
##   next sample, and the same goes for a sequence key (the edges are spent);
## - the care state carries the cushion state and the bomb's reader ("driver"
##   unless the owner is the driver), which the box, the card and the
##   dashboard read on every peer.

const VEHICLE_SOURCE: String = """extends Node3D
var driver_peer_id: int = 0
var velocity := Vector3.ZERO
func carries(_point: Vector3, _margin: float = 0.0) -> bool:
	return true
func point_velocity(_point: Vector3) -> Vector3:
	return velocity
func needs_sweep(_package: Node, _margin: float = 0.0) -> bool:
	return false
"""
const TICK: float = 1.0 / 60.0
const FRAGILE: String = "res://data/traps/fragile.tres"
const EXPLOSIVE: String = "res://data/traps/explosive.tres"

var _failures: int = 0
var _serial: int = 0
var _vehicle: Node3D
var _run_manager: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_run_manager = root.get_node(^"/root/RunManager")
	_test_road_lookup()
	await _test_crossings()
	await _test_input_path()
	await _test_state_and_reader()
	_run_manager.set(&"is_running", false)
	if _failures == 0:
		print("PASS: bumps announce themselves, a tap softens the jolt once, and the state reaches every peer")
	quit(_failures)


# --- The road ----------------------------------------------------------------


func _test_road_lookup() -> void:
	var bump := SpeedBumpSegment.new()
	root.add_child(bump)
	_expect(bump.is_in_group(RoadImpacts.GROUP), "A speed bump joins the announced impacts")
	_expect(bump.announced_impacts().size() == 1 and is_equal_approx(bump.announced_impacts()[0].z, -10.2),
		"It announces the foot of its approach ramp")
	var plain := StraightSegment.new()
	root.add_child(plain)
	_expect(not plain.is_in_group(RoadImpacts.GROUP), "A plain road announces nothing")
	var heading := Vector3(0.0, 0.0, -13.9)
	var found: Dictionary = RoadImpacts.nearest_ahead(self, Vector3(0.0, 0.3, 10.0), heading, 2.0)
	_expect(not found.is_empty() and is_equal_approx(float(found["eta"]), 20.2 / 13.9),
		"The bump is found ahead with its time to reach (%s)" % str(found))
	_expect(RoadImpacts.nearest_ahead(self, Vector3(0.0, 0.3, 10.0), heading, 1.0).is_empty(),
		"Beyond the lookahead it is not announced yet")
	_expect(RoadImpacts.nearest_ahead(self, Vector3(0.0, 0.3, -20.0), heading, 2.0).is_empty(),
		"Once past it, it is behind")
	_expect(RoadImpacts.nearest_ahead(self, Vector3(30.0, 0.3, 0.0), heading, 2.0).is_empty(),
		"A bump off to the side is not on the way")
	_expect(RoadImpacts.nearest_ahead(self, Vector3(0.0, 0.3, 10.0), Vector3(0.0, 0.0, -1.0), 30.0).is_empty(),
		"Barely moving there is no heading to look along")
	_expect(RoadImpacts.nearest_ahead(self, Vector3(0.0, 0.3, 10.0), -heading, 5.0).is_empty(),
		"Driving away from it, it is not ahead")
	var here: Dictionary = RoadImpacts.nearest_ahead(self, Vector3(0.0, 0.3, -10.4), heading, 1.0)
	_expect(not here.is_empty() and float(here["distance"]) < 0.0 and float(here["eta"]) == 0.0,
		"Just over the ramp foot it is still found, at zero")
	var turned := SpeedBumpSegment.new()
	turned.rotation.y = PI * 0.5
	turned.position = Vector3(100.0, 0.0, 0.0)
	root.add_child(turned)
	var sideways: Dictionary = RoadImpacts.nearest_ahead(self, Vector3(100.0, 0.3, 0.0), Vector3(-10.0, 0.0, 0.0), 3.0)
	_expect(not sideways.is_empty() and is_equal_approx(float(sideways["distance"]), 10.2)
			and found["id"] != sideways["id"], "A turned segment is found along its own road")
	bump.free()
	plain.free()
	turned.free()


# --- Crossing a bump -----------------------------------------------------------


func _make_vehicle() -> Node3D:
	if is_instance_valid(_vehicle):
		return _vehicle
	var script := GDScript.new()
	script.source_code = VEHICLE_SOURCE
	script.reload()
	_vehicle = Node3D.new()
	_vehicle.set_script(script)
	_vehicle.add_to_group(&"vehicle")
	root.add_child(_vehicle)
	return _vehicle


func _package(definition_path: String) -> DeliveryPackage:
	_serial += 1
	var package := DeliveryPackage.new()
	package.package_id = StringName("cushion_%d" % _serial)
	package.trap_definition = load(definition_path)
	package.freeze = true
	root.add_child(package)
	package.set_tender(1)
	return package


## Drives a box over a speed bump at `kmh`. `tap_at` is the eta (s) at which
## the tap arrives (-1: none), `hold` sends the primary held down instead. The
## bump's foot is at z = -10.2. Returns the integrity lost.
func _cross(kmh: float, tap_at: float, hold: bool = false) -> float:
	var bump := SpeedBumpSegment.new()
	root.add_child(bump)
	var vehicle: Node3D = _make_vehicle()
	var package: DeliveryPackage = _package(FRAGILE)
	_run_manager.set(&"is_running", true)
	var speed: float = kmh / 3.6
	vehicle.set(&"velocity", Vector3(0.0, 0.0, -speed))
	var z: float = 6.0
	var tapped: bool = false
	var before: float = package.integrity
	var ticks_over: int = 0
	while z > -16.0:
		package.global_position = Vector3(0.0, 0.3, z)
		var eta: float = float(package.trap_behavior.cushion_state()["eta"])
		var input: Dictionary = {"steady": hold, "calm": hold, "tap": false, "balance": Vector2.ZERO}
		if tap_at >= 0.0 and not tapped and eta >= 0.0 and eta <= tap_at:
			input["tap"] = true
			tapped = true
		package._accept_tender_input(1, input)
		PackageRescue.simulate_cargo(package, TICK)
		z -= speed * TICK
		ticks_over += int(z < -10.2)
	var lost: float = before - package.integrity
	package.free()
	bump.free()
	return lost


func _test_crossings() -> void:
	var fast: float = _cross(50.0, -1.0)
	_expect(is_equal_approx(fast, 35.0), "A bump at 50 km/h is a heavy hit, once (lost %.1f)" % fast)
	_expect(is_equal_approx(_cross(30.0, -1.0), 0.0), "A bump at 30 km/h is swallowed by the truck")
	_expect(is_equal_approx(_cross(40.0, -1.0), 0.0), "Around 40 km/h it does not hurt either")
	var tapped: float = _cross(50.0, 0.25)
	_expect(is_equal_approx(tapped, 3.5), "A tap a quarter second before softens it to a tenth (lost %.1f)" % tapped)
	_expect(is_equal_approx(_cross(50.0, 0.33), 3.5), "A tap at the edge of the window still counts")
	_expect(is_equal_approx(_cross(50.0, 0.6), 35.0), "A tap that comes too early is spent by the time it lands")
	_expect(is_equal_approx(_cross(50.0, -1.0, true), 35.0), "Holding the primary down protects nothing")
	await process_frame
	var kmh: float = 60.0
	_expect(_cross(kmh, -1.0) >= 35.0, "The fastest bump is at least as hard")


# --- The input's way in ----------------------------------------------------------


func _test_input_path() -> void:
	var package: DeliveryPackage = _package(FRAGILE)
	package._accept_tender_input(1, {"steady": false, "tap": true})
	_expect(bool(package.player_input.get("tap", false)), "A tap sample reaches the package's combined input")
	PackageRescue.consume_input_edges(package)
	_expect(not bool(package.player_input.get("tap", false)), "Once used it is spent")
	package.set_assistant(2)
	package._accept_tender_input(2, {"steady": false, "tap": true})
	_expect(bool(package.player_input.get("tap", false)), "The assistant's tap counts too")
	PackageRescue.consume_input_edges(package)

	# The care input, the way the seat's owner sends it (PackageRescue.submit_care_input).
	var operator := Node3D.new()
	operator.add_to_group(&"player")
	root.add_child(operator)
	package.global_position = Vector3(0.0, 0.3, 0.0)
	package.submit_care_input({"steady": false, "calm": false, "tap": true, "balance": Vector2.ZERO})
	_expect(bool(package.player_input.get("tap", false)), "A tap in the care input is kept")
	package.submit_care_input({"steady": true, "calm": true, "tap": true, "work": true, "balance": Vector2.ZERO})
	_expect(not bool(package.player_input.get("tap", false)), "Working with a tool takes both hands: no tap")
	package.submit_care_input({"steady": true, "tap": false, "balance": Vector2.ZERO})
	_expect(bool(package.player_input.get("steady", false)) and not bool(package.player_input.get("tap", false)),
		"Holding sends no tap")

	# One tap counts once, however many host ticks pass before the next sample.
	var behavior: FragileTrapBehavior = package.trap_behavior
	behavior.on_setup(null, {})
	_make_vehicle().set(&"velocity", Vector3.ZERO)
	package._accept_tender_input(1, {"tap": true, "balance": Vector2.ZERO})
	for tick: int in range(5):
		PackageRescue.simulate_cargo(package, TICK)
	_expect(behavior.tap_count == 1, "One press is one tap across several host ticks (%d)" % behavior.tap_count)
	# A press held down long enough to be re-sampled is still the one press: the
	# client only sends the edge.
	package._accept_tender_input(1, {"tap": false, "balance": Vector2.ZERO})
	PackageRescue.simulate_cargo(package, TICK)
	_expect(behavior.tap_count == 1, "No new sample, no new tap")

	# A sequence key too: the bomb's code advances once per press.
	var bomb_box: DeliveryPackage = _package(EXPLOSIVE)
	var bomb: ExplosiveTrapBehavior = bomb_box.trap_behavior
	var first_step: StringName = bomb.sequence[0]
	bomb_box._accept_tender_input(1, {"direction_pressed": first_step, "balance": Vector2.ZERO})
	for tick: int in range(4):
		PackageRescue.simulate_cargo(bomb_box, TICK)
	_expect(bomb.sequence_index == 1,
		"A key press advances the code once, not once per host tick (%d)" % bomb.sequence_index)
	_expect(bomb.sequence_state()["mistakes"] == 0, "Nor does it read as a mistake the second time")
	operator.free()
	bomb_box.free()
	package.free()
	await process_frame


# --- What every peer reads --------------------------------------------------------


func _test_state_and_reader() -> void:
	var vehicle: Node3D = _make_vehicle()
	vehicle.set(&"velocity", Vector3.ZERO)
	var fragile: DeliveryPackage = _package(FRAGILE)
	PackageRescue.simulate_cargo(fragile, TICK)
	PackageRescue.publish_care(fragile)
	var cushion: Dictionary = fragile.care_state.get("cushion", {})
	_expect(not cushion.is_empty() and cushion.has("eta") and cushion.has("ready") and cushion.has("window"),
		"Fragile publishes its cushion state with the care state (%s)" % str(fragile.care_state.keys()))
	_expect(StringName(fragile.care_state.get("action", &"x")) == &"", "and asks for no held hands")
	var seen: int = int(cushion.get("taps", -1))
	fragile._accept_tender_input(1, {"tap": true, "balance": Vector2.ZERO})
	PackageRescue.simulate_cargo(fragile, TICK)
	PackageRescue.simulate_cargo(fragile, 0.1)
	_expect(int((fragile.care_state.get("cushion", {}) as Dictionary).get("taps", -1)) == seen + 1,
		"A tap goes out at once, not on the next ten-hertz publish")

	var bomb_box: DeliveryPackage = _package(EXPLOSIVE)
	bomb_box.set_tender(2)
	vehicle.set(&"driver_peer_id", 1)
	PackageRescue.simulate_cargo(bomb_box, TICK)
	PackageRescue.publish_care(bomb_box)
	var sequence: Dictionary = bomb_box.care_state.get("sequence", {})
	_expect(StringName(sequence.get("reader", &"")) == &"driver", "A driver who is not the owner reads the code")
	_expect((sequence.get("steps", []) as Array).size() == 3, "The code travels with the care state")
	_expect(not LocText.render(bomb_box.care_state.get("hint", [])).contains("↑")
			and not LocText.render(bomb_box.care_state.get("hint", [])).contains("←"), "The hint names no arrow")
	vehicle.set(&"driver_peer_id", 2)
	PackageRescue.simulate_cargo(bomb_box, TICK)
	PackageRescue.publish_care(bomb_box)
	_expect(StringName((bomb_box.care_state.get("sequence", {}) as Dictionary).get("reader", &"")) == &"owner",
		"An owner who drives reads it themselves")
	vehicle.set(&"driver_peer_id", 0)
	PackageRescue.simulate_cargo(bomb_box, TICK)
	PackageRescue.publish_care(bomb_box)
	_expect(StringName((bomb_box.care_state.get("sequence", {}) as Dictionary).get("reader", &"")) == &"owner",
		"With nobody at the wheel the owner reads it")
	var on_dashboard: Array[Dictionary] = DashboardGps.bomb_codes([bomb_box])
	_expect(on_dashboard.is_empty(), "Then the dashboard leaves it out")
	vehicle.set(&"driver_peer_id", 1)
	PackageRescue.simulate_cargo(bomb_box, TICK)
	PackageRescue.publish_care(bomb_box)
	on_dashboard = DashboardGps.bomb_codes([bomb_box])
	var code: Array = bomb_box.trap_behavior.sequence
	_expect(on_dashboard.size() == 1 and (on_dashboard[0]["steps"] as Array) == code,
		"and the dashboard lists the code once a driver is there")
	fragile.free()
	bomb_box.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
