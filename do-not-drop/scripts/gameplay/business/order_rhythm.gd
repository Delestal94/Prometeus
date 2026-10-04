class_name OrderRhythm
extends RefCounted
## When the day's customer orders come in (expansion D-0803, "Modo Empresa").
##
## How many orders a day comes from the crew size, and each arrival minute is
## drawn from the hourly curve of CompanyTuning.ORDER_HOUR_WEIGHTS with a seeded
## generator: the same seed and crew size give the same minutes on every peer.
## Pure functions: no node, no autoload, no UI.


## Orders of one day: base + per player, capped.
static func orders_for_day(players: int) -> int:
	var count := CompanyTuning.ORDERS_BASE_PER_DAY + CompanyTuning.ORDERS_PER_PLAYER * maxi(players, 1)
	return mini(count, CompanyTuning.ORDERS_MAX_PER_DAY)


## Relative weight of the hour that holds `minute` (0 outside the order hours).
static func weight_at(minute: int) -> float:
	var hour := _hour_index(minute)
	if hour < 0:
		return 0.0
	return CompanyTuning.ORDER_HOUR_WEIGHTS[hour]


## Sorted arrival minutes (since midnight) of the day's orders.
static func arrival_minutes(day_seed: int, players: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = day_seed
	var weights: Array[float] = CompanyTuning.ORDER_HOUR_WEIGHTS
	var total := 0.0
	for weight: float in weights:
		total += weight
	var out: Array[int] = []
	for _i in orders_for_day(players):
		var pick := rng.randf() * total
		var hour := 0
		while hour < weights.size() - 1 and pick >= weights[hour]:
			pick -= weights[hour]
			hour += 1
		var start := CompanyTuning.DAY_START_MIN + hour * 60
		out.append(mini(start + rng.randi_range(0, 59), CompanyTuning.ORDER_LAST_ARRIVAL_MIN - 1))
	out.sort()
	return out


## Orders per game hour (08:00 first), to print the curve of a day.
static func hourly_histogram(minutes: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.resize(CompanyTuning.ORDER_HOUR_WEIGHTS.size())
	out.fill(0)
	for minute in minutes:
		var hour := _hour_index(minute)
		if hour >= 0:
			out[hour] += 1
	return out


static func _hour_index(minute: int) -> int:
	var hour := floori((minute - CompanyTuning.DAY_START_MIN) / 60.0)
	if minute < CompanyTuning.DAY_START_MIN or hour >= CompanyTuning.ORDER_HOUR_WEIGHTS.size():
		return -1
	return hour
