extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_route_duration_budget.gd
## The golden rule of 2-5 minutes per delivery (tareas de Nacho N-102),
## checked without driving: route.gd cuts each leg to a time budget, so for
## 1 to 4 houses the road it plans -- and the one it actually builds, for a
## few seeds -- takes between 2 and 5 minutes at the average speed the
## driving bench measured (tests/bench_route_duration.gd), counting each
## stop at a house. One house gets long legs, four get short ones.

const Route = preload("res://scripts/gameplay/route/route.gd")
const MIN_SECONDS: float = 120.0
const MAX_SECONDS: float = 300.0
## Most a leg may run past its target: the segment that crosses it finishes.
const MAX_OVERSHOOT: float = 80.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_leg: float = INF
	for houses: int in range(1, 5):
		var leg: float = Route.leg_target_length(houses)
		_expect(leg >= Route.LEG_MIN_LENGTH and leg <= Route.LEG_MAX_LENGTH,
			"%d houses: legs of %.0f m, within %.0f-%.0f" % [houses, leg, Route.LEG_MIN_LENGTH, Route.LEG_MAX_LENGTH])
		_expect(leg <= previous_leg, "More houses never means longer legs (%d houses: %.0f m)" % [houses, leg])
		previous_leg = leg
		var planned: float = _seconds(leg * (houses + 1), houses)
		_expect(planned >= MIN_SECONDS and planned <= MAX_SECONDS,
			"%d houses: the planned road takes %.1f min" % [houses, planned / 60.0])

	var network: Node = root.get_node(^"/root/NetworkManager")
	for houses: int in range(1, 5):
		for seed_value: int in [11, 222, 3333]:
			network.set(&"world_seed", seed_value)
			network.set(&"world_house_count", houses)
			var route: Node3D = (load("res://scenes/gameplay/route/route.tscn") as PackedScene).instantiate()
			route.set(&"batch_dressing", false)
			root.add_child(route)
			var length: float = float(route.get(&"route_length"))
			var leg: float = Route.leg_target_length(houses)
			var shortest: float = (houses + 1) * maxf(leg * (1.0 - Route.LEG_LENGTH_JITTER), Route.LEG_MIN_LENGTH)
			var longest: float = (houses + 1) * (minf(leg * (1.0 + Route.LEG_LENGTH_JITTER), Route.LEG_MAX_LENGTH) + MAX_OVERSHOOT)
			_expect(length >= shortest and length <= longest,
				"Seed %d, %d houses: %.0f m of road, within %.0f-%.0f" % [seed_value, houses, length, shortest, longest])
			var built: float = _seconds(length, houses)
			_expect(built >= MIN_SECONDS and built <= MAX_SECONDS,
				"Seed %d, %d houses: the built road takes %.1f min" % [seed_value, houses, built / 60.0])
			route.free()
			await process_frame
	network.set(&"world_seed", 0)
	network.set(&"world_house_count", 0)

	if _failures == 0:
		print("PASS: with 1 to 4 houses, the planned and the built routes take 2-5 minutes")
	quit(_failures)


func _seconds(length: float, houses: int) -> float:
	return length / Route.ROUTE_CRUISE_SPEED + houses * Route.HOUSE_STOP_SECONDS


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
