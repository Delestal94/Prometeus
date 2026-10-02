extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_prediction/tests/test_net_prediction.gd
##
## The two halves of client-side prediction on their own (N-218):
## - NetInputBuffer (host): plays numbered inputs one per tick, CUSHION behind
##   the newest; holds the last one through a loss; skips ahead when too many
##   wait, steps back when the link slowed for good; ignores repeats and old
##   ones; says the input is stale once nothing new landed for more than
##   STALE_TICKS, and not once one does; starts over on clear().
## - NetPredictionReconciler (client): a host state matching the prediction
##   leaves nothing to correct; an offset is eased out (most of it within
##   150 ms, never more than MAX_STEP a tick) and never corrected twice even
##   while states keep arriving for later inputs; small noise inside the dead
##   zone is left alone; a big jump snaps in one tick; the heading is corrected
##   too, and the velocity slowly once clearly off (not suspension shake);
##   states for unknown inputs are ignored, and a link that
##   lost track for too long snaps to the host.

const TICK: float = 1.0 / 60.0

var _failures: int = 0


func _initialize() -> void:
	_input_buffer()
	_reconciler_eases()
	_reconciler_edges()
	if _failures == 0:
		print("PASS: net_prediction")
	quit(_failures)


func _input_buffer() -> void:
	var buffer := NetInputBuffer.new()
	_expect(buffer.consume().is_empty(), "No input yet: nothing to play")
	for seq: int in range(10, 15):
		buffer.push(seq, [seq])
	var first: Array = buffer.consume()
	_expect(int(first[0]) == 14 - NetInputBuffer.CUSHION and int(first[1][0]) == 14 - NetInputBuffer.CUSHION,
		"It starts CUSHION inputs behind the newest (got %s)" % [first])
	var second: Array = buffer.consume()
	_expect(int(second[0]) == int(first[0]) + 1 and int(second[1][0]) == int(second[0]), "One input per tick, in order")
	# 15 lost; 16 arrives late.
	buffer.consume()  # 14
	var held: Array = buffer.consume()  # 15: lost
	_expect(int(held[0]) == 15 and int(held[1][0]) == 14, "A lost input: the tick still counts, the last input is held")
	buffer.push(16, [16])
	var late: Array = buffer.consume()
	_expect(int(late[0]) == 16 and int(late[1][0]) == 16, "The next one plays on its own tick")
	buffer.push(16, [99])
	buffer.push(3, [3])
	_expect(buffer.newest() == 16, "Repeats and old inputs are ignored")
	# A burst: far more waiting than MAX_LAG.
	for seq: int in range(17, 40):
		buffer.push(seq, [seq])
	var skipped: Array = buffer.consume()
	_expect(int(skipped[0]) == 39 - NetInputBuffer.CUSHION,
		"Too many waiting: it skips ahead to CUSHION behind the newest")
	# Starved for a while, then inputs flow again from far behind the counter.
	for _tick: int in range(12):
		buffer.consume()
	buffer.push(40, [40])
	var back: Array = buffer.consume()
	_expect(int(back[0]) == 40 and int(back[1][0]) == 40,
		"Inputs flowing again far behind the counter: it steps back to the newest (got %s)" % [back])
	_expect(not buffer.is_stale(), "Inputs flowing: the one played is not stale")
	# The peer goes quiet without leaving (a hitch, a Wi-Fi drop).
	for _tick: int in range(NetInputBuffer.STALE_TICKS):
		buffer.consume()
	_expect(not buffer.is_stale(), "Held up to STALE_TICKS past the newest: not stale yet")
	var stale: Array = buffer.consume()
	_expect(buffer.is_stale() and int(stale[1][0]) == 40,
		"Nothing new for more than STALE_TICKS: stale, the last input still handed back (got %s)" % [stale])
	buffer.push(41, [41])
	buffer.consume()
	_expect(not buffer.is_stale(), "A new input lands: not stale any more")
	buffer.clear()
	_expect(buffer.consume().is_empty() and buffer.tick_seq() == -1 and not buffer.is_stale(), "clear() starts over")


## A body moving along +X at 20 m/s, predicted with an error the host doesn't have.
func _reconciler_eases() -> void:
	var reconciler := NetPredictionReconciler.new()
	var speed := Vector3(20.0, 0.0, 0.0)
	var offset := Vector3(0.0, 0.0, 0.8)
	var predicted := Transform3D.IDENTITY
	var host_states: Array = []
	var lag_ticks: int = 9
	var worst_step: float = 0.0
	var left_at_150ms: float = INF
	var applied_total := Vector3.ZERO
	for tick: int in range(120):
		var seq: int = 100 + tick
		reconciler.record(seq, predicted, speed, Vector3.ZERO)
		# The host is where the prediction would be without the offset.
		var host_pose := Transform3D(Basis(), Vector3(speed.x * TICK * tick, 0.0, 0.0))
		if tick == 0:
			predicted.origin += offset
			reconciler.record(seq, predicted, speed, Vector3.ZERO)
		host_states.append([seq, host_pose])
		if host_states.size() > lag_ticks:
			var state: Array = host_states.pop_front()
			reconciler.reconcile(int(state[0]), state[1], speed, Vector3.ZERO)
		var correction: Array = reconciler.step(TICK)
		var shift: Vector3 = correction[0]
		worst_step = maxf(worst_step, shift.length())
		applied_total += shift
		predicted.origin += shift
		predicted.origin += speed * TICK
		if tick == lag_ticks + 9:
			left_at_150ms = (offset + applied_total).length()
	_expect(worst_step <= NetPredictionReconciler.MAX_STEP + 0.0001,
		"Never more than MAX_STEP a tick (worst %.3f m)" % worst_step)
	_expect(left_at_150ms < 0.15 * offset.length(),
		"Most of the error is gone 150 ms after it's measured (%.3f m of %.2f left)" % [left_at_150ms, offset.length()])
	_expect((offset + applied_total).length() < NetPredictionReconciler.DEAD_POSITION + 0.005,
		"Corrected once, not again for every state that kept arriving (left %s)" % [offset + applied_total])

	# Noise under the dead zone.
	var quiet := NetPredictionReconciler.new()
	quiet.record(1, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	quiet.reconcile(1, Transform3D(Basis(), Vector3(0.01, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO)
	var none: Array = quiet.step(TICK)
	_expect(none[0] == Vector3.ZERO and none[1] == Quaternion.IDENTITY, "A centimetre of difference is left alone")

	# Heading and velocity.
	var turned := NetPredictionReconciler.new()
	turned.record(1, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	turned.reconcile(1, Transform3D(Basis(Vector3.UP, 0.2), Vector3.ZERO), Vector3(2.0, 0.0, 0.0), Vector3.ZERO)
	var heading: float = 0.0
	var velocity := Vector3.ZERO
	for _tick: int in range(120):
		var step: Array = turned.step(TICK)
		heading += (step[1] as Quaternion).get_angle()
		velocity += step[2] as Vector3
		_expect((step[1] as Quaternion).get_angle() <= NetPredictionReconciler.MAX_TURN_STEP + 0.0001,
			"The heading turns at most MAX_TURN_STEP a tick")
	_expect(absf(heading - 0.2) < 0.01, "The heading is corrected too (%.3f of 0.2 rad)" % heading)
	_expect(velocity.distance_to(Vector3(2.0, 0.0, 0.0)) <= NetPredictionReconciler.DEAD_VELOCITY + 0.01,
		"And the velocity, slowly, down to its dead zone (%s)" % [velocity])
	var shaky := NetPredictionReconciler.new()
	shaky.record(1, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	shaky.reconcile(1, Transform3D.IDENTITY, Vector3(0.0, 0.3, 0.0), Vector3.ZERO)
	_expect(shaky.step(TICK)[2] == Vector3.ZERO, "A velocity off by suspension shake (0.3 m/s) is left alone")


func _reconciler_edges() -> void:
	var reconciler := NetPredictionReconciler.new()
	for seq: int in range(1, 11):
		reconciler.record(seq, Transform3D(Basis(), Vector3(seq, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO)
	_expect(not reconciler.reconcile(20, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO),
		"A state for an input not predicted yet is ignored")
	_expect(not reconciler.reconcile(0, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO),
		"A state from before the prediction started is ignored")
	_expect(reconciler.step(TICK)[0] == Vector3.ZERO, "Ignored states correct nothing")
	# A reset on the host: 30 m away.
	_expect(reconciler.reconcile(5, Transform3D(Basis(), Vector3(35.0, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO),
		"A state for a recorded input is compared")
	var snap: Array = reconciler.step(TICK)
	_expect((snap[0] as Vector3).is_equal_approx(Vector3(30.0, 0.0, 0.0)) and reconciler.snaps == 1,
		"A big jump snaps whole in one tick (%s)" % [snap[0]])
	_expect(reconciler.step(TICK)[0] == Vector3.ZERO, "And is done with")

	# Lost track: the history full and the host stuck far behind it.
	var lost := NetPredictionReconciler.new()
	for seq: int in range(1000, 1000 + NetPredictionReconciler.HISTORY_SIZE):
		lost.record(seq, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	for _packet: int in range(NetPredictionReconciler.UNMATCHED_LIMIT):
		lost.reconcile(10, Transform3D(Basis(), Vector3(0.0, 0.0, 9.0)), Vector3.ZERO, Vector3.ZERO)
	var fallback: Array = lost.step(TICK)
	_expect((fallback[0] as Vector3).is_equal_approx(Vector3(0.0, 0.0, 9.0)),
		"Host states it can't match for too long: it snaps to the host (%s)" % [fallback[0]])

	# The input numbers going back (a new prediction session) start the history over.
	lost.record(5, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	_expect(lost.history_size() == 1, "Numbers going back start the history over")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
