extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/day_clock/tests/test_day_clock.gd
##
## The day_clock module on its own (docs/modulos.md, DayClock):
## - a clock starts stopped; a running anchor advances `speed` game minutes per real second
##   from its tick, a stopped one reads its minute at any tick, and a tick before the anchor's
##   never reads less (the clock doesn't run backwards);
## - to_dict() carries exactly minute, speed and paused, moved to the tick it is taken at, and
##   survives var_to_bytes; from_dict() takes it with the receiver's own tick;
## - two holders on clocks that don't agree (one machine's tick means nothing on the other)
##   read the same time 60 s later when the receiver takes its tick minus the transit, and the
##   sender's pause stops both at the same minute;
## - from_dict() refuses, changing nothing, anything that isn't exactly an anchor: not a
##   Dictionary, a key missing or extra, a minute or speed that is text, NaN, infinite,
##   negative or over the caller's limit, a `paused` that isn't a bool; whole numbers pass.

var _failures: int = 0


func _initialize() -> void:
	_check_one_clock()
	_check_two_holders()
	_check_refused()
	if _failures == 0:
		print("PASS: day clocks run from their anchor, travel without a tick, agree across holders"
			+ " and refuse what isn't an anchor")
	quit(_failures)


func _check_one_clock() -> void:
	var clock := DayClock.new()
	_expect(clock.paused and is_zero_approx(clock.minute_at(123456)),
		"A new clock is stopped at minute 0 (got %s at %.2f)" % [clock.paused, clock.minute_at(123456)])
	# 480 at tick 10 000, two thirds of a minute per second: 90 s later it is 540.
	clock.set_anchor(480.0, 2.0 / 3.0, false, 10_000)
	_expect(is_equal_approx(clock.minute_at(100_000), 540.0),
		"90 s at 2/3 min/s runs an hour (got %.3f)" % clock.minute_at(100_000))
	_expect(is_equal_approx(clock.minute_at(10_000), 480.0) and is_equal_approx(clock.minute_at(5_000), 480.0),
		"At its tick, and before it, it reads the anchor's minute (got %.3f, %.3f)"
		% [clock.minute_at(10_000), clock.minute_at(5_000)])
	clock.set_anchor(clock.minute_at(55_000), clock.speed, true, 55_000)
	_expect(is_equal_approx(clock.minute_at(55_000), 510.0)
		and is_equal_approx(clock.minute_at(9_999_999), 510.0),
		"A stopped clock reads its minute at any tick (got %.3f)" % clock.minute_at(9_999_999))

	var running := DayClock.new(600.0, 1.0, false, 1_000)
	var anchor: Dictionary = running.to_dict(31_000)
	_expect(anchor.keys().size() == DayClock.KEYS.size() and DayClock.anchor_ok(anchor),
		"to_dict() carries exactly %s (got %s)" % [DayClock.KEYS, anchor.keys()])
	_expect(is_equal_approx(float(anchor["minute"]), 630.0) and is_equal_approx(float(anchor["speed"]), 1.0)
		and anchor["paused"] == false,
		"...moved to the tick it is taken at (got %s)" % [anchor])
	var back: Variant = bytes_to_var(var_to_bytes(anchor))
	_expect(back == anchor, "...and comes back the same from var_to_bytes (got %s)" % [back])


## A sends at its tick 1 000; the message takes 100 ms and reaches B at B's tick 50 100 (B's
## clock started 49 000 ms before A's). B takes its own tick minus the transit.
func _check_two_holders() -> void:
	var a := DayClock.new(480.0, 2.0 / 3.0, false, 1_000)
	var b := DayClock.new()
	_expect(b.from_dict(a.to_dict(1_000), 50_100 - 100), "B takes A's anchor with its own tick")
	_expect(b.origin_msec == 50_000 and not b.paused,
		"...as valid at its tick minus the transit (origin %d)" % b.origin_msec)
	# 60 s later on both clocks.
	var on_a: float = a.minute_at(61_000)
	var on_b: float = b.minute_at(110_000)
	_expect(is_equal_approx(on_a, 520.0) and is_equal_approx(on_a, on_b),
		"60 s later both read the same minute (A %.3f, B %.3f)" % [on_a, on_b])
	# A stops at its tick 70 000; the anchor reaches B 100 ms later.
	a.set_anchor(a.minute_at(70_000), a.speed, true, 70_000)
	_expect(b.from_dict(a.to_dict(70_000), 119_100 - 100), "B takes A's pause")
	var a_later: float = a.minute_at(500_000)
	var b_later: float = b.minute_at(549_000)
	_expect(a.paused and b.paused and is_equal_approx(a_later, b_later) and is_equal_approx(a_later, 526.0),
		"The pause stops both at the same minute (A %.3f, B %.3f)" % [a_later, b_later])


func _check_refused() -> void:
	var clock := DayClock.new(700.0, 0.5, false, 2_000)
	var good: Dictionary = {"minute": 480.0, "speed": 1.0, "paused": false}
	_expect(DayClock.anchor_ok({"minute": 480, "speed": 1, "paused": true}),
		"Whole numbers are numbers too")
	var bad_cases: Array = [
		[[1, 2, 3], "an Array"],
		["480", "text"],
		[_without(good, "paused"), "a missing key"],
		[_with(good, "tick", 99), "an extra key"],
		[_with(good, "minute", "480"), "a minute that is text"],
		[_with(good, "minute", NAN), "a NaN minute"],
		[_with(good, "minute", INF), "an infinite minute"],
		[_with(good, "minute", -1.0), "a negative minute"],
		[_with(good, "minute", 3000.0), "a minute over the limit"],
		[_with(good, "speed", -0.5), "a negative speed"],
		[_with(good, "speed", 99.0), "a speed over the limit"],
		[_with(good, "speed", INF), "an infinite speed"],
		[_with(good, "paused", 1), "a paused that is an int"],
	]
	for case: Array in bad_cases:
		_expect(not clock.from_dict(case[0], 9_000, 2880.0, 10.0), "An anchor with %s is refused" % case[1])
	_expect(is_equal_approx(clock.minute, 700.0) and is_equal_approx(clock.speed, 0.5)
		and not clock.paused and clock.origin_msec == 2_000,
		"...and the refused ones changed nothing (minute %.1f, origin %d)" % [clock.minute, clock.origin_msec])
	_expect(clock.from_dict(good, 9_000, 2880.0, 10.0) and clock.origin_msec == 9_000,
		"A good one within the limits is taken")


static func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate()
	copy[key] = value
	return copy


static func _without(data: Dictionary, key: String) -> Dictionary:
	var copy: Dictionary = data.duplicate()
	copy.erase(key)
	return copy


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
