class_name GameClock
extends Node
## The company day's clock (D-0219): the host sets its pace, every peer reads the same time.
##
## Adapter of the day_clock module (DayClock, docs/modulos.md). The time is an anchor
## {minute, speed, paused} plus the local tick it was taken at, never a value sent every few
## seconds (docs/decisiones/2026-10-04-reloj-por-ancla.md). Only the host changes the pace:
## start() when the day opens (or a loaded day goes on), pause() and resume() (the coop pause and
## the frozen shed of S4 call them: D-0203), set_speed(). Each change goes out once, as
## CompanyNet's clock_anchor event (reliable, numbered), and every peer, the host too, takes it
## in apply_anchor() with its own tick minus half its round trip to the host (NetStats): a tick
## of one machine means nothing on another. Nothing travels while the clock just runs. A late
## joiner gets the anchor in the snapshot (part SNAPSHOT_KEY), moved to when the host takes it.
##
## Any peer reads the time with minute_now(). A HUD that shows the pause listens to CompanyNet's
## event_applied (kind clock_anchor) and company_state_restored, like any business fact. On the
## host the clock also writes the whole minute into the company (CompanyState.clock_minutes)
## while it runs, so a save and the wallet history carry the time; a client never writes there
## (rule 1 of red-autoridad.md: its mirror only takes the host's snapshot).
##
## Without a CompanyNet (attach() not called) the clock is this peer's alone and a change of pace
## applies here at once. It names no autoload (lesson N-919).

## S3: one game hour every CompanyTuning.SECONDS_PER_GAME_HOUR real seconds, as game minutes per
## real second (2/3).
const DEFAULT_SPEED: float = 60.0 / CompanyTuning.SECONDS_PER_GAME_HOUR
## Fastest pace an anchor may carry: a test or a bench may run the day x100 (D-0203); past x1000
## it is a broken or forged anchor.
const MAX_SPEED: float = DEFAULT_SPEED * 1000.0
## Latest minute an anchor may carry: a year of game time. A day that waits past midnight for a
## trip out (S3) never gets near it (243 real days at S3's pace, 6 real hours at MAX_SPEED), so a
## clock left running can't reach a minute its own peers refuse; past it the anchor is garbage.
const MAX_MINUTE: float = 365.0 * CompanyTuning.MINUTES_PER_DAY
## Key of the anchor in CompanyNet's snapshot (add_snapshot_part()).
const SNAPSHOT_KEY: String = "clock"
## A received anchor is moved back half a round trip to the host, never more than this (an
## estimate gone wild after a stall).
const MAX_LEAD_MSEC: int = 1000

## The CompanyNet the pace travels through (attach()), or null: this peer's clock alone.
var net: CompanyNet = null
## The CompanyState node (by reference, never by autoload name) the host writes the minute into,
## or null.
var company: Object = null
## Local ticks in msec, as Callable() -> int; unset, Time.get_ticks_msec(). A test drives it to
## simulate a minute in no time.
var ticks: Callable = Callable()
## How far back (msec) the last anchor taken here was moved for its trip from the host: half the
## round trip on a client, 0 on the host.
var lead_msec: int = 0

var _clock := DayClock.new(float(CompanyTuning.DAY_START_MIN), DEFAULT_SPEED, true, 0)


## Every peer keeps the host's minute as it runs; only the host writes it into the company.
func _process(_delta: float) -> void:
	if not _clock.paused:
		_write_company()


## Hooks this clock to `company_net`, on every peer before its world is up (like any snapshot
## part): its clock_anchor events land in apply_anchor() and its snapshot carries the anchor.
## `company_state` is the CompanyState node the host writes the minute into (null: none). False,
## changing nothing, without a CompanyNet or when it already has a clock part.
func attach(company_net: CompanyNet, company_state: Object = null) -> bool:
	if company_net == null:
		return false
	if not company_net.add_snapshot_part(SNAPSHOT_KEY, _take_snapshot_part, _put_snapshot_part):
		return false
	net = company_net
	company = company_state
	company_net.clock = self
	return true


## True where the pace is decided: the host (solo too), or this peer when the clock has no
## CompanyNet.
func is_host() -> bool:
	return net.is_host() if _has_net() else true


## Host: the clock runs from `minute` (minutes since midnight) at its speed. False on a client or
## for a minute that isn't 0..MAX_MINUTE.
func start(minute: float = float(CompanyTuning.DAY_START_MIN)) -> bool:
	if not is_finite(minute) or minute < 0.0 or minute > MAX_MINUTE:
		return false
	return _set_pace(minute, _clock.speed, false)


## Host: the clock stops where it is. False, sending nothing, on a client or when it is stopped.
func pause() -> bool:
	if _clock.paused:
		return false
	return _set_pace(minute_now(), _clock.speed, true)


## Host: a stopped clock runs again from where it stopped. False, sending nothing, on a client or
## when it runs.
func resume() -> bool:
	if not _clock.paused:
		return false
	return _set_pace(minute_now(), _clock.speed, false)


## Host: from now on the clock runs `speed` game minutes per real second (DEFAULT_SPEED is S3's
## pace), stopped or not. False, sending nothing, on a client, for the speed it has or one that
## isn't 0..MAX_SPEED.
func set_speed(speed: float) -> bool:
	if not is_finite(speed) or speed < 0.0 or speed > MAX_SPEED or is_equal_approx(speed, _clock.speed):
		return false
	return _set_pace(minute_now(), speed, _clock.paused)


## The game minute now, minutes since midnight with their fraction (any peer).
func minute_now() -> float:
	return _clock.minute_at(_now())


## The game minute at local tick `now_msec` (on the scale of `ticks`, Time.get_ticks_msec() by
## default).
func minute_at(now_msec: int) -> float:
	return _clock.minute_at(now_msec)


func is_paused() -> bool:
	return _clock.paused


## Game minutes per real second.
func current_speed() -> float:
	return _clock.speed


## The anchor as it travels, moved to now: {minute, speed, paused}.
func anchor() -> Dictionary:
	return _clock.to_dict(_now())


## Every peer, the host too: the host's clock_anchor (CompanyNet._apply_state()) or its snapshot's
## anchor. Checked like any data from the network (rule 5: DayClock.anchor_ok() up to MAX_MINUTE
## and MAX_SPEED) and taken as valid at this peer's tick minus half its round trip to the host
## (lead_msec). False, changing nothing, when it doesn't fit.
func apply_anchor(data: Dictionary) -> bool:
	var lead: int = _lead_msec()
	if not _clock.from_dict(data, _now() - lead, MAX_MINUTE, MAX_SPEED):
		return false
	lead_msec = lead
	_write_company()
	return true


## Host: the new pace goes out as an anchor taken now. Through CompanyNet it comes back to
## apply_anchor() here, the code every peer runs; without one it applies here at once.
func _set_pace(minute: float, speed: float, paused: bool) -> bool:
	if not is_host():
		return false
	var next: Dictionary = {"minute": minute, "speed": speed, "paused": paused}
	if _has_net():
		return net.publish(CompanyNet.CLOCK_ANCHOR, next)
	return apply_anchor(next)


## Host: the anchor a snapshot carries, moved to the moment it is taken (the joiner takes its own
## tick when it arrives).
func _take_snapshot_part() -> Variant:
	return anchor()


## Client: the snapshot's anchor. There is no fact signal to hold back. False when it doesn't fit.
func _put_snapshot_part(value: Variant) -> bool:
	return value is Dictionary and apply_anchor(value)


## Host: the whole minute into the company, kept within one day (CompanyState's range).
func _write_company() -> void:
	if company == null or not is_instance_valid(company) or not is_host():
		return
	var whole: int = clampi(floori(minute_now()), 0, CompanyTuning.MINUTES_PER_DAY - 1)
	if int(company.get(&"clock_minutes")) != whole:
		company.set(&"clock_minutes", whole)


## Half the round trip to the host, in msec (0 on the host, offline or unknown).
func _lead_msec() -> int:
	if is_host():
		return 0
	var where: Node = net if _has_net() else self
	if not where.is_inside_tree():
		return 0
	var round_trip: float = NetStats.round_trip_seconds(where.multiplayer.multiplayer_peer, CompanyNet.HOST_ID)
	return clampi(roundi(round_trip * 500.0), 0, MAX_LEAD_MSEC)


func _now() -> int:
	return int(ticks.call()) if ticks.is_valid() else Time.get_ticks_msec()


func _has_net() -> bool:
	return net != null and is_instance_valid(net)
