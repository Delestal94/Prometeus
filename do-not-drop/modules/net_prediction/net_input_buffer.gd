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
## - **Ahead:** the link slowed down for good (its latency rose, a `--net-sim`
##   switched on): the counter went on through the gap, and the inputs flowing
##   again land behind it. Each one plays the tick it lands, but the counter
##   would stamp it a few ticks ahead: a pose said to come after an input not
##   played yet, which the client, steering, corrects toward a body that
##   reacts late, for as long as the link stays slow (N-922.9). So once
##   REANCHOR_TICKS inputs in a row have landed behind the counter, none on
##   time in between, it steps back to CUSHION behind the newest. The numbers
##   it stands for repeat for a few ticks then (the client skips those it has
##   compared past), and the ticks an input was held meanwhile (the gap, the
##   cushion built again: as many as the latency rose) show up once, as a
##   difference the client is corrected for, like a loss. A loss doesn't count
##   toward it (the inputs after it are on time), nor do ticks where nothing
##   landed (jitter, or a peer gone quiet: stale), so jitter within the
##   cushion never moves the counter. MAX_LEAD or more behind, it steps back to
##   the newest one at once, rather than keep playing every input that many
##   ticks late.
## - **Stale:** the counter more than STALE_TICKS past the newest input (the
##   peer stopped sending without leaving: a hitch, a Wi-Fi drop), is_stale()
##   says so. The last input is still handed back; what holding it that long
##   means is the game's to decide (a pedal let go, a button released). It
##   stays stale until an input that landed since is played: inputs flowing
##   again come in a cushion ahead of the counter, and for those ticks the old
##   one would otherwise have been handed back as if fresh (N-922.8).
## - Inputs at or below the newest one already in (a repeat, an old one from
##   before a reset) are ignored. Numbers only ever grow on the sending side.
##
## The data is opaque: whatever the game sends (an Array of axes and buttons).

## Inputs kept back against jitter: the host plays each one this many ticks
## after the newest has landed.
const CUSHION: int = 2
const MAX_LAG: int = 8
const MAX_LEAD: int = 6
## Inputs landing in a row behind the counter before it re-anchors a cushion
## behind the newest (a quarter second at 60 Hz: far longer than jitter keeps
## the counter waiting, short enough that a slower link costs little).
const REANCHOR_TICKS: int = 15
## Ticks the last input may be held past the newest one before it is stale:
## half a second at 60 Hz, far past any jitter or single lost packet.
const STALE_TICKS: int = 30
## Inputs kept at most (anything older than the counter is dropped sooner).
const MAX_INPUTS: int = 64

## [seq, data], oldest first.
var _inputs: Array = []
var _newest: int = -1
var _tick_seq: int = -1
var _last: Variant = null
## The number of the input in `_last`.
var _last_seq: int = -1
var _fresh: bool = false
var _stale: bool = false
## Inputs that landed in a row behind the counter, none on time in between.
var _landed_behind: int = 0


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
	elif _fresh and _newest < _tick_seq:
		# Inputs landing, but behind the counter: each would be stamped ahead
		# of itself. For long enough in a row, the link is slower now, not
		# jittery: a cushion behind the newest again, once (N-922.9).
		_landed_behind += 1
		if _landed_behind >= REANCHOR_TICKS:
			_tick_seq = _newest - CUSHION
	if _newest >= _tick_seq:
		_landed_behind = 0
	_fresh = false
	var played_new: bool = false
	while not _inputs.is_empty() and int(_inputs[0][0]) <= _tick_seq:
		var entry: Array = _inputs.pop_front()
		_last_seq = int(entry[0])
		_last = entry[1]
		played_new = true
	if _last == null:
		# Started with only inputs ahead of the counter: play the oldest early
		# rather than nothing.
		_last_seq = int(_inputs[0][0])
		_last = _inputs[0][1]
		played_new = true
	if played_new:
		_stale = false
	elif _tick_seq - _newest > STALE_TICKS:
		_stale = true
	return [_tick_seq, _last]


## The input number the last consume() stood for (-1 before the first).
func tick_seq() -> int:
	return _tick_seq


## The number of the input the last consume() handed back (-1 before the
## first). Below tick_seq() while one is held (a loss, a late packet); never
## above it, except while starting with only inputs ahead of the counter.
func played_seq() -> int:
	return _last_seq


## The newest input number that has landed (-1 before the first).
func newest() -> int:
	return _newest


## Whether the last consume() played an input held more than STALE_TICKS past
## the newest one (nothing new had landed for that long), and none of the
## inputs landed since has been played yet.
func is_stale() -> bool:
	return _stale


## Somebody else took the controls, or nobody holds them: start over.
func clear() -> void:
	_inputs.clear()
	_newest = -1
	_tick_seq = -1
	_last = null
	_last_seq = -1
	_fresh = false
	_stale = false
	_landed_behind = 0
