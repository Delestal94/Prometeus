extends RefCounted
class_name VehicleNetSmoother
## The host's truck, drawn smoothly on a client (tareas de Nacho N-208).
##
## The host sends the truck's pose about 60 times a second, but they don't
## arrive that evenly: two land in one frame, then none for three, and with
## lag it only gets worse. Put straight onto the truck, every burst was a jump
## ahead and every gap a stall -- tens of centimetres per frame at cruising
## speed. So each pose carries the host's clock (vehicle.gd net_time), goes
## into a short buffer, and the client draws the truck DELAY seconds in the
## past, interpolated between the two poses either side of that moment. It
## lags the host by DELAY, and never predicts physics of its own: the host
## decides where the truck is.
##
## A pose that lands far from the last one (a respawn, a restart) is a
## teleport, not motion: the buffer starts over there.
##
## Debug: `--fake-lag=<ms>` on a client holds every arriving pose back that
## long, plus a random jitter of up to a third of it, to see what a bad
## connection does (measured in test_vehicle_net_smoothing.gd).

const DELAY: float = 0.1
## Poses kept: a little over half a second at 60 Hz.
const MAX_SNAPSHOTS: int = 40
## Past the newest pose, keep going on its velocity at most this long, then hold.
const MAX_EXTRAPOLATION: float = 0.1
const TELEPORT_DISTANCE: float = 6.0

## [host_time, Transform3D], oldest first.
var _snapshots: Array = []
## host clock minus local clock, the smallest seen (the least-delayed arrival).
var _clock_offset: float = INF
## Arrived but held back by --fake-lag: [release_at, host_time, Transform3D].
var _held: Array = []
var fake_lag: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-lag="):
			fake_lag = maxf(float(arg.get_slice("=", 1)) / 1000.0, 0.0)
	_rng.randomize()


func is_empty() -> bool:
	return _snapshots.is_empty() and _held.is_empty()


## A pose from the host, stamped with the host's clock, arriving at local
## time `now` (seconds).
func push(host_time: float, pose: Transform3D, now: float) -> void:
	if fake_lag > 0.0:
		_held.append([now + fake_lag + _rng.randf_range(0.0, fake_lag / 3.0), host_time, pose])
		return
	_accept(host_time, pose, now)


func _accept(host_time: float, pose: Transform3D, now: float) -> void:
	if not _snapshots.is_empty():
		var last: Array = _snapshots[-1]
		if host_time <= float(last[0]):
			return  # Late and out of order: we're past it already.
		if (last[1] as Transform3D).origin.distance_to(pose.origin) > TELEPORT_DISTANCE:
			_snapshots.clear()
			_clock_offset = INF
	_clock_offset = minf(_clock_offset, host_time - now)
	_snapshots.append([host_time, pose])
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## Where to draw the truck at local time `now`.
func sample(now: float) -> Transform3D:
	_release_held(now)
	if _snapshots.is_empty():
		return Transform3D.IDENTITY
	if _snapshots.size() == 1:
		return _snapshots[0][1]
	var render_time: float = now + _clock_offset - DELAY
	var first: Array = _snapshots[0]
	if render_time <= float(first[0]):
		return first[1]
	for index: int in range(_snapshots.size() - 1):
		var a: Array = _snapshots[index]
		var b: Array = _snapshots[index + 1]
		if render_time <= float(b[0]):
			var span: float = maxf(float(b[0]) - float(a[0]), 0.0001)
			return (a[1] as Transform3D).interpolate_with(b[1], (render_time - float(a[0])) / span)
	# Past the newest pose: carry on its motion briefly, then hold.
	var before: Array = _snapshots[-2]
	var last: Array = _snapshots[-1]
	var step: float = maxf(float(last[0]) - float(before[0]), 0.0001)
	var ahead: float = minf(render_time - float(last[0]), MAX_EXTRAPOLATION)
	var velocity: Vector3 = ((last[1] as Transform3D).origin - (before[1] as Transform3D).origin) / step
	var pose: Transform3D = last[1]
	pose.origin += velocity * ahead
	return pose


func _release_held(now: float) -> void:
	if _held.is_empty():
		return
	_held.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	while not _held.is_empty() and float(_held[0][0]) <= now:
		var entry: Array = _held.pop_front()
		_accept(float(entry[1]), entry[2], now)


func clear() -> void:
	_snapshots.clear()
	_held.clear()
	_clock_offset = INF
