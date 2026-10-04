extends RefCounted
class_name NetDelayQueue
## One way of a bad link, simulated where the transport simulates nothing (a
## LAN test with `--net-sim`): what goes in comes out `lag` seconds later, plus
## a random 0..`jitter`, and a `loss` share never comes out, as on an
## unreliable channel. Items come out in the order they went in (an ordered
## channel drops what would overtake; here it just waits behind).
##
## A predicted body needs its two ways delayed, or the prediction looks
## perfect on a LAN: the inputs the client sends to the host, and the host's
## states that come back to compare with. `configure_sim()` takes the profile
## and the share of its lag this way carries (half each way: the round trip
## grows by the whole lag, as when the sockets simulate it).
##
## Inactive (no lag, jitter nor loss), push() still holds items until the
## next take(): callers that want them at once ask is_active() first.

var lag: float = 0.0
var jitter: float = 0.0
## Share of items dropped (0..1).
var loss: float = 0.0
## [release_at, item], oldest first.
var _queue: Array = []
var _last_release: float = -INF
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


## A `--net-sim` profile ({lag_ms, jitter_ms, loss_pct}), this way carrying `lag_share` of its lag. An empty one
## turns the simulation off.
func configure_sim(sim: Dictionary, lag_share: float = 1.0) -> void:
	lag = maxf(float(sim.get("lag_ms", 0)) / 1000.0 * clampf(lag_share, 0.0, 1.0), 0.0)
	jitter = maxf(float(sim.get("jitter_ms", 0)) / 1000.0, 0.0)
	loss = clampf(float(sim.get("loss_pct", 0.0)) / 100.0, 0.0, 1.0)


## For tests: the same draws every run.
func set_seed(value: int) -> void:
	_rng.seed = value


func is_active() -> bool:
	return lag > 0.0 or jitter > 0.0 or loss > 0.0


## `item` leaves at `now` (seconds, any clock that take() is given too).
func push(item: Variant, now: float) -> void:
	if loss > 0.0 and _rng.randf() < loss:
		return
	var release_at: float = maxf(now + lag + (_rng.randf_range(0.0, jitter) if jitter > 0.0 else 0.0), _last_release)
	_last_release = release_at
	_queue.append([release_at, item])


## Everything that has arrived by `now`, in order.
func take(now: float) -> Array:
	var arrived: Array = []
	while not _queue.is_empty() and float(_queue[0][0]) <= now:
		arrived.append(_queue.pop_front()[1])
	return arrived


## Items still on the way.
func pending() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()
	_last_release = -INF
