extends SceneTree
## 1000 seeded orders per house count: every result stays inside the campaign
## curve, and identical inputs always produce identical house assignments.

const ORDER_BALANCER = preload("res://scripts/gameplay/traps/order_balancer.gd")
const TRAP_PATHS: Array[String] = [
	"res://data/traps/fragile.tres",
	"res://data/traps/growing_weight.tres",
	"res://data/traps/balance.tres",
	"res://data/traps/liquid.tres",
	"res://data/traps/noisy.tres",
	"res://data/traps/explosive.tres",
	"res://data/traps/hostile.tres",
]

var _failures: int = 0
var _difficulty: Dictionary = {}


func _initialize() -> void:
	var traps: Array = []
	for path: String in TRAP_PATHS:
		var trap: Resource = load(path)
		traps.append(trap)
		_difficulty[StringName(trap.get(&"id"))] = int(trap.get(&"difficulty"))
	var starter: Array = [traps[0], traps[1]]
	var run_bands: Array[int] = [0, 9, 10, 20]
	var saw_two_hard_after_ten := false

	for houses: int in range(1, 5):
		for seed_value: int in range(1000):
			var completed_runs: int = run_bands[seed_value % run_bands.size()]
			var order := _build(traps, houses, completed_runs, seed_value)
			_check(order, traps, houses, completed_runs, seed_value)
			var repeat := _build(traps, houses, completed_runs, seed_value)
			_expect(order == repeat, "Same seed changed order for %d houses (seed %d)" % [houses, seed_value])
			var starter_order := _build(starter, houses, completed_runs, seed_value)
			_check(starter_order, starter, houses, completed_runs, seed_value)
			if completed_runs >= 10 and _hard_count(order) >= 2:
				saw_two_hard_after_ten = true
	_expect(saw_two_hard_after_ten, "Difficulty-4 pairs become eligible after 10 completed runs")

	if _failures == 0:
		print("PASS: 1000 deterministic orders per house count obey every balance rule")
	quit(_failures)


func _build(traps: Array, houses: int, completed_runs: int, seed_value: int) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return ORDER_BALANCER.build_order(traps, houses, completed_runs, rng)


func _check(order: Array[StringName], traps: Array, houses: int, completed_runs: int,
		seed_value: int) -> void:
	_expect(order.size() == houses, "Expected %d houses, got %s (seed %d, runs %d)" % [houses, order, seed_value, completed_runs])
	if order.size() != houses:
		return
	var total := 0
	var easy := false
	for trap_id: StringName in order:
		var difficulty := int(_difficulty.get(trap_id, 99))
		total += difficulty
		easy = easy or difficulty <= 2
	_expect(total <= 4 + houses + mini(completed_runs, 6), "Budget exceeded by %s (seed %d, runs %d)" % [order, seed_value, completed_runs])
	_expect(easy, "Order has no difficulty <= 2: %s (seed %d)" % [order, seed_value])
	if completed_runs < 10:
		_expect(_hard_count(order) <= 1, "Early order paired difficulty 4: %s (seed %d)" % [order, seed_value])

	var distinct: int = traps.size()
	for cycle_start: int in range(0, order.size(), distinct):
		var used: Dictionary = {}
		for index: int in range(cycle_start, mini(cycle_start + distinct, order.size())):
			_expect(not used.has(order[index]), "Trap repeated before the pool was exhausted: %s (seed %d)" % [order, seed_value])
			used[order[index]] = true


func _hard_count(order: Array[StringName]) -> int:
	var count := 0
	for trap_id: StringName in order:
		if int(_difficulty.get(trap_id, 0)) == 4:
			count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
