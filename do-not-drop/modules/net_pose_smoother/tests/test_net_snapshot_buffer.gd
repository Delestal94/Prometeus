extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_pose_smoother/tests/test_net_snapshot_buffer.gd
##
## NetSnapshotBuffer on its own (N-217, docs/modulos.md): poses stamped with
## the sender's clock at 30 Hz.
## - Even arrivals: a body at a steady speed is drawn at that speed, with no
##   jumps, and the cushion stays at its floor (MIN_DELAY..2 intervals).
## - A jittery link (each pose 0..60 ms late at random) raises the cushion by
##   about twice the measured jitter, never past MAX_DELAY, and the body is
##   still drawn without going backwards.
## - Poses in the truck's space are drawn on the truck as given to sample().
## - Swapped poses are sorted in, a repeated one ignored; a far pose is a
##   teleport; past the newest pose it extrapolates at most
##   MAX_EXTRAPOLATION, then holds.
## - After a long rest (a sender slowed down by NetRestThrottle), motion starts
##   one interval before the first pose that moved, not across the whole gap.
## - take() reads replicated properties every frame: a repeated (stamp,
##   pose) is ignored, a new one goes in, an unstamped one (0: a spawn state, a
##   test) is drawn at once, and stamped ones after it start the buffer over.
## - configure_sim() and clear().

const RATE: float = 30.0
const SPEED: float = 6.0

var _failures: int = 0


func _initialize() -> void:
	_check_even()
	_check_jitter()
	_check_truck_space()
	_check_order_and_teleport()
	_check_extrapolation()
	_check_rest()
	_check_take()
	_check_sim_and_clear()
	if _failures == 0:
		print("PASS: NetSnapshotBuffer draws remote poses smoothly with an adaptive cushion")
	quit(_failures)


static func _pose(sender_time: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -SPEED * sender_time))


## Pushes 2 s of poses (sent at RATE, arriving after `late` + 0..`jitter` s)
## and samples at 60 fps; returns [largest backward step, largest step, buffer].
func _run(late: float, jitter: float, seed_value: int) -> Array:
	var buffer := NetSnapshotBuffer.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var arrivals: Array = []
	for index: int in range(int(2.0 * RATE)):
		var sent: float = index / RATE
		arrivals.append([sent + late + rng.randf_range(0.0, jitter), sent])
	arrivals.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var backward: float = 0.0
	var largest: float = 0.0
	var previous: float = INF
	var next: int = 0
	var frame: float = 0.0
	while frame < 2.0:
		while next < arrivals.size() and float(arrivals[next][0]) <= frame:
			buffer.push(float(arrivals[next][1]), _pose(float(arrivals[next][1])), float(arrivals[next][0]))
			next += 1
		if not buffer.is_empty() and frame > 0.5:
			var z: float = buffer.sample(frame).origin.z
			if previous != INF:
				backward = maxf(backward, z - previous)
				largest = maxf(largest, absf(z - previous))
			previous = z
		frame += 1.0 / 60.0
	return [backward, largest, buffer]


func _check_even() -> void:
	var empty := NetSnapshotBuffer.new()
	_expect(empty.is_empty() and empty.sample(0.0) == Transform3D.IDENTITY, "An empty buffer samples the identity")
	var result: Array = _run(0.03, 0.0, 1)
	var buffer: NetSnapshotBuffer = result[2]
	_expect(absf(buffer.interval() - 1.0 / RATE) < 0.002, "It measures the send interval (%.4f s)" % buffer.interval())
	_expect(buffer.delay() <= 2.0 / RATE + 0.005 and buffer.delay() >= NetSnapshotBuffer.MIN_DELAY,
		"On an even link the cushion is about 2 intervals (%.0f ms)" % (buffer.delay() * 1000.0))
	var per_frame: float = SPEED / 60.0
	_expect(float(result[0]) < 0.001, "Never drawn going backwards (%.4f m)" % float(result[0]))
	_expect(float(result[1]) < per_frame * 1.2,
		"No jumps: at most %.3f m a frame (%.3f)" % [per_frame * 1.2, float(result[1])])


func _check_jitter() -> void:
	var result: Array = _run(0.03, 0.06, 7)
	var buffer: NetSnapshotBuffer = result[2]
	_expect(buffer.jitter() > 0.005, "It measures the jitter (%.0f ms)" % (buffer.jitter() * 1000.0))
	_expect(buffer.delay() > 2.0 / RATE + 0.01 and buffer.delay() <= NetSnapshotBuffer.MAX_DELAY,
		"A jittery link gets a bigger cushion, within MAX_DELAY (%.0f ms)" % (buffer.delay() * 1000.0))
	_expect(float(result[0]) < 0.001, "Even jittery, never drawn going backwards (%.4f m)" % float(result[0]))
	_expect(float(result[1]) < SPEED / 60.0 * 2.0, "...nor jumping (%.3f m in a frame)" % float(result[1]))
	var awful: Array = _run(0.03, 0.8, 3)
	_expect((awful[2] as NetSnapshotBuffer).delay() <= NetSnapshotBuffer.MAX_DELAY + 0.0001,
		"However bad, the cushion stops at MAX_DELAY")


func _check_truck_space() -> void:
	var buffer := NetSnapshotBuffer.new()
	var spot := Transform3D(Basis.IDENTITY, Vector3(0.5, 1.0, 2.0))
	for index: int in range(4):
		buffer.push(index / RATE, spot, index / RATE, true)
	_expect(buffer.latest_local(), "The newest pose is known to be in the truck's space")
	var truck := Transform3D(Basis(Vector3.UP, 0.5), Vector3(100.0, 0.0, -40.0))
	var drawn: Transform3D = buffer.sample(0.2, truck)
	_expect(drawn.origin.distance_to(truck * spot.origin) < 0.001,
		"A pose in the truck's space is drawn on the truck given")


func _check_order_and_teleport() -> void:
	var swapped := NetSnapshotBuffer.new()
	for sent: float in [0.0, 2.0 / RATE, 1.0 / RATE, 3.0 / RATE, 3.0 / RATE]:
		swapped.push(sent, _pose(sent), sent + 0.02)
	var at: float = 1.5 / RATE
	var mid: float = swapped.sample(at + 0.02 + swapped.delay()).origin.z
	_expect(absf(mid - _pose(at).origin.z) < 0.05,
		"Swapped poses are sorted in (%.3f, wanted %.3f)" % [mid, _pose(at).origin.z])

	var teleport := NetSnapshotBuffer.new()
	teleport.push(0.0, _pose(0.0), 0.0)
	teleport.push(1.0 / RATE, _pose(1.0 / RATE), 1.0 / RATE)
	var far := Transform3D(Basis.IDENTITY, Vector3(50.0, 0.0, 0.0))
	teleport.push(2.0 / RATE, far, 2.0 / RATE)
	_expect(teleport.sample(2.0 / RATE).origin.distance_to(far.origin) < 0.001, "A far pose is a teleport, not a slide")


func _check_extrapolation() -> void:
	var buffer := NetSnapshotBuffer.new()
	for index: int in range(10):
		buffer.push(index / RATE, _pose(index / RATE), index / RATE)
	var last: float = _pose(9.0 / RATE).origin.z
	var held: float = buffer.sample(5.0).origin.z
	var expected: float = last - SPEED * NetSnapshotBuffer.MAX_EXTRAPOLATION
	_expect(absf(held - expected) < 0.01,
		"Past the newest pose it goes on MAX_EXTRAPOLATION, then holds (%.3f, wanted %.3f)" % [held, expected])


func _check_rest() -> void:
	var buffer := NetSnapshotBuffer.new()
	for index: int in range(10):
		buffer.push(index / RATE, Transform3D.IDENTITY, index / RATE)
	# At rest, one pose every half second, then it moves again.
	for sent: float in [0.8, 1.3]:
		buffer.push(sent, Transform3D.IDENTITY, sent)
	var moved_at: float = 1.6
	buffer.push(moved_at, Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)), moved_at)
	var drawn_late: float = moved_at - buffer.interval() * 1.5
	var before: float = buffer.sample(drawn_late - _offset(buffer)).origin.x
	_expect(before < 0.001, "After a long rest it stays put until one interval before it moved (x %.3f)" % before)


func _check_take() -> void:
	var buffer := NetSnapshotBuffer.new()
	var here := Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0))
	var there := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 0.0))
	buffer.take(0, here, false, 10.0)
	_expect(buffer.sample(10.0).origin == here.origin, "An unstamped pose is drawn at once")
	buffer.take(0, there, false, 10.01)
	_expect(buffer.sample(10.01).origin == there.origin, "...and so is the next one: no cushion without stamps")
	for index: int in range(1, 6):
		buffer.take(index * 33, _pose(index * 0.033), false, 20.0 + index * 0.033)
		buffer.take(index * 33, _pose(index * 0.033), false, 20.0 + index * 0.033 + 0.005)
	_expect(absf(buffer.interval() - 0.033) < 0.002,
		"A repeated stamp isn't taken twice (interval %.4f)" % buffer.interval())
	var drawn: float = buffer.sample(20.0 + 5 * 0.033).origin.z
	_expect(drawn > _pose(5 * 0.033).origin.z and drawn < _pose(0.033).origin.z + 0.001,
		"Stamped poses after unstamped ones are drawn in the past, between them (z %.3f)" % drawn)


## sender_time - local time - cushion, as the buffer draws it right now.
func _offset(buffer: NetSnapshotBuffer) -> float:
	return buffer.render_time(0.0)


func _check_sim_and_clear() -> void:
	var buffer := NetSnapshotBuffer.new()
	buffer.configure_sim({"lag_ms": 150, "jitter_ms": 20, "loss_pct": 2.0})
	_expect(is_equal_approx(buffer.fake_lag, 0.15) and is_equal_approx(buffer.fake_jitter, 0.02)
			and is_equal_approx(buffer.fake_loss, 0.02), "configure_sim() takes a --net-sim profile")
	buffer.configure_sim({})
	_expect(is_equal_approx(buffer.fake_lag, 0.15), "An empty profile leaves it as it was")
	buffer.push(0.0, _pose(0.0), 0.0)
	_expect(not buffer.is_empty() and buffer.sample(0.0) == Transform3D.IDENTITY,
		"A pose held back by the simulated lag isn't drawn yet")
	_expect(buffer.sample(0.2).origin.distance_to(_pose(0.0).origin) < 0.001, "...and is once its time comes")
	buffer.clear()
	_expect(buffer.is_empty(), "clear() empties it")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
