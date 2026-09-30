extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_liquid_trap.gd
## Liquid trap rules ("Fregá", N-117): tilting spills, a hard hit spills
## suddenly, an unattended spill does permanent damage and a big puddle reads
## as at risk. The mop is a scrub:
## - each swing to the other side (left then right, right then left) dries a
##   little; the first swing of a scrub only starts it, and the same side twice
##   dries nothing;
## - holding the primary or the calm input dries nothing any more;
## - a swing too soon after the last is the same swing, and a scrub that stops
##   for a while starts over;
## - the gesture state names the last side and sways the passenger's body, and
##   two boxes never share their scrub.

const LiquidBehavior = preload("res://scripts/gameplay/traps/liquid_trap_behavior.gd")
const CONFIG: Dictionary = {
	"integrity_max": 100.0, "safe_angle": 10.0, "danger_angle": 24.0,
	"leak_per_second": 8.0, "surge_per_second": 26.0, "impact_threshold": 4.0,
	"impact_spill": 18.0, "scrub_amount": 2.0, "scrub_gap": 0.08, "integrity_loss_per_spill": 0.25,
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var package := Node3D.new()
	root.add_child(package)
	await process_frame
	var behavior: LiquidTrapBehavior = LiquidBehavior.new()
	behavior.on_setup(package, CONFIG)
	package.rotation_degrees.z = 20.0
	for i: int in 20:
		behavior.on_physics_process(package, 0.1, {"input": {}})
	_expect(behavior.spill_amount > 0.0, "Tilting a liquid cargo makes it spill")

	# Holding and calming dry nothing any more.
	package.rotation_degrees.z = 0.0
	var wet: float = behavior.spill_amount
	for i: int in 10:
		behavior.on_physics_process(package, 0.1, {"input": {"steady": true, "calm": true, "steady_strength": 1.0,
			"calm_strength": 1.0}})
	_expect(behavior.spill_amount >= wet, "Holding the action no longer dries the puddle")

	# The scrub.
	behavior.on_physics_process(package, 0.1, {"input": {"direction_pressed": &"left"}})
	_expect(is_equal_approx(behavior.spill_amount, wet), "The first swing only starts the scrub")
	for pair: Array in [[&"right"], [&"left"], [&"right"]]:
		var before: float = behavior.spill_amount
		behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": pair[0]}})
		_expect(is_equal_approx(before - behavior.spill_amount, 2.0), "Other side dries 2 (%s)" % pair[0])
	_expect(behavior.scrubs == 3, "Three swings counted (%d)" % behavior.scrubs)
	var kept: float = behavior.spill_amount
	behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": &"right"}})
	behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": &"right"}})
	_expect(is_equal_approx(behavior.spill_amount, kept), "The same side again dries nothing")
	behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": &"up"}})
	behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": &"down"}})
	_expect(is_equal_approx(behavior.spill_amount, kept), "Up and down are not part of it")
	behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": &"left"}})
	_expect(is_equal_approx(kept - behavior.spill_amount, 2.0), "...and the scrub goes on from the other side")
	# Too soon: the same swing twice.
	kept = behavior.spill_amount
	behavior.on_physics_process(package, 0.03, {"input": {"direction_pressed": &"right"}})
	_expect(is_equal_approx(behavior.spill_amount, kept), "A swing 30 ms after the last does not count")
	# A pause starts it over.
	behavior.on_physics_process(package, 1.5, {"input": {}})
	kept = behavior.spill_amount
	behavior.on_physics_process(package, 0.1, {"input": {"direction_pressed": &"right"}})
	_expect(is_equal_approx(behavior.spill_amount, kept), "After a pause a lone swing only restarts the scrub")
	behavior.on_physics_process(package, 0.15, {"input": {"direction_pressed": &"left"}})
	_expect(is_equal_approx(kept - behavior.spill_amount, 2.0), "...and the next one counts")
	# A null press (the input's way of saying none) is fine.
	behavior.on_physics_process(package, 0.1, {"input": {"direction_pressed": null}})
	# It never goes below dry.
	for i: int in 200:
		var side: StringName = &"left" if i % 2 == 0 else &"right"
		behavior.on_physics_process(package, 0.12, {"input": {"direction_pressed": side}})
	_expect(is_zero_approx(behavior.spill_amount), "A long scrub dries it out completely")

	# The state the card, the box and the body read.
	behavior.on_physics_process(package, 0.12, {"input": {"direction_pressed": &"right"}})
	var gesture: Dictionary = behavior.gesture_state()
	_expect(gesture["kind"] == &"scrub" and float(gesture["last"]) == 1.0 and float(gesture["push"]) == 1.0,
		"The gesture names the last side and sways the body toward it (%s)" % str(gesture))
	behavior.on_physics_process(package, 1.0, {"input": {}})
	gesture = behavior.gesture_state()
	_expect(float(gesture["push"]) == 0.0, "The body settles when the scrub stops")
	_expect(behavior.care_action() == &"scrub", "The card is told to scrub")

	# The rest of the trap is as it was.
	package.rotation_degrees.z = 20.0
	behavior.on_setup(package, CONFIG)
	for i: int in 20:
		behavior.on_physics_process(package, 0.1, {"input": {}})
	var before_impact: float = behavior.spill_amount
	behavior.on_impact(8.0)
	_expect(behavior.spill_amount > before_impact, "A hard hit makes it spill suddenly")
	for i: int in 80:
		behavior.on_physics_process(package, 0.1, {"input": {}})
	_expect(behavior.integrity < behavior.integrity_max, "An unattended spill does permanent damage")
	_expect(behavior.get_state() != ITrapBehavior.TrapState.OK, "A big puddle reads as at risk")

	# Reset and isolation.
	var one: LiquidTrapBehavior = LiquidBehavior.new()
	var other: LiquidTrapBehavior = LiquidBehavior.new()
	one.on_setup(package, CONFIG)
	other.on_setup(package, CONFIG)
	one.spill_amount = 30.0
	one.on_physics_process(package, 0.1, {"input": {"direction_pressed": &"left"}})
	one.on_physics_process(package, 0.2, {"input": {"direction_pressed": &"right"}})
	_expect(one.scrubs == 1 and other.scrubs == 0, "One box's scrub never reaches another's")
	one.on_setup(package, CONFIG)
	_expect(one.scrubs == 0 and one.gesture_state()["last"] == 0.0, "Setup clears the scrub")
	var definition: Resource = load("res://data/traps/liquid.tres")
	var params: Dictionary = definition.get(&"params")
	_expect(params.has("scrub_amount") and not params.has("mop_rate"), "The data has the scrub, not the mop")
	package.free()
	if _failures == 0:
		print("PASS: liquid trap leaks on tilt/impact, dries only by scrubbing side to side, and damages when ignored")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
