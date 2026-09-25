extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_vehicle_net_smoothing.gd
##
## The host's truck on a client (N-208, vehicle_net_smoother.gd, vehicle.gd):
## measured with artificial latency -- the host's 60 Hz poses arriving 150 ms
## late with up to 50 ms of jitter (what `--fake-lag=150` does), drawn at
## 144 fps while the truck cruises at 60 km/h round a bend:
## - drawn straight as they land (how it was), the truck jumps: well over
##   10 cm a frame away from smooth motion;
## - through the smoother, never more than 10 cm (the task's limit), and it
##   trails the host by the buffer's delay, not more;
## - a teleport (respawn) snaps instead of sliding across the map;
## - `--fake-lag` really holds poses back;
## - wired into vehicle.gd: a client's copy follows the replicated pose.

const SPEED: float = 60.0 / 3.6
const HOST_RATE: float = 60.0
const FRAME_RATE: float = 144.0
const LAG: float = 0.15
const JITTER: float = 0.05
const LIMIT: float = 0.10

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


## Where the host's truck is at host time `t`: a wide bend at cruise speed.
static func host_pose(t: float) -> Transform3D:
	var radius: float = 120.0
	var angle: float = SPEED * t / radius
	var at := Vector3(radius * (1.0 - cos(angle)), 0.0, -radius * sin(angle))
	return Transform3D(Basis(Vector3.UP, -angle), at)


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 208
	# The packets: sent every 1/60 s, arriving LAG + jitter later.
	var packets: Array = []
	for index: int in range(int(HOST_RATE * 6.0)):
		var sent: float = float(index) / HOST_RATE
		packets.append([sent + LAG + rng.randf_range(0.0, JITTER), sent])
	packets.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	var smoother := VehicleNetSmoother.new()
	smoother.fake_lag = 0.0
	var raw := Transform3D.IDENTITY
	var raw_time: float = -1.0
	var next: int = 0
	var raw_jump: float = 0.0
	var smooth_jump: float = 0.0
	var worst_trail: float = 0.0
	var previous_raw := Vector3.ZERO
	var previous_smooth := Vector3.ZERO
	var frame: int = 0
	var now: float = 0.0
	var ideal_step: float = SPEED / FRAME_RATE
	while now < 5.5:
		now = float(frame) / FRAME_RATE
		while next < packets.size() and float(packets[next][0]) <= now:
			var host_time: float = packets[next][1]
			smoother.push(host_time, host_pose(host_time), now)
			if host_time > raw_time:
				raw_time = host_time
				raw = host_pose(host_time)
			next += 1
		var drawn: Transform3D = smoother.sample(now)
		# Skip the first second: the buffer filling, the first packets landing.
		if now > 1.0:
			raw_jump = maxf(raw_jump, absf(raw.origin.distance_to(previous_raw) - ideal_step))
			smooth_jump = maxf(smooth_jump, absf(drawn.origin.distance_to(previous_smooth) - ideal_step))
			# How far behind the host it's drawn, in time.
			var trail: float = now - _time_of(drawn.origin, now)
			worst_trail = maxf(worst_trail, trail)
		previous_raw = raw.origin
		previous_smooth = drawn.origin
		frame += 1
	print("net smoothing @ %.0f ms lag + %.0f ms jitter: raw worst %.1f cm/frame off smooth motion, smoothed %.1f cm, trailing the host by %.0f ms" % [LAG * 1000.0, JITTER * 1000.0, raw_jump * 100.0, smooth_jump * 100.0, worst_trail * 1000.0])
	_expect(raw_jump > LIMIT, "Unsmoothed, the lagged truck jumps visibly (%.1f cm a frame)" % (raw_jump * 100.0))
	_expect(smooth_jump < LIMIT, "Smoothed, it never jumps more than %.0f cm a frame (%.1f cm)" % [LIMIT * 100.0, smooth_jump * 100.0])
	_expect(worst_trail < LAG + JITTER + VehicleNetSmoother.DELAY + 0.02, "It trails the host by the lag plus the buffer, no more (%.0f ms)" % (worst_trail * 1000.0))

	# A respawn: snaps, doesn't slide.
	var teleport := VehicleNetSmoother.new()
	teleport.push(0.0, Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.0)
	teleport.push(1.0 / 60.0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.3)), 1.0 / 60.0)
	teleport.push(2.0 / 60.0, Transform3D(Basis.IDENTITY, Vector3(200.0, 0.0, 0.0)), 2.0 / 60.0)
	var after: Transform3D = teleport.sample(2.0 / 60.0 + 0.2)
	_expect(after.origin.distance_to(Vector3(200.0, 0.0, 0.0)) < 0.5, "A teleport snaps to the new spot (%s)" % after.origin)

	# --fake-lag holds poses back.
	var lagged := VehicleNetSmoother.new()
	lagged.fake_lag = 0.15
	lagged.push(0.0, Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)), 0.0)
	_expect(lagged.sample(0.1) == Transform3D.IDENTITY, "With --fake-lag a pose isn't there before its time")
	_expect(lagged.sample(0.25).origin.is_equal_approx(Vector3(1.0, 0.0, 0.0)), "...and is once the lag has passed")

	# Wired into the truck: a client's copy (not the authority) follows.
	var van := (load("res://scenes/gameplay/vehicle/vehicle.tscn") as PackedScene).instantiate() as VehicleBody3D
	root.add_child(van)
	await process_frame
	# A remote copy is frozen: the network places it, not its own physics.
	van.freeze = true
	van.set_multiplayer_authority(2)
	var target := Vector3(3.0, 1.0, -7.0)
	van.set(&"net_time", 10.0)
	van.set(&"net_position", target)
	van.set(&"net_rotation", Vector3(0.0, 0.4, 0.0))
	await process_frame
	_expect(van.position.is_equal_approx(target) and is_equal_approx(van.rotation.y, 0.4), "A client's truck takes the replicated pose (%s)" % van.position)
	van.set_multiplayer_authority(1)
	_expect(is_equal_approx(float(van.get(&"net_time")), float(van.get(&"_host_clock"))) and van.get(&"net_position") == van.position,
		"On the host the replicated pose is the truck's own, with its clock")
	van.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: with 150 ms of lag the host's truck is drawn smooth on a client, and a respawn still snaps")
	quit(_failures)


## The host time whose pose is nearest `point` (searching the last second).
func _time_of(point: Vector3, now: float) -> float:
	var best: float = now
	var best_distance: float = INF
	var t: float = now - 1.0
	while t <= now:
		var d: float = host_pose(t).origin.distance_to(point)
		if d < best_distance:
			best_distance = d
			best = t
		t += 0.002
	return best


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
