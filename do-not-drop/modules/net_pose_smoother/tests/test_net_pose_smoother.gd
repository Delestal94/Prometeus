extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_pose_smoother/tests/test_net_pose_smoother.gd
##
## The net_pose_smoother module on its own (docs/modulos.md): poses stamped
## with the sender's clock are drawn a cushion in the past and interpolated,
## so a body moving at a steady speed is drawn at that speed without jumps.
## The cushion adapts (N-217): 2 send intervals + 2 x the measured jitter,
## between MIN_DELAY and MAX_DELAY, and a sender pausing at rest doesn't
## inflate it. Out-of-order poses are sorted in; a far pose is a teleport that
## restarts the buffer; `local` poses ride on the moving space they're drawn
## on; latest_pose() is the newest as sent; a repeated stamp doesn't move the
## jitter; `extra` numbers (animation) are drawn interpolated in step; configure_sim() holds poses back
## (all of the profile's lag, or the share given: half for a truck whose other way is simulated too, N-922.9)
## and drops a share of them; clear() empties everything.

var _failures: int = 0


func _initialize() -> void:
	var smoother := NetPoseSmoother.new()
	_expect(smoother.is_empty(), "A new buffer is empty")
	_expect(smoother.sample(0.0) == Transform3D.IDENTITY, "An empty buffer samples the identity")
	# The sender moves 10 m/s along -Z at 30 Hz; poses arrive with a fixed 50 ms delay.
	var speed: float = 10.0
	var transit: float = 0.05
	for tick: int in range(30):
		var sent: float = tick / 30.0
		smoother.push(sent, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -speed * sent)), sent + transit)
	_expect(not smoother.is_empty(), "Poses were kept")
	_expect(is_equal_approx(smoother.delay(), 2.0 / 30.0),
		"No jitter at 30 Hz: the cushion is two intervals (%.0f ms)" % (smoother.delay() * 1000.0))
	var worst_jump: float = 0.0
	var previous: Vector3 = smoother.sample(0.6).origin
	for step: int in range(1, 30):
		var now: float = 0.6 + step / 144.0
		var origin: Vector3 = smoother.sample(now).origin
		worst_jump = maxf(worst_jump, absf(previous.distance_to(origin) - speed / 144.0))
		previous = origin
	_expect(worst_jump < 0.01, "Drawn at 144 fps the body moves evenly (worst deviation %.4f m)" % worst_jump)
	var drawn: Vector3 = smoother.sample(0.8).origin
	var sender_now: Vector3 = Vector3(0.0, 0.0, -speed * (0.8 - transit))
	var trail: float = drawn.distance_to(sender_now) / speed
	_expect(absf(trail - smoother.delay()) < 0.01, "It trails the sender by its cushion (%.3f s)" % trail)
	_expect(smoother.latest_pose().origin.is_equal_approx(Vector3(0.0, 0.0, -speed * 29.0 / 30.0)),
		"latest_pose() is the newest pose as sent")

	# At 60 Hz on a quiet link two intervals are under the floor.
	var fast := NetPoseSmoother.new()
	for tick: int in range(60):
		fast.push(tick / 60.0, Transform3D.IDENTITY, tick / 60.0 + 0.01)
	_expect(is_equal_approx(fast.delay(), NetPoseSmoother.MIN_DELAY),
		"A quiet 60 Hz link draws MIN_DELAY behind (%.0f ms)" % (fast.delay() * 1000.0))

	# Jitter widens it; a very bad link hits the ceiling.
	var rng := RandomNumberGenerator.new()
	rng.seed = 217
	var jittery := NetPoseSmoother.new()
	var wild := NetPoseSmoother.new()
	for tick: int in range(120):
		var sent: float = tick / 30.0
		jittery.push(sent, Transform3D.IDENTITY, sent + 0.1 + rng.randf_range(0.0, 0.06))
		wild.push(sent, Transform3D.IDENTITY, sent + 0.1 + rng.randf_range(0.0, 0.4))
	var expected: float = 2.0 * jittery.interval() + 2.0 * jittery.jitter()
	_expect(jittery.jitter() > 0.01 and is_equal_approx(jittery.delay(), clampf(expected, 0.05, 0.2)),
		"60 ms of jitter: 2 intervals + 2 x jitter (%.0f ms, jitter %.0f ms)" % [
			jittery.delay() * 1000.0, jittery.jitter() * 1000.0])
	_expect(jittery.delay() > 2.0 / 30.0 + 0.01, "...which is more than on a quiet link")
	_expect(is_equal_approx(wild.delay(), NetPoseSmoother.MAX_DELAY),
		"400 ms of jitter is capped at MAX_DELAY (%.0f ms)" % (wild.delay() * 1000.0))

	# A sender at rest slows to 2 Hz (NetRestThrottle): not a new interval.
	var resting := NetPoseSmoother.new()
	for tick: int in range(30):
		resting.push(tick / 30.0, Transform3D.IDENTITY, tick / 30.0)
	for slow: int in range(1, 6):
		var sent: float = 29.0 / 30.0 + slow * 0.49
		resting.push(sent, Transform3D.IDENTITY, sent)
	_expect(absf(resting.interval() - 1.0 / 30.0) < 0.002,
		"Half-second gaps at rest don't count as the interval (%.0f ms)" % (resting.interval() * 1000.0))

	# The same pose again (a resend) says nothing about the link.
	var before_repeats: float = jittery.jitter()
	for repeat: int in range(10):
		jittery.push(119.0 / 30.0, Transform3D.IDENTITY, 5.0 + repeat * 0.07)
	_expect(is_equal_approx(jittery.jitter(), before_repeats),
		"A repeated stamp leaves the jitter alone (%.1f ms, was %.1f)" % [
			jittery.jitter() * 1000.0, before_repeats * 1000.0])

	# Extra numbers ride with the poses, drawn in step with them.
	var animated := NetPoseSmoother.new()
	animated.push(0.0, Transform3D.IDENTITY, 0.0, false, PackedFloat32Array([0.0, 10.0]))
	animated.push(0.1, Transform3D.IDENTITY, 0.1, false, PackedFloat32Array([1.0, 20.0]))
	animated.sample(0.1 + animated.delay() - 0.05)
	var halfway: PackedFloat32Array = animated.drawn_extra()
	_expect(halfway.size() == 2 and is_equal_approx(halfway[0], 0.5) and is_equal_approx(halfway[1], 15.0),
		"drawn_extra() is interpolated at the moment drawn (got %s)" % halfway)

	var reordered := NetPoseSmoother.new()
	reordered.push(0.0, Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.0)
	reordered.push(2.0 / 30.0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -2.0)), 2.0 / 30.0)
	reordered.push(1.0 / 30.0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -1.0)), 3.0 / 30.0)
	var mid: Vector3 = reordered.sample(1.0 / 30.0 + reordered.delay()).origin
	_expect(absf(mid.z + 1.0) < 0.05, "A late pose is sorted into place (got z=%.2f)" % mid.z)

	var teleport := NetPoseSmoother.new()
	teleport.push(0.0, Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.0)
	teleport.push(1.0 / 30.0, Transform3D(Basis.IDENTITY, Vector3(100.0, 0.0, 0.0)), 1.0 / 30.0)
	_expect(teleport.sample(1.0).origin.x > 99.0,
		"A far pose is a teleport, drawn there at once (got %.1f)" % teleport.sample(1.0).origin.x)

	# Local poses: still in the bay, drawn wherever the bay is drawn now.
	var riding := NetPoseSmoother.new()
	var seat := Transform3D(Basis.IDENTITY, Vector3(0.5, 1.0, 2.0))
	for tick: int in range(10):
		riding.push(tick / 30.0, seat, tick / 30.0, true)
	var bay := Transform3D(Basis(Vector3.UP, 0.5), Vector3(40.0, 0.0, -300.0))
	_expect(riding.sample(0.5, bay).origin.is_equal_approx(bay * seat.origin),
		"A local pose is put on the moving space as drawn")
	_expect(riding.latest_local(), "latest_local() says the newest pose is local")
	# Stepping out: from the bay's space to the world's without a jump at the switch.
	riding.push(10.0 / 30.0, Transform3D(Basis.IDENTITY, bay * seat.origin), 10.0 / 30.0, false)
	var across: Vector3 = riding.sample(10.0 / 30.0 + riding.delay() - 1.0 / 60.0, bay).origin
	var off: float = across.distance_to(bay * seat.origin)
	_expect(off < 0.01, "Local to world interpolates in the world (off by %.3f m)" % off)

	_expect(NetPoseSmoother.clock_ms() == int(Engine.get_physics_frames() * 1000 / Engine.physics_ticks_per_second),
		"clock_ms() is physics time in milliseconds")

	var simulated := NetPoseSmoother.new()
	simulated.configure_sim({"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0})
	_expect(is_equal_approx(simulated.fake_lag, 0.15) and is_equal_approx(simulated.fake_jitter, 0.02)
		and is_equal_approx(simulated.fake_loss, 0.02), "configure_sim() reads lag, jitter and loss")
	simulated.configure_sim({})
	_expect(is_equal_approx(simulated.fake_lag, 0.15), "An empty profile leaves the buffer as it was")
	var one_way := NetPoseSmoother.new()
	one_way.configure_sim({"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0}, 0.5)
	_expect(is_equal_approx(one_way.fake_lag, 0.075) and is_equal_approx(one_way.fake_jitter, 0.02)
			and is_equal_approx(one_way.fake_loss, 0.02),
		"configure_sim() with half the lag this way: 75 ms, the whole jitter and loss (%.3f s)" % one_way.fake_lag)
	var lagged := NetPoseSmoother.new()
	lagged.configure_sim({"lag_ms": 200, "jitter_ms": 0, "loss_pct": 0.0})
	lagged.push(0.0, Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 0.0)), 0.0)
	_expect(lagged.sample(0.1) == Transform3D.IDENTITY, "A held pose isn't drawn before its lag is up")
	_expect(lagged.sample(0.25).origin.x > 4.9, "It is drawn once the lag has passed")
	var lossy := NetPoseSmoother.new()
	lossy.configure_sim({"lag_ms": 0, "jitter_ms": 0, "loss_pct": 100.0})
	lossy.push(0.0, Transform3D.IDENTITY, 0.0)
	_expect(lossy.is_empty(), "With full loss nothing arrives")
	lagged.clear()
	_expect(lagged.is_empty() and is_equal_approx(lagged.interval(), NetPoseSmoother.DEFAULT_INTERVAL),
		"clear() empties the buffer, the held poses and what it measured")
	if _failures == 0:
		print("PASS: NetPoseSmoother interpolates with an adaptive cushion, sorts, teleports, rides",
			" and simulates a bad link")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
