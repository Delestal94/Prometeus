extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_pose_smoother/tests/test_net_pose_smoother.gd
##
## The net_pose_smoother module on its own (docs/modulos.md): poses stamped
## with the host's clock are drawn DELAY seconds in the past and
## interpolated, so a body moving at a steady speed is drawn at that speed
## without jumps; out-of-order poses are sorted in; a far pose is a
## teleport that restarts the buffer; configure_sim() holds poses back and
## drops a share of them; clear() empties everything.

var _failures: int = 0


func _initialize() -> void:
	var smoother := NetPoseSmoother.new()
	_expect(smoother.is_empty(), "A new buffer is empty")
	_expect(smoother.sample(0.0) == Transform3D.IDENTITY, "An empty buffer samples the identity")
	# The host moves 10 m/s along -Z; poses arrive with a fixed 50 ms delay.
	var speed: float = 10.0
	var delay: float = 0.05
	for tick: int in range(60):
		var host_time: float = tick / 60.0
		smoother.push(host_time, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -speed * host_time)), host_time + delay)
	_expect(not smoother.is_empty(), "Poses were kept")
	var worst_jump: float = 0.0
	var previous: Vector3 = smoother.sample(0.5).origin
	for step: int in range(1, 30):
		var now: float = 0.5 + step / 144.0
		var origin: Vector3 = smoother.sample(now).origin
		worst_jump = maxf(worst_jump, absf(previous.distance_to(origin) - speed / 144.0))
		previous = origin
	_expect(worst_jump < 0.01, "Drawn at 144 fps the body moves evenly (worst deviation %.4f m)" % worst_jump)
	var drawn: Vector3 = smoother.sample(0.8).origin
	var host_now: Vector3 = Vector3(0.0, 0.0, -speed * (0.8 - delay))
	var trail: float = drawn.distance_to(host_now) / speed
	_expect(absf(trail - NetPoseSmoother.DELAY) < 0.01, "It trails the host by DELAY (%.3f s)" % trail)

	var reordered := NetPoseSmoother.new()
	reordered.push(0.0, Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.0)
	reordered.push(2.0 / 60.0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -2.0)), 2.0 / 60.0)
	reordered.push(1.0 / 60.0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -1.0)), 3.0 / 60.0)
	var mid: Vector3 = reordered.sample(1.0 / 60.0 + NetPoseSmoother.DELAY).origin
	# The clock offset eases a hair toward the late arrival, so "at" the pose is within a few cm.
	_expect(absf(mid.z + 1.0) < 0.05, "A late pose is sorted into place (got z=%.2f)" % mid.z)

	var teleport := NetPoseSmoother.new()
	teleport.push(0.0, Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.0)
	teleport.push(1.0 / 60.0, Transform3D(Basis.IDENTITY, Vector3(100.0, 0.0, 0.0)), 1.0 / 60.0)
	_expect(teleport.sample(1.0).origin.x > 99.0,
		"A far pose is a teleport, drawn there at once (got %.1f)" % teleport.sample(1.0).origin.x)

	var simulated := NetPoseSmoother.new()
	simulated.configure_sim({"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0})
	_expect(is_equal_approx(simulated.fake_lag, 0.15) and is_equal_approx(simulated.fake_jitter, 0.02)
		and is_equal_approx(simulated.fake_loss, 0.02), "configure_sim() reads lag, jitter and loss")
	simulated.configure_sim({})
	_expect(is_equal_approx(simulated.fake_lag, 0.15), "An empty profile leaves the buffer as it was")
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
	_expect(lagged.is_empty(), "clear() empties the buffer and the held poses")
	if _failures == 0:
		print("PASS: NetPoseSmoother interpolates, sorts, teleports and simulates a bad link")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
