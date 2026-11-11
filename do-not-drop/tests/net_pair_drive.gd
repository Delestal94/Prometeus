extends RefCounted
## The client at the wheel in net_pair.gd (N-218, N-922.5, N-922.9): the drives it measures, on a clean link and into
## the standard --net-sim profile. Split from it, which reports what these return (N-987).

## N-922.9, the drive into --net-sim: the wheel weaves this far (of full lock) every this many seconds...
const NET_SIM_WEAVE: float = 0.6
const NET_SIM_WEAVE_PERIOD: float = 1.5
## ...and from a second after the switch, the error stays within this (m) over the mean before it for
## NET_SIM_QUIET_MS straight: the truck is faster by then and 2 % of its inputs are lost (2.4-7 cm measured, against
## 1.6 cm before). What it guards against is a counter that keeps moving, or a correction that doesn't settle; one
## left ahead for good is caught by the host's count of ticks stamped ahead (at these speeds its error is only ~3 cm).
## A stretch, not a mean over a fixed second (N-987): the re-anchor's one correction (0.8-1.5 m, gone in half a second)
## comes more than a second after the switch on a machine short of CPU, and it put that mean past this in 2 runs of 10.
const MAX_NET_SIM_ERROR_GROWTH: float = 0.15
const NET_SIM_QUIET_MS: int = 500
## ...and if that stretch hasn't come by the end of the drive, this much more of it at most (ms), still short of the
## bump past the yard: contacts are what each peer feels its own way.
const NET_SIM_EXTRA_MS: int = 1000


## Client at the wheel: accelerates for `seconds`, then holds the handbrake for one. Returns the worst correction
## in a tick, the median and worst error measured, and how many ticks behind the client's newest input the host's
## newest state was (median).
static func drive_for(vehicle: VehicleBody3D, seconds: float) -> Dictionary:
	var prediction: VehiclePrediction = vehicle.get(&"_prediction")
	var worst_shift: float = 0.0
	var errors: Array[float] = []
	var behind: Array[int] = []
	var held_out: Array[int] = []
	var held_back: Array[int] = []
	Input.action_press(&"drive_accelerate")
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await vehicle.get_tree().physics_frame
		worst_shift = maxf(worst_shift, prediction.last_shift)
		errors.append(prediction.reconciler.last_error)
		if prediction.host_seq > 0:
			behind.append(prediction.applied_seq - prediction.host_seq)
		held_out.append(prediction.uplink.pending())
		held_back.append(prediction.downlink.pending())
	Input.action_release(&"drive_accelerate")
	Input.action_press(&"drive_handbrake")
	await _pump(vehicle.get_tree(), 1.0)
	Input.action_release(&"drive_handbrake")
	return {
		"worst_shift": worst_shift,
		"median_error": _median(errors),
		"worst_error": errors.max() if not errors.is_empty() else INF,
		"behind": int(_median(behind)),
		"inputs_held": int(_median(held_out)),
		"states_held": int(_median(held_back)),
	}


## N-922.9: the client accelerates with the wheel weaving for `clean_seconds`, then the standard --net-sim profile is
## switched on mid-drive for `sim_seconds` more, then the handbrake for a second and the profile off again. Returns
## the reconciler's mean error before the switch, over the first second after it (the host's counter lands ahead of
## the inputs and re-anchors: the ticks it held an input meanwhile are corrected once) and over the rest; the worst
## correction in a tick since the switch; over the rest also the worst error, the longest stretch the error stayed
## within MAX_NET_SIM_ERROR_GROWTH of the one before the switch (N-987: the drive runs on up to NET_SIM_EXTRA_MS for
## it), how many ticks behind the client's newest input the host's newest state was, and the inputs and states held
## (medians, and the most at a time: a peer stalling for longer than the profile's lag finds none held most ticks).
static func drive_into_net_sim(vehicle: VehicleBody3D, clean_seconds: float, sim_seconds: float) -> Dictionary:
	var prediction: VehiclePrediction = vehicle.get(&"_prediction")
	var clean: Array[float] = []
	var settling: Array[float] = []
	var settled: Array[float] = []
	var behind: Array[int] = []
	var held_out: Array[int] = []
	var held_back: Array[int] = []
	var worst_shift: float = 0.0
	var started: int = Time.get_ticks_msec()
	var sim_at: int = started + int(clean_seconds * 1000.0)
	var end_at: int = sim_at + int(sim_seconds * 1000.0)
	var quiet_limit: float = INF
	var quiet_since: int = sim_at + 1000
	var quiet_ms: int = 0
	var simulating: bool = false
	var now: int = started
	Input.action_press(&"drive_accelerate")
	while now < end_at or (quiet_ms < NET_SIM_QUIET_MS and now < end_at + NET_SIM_EXTRA_MS):
		await vehicle.get_tree().physics_frame
		now = Time.get_ticks_msec()
		_steer(NET_SIM_WEAVE * sin(float(now - started) / 1000.0 * TAU / NET_SIM_WEAVE_PERIOD))
		if not simulating and now >= sim_at:
			vehicle.call(&"configure_net_sim", NetStats.STANDARD_SIM)
			simulating = true
			quiet_limit = _mean(clean) + MAX_NET_SIM_ERROR_GROWTH
			continue
		var error: float = prediction.reconciler.last_error
		if not simulating:
			clean.append(error)
			continue
		worst_shift = maxf(worst_shift, prediction.last_shift)
		if now < sim_at + 1000:
			settling.append(error)
		else:
			settled.append(error)
			if error > quiet_limit:
				quiet_since = now
			quiet_ms = maxi(quiet_ms, now - quiet_since)
			if prediction.host_seq > 0:
				behind.append(prediction.applied_seq - prediction.host_seq)
			held_out.append(prediction.uplink.pending())
			held_back.append(prediction.downlink.pending())
	Input.action_release(&"drive_accelerate")
	_steer(0.0)
	Input.action_press(&"drive_handbrake")
	await _pump(vehicle.get_tree(), 1.0)
	Input.action_release(&"drive_handbrake")
	vehicle.call(&"configure_net_sim", {"lag_ms": 0, "jitter_ms": 0, "loss_pct": 0.0})
	return {
		"clean_error": _mean(clean),
		"settling_error": _mean(settling),
		"settling_worst": settling.max() if not settling.is_empty() else INF,
		"settled_error": _mean(settled),
		"worst_error": settled.max() if not settled.is_empty() else INF,
		"quiet_ms": quiet_ms,
		"worst_shift": worst_shift,
		"behind": int(_median(behind)),
		"inputs_held": int(_median(held_out)),
		"states_held": int(_median(held_back)),
		"inputs_most": int(held_out.max()) if not held_out.is_empty() else 0,
		"states_most": int(held_back.max()) if not held_back.is_empty() else 0,
	}


## The wheel at `value` (-1 left .. 1 right), as a stick would put it.
static func _steer(value: float) -> void:
	Input.action_release(&"drive_left")
	Input.action_release(&"drive_right")
	if value > 0.0:
		Input.action_press(&"drive_right", value)
	elif value < 0.0:
		Input.action_press(&"drive_left", -value)


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return INF
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / values.size()


static func _median(values: Array) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


static func _pump(tree: SceneTree, seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
