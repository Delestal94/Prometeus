class_name DayClock
extends RefCounted
## A game clock kept as an anchor: the game minute it read at one local tick, how fast it runs
## (game minutes per real second) and whether it is stopped. The time at any later tick comes
## from the anchor alone (minute_at()), so nothing has to be sent while the clock just runs.
##
## Across a network the anchor travels without its tick (to_dict(): minute, speed, paused): a
## tick of one machine means nothing on another. Whoever gets it pairs it with a tick of its own
## (from_dict(), with the moment it was valid at, e.g. "now minus half the round trip") and from
## then on reads the same time as the sender. Only a change of pace (start, pause, resume, a new
## speed) needs a new anchor; which peer may change it, and how the anchor reaches the others,
## is the game's (an adapter outside the module).
##
## Pure: no node, no tree, no network, no time source of its own. Ticks are msec on one
## monotonic clock (Time.get_ticks_msec(), or one a test drives) passed in by the caller.

## The keys an anchor travels with, and nothing else.
const KEYS: Array[String] = ["minute", "speed", "paused"]

## The game minute the clock read at origin_msec.
var minute: float = 0.0
## Game minutes per real second while it runs.
var speed: float = 1.0
## Stopped: the time stays at `minute`, whatever the tick.
var paused: bool = true
## The local tick (msec) `minute` was read at.
var origin_msec: int = 0


func _init(at_minute: float = 0.0, at_speed: float = 1.0, is_paused: bool = true, at_msec: int = 0) -> void:
	set_anchor(at_minute, at_speed, is_paused, at_msec)


## Puts a new anchor in place: at local tick `at_msec` the clock reads `at_minute` and from then
## on runs at `at_speed` game minutes per real second, unless `is_paused`.
func set_anchor(at_minute: float, at_speed: float, is_paused: bool, at_msec: int) -> void:
	minute = at_minute
	speed = at_speed
	paused = is_paused
	origin_msec = at_msec


## The game minute at local tick `now_msec`. A stopped clock reads its anchor's minute; a tick
## before the anchor's reads it too (the clock never runs backwards).
func minute_at(now_msec: int) -> float:
	if paused:
		return minute
	return minute + speed * float(maxi(now_msec - origin_msec, 0)) / 1000.0


## The anchor as it travels, moved to `now_msec` (the minute it reads then): {minute, speed,
## paused}, plain data, without a tick.
func to_dict(now_msec: int) -> Dictionary:
	return {"minute": minute_at(now_msec), "speed": speed, "paused": paused}


## Takes an anchor that came from elsewhere (to_dict() of another holder) as valid at local tick
## `at_msec`. False, changing nothing, when anchor_ok() refuses it.
func from_dict(data: Variant, at_msec: int, max_minute: float = INF, max_speed: float = INF) -> bool:
	if not anchor_ok(data, max_minute, max_speed):
		return false
	var anchor: Dictionary = data
	set_anchor(float(anchor["minute"]), float(anchor["speed"]), bool(anchor["paused"]), at_msec)
	return true


## True when `data` is an anchor as to_dict() writes it and nothing more: exactly KEYS, `minute`
## and `speed` finite numbers from 0 up to `max_minute` and `max_speed`, `paused` a bool. Data
## from the network is checked with this before it is used.
static func anchor_ok(data: Variant, max_minute: float = INF, max_speed: float = INF) -> bool:
	if not data is Dictionary:
		return false
	var anchor: Dictionary = data
	if anchor.size() != KEYS.size():
		return false
	for key: String in KEYS:
		if not anchor.has(key):
			return false
	if typeof(anchor["paused"]) != TYPE_BOOL:
		return false
	return _number_ok(anchor["minute"], max_minute) and _number_ok(anchor["speed"], max_speed)


static func _number_ok(value: Variant, top: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= top
