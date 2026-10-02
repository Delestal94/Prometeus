extends RefCounted
class_name NetInputBuffer
## The host's side of a client-predicted body: the controlling peer's inputs,
## numbered one per physics tick on its side, played back one per physics tick
## here, with the number each tick stands for.
##
## Inputs travel unreliable and land unevenly: two in one frame, none in the
## next, one lost now and then. Applied as they land, the host would run some
## of them for no tick and others for two, and the client could never tell
## which of its own ticks a host pose matches. So the host keeps a tick
## counter (`tick_seq()`) that moves on by one every consume() and starts
## CUSHION inputs behind the newest one that has landed: each tick it plays
## the input numbered as the counter, or the newest one before it when that one
## hasn't arrived (a loss, a late packet: the last input held, as a dropped
## sample always was). The pose the host sends goes with that counter, so the
## client compares it against its own state after the same input.
##
## - **Behind:** more than MAX_LAG inputs waiting (the link sped up, or the
##   client's clock runs fast), it skips ahead to CUSHION behind the newest.
## - **Ahead:** inputs flowing again but MAX_LEAD or more behind the counter
##   (the link slowed down for good), it steps back to the newest one, rather
##   than keep playing every input that many ticks late.
## - Inputs at or below the newest one already in (a repeat, an old one from
##   before a reset) are ignored. Numbers only ever grow on the sending side.
##
## The data is opaque: whatever the game sends (an Array of axes and buttons).

## Inputs kept back against jitter: the host plays each one this many ticks
## after the newest has landed.
const CUSHION: int = 2
const MAX_LAG: int = 8
const MAX_LEAD: int = 6
## Inputs kept at most (anything older than the counter is dropped sooner).
const MAX_INPUTS: int = 64

## [seq, data], oldest first.
var _inputs: Array = []
var _newest: int = -1
var _tick_seq: int = -1
var _last: Variant = null
var _fresh: bool = false


## An input from the controlling peer, numbered by its own physics tick.
func push(seq: int, data: Variant) -> void:
	if seq <= _newest:
		return
	_newest = seq
	_fresh = true
	_inputs.append([seq, data])
	while _inputs.size() > MAX_INPUTS:
		_inputs.pop_front()


## This tick's input: [seq it stands for, data], or [] while none has landed.
func consume() -> Array:
	if _newest < 0:
		return []
	if _tick_seq < 0:
		_tick_seq = _newest - CUSHION
	else:
		_tick_seq += 1
	if _newest - _tick_seq > MAX_LAG:
		_tick_seq = _newest - CUSHION
	elif _fresh and _tick_seq - _newest >= MAX_LEAD:
		_tick_seq = _newest
	_fresh = false
	while not _inputs.is_empty() and int(_inputs[0][0]) <= _tick_seq:
		_last = _inputs.pop_front()[1]
	if _last == null:
		# Started with only inputs ahead of the counter: play the oldest early
		# rather than nothing.
		_last = _inputs[0][1]
	return [_tick_seq, _last]


## The input number the last consume() stood for (-1 before the first).
func tick_seq() -> int:
	return _tick_seq


## The newest input number that has landed (-1 before the first).
func newest() -> int:
	return _newest


## Somebody else took the controls, or nobody holds them: start over.
func clear() -> void:
	_inputs.clear()
	_newest = -1
	_tick_seq = -1
	_last = null
	_fresh = false
