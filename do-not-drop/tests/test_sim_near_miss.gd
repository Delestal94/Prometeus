extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_sim_near_miss.gd
## The balance harness's near miss (tests/sim_trap_balance.gd, N-229):
## - any trap: a box that arrives with 5 to 25 of integrity was nearly lost;
##   one below 5 (and above 0), above 25, or ruined was not;
## - Noisy: a box that hit full agitation (integrity 0) and was calmed before
##   it got loose also counts; for any other trap 0 is not a near miss;
## - with the real NoisyTrapBehavior and noisy.tres: a burst to the top, then
##   calming in time, leaves it not ruined, and the harness counts it.

const SIM = preload("res://tests/sim_trap_balance.gd")
const NOISY_DATA: String = "res://data/traps/noisy.tres"

var _failures: int = 0


func _initialize() -> void:
	_expect(SIM.is_near_miss(&"fragile", false, 24.4), "Inside the band is a near miss")
	_expect(SIM.is_near_miss(&"fragile", false, 5.0) and SIM.is_near_miss(&"fragile", false, 25.0),
		"Both edges of the band count")
	_expect(not SIM.is_near_miss(&"fragile", false, 26.5), "Above 25 is not a near miss")
	_expect(not SIM.is_near_miss(&"fragile", false, 4.9), "Below 5 is not a near miss for Fragile")
	_expect(not SIM.is_near_miss(&"fragile", false, 0.0), "Zero is not a near miss for other traps")
	_expect(not SIM.is_near_miss(&"hostile", true, 20.0), "A ruined box is never a near miss")
	_expect(SIM.is_near_miss(&"noisy", false, 0.0), "Noisy rescued at full agitation is a near miss")
	_expect(SIM.is_near_miss(&"noisy", false, 20.0), "Noisy keeps the band too")
	_expect(not SIM.is_near_miss(&"noisy", true, 0.0), "Noisy that got loose is lost, not nearly")
	_expect(not SIM.is_near_miss(&"noisy", false, 3.0), "Noisy just below the band without topping out is not")
	_test_real_noisy()
	if _failures == 0:
		print("PASS: harness near miss, band and Noisy's rescue at full agitation")
	quit(_failures)


func _test_real_noisy() -> void:
	var definition := load(NOISY_DATA) as TrapDefinition
	var trap := definition.create_behavior() as ITrapBehavior
	trap.on_setup(null, definition.params.duplicate(true))
	var lowest: float = trap.integrity
	for shake: int in range(15):
		trap.on_impact(1.0)
		lowest = minf(lowest, trap.integrity)
	_expect(is_zero_approx(lowest), "A burst of 15 shakes takes it to full agitation")
	# Calmed right away, well inside the grace at the top.
	for tick: int in range(120):
		trap.on_physics_process(null, 1.0 / 60.0, {"input": {"calm": true}})
		lowest = minf(lowest, trap.integrity)
	var ruined: bool = trap.get_state() == ITrapBehavior.TrapState.RUINED
	_expect(not ruined, "Calmed in time, it did not get loose")
	_expect(SIM.is_near_miss(definition.id, ruined, lowest), "And the harness counts it as a near miss")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
