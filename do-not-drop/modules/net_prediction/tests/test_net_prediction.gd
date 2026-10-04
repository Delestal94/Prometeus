extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://modules/net_prediction/tests/test_net_prediction.gd
##
## The two halves of client-side prediction on their own (N-218):
## - NetInputBuffer (host): plays numbered inputs one per tick, CUSHION behind
##   the newest; holds the last one through a loss; skips ahead when too many
##   wait, steps back when the link slowed for good; ignores repeats and old
##   ones; says the input is stale once nothing new landed for more than
##   STALE_TICKS, and not once one that landed since plays (inputs back a
##   cushion ahead of the counter keep it stale until then, N-922.8); starts
##   over on clear().
## - NetInputBuffer over a link (N-922.9), one different input a tick: the
##   upload going from 2 to 7 ticks mid-run leaves the counter ahead of the
##   inputs that land, and within REANCHOR_TICKS of them it is back a cushion
##   behind the newest, the number it stamps the input it plays (before, 3
##   ticks ahead for good); jitter within the cushion and 10 % loss never move
##   the counter.
## - NetPredictionReconciler (client): a host state matching the prediction
##   leaves nothing to correct; an offset is eased out (most of it within
##   150 ms, never more than MAX_STEP a tick) and never corrected twice even
##   while states keep arriving for later inputs; small noise inside the dead
##   zone is left alone; a big jump snaps in one tick; the heading is corrected
##   too, and the velocity slowly once clearly off (not suspension shake);
##   states for unknown inputs are ignored, and a link that
##   lost track for too long snaps to the host. An error known before any
##   host state (nudge(): a body started where it is drawn, N-922.7) is eased
##   like a measured one, snapped when far (counted in start_snaps, not snaps:
##   N-922.9), and replaced by the next measure, its snap too.
## - NetDelayQueue (one way of a simulated link, N-922.5): inactive without a
##   profile; with one, each item comes out `lag` to `lag + jitter` later, in
##   the order it went in, about `loss` of them never; half the lag each way
##   for a predicted body's two ways; clear() drops what is on the way.

const TICK: float = 1.0 / 60.0

var _failures: int = 0


func _initialize() -> void:
	_input_buffer()
	_input_buffer_latency()
	_reconciler_eases()
	_reconciler_edges()
	_reconciler_nudge()
	_delay_queue()
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
	# N-922.8: the peer's own count went on while its inputs were cut off, so they come back a cushion ahead of the
	# counter. Until the counter reaches them the held input stays stale (not handed back as if fresh).
	for _tick: int in range(NetInputBuffer.STALE_TICKS + 5):
		buffer.consume()
	_expect(buffer.is_stale(), "Cut off again for longer than STALE_TICKS: stale")
	var resumed_at: int = buffer.tick_seq() + NetInputBuffer.CUSHION + 1
	var waiting: Array = []
	for tick: int in range(NetInputBuffer.CUSHION + 3):
		buffer.push(resumed_at + tick, [resumed_at + tick])
		var played: Array = buffer.consume()
		waiting.append([played[0], played[1][0], buffer.is_stale()])
	var caught_up: Array = waiting[-1]
	var still_stale: bool = true
	for entry: Array in waiting:
		if int(entry[0]) < resumed_at:
			still_stale = still_stale and bool(entry[2]) and int(entry[1]) == 41
	_expect(still_stale and int(caught_up[1]) == int(caught_up[0]) and not bool(caught_up[2]),
		"Inputs back a cushion ahead: stale until the counter reaches them, then the new ones play (%s)" % [waiting])
	buffer.clear()
	_expect(buffer.consume().is_empty() and buffer.tick_seq() == -1 and buffer.played_seq() == -1
			and not buffer.is_stale(), "clear() starts over")


## N-922.9: inputs sent one a tick, each one different (a wheel that keeps turning), over a link whose latency
## changes. What the host's counter stamps a tick with must be the input it plays: a pose stamped ahead of it is
## compared by the client with a state after an input the host hasn't played yet.
func _input_buffer_latency() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9229
	# The upload goes from 2 ticks to 7 at tick 60 (a --net-sim switched on mid-drive, a worse route).
	var rise: Array = _play_over_link(func(tick: int) -> int: return 2 if tick < 60 else 7, 0.0, rng)
	var off: Array[int] = []
	for tick: int in range(60, rise.size()):
		if int(rise[tick][0]) != int(rise[tick][1]):
			off.append(tick)
	var settled_by: int = 60 + 7 + NetInputBuffer.REANCHOR_TICKS + 2
	_expect(not off.is_empty() and int(off[-1]) < settled_by,
		("The upload 5 ticks slower: within REANCHOR_TICKS of the inputs flowing again the counter stamps the input"
				+ " it plays (off on %d ticks, %d to %d; all over by %d)") % [
			off.size(), off[0] if not off.is_empty() else -1, off[-1] if not off.is_empty() else -1, settled_by])
	_expect(int(rise[-1][2]) == NetInputBuffer.CUSHION,
		"...a cushion behind the newest again (%d behind)" % int(rise[-1][2]))
	# Jitter within the cushion (2 to 4 ticks, in order): never moves the counter, every input plays on its own tick.
	var jittery: Array = _play_over_link(func(_tick: int) -> int: return rng.randi_range(2, 2 + NetInputBuffer.CUSHION),
			0.0, rng)
	var steady: bool = true
	for tick: int in range(10, jittery.size()):
		steady = steady and int(jittery[tick][0]) == int(jittery[tick][1]) \
				and int(jittery[tick][0]) - int(jittery[tick - 1][0]) == 1
	_expect(steady, "Jitter within the cushion: the counter goes one a tick and plays every input on its own tick")
	# Losses (10 %) at a steady latency: the inputs after a loss are on time, so the counter never re-anchors.
	var lossy: Array = _play_over_link(func(_tick: int) -> int: return 3, 0.1, rng)
	var even: bool = true
	var held: int = 0
	for tick: int in range(10, lossy.size()):
		even = even and int(lossy[tick][0]) - int(lossy[tick - 1][0]) == 1
		if int(lossy[tick][0]) != int(lossy[tick][1]):
			held += 1
	_expect(even and held > 5, "10 %% of inputs lost: each held a tick (%d), the counter never moved" % held)


## One input a tick for 200 ticks, numbered by the tick and carrying it, each `delay_ticks.call(tick)` ticks late
## (an ordered link: none overtakes the one before), `loss` of them never; the host consumes one a tick from the
## moment the first lands. Per tick: [number stamped, number of the input played, newest - stamped].
func _play_over_link(delay_ticks: Callable, loss: float, rng: RandomNumberGenerator) -> Array:
	var buffer := NetInputBuffer.new()
	var in_flight: Array = []
	var played: Array = []
	for tick: int in range(200):
		if loss <= 0.0 or rng.randf() >= loss:
			var at: int = tick + int(delay_ticks.call(tick))
			if not in_flight.is_empty():
				at = maxi(at, int(in_flight[-1][0]))
			in_flight.append([at, tick])
		while not in_flight.is_empty() and int(in_flight[0][0]) <= tick:
			var seq: int = in_flight.pop_front()[1]
			buffer.push(seq, [seq])
		var entry: Array = buffer.consume()
		played.append([-1, -1, 0] if entry.is_empty()
				else [int(entry[0]), int(entry[1][0]), buffer.newest() - int(entry[0])])
	return played


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


func _reconciler_nudge() -> void:
	var reconciler := NetPredictionReconciler.new()
	reconciler.nudge(Vector3(1.5, 0.0, 0.0), Quaternion(Vector3.UP, 0.1))
	var moved := Vector3.ZERO
	var turned: float = 0.0
	var worst: float = 0.0
	for _tick: int in range(60):
		var step: Array = reconciler.step(TICK)
		moved += step[0] as Vector3
		turned += (step[1] as Quaternion).get_angle()
		worst = maxf(worst, (step[0] as Vector3).length())
	_expect(moved.distance_to(Vector3(1.5, 0.0, 0.0)) < NetPredictionReconciler.DEAD_POSITION + 0.005
			and absf(turned - 0.1) < 0.01 and worst <= NetPredictionReconciler.MAX_STEP + 0.0001
			and reconciler.snaps == 0 and reconciler.last_error == 0.0,
		"A nudge is eased in, never more than MAX_STEP a tick (moved %s, turned %.3f, worst %.3f)" % [
			moved, turned, worst])
	var far := NetPredictionReconciler.new()
	far.nudge(Vector3(0.0, 0.0, 5.0))
	_expect((far.step(TICK)[0] as Vector3).is_equal_approx(Vector3(0.0, 0.0, 5.0)) and far.start_snaps == 1
			and far.snaps == 0,
		"A nudge past SNAP_DISTANCE is snapped, counted as a start's, not as a prediction gone wrong (N-922.9)")
	# A host state measured later replaces what is left of it.
	var measured := NetPredictionReconciler.new()
	measured.record(1, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	measured.nudge(Vector3(2.0, 0.0, 0.0))
	measured.reconcile(1, Transform3D(Basis(), Vector3(0.5, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO)
	_expect(is_equal_approx(measured.pending_distance(), 0.5),
		"...and a host state measured after it replaces it (%.2f m left)" % measured.pending_distance())
	# ...its snap too: what is measured is eased, as far as it is.
	var replaced := NetPredictionReconciler.new()
	replaced.record(1, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	replaced.nudge(Vector3(5.0, 0.0, 0.0))
	replaced.reconcile(1, Transform3D(Basis(), Vector3(0.5, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO)
	var eased: float = (replaced.step(TICK)[0] as Vector3).length()
	_expect(eased > 0.0 and eased <= NetPredictionReconciler.MAX_STEP + 0.0001 and replaced.snaps == 0
			and replaced.start_snaps == 0,
		"A far nudge replaced by a small measured error: eased, no snap of either kind (%.3f m)" % eased)
	# A measured snap stays one even with a nudge on top.
	var both := NetPredictionReconciler.new()
	both.record(1, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	both.reconcile(1, Transform3D(Basis(), Vector3(10.0, 0.0, 0.0)), Vector3.ZERO, Vector3.ZERO)
	both.nudge(Vector3(0.0, 0.0, 1.0))
	both.step(TICK)
	_expect(both.snaps == 1 and both.start_snaps == 0, "A measured snap with a nudge after it counts as measured")


func _delay_queue() -> void:
	var queue := NetDelayQueue.new()
	queue.set_seed(922)
	_expect(not queue.is_active(), "No profile: nothing simulated")
	queue.configure_sim({"lag_ms": 150, "jitter_ms": 20, "loss_pct": 0.0}, 0.5)
	_expect(queue.is_active() and is_equal_approx(queue.lag, 0.075) and is_equal_approx(queue.jitter, 0.02),
		"Half of a 150 ms lag this way, the whole jitter (lag %.3f, jitter %.3f)" % [queue.lag, queue.jitter])
	# One item a tick for a second; read every tick.
	var sent_at: Dictionary = {}
	var delays: Array[float] = []
	var order: Array[int] = []
	for tick: int in range(120):
		var now: float = tick * TICK
		if tick < 60:
			queue.push(tick, now)
			sent_at[tick] = now
		for item: Variant in queue.take(now):
			delays.append(now - float(sent_at[int(item)]))
			order.append(int(item))
	var in_order: bool = true
	for index: int in range(1, order.size()):
		in_order = in_order and order[index] > order[index - 1]
	delays.sort()
	_expect(order.size() == 60 and in_order, "Every item comes out, in the order it went in (%d)" % order.size())
	_expect(delays[0] >= 0.075 - 0.0001 and delays[-1] <= 0.075 + 0.02 + TICK + 0.0001,
		"...each 75 ms to 95 ms later, read a tick at a time (%.3f..%.3f s)" % [delays[0], delays[-1]])
	_expect(queue.take(10.0).is_empty() and queue.pending() == 0, "Nothing is left on the way")
	# Loss.
	var lossy := NetDelayQueue.new()
	lossy.set_seed(5)
	lossy.configure_sim({"lag_ms": 0, "jitter_ms": 0, "loss_pct": 10.0})
	for index: int in range(1000):
		lossy.push(index, 0.0)
	var arrived: int = lossy.take(0.0).size()
	_expect(lossy.is_active() and arrived > 860 and arrived < 940, "About 10 %% lost (%d of 1000 arrive)" % arrived)
	# Turned off again, and cleared.
	queue.push(1, 0.0)
	queue.clear()
	_expect(queue.pending() == 0 and queue.take(10.0).is_empty(), "clear() drops what is on the way")
	queue.configure_sim({})
	_expect(not queue.is_active(), "An empty profile turns it off")


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
