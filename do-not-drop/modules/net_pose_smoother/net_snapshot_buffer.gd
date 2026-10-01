class_name NetSnapshotBuffer
extends RefCounted
## Something another peer owns, drawn smoothly here (N-217: players and
## boxes; NetPoseSmoother, the truck's from N-208, keeps a fixed delay).
##
## Poses come over the network at a fixed rate but don't land evenly: two in
## one frame, then none for three, a lost one now and then, and with an
## internet connection every one a little late by a different amount. Put
## straight onto a node, every burst is a jump and every gap a stall. So each
## pose carries its sender's clock, goes into this short buffer, and the node
## is drawn a touch in the past, interpolated between the two poses either side
## of that moment. The owner decides where it is; this never predicts physics.
##
## - **Sender clock.** A pose is stamped with the clock of whoever sent it
##   (clock(): physics time, so it matches the physics step the pose comes
##   from). Its offset to this peer's clock is taken from the least-delayed
##   arrival of the last second, which follows a drifting clock or a hitch on
##   either side instead of keeping a stale guess.
## - **Adaptive cushion.** How far in the past it's drawn: 2 send intervals
##   plus 2 x the jitter measured on arrival (RFC 3550's running average),
##   kept between MIN_DELAY and MAX_DELAY -- small on a LAN, bigger on a bad
##   connection. Changes in either are eased in (CLOCK_SLEW): every jump in the
##   drawing time would be a jump in where the node is drawn.
## - **Loss.** Past the newest pose it carries on at its last velocity for up
##   to MAX_EXTRAPOLATION, then holds.
## - **Rest.** A sender that slows down while its pose stays put (a box at
##   rest, NetRestThrottle) leaves a long gap before the first pose that moves
##   again: the resting pose is repeated one interval before it, so the motion
##   starts there instead of creeping across the whole gap.
## - **Order.** Poses are kept in sender order even when the network swapped
##   two; a repeated one is ignored.
## - **Truck space.** A pose can be `local`: in the space of something that
##   moves (the truck's cargo bay), interpolated there and put on that
##   something as this peer draws it (`local_to_world` in sample()).
## - **Teleports.** A pose far from the previous one (a respawn, a rescue)
##   starts the buffer over there instead of sliding across the map.
##
## Debug: `--fake-lag=<ms>` holds every arriving pose back that long, plus a
## random jitter of up to a third of it. `--net-sim=lag,jitter,loss` (N-216,
## net_stats.gd) does the same on LAN with its own jitter (0..jitter ms) and
## drops `loss` % of the poses, as a lossy link would. The owner hands that
## profile in (configure_sim()): the buffer never looks the session up.

const MIN_DELAY: float = 0.05
const MAX_DELAY: float = 0.2
## What the send interval is taken to be until two poses say otherwise.
const DEFAULT_INTERVAL: float = 1.0 / 30.0
## Past the newest pose, keep going on its velocity at most this long, then hold.
const MAX_EXTRAPOLATION: float = 0.1
const TELEPORT_DISTANCE: float = 6.0
## Poses kept at most (the ones already drawn past are dropped sooner).
const MAX_SNAPSHOTS: int = 40
## Arrivals the clock offset is taken from (seconds of this peer's clock).
const CLOCK_WINDOW: float = 1.0
## How fast the drawing time may drift toward a new offset or cushion: 5 %,
## so something moving is drawn at most 5 % faster or slower meanwhile.
const CLOCK_SLEW: float = 0.05
## Further off than this (a long hitch on either side) it jumps instead.
const CLOCK_SNAP: float = 0.25
## Poses in a row this much later than the clock expects before the clock is
## taken to have moved (a hitch on the sender), not the network to be slow.
const LATE_STREAK: int = 6
## RFC 3550: the jitter estimate moves 1/16 of the way to each new sample.
const JITTER_GAIN: float = 1.0 / 16.0
## Gaps longer than this (a hitch, a pause) say nothing about the link.
const MAX_SAMPLE_GAP: float = 0.5
## A gap of more than this many send intervals before a pose is a sender at
## rest (or a burst lost): the pose before it is held until one interval before.
const REST_GAP_INTERVALS: float = 4.0

## [sender_time, Transform3D, local], oldest first.
var _snapshots: Array = []
## [arrival, sender_time - arrival] of the last CLOCK_WINDOW, oldest first.
var _offsets: Array = []
var _offset_max: float = -INF
var _late_streak: int = 0
## sender clock - local clock - cushion, as drawn (eased toward the target).
var _render_offset: float = INF
var _last_sample_at: float = -INF
var _interval: float = DEFAULT_INTERVAL
var _interval_known: bool = false
var _jitter: float = 0.0
var _last_transit: float = INF
## Arrived but held back by --fake-lag: [release_at, sender_time, Transform3D, local].
var _held: Array = []
var fake_lag: float = 0.0
## Seconds of random extra hold per pose, 0..this; below 0, the old
## --fake-lag spread (up to a third of fake_lag).
var fake_jitter: float = -1.0
## Share of arriving poses dropped (0..1), like packets lost on the way.
var fake_loss: float = 0.0
var _rng := RandomNumberGenerator.new()
## What take() last saw, and whether the buffer holds unstamped poses.
var _taken: Array = []
var _unstamped: bool = false


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-lag="):
			fake_lag = maxf(float(arg.get_slice("=", 1)) / 1000.0, 0.0)
	_rng.randomize()


## The clock a sender stamps its poses with: seconds of physics simulated in
## this process, so a stamp matches the physics step its pose comes from.
static func clock() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## clock() in whole milliseconds: what players and boxes send (an int goes in
## 8 bytes; a float that isn't a round binary fraction takes 12).
static func clock_ms() -> int:
	return int(Engine.get_physics_frames() * 1000 / Engine.physics_ticks_per_second)


## This peer's own clock for arrivals and drawing (seconds).
static func local_now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Takes a `--net-sim` profile ({lag_ms, jitter_ms, loss_pct}); an empty one
## leaves the buffer as it was. The owner calls it (the game knows whether the
## transport already simulates the link).
func configure_sim(sim: Dictionary) -> void:
	if sim.is_empty():
		return
	fake_lag = maxf(float(sim.get("lag_ms", 0)) / 1000.0, 0.0)
	fake_jitter = maxf(float(sim.get("jitter_ms", 0)) / 1000.0, 0.0)
	fake_loss = clampf(float(sim.get("loss_pct", 0.0)) / 100.0, 0.0, 1.0)


func is_empty() -> bool:
	return _snapshots.is_empty() and _held.is_empty()


## A pose from its owner, stamped with the owner's clock, arriving at local
## time `now` (seconds). `local`: it's in the space of whatever sample() is
## given as `local_to_world` (the truck), not the world's.
func push(sender_time: float, pose: Transform3D, now: float, local: bool = false) -> void:
	if fake_loss > 0.0 and _rng.randf() < fake_loss:
		return
	if fake_lag > 0.0 or fake_jitter > 0.0:
		var spread: float = fake_jitter if fake_jitter >= 0.0 else fake_lag / 3.0
		_held.append([now + fake_lag + _rng.randf_range(0.0, spread), sender_time, pose, local])
		return
	_accept(sender_time, pose, now, local)


## A replicated pose read straight off the synchronized properties, every
## frame: only a new (stamp, pose, local) goes in, so the owner polls its
## properties instead of hooking each setter (they land one by one, in any
## order). `stamp_ms` is the sender's clock_ms(); 0, never stamped (a spawn
## state from before the stamp, a test placing a body by hand), puts the pose
## there at once, as if there were no buffer.
func take(stamp_ms: int, pose: Transform3D, local: bool, now: float) -> void:
	var state: Array = [stamp_ms, pose, local]
	if state == _taken:
		return
	if stamp_ms <= 0 or _unstamped:
		clear()
	_taken = state
	_unstamped = stamp_ms <= 0
	if _unstamped:
		_accept(now, pose, now, local)
	else:
		push(stamp_ms / 1000.0, pose, now, local)


func _accept(sender_time: float, pose: Transform3D, now: float, local: bool) -> void:
	_measure(sender_time, now)
	if not _snapshots.is_empty():
		var last: Array = _snapshots[-1]
		if sender_time > float(last[0]) and bool(last[2]) == local \
				and (last[1] as Transform3D).origin.distance_to(pose.origin) > TELEPORT_DISTANCE:
			_snapshots.clear()
	# In order, even when the network swapped two packets.
	var at: int = _snapshots.size()
	while at > 0 and float(_snapshots[at - 1][0]) > sender_time:
		at -= 1
	if at > 0 and is_equal_approx(float(_snapshots[at - 1][0]), sender_time):
		return
	if at == _snapshots.size() and at > 0:
		var previous: Array = _snapshots[at - 1]
		var gap: float = sender_time - float(previous[0])
		if gap > 0.0 and gap < MAX_SAMPLE_GAP:
			_interval = gap if not _interval_known else lerpf(_interval, gap, 0.1)
			_interval_known = true
		if gap > REST_GAP_INTERVALS * _interval:
			_snapshots.append([sender_time - _interval, previous[1], previous[2]])
			at += 1
	_snapshots.insert(at, [sender_time, pose, local])
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## The clock offset (least-delayed arrival of the window) and the jitter.
func _measure(sender_time: float, now: float) -> void:
	var offset: float = sender_time - now
	var transit: float = -offset
	if _last_transit != INF:
		var swing: float = minf(absf(transit - _last_transit), MAX_SAMPLE_GAP)
		_jitter += (swing - _jitter) * JITTER_GAIN
	_last_transit = transit
	# Much later than the clock expects, many times in a row: the sender's
	# clock lost time (a hitch there), so start the window over from these.
	if _offset_max != -INF and _offset_max - offset > CLOCK_SNAP:
		_late_streak += 1
		if _late_streak >= LATE_STREAK:
			_offsets.clear()
			_late_streak = 0
	else:
		_late_streak = 0
	_offsets.append([now, offset])
	while _offsets.size() > 1 and float(_offsets[0][0]) < now - CLOCK_WINDOW:
		_offsets.pop_front()
	_offset_max = -INF
	for entry: Array in _offsets:
		_offset_max = maxf(_offset_max, float(entry[1]))


## How far in the past it's drawn right now: 2 send intervals + 2 x jitter,
## within MIN_DELAY..MAX_DELAY.
func delay() -> float:
	return clampf(2.0 * _interval + 2.0 * _jitter, MIN_DELAY, MAX_DELAY)


## The measured jitter of arrivals (seconds).
func jitter() -> float:
	return _jitter


## The measured send interval (seconds).
func interval() -> float:
	return _interval


## The newest pose that arrived, as sent (in its own space), and whether it's
## a `local` one. For judging where the owner is now, not where it's drawn.
func latest_pose() -> Transform3D:
	return _snapshots[-1][1] if not _snapshots.is_empty() else Transform3D.IDENTITY


func latest_local() -> bool:
	return bool(_snapshots[-1][2]) if not _snapshots.is_empty() else false


## The sender time drawn at local time `now`.
func render_time(now: float) -> float:
	var target: float = _offset_max - delay()
	if _render_offset == INF or absf(target - _render_offset) > CLOCK_SNAP:
		_render_offset = target
	else:
		_render_offset = move_toward(_render_offset, target, CLOCK_SLEW * maxf(now - _last_sample_at, 0.0))
	_last_sample_at = maxf(_last_sample_at, now)
	return now + _render_offset


## Where to draw it at local time `now`, in world space: `local` poses go on
## `local_to_world` (the truck as this peer draws it).
func sample(now: float, local_to_world: Transform3D = Transform3D.IDENTITY) -> Transform3D:
	_release_held(now)
	if _snapshots.is_empty():
		return Transform3D.IDENTITY
	if _snapshots.size() == 1:
		return _world(_snapshots[0], local_to_world)
	var drawn_at: float = render_time(now)
	# Poses already drawn past are done with (one is kept before the moment).
	while _snapshots.size() > 2 and float(_snapshots[1][0]) <= drawn_at:
		_snapshots.pop_front()
	var first: Array = _snapshots[0]
	if drawn_at <= float(first[0]):
		return _world(first, local_to_world)
	for index: int in range(_snapshots.size() - 1):
		var a: Array = _snapshots[index]
		var b: Array = _snapshots[index + 1]
		if drawn_at <= float(b[0]):
			var weight: float = (drawn_at - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			if bool(a[2]) == bool(b[2]):
				var between: Transform3D = (a[1] as Transform3D).interpolate_with(b[1], weight)
				return local_to_world * between if bool(a[2]) else between
			return _world(a, local_to_world).interpolate_with(_world(b, local_to_world), weight)
	# Past the newest pose: carry on its motion briefly, then hold.
	var before: Array = _snapshots[-2]
	var last: Array = _snapshots[-1]
	var pose: Transform3D = last[1]
	if bool(before[2]) == bool(last[2]):
		var step: float = maxf(float(last[0]) - float(before[0]), 0.0001)
		var ahead: float = minf(drawn_at - float(last[0]), MAX_EXTRAPOLATION)
		pose.origin += ((last[1] as Transform3D).origin - (before[1] as Transform3D).origin) / step * ahead
	return local_to_world * pose if bool(last[2]) else pose


static func _world(snapshot: Array, local_to_world: Transform3D) -> Transform3D:
	return local_to_world * (snapshot[1] as Transform3D) if bool(snapshot[2]) else snapshot[1]


func _release_held(now: float) -> void:
	if _held.is_empty():
		return
	_held.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	while not _held.is_empty() and float(_held[0][0]) <= now:
		var entry: Array = _held.pop_front()
		_accept(float(entry[1]), entry[2], now, bool(entry[3]))


func clear() -> void:
	_snapshots.clear()
	_held.clear()
	_offsets.clear()
	_offset_max = -INF
	_late_streak = 0
	_render_offset = INF
	_last_sample_at = -INF
	_interval = DEFAULT_INTERVAL
	_interval_known = false
	_jitter = 0.0
	_last_transit = INF
	_taken = []
	_unstamped = false
