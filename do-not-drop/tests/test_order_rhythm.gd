extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_order_rhythm.gd
##
## Order arrival curve of the day (expansion D-0803, order_rhythm.gd):
## - orders a day = 6 + 2 per player, capped at 16;
## - the same seed and crew size give the same arrival minutes, sorted, inside
##   the order hours and none in the last hour;
## - over many days the busiest hours are 10-12 and the lunch dip is lower
##   (the histogram is printed as the curve).

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_count()
	_test_determinism_and_range()
	_test_curve()
	quit(_failures)


func _test_count() -> void:
	_expect(OrderRhythm.orders_for_day(1) == 8, "1 player: 8 orders")
	_expect(OrderRhythm.orders_for_day(4) == 14, "4 players: 14 orders")
	_expect(OrderRhythm.orders_for_day(8) == 16, "8 players: capped at 16")
	_expect(OrderRhythm.orders_for_day(0) == 8, "0 players counts as 1")


func _test_determinism_and_range() -> void:
	var a := OrderRhythm.arrival_minutes(42, 3)
	var b := OrderRhythm.arrival_minutes(42, 3)
	_expect(a == b, "same seed, same minutes")
	_expect(a.size() == 12, "3 players: 12 arrivals")
	_expect(a != OrderRhythm.arrival_minutes(43, 3), "another seed, other minutes")
	var sorted := a.duplicate()
	sorted.sort()
	_expect(a == sorted, "minutes come sorted")
	for seed_value in 50:
		for minute in OrderRhythm.arrival_minutes(seed_value, 8):
			_expect(minute >= CompanyTuning.DAY_START_MIN, "arrival not before opening")
			_expect(minute < CompanyTuning.ORDER_LAST_ARRIVAL_MIN, "no arrival in the last hour")


func _test_curve() -> void:
	var all: Array[int] = []
	for seed_value in 400:
		all.append_array(OrderRhythm.arrival_minutes(seed_value, 4))
	var histogram := OrderRhythm.hourly_histogram(all)
	print("orders per hour from 08:00 (400 days): ", histogram)
	_expect(histogram.size() == 11, "11 hourly buckets")
	_expect(histogram.max() == histogram[2] or histogram.max() == histogram[3], "rush at 10:00-12:00")
	_expect(histogram[5] < histogram[3], "lunch dip below the rush")
	_expect(histogram[10] < histogram[0], "last hour thinner than opening")
	_expect(OrderRhythm.weight_at(10 * 60) == 3.0, "weight at 10:00")
	_expect(OrderRhythm.weight_at(7 * 60) == 0.0, "no weight before opening")
	_expect(OrderRhythm.weight_at(19 * 60) == 0.0, "no weight after the order hours")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)
	print("FAIL: ", label)
