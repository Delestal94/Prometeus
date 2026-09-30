extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fragile.gd
## Fragile trap: damage thresholds, the OK / at-risk / ruined states, and two
## packages taking damage independently.
## "Amortiguá" (N-117), on the behavior alone (the road and the network are in
## test_fragile_cushion.gd):
## - one tap of the primary in the short window before an announced hit cuts
##   its damage to a tenth; holding the button does nothing, only the tap;
## - a tap too early, a second tap inside the wait, and a hit nobody announced
##   are not softened; after the wait a new tap counts again;
## - a bump only hurts above the safe speed, and hurts more the faster it is;
## - reset with on_setup clears the taps, and two instances never share them.

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
var _failures: int = 0


func _initialize() -> void:
	# Keep test instances outside SceneTree so autoload startup is irrelevant.
	var first: RigidBody3D = PACKAGE_SCENE.instantiate()
	var second: RigidBody3D = PACKAGE_SCENE.instantiate()
	first.call("initialize_trap")
	second.call("initialize_trap")
	_expect(float(first.get("integrity")) == 100.0, "Starts with full integrity")
	first.call("apply_impact", 2.99)
	_expect(float(first.get("integrity")) == 100.0, "Subthreshold motion causes no damage")
	first.call("apply_impact", 3.0)
	_expect(float(first.get("integrity")) == 90.0, "Light threshold applies 10 damage")
	first.call("apply_impact", 7.0)
	_expect(float(first.get("integrity")) == 55.0, "Heavy threshold applies 35 damage")
	_expect(int(first.get("trap_state")) == 0, "Integrity above 40 is OK")
	first.call("apply_impact", 7.0)
	_expect(float(first.get("integrity")) == 20.0, "Damage is progressive")
	_expect(int(first.get("trap_state")) == 1, "Low integrity enters AT_RISK")
	_expect(float(second.get("integrity")) == 100.0, "Shared definition never shares mutable state")
	first.call("apply_impact", 7.0)
	_expect(float(first.get("integrity")) == 0.0, "Integrity clamps at zero")
	# Broken isn't lost yet: it opens a rescue (docs/jugabilidad-paquetes-rescate.md).
	_expect(int(first.get("trap_state")) == 1 and first.get("care").phase == &"crisis", "Zero integrity opens a rescue")
	first.call("apply_impact", 20.0)
	_expect(float(first.get("integrity")) == 0.0, "Ruined package cannot lose further integrity")
	first.call("initialize_trap")
	_expect(float(first.get("integrity")) == 100.0, "Reinitializing creates fresh behavior state")
	for index in range(6):
		first.call("apply_impact", 3.0)
	_expect(float(first.get("integrity")) == 40.0 and int(first.get("trap_state")) == 1, "AT_RISK boundary includes exactly 40")
	first.free()
	second.free()
	_test_cushion()
	if _failures == 0:
		print("PASS: fragile package thresholds, states, reset and instance isolation")
	quit(_failures)


func _new_trap(config: Dictionary = {}) -> FragileTrapBehavior:
	var trap := FragileTrapBehavior.new()
	trap.on_setup(null, config)
	return trap


## Runs the last `lead` seconds before an announced hit in 10 ms ticks and
## lands an impact of `strength` at the end. `tap_at` is how long before the
## hit the tap comes (-1: none), `hold` keeps the primary held throughout, and
## `announced` false leaves the road quiet (a crash). Returns the damage.
func _hit(trap: FragileTrapBehavior, tap_at: float, hold: bool = false, announced: bool = true,
		strength: float = 8.0, lead: float = 1.0) -> float:
	var before: float = trap.integrity
	var eta: float = lead
	var tapped: bool = false
	while eta > 0.0:
		var tap: bool = tap_at >= 0.0 and not tapped and eta <= tap_at
		tapped = tapped or tap
		trap.on_physics_process(null, 0.01, {"impact_ahead": eta if announced else INF,
			"input": {"steady": hold, "calm": hold, "tap": tap}})
		eta -= 0.01
	trap.on_impact(strength)
	return before - trap.integrity


func _test_cushion() -> void:
	var bare: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(bare, -1.0), 35.0), "A heavy announced hit with no tap does full damage")
	_expect(bare.saved_hits == 0, "Nothing was softened")
	var tapped: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(tapped, 0.2), 3.5), "A tap 0.2 s before takes a heavy hit down to a tenth")
	_expect(tapped.saved_hits == 1 and tapped.tap_count == 1, "The softened hit and the tap are counted")
	var light: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(light, 0.2, false, true, 4.0), 1.0), "A light hit is softened too")
	var edge: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(edge, 0.30), 3.5), "A tap just inside the window still counts")
	var early: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(early, 0.6), 35.0), "A tap before the window has run out by the time of the hit")
	var holding: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(holding, -1.0, true), 35.0), "Holding the primary does not soften anything")
	_expect(holding.tap_count == 0, "Holding is not a tap")
	var crash: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(crash, 0.2, false, false), 35.0), "A hit nobody announced cannot be softened")
	# The wait: a second tap inside it is ignored, one after it counts.
	var mash: FragileTrapBehavior = _new_trap()
	_expect(is_equal_approx(_hit(mash, 0.6), 35.0), "The first tap was too early for that bump")
	_expect(mash.tap_count == 1, "It did count as a tap")
	# Another bump 0.9 s after that tap: still inside the 1.0 s wait.
	_expect(is_equal_approx(_hit(mash, 0.2, false, true, 8.0, 0.5), 35.0), "A tap inside the wait does not count")
	_expect(mash.tap_count == 1, "The tap inside the wait was thrown away")
	mash.on_physics_process(null, 1.1, {"input": {}})
	_expect(is_equal_approx(_hit(mash, 0.2), 3.5), "After the wait a new tap counts again")
	_expect(mash.tap_count == 2, "Two taps counted in the end")
	# Mashing: a tap every other tick is one tap.
	var rapid: FragileTrapBehavior = _new_trap()
	for tick: int in range(10):
		rapid.on_physics_process(null, 0.01, {"input": {"tap": tick % 2 == 0}})
	_expect(rapid.tap_count == 1, "Mashing inside the wait counts once (%d)" % rapid.tap_count)
	# The state the box and the card read.
	var state_trap: FragileTrapBehavior = _new_trap()
	_expect(state_trap.cushion_state()["eta"] < 0.0 and state_trap.cushion_state()["ready"],
		"A quiet road announces nothing")
	state_trap.on_physics_process(null, 0.01, {"impact_ahead": 0.5, "input": {}})
	_expect(is_equal_approx(float(state_trap.cushion_state()["eta"]), 0.5) and state_trap.cushion_due(),
		"Half a second out, the box asks for a tap")
	state_trap.on_physics_process(null, 0.01, {"impact_ahead": 2.0, "input": {}})
	_expect(state_trap.cushion_state()["eta"] < 0.0, "A bump further than the lead is not shown yet")
	state_trap.on_physics_process(null, 0.01, {"impact_ahead": 0.3, "input": {"tap": true}})
	_expect(state_trap.cushion_state()["shield"] and not state_trap.cushion_state()["ready"]
			and not state_trap.cushion_due(), "After a tap the shield is up and the next tap has to wait")
	_expect(state_trap.care_action() == &"", "Fragile asks for no held hands")
	# Bumps only hurt when taken fast.
	var jolt: FragileTrapBehavior = _new_trap()
	_expect(jolt.road_jolt_strength(8.0) == 0.0 and jolt.road_jolt_strength(9.7) == 0.0,
		"Slow, the truck swallows the bump")
	_expect(jolt.road_jolt_strength(11.1) < 3.0, "Around 40 km/h it is still below Fragile's light threshold")
	_expect(jolt.road_jolt_strength(13.9) >= 7.0, "At 50 km/h a bump is a heavy hit")
	_expect(jolt.road_jolt_strength(16.7) > jolt.road_jolt_strength(13.9), "Faster hurts more")
	var never: FragileTrapBehavior = _new_trap({"bump_jolt_per_speed": 0.0})
	_expect(never.road_jolt_strength(20.0) == 0.0, "The jolt can be turned off in the data")
	var wide: FragileTrapBehavior = _new_trap({"cushion_window": 0.6, "cushion_leak": 0.5})
	_expect(is_equal_approx(_hit(wide, 0.5), 17.5), "Window and leak come from the data")
	# Reset and isolation.
	var one: FragileTrapBehavior = _new_trap()
	var other: FragileTrapBehavior = _new_trap()
	one.on_physics_process(null, 0.01, {"input": {"tap": true}})
	_expect(one.tap_count == 1 and other.tap_count == 0, "A tap on one box never reaches another")
	other.on_physics_process(null, 0.01, {"impact_ahead": 0.2, "input": {}})
	other.on_impact(8.0)
	_expect(other.saved_hits == 0, "The other box was not shielded by the first one's tap")
	one.on_setup(null, {})
	_expect(one.tap_count == 0 and one.saved_hits == 0 and one.cushion_state()["ready"],
		"Setup clears the taps and the wait")
	var definition: Resource = load("res://data/traps/fragile.tres")
	var made: Resource = definition.call(&"create_behavior")
	var made_again: Resource = definition.call(&"create_behavior")
	made.call(&"on_setup", null, (definition.get(&"params") as Dictionary).duplicate(true))
	made.call(&"on_physics_process", null, 0.01, {"input": {"tap": true}})
	_expect(int(made.get(&"tap_count")) == 1 and int(made_again.get(&"tap_count")) == 0,
		"Two behaviors from the shared definition keep their own taps")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
