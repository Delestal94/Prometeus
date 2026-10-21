class_name DayCycle
extends Node
## The company day's phases (D-0203): OPENING, OPERATING, CLOSING, SUMMARY, then the next day.
##
## Child of the company world, not an autoload; it names no autoload either (lesson N-919). The
## owner (CompanyRoot) hands it the CompanyNet, the GameClock and the CompanyState by reference
## (attach()) and two Callables for what only the world knows (crew_in_shed, trips_out).
##
## Phases are host facts (docs/expansion-distritos/diseno/red-autoridad.md, "Fases del día"). Only
## the host decides a transition, in poll() and open_day() / next_day(); each one goes out once as
## CompanyNet's day_phase event (reliable, numbered) and every peer, the host too, takes it in
## apply_phase() with the same code: it checks the data like any from the network (rule 5), sets
## the phase. EventBus' company_day_* signal is emitted locally from CompanyNet.event_applied (in
## the same order on every peer), not from inside the apply, where CompanyNet is busy
## (_applying) and takes no request or event. A signal is never relayed. A client is passive: it
## never moves the phase by itself. Without a CompanyNet (attach() not called) the phase applies
## and the signal goes out here at once, like GameClock's pace.
##
## Who listens to what: a host rule that reacts to a phase (rent at company_day_closing, D-0320)
## listens to CompanyNet.event_applied (kind DAY_PHASE), guarded by is_host(): from there it may
## publish or request, and what it writes to CompanyState must come back as an event, never run on
## every mirror. EventBus' company_day_* signals are for presentation (sounds, notices). Applying a
## snapshot (part SNAPSHOT_KEY: a late join, or a resync after a gap) fires none of them, and a
## resync can cross a phase (a client in SUMMARY gets OPENING of the next day): whatever shows the
## phase also redraws on CompanyNet.company_state_restored, from phase() and summary().
##
## The day, in order:
##   OPENING    open_day() / next_day(): the clock restarts at 08:00 and the day is company.day (set
##              on every peer as the event is applied). Lasts OPENING_REAL_SECONDS real seconds (the
##              supplier shows up); the clock already runs.
##   OPERATING  until the world clock reads DAY_END_MIN (20:00).
##   CLOSING    from 20:00 on. S3: a trip out is never cut, so SUMMARY waits until trips_out() is 0.
##              It lasts at least one poll, so what listens to company_day_closing (rent, D-0320)
##              lands in the summary.
##   SUMMARY    the closing screen: DaySummary.build() of the day goes out inside the event and the
##              world clock stops. Only the host's next_day() moves on (a client can't hurry the day).
##
## The frozen shed (S4): while nobody is in the shed (crew_in_shed() false; no employees exist in F1)
## the shed's own minute, shed_minute(), stands still. It is NOT the world clock paused: the trips
## keep going and the day keeps closing at 20:00 by the world clock, so a frozen shed costs day time
## instead of being free. shed_minute() = frozen ? frozen_at : world minute - lag; freezing records
## frozen_at, unfreezing sets lag = world minute - frozen_at. Each toggle is a host fact too
## (day_phase with the same phase and a new frozen), at most one per CompanyTuning
## SHED_FREEZE_SETTLE_REAL_SECONDS so a player on the door line can't flood the channel. Whatever
## runs on the shed's time (orders, supplier) reads shed_minute(); a peer computes it from the
## event's lag, never from its own idea of who is inside.

enum Phase { IDLE, OPENING, OPERATING, CLOSING, SUMMARY }

## Wire names of the phases, by Phase value. IDLE only lives in a snapshot (a day not opened yet).
const PHASE_NAMES: Array[String] = ["IDLE", "OPENING", "OPERATING", "CLOSING", "SUMMARY"]
## Key of the phase in CompanyNet's snapshot (add_snapshot_part()).
const SNAPSHOT_KEY: String = "day_cycle"
## Latest day number an event may carry (garbage past it).
const MAX_DAY: int = 100000
## The host looks at the world (trips, crew, the clock) this often, in real seconds.
const POLL_SECONDS: float = 0.25
## Keys of the event, and of the snapshot part, besides "summary" (only in SUMMARY).
const KEYS: Array[String] = ["day", "phase", "frozen", "lag", "frozen_at"]
## DaySummary.build()'s money fields (ints) and its two reason tables (reason -> int).
const SUMMARY_MONEY_KEYS: Array[String] = ["income", "costs", "profit", "opening", "closing"]
const SUMMARY_REASON_KEYS: Array[String] = ["income_by_reason", "cost_by_reason"]
## A summary's reason table holds at most this many reasons, each a short text. The host folds
## what doesn't fit into OTHER_REASON before it publishes (_bounded_summary()).
const MAX_SUMMARY_REASONS: int = 32
const MAX_REASON_LENGTH: int = 64
const OTHER_REASON: String = "other"
## After an event the host could not publish, poll() waits this long (msec) before trying again, so
## a stuck phase logs one error every few seconds, not four times a second.
const RETRY_MSEC: int = 5000

## The CompanyNet the phases travel through (attach()), or null: this peer's day alone.
var net: CompanyNet = null
## The world clock (by reference), or null: the day then neither starts nor stops a clock and the
## world minute reads 08:00.
var clock: GameClock = null
## The CompanyState node (by reference, never by autoload name) the summary is built from and the
## day number is written to, or null.
var company: Object = null
## Host: is anyone in the shed? Callable() -> bool. Unset: yes, always (the shed never freezes). The
## world that knows the shed's area and the players sets it.
var crew_in_shed: Callable = Callable()
## Host: trips out now, Callable() -> int (D-0319 gives it). Unset: 0.
var trips_out: Callable = Callable()
## Local ticks in msec, as Callable() -> int; unset, Time.get_ticks_msec(). A test drives it.
var ticks: Callable = Callable()
## The closing summary of the day (DaySummary.build()), {} outside SUMMARY. A closing screen that
## opens after the event (a late joiner) reads it here.
var summary: Dictionary = {}
## What a new day's opening tells this peer, as Callable() -> String ("" for nothing): the world
## sets it (CompanyRoot, Bankruptcy.opening_text, D-0510.2) and it goes out as EventBus.depot_notice
## right after company_day_started.
var opening_notice: Callable = Callable()

var _phase: Phase = Phase.IDLE
var _day: int = 0
var _frozen: bool = false
var _lag: float = 0.0
var _frozen_at: float = 0.0
## Local tick the phase began at (the OPENING timer, host) and when the shed last froze or thawed.
var _phase_msec: int = 0
var _toggle_msec: int = -1
var _since_poll: float = 0.0
## Host: no poll() tries a phase before this tick (a failed publish), and EventBus facts this
## peer applied and has not emitted yet ([fact, args]), flushed on event_applied.
var _retry_at_msec: int = 0
var _pending_facts: Array = []


## The host looks at the world a few times a second, not every frame.
func _process(delta: float) -> void:
	_since_poll += delta
	if _since_poll >= POLL_SECONDS:
		_since_poll = 0.0
		poll()


## Leaving the world, the cycle unhooks from its CompanyNet: no phase lands here any more and
## snapshots go without its part (a client keeps the phase it had). attach() hooks it back.
func _exit_tree() -> void:
	if _has_net() and net.day_cycle == self:
		net.day_cycle = null
		net.remove_snapshot_part(SNAPSHOT_KEY)
		if net.event_applied.is_connected(_on_event_applied):
			net.event_applied.disconnect(_on_event_applied)
	net = null


## Hooks this cycle to `company_net` and `game_clock` on every peer before its world is up (like
## any snapshot part): day_phase events land in apply_phase() and the snapshot carries the phase.
## `company_state` is the CompanyState node (null: none). False, changing nothing, without a
## CompanyNet or when it already has a day_cycle part.
func attach(company_net: CompanyNet, game_clock: GameClock, company_state: Object = null) -> bool:
	if company_net == null:
		return false
	if not company_net.add_snapshot_part(SNAPSHOT_KEY, _take_snapshot_part, _put_snapshot_part):
		return false
	net = company_net
	clock = game_clock
	company = company_state
	company_net.day_cycle = self
	company_net.event_applied.connect(_on_event_applied)
	return true


## True where the phase is decided: the host (solo too), or this peer when it has no CompanyNet.
func is_host() -> bool:
	return net.is_host() if _has_net() else true


## Host: opens day `day` (company.day, or 1) when none has been opened yet. False, sending nothing,
## on a client, past the first day or for a day out of 1..MAX_DAY.
func open_day(day: int = CompanyTuning.STARTING_DAY) -> bool:
	if not is_host() or _phase != Phase.IDLE:
		return false
	return _open(day)


## Host, from the closing screen's "continue": the next day opens. False, sending nothing, on a
## client or outside SUMMARY.
func next_day() -> bool:
	if not is_host() or _phase != Phase.SUMMARY:
		return false
	return _open(_day + 1)


## Host: moves the day on if it is time, once per call: OPENING to OPERATING after
## OPENING_REAL_SECONDS, OPERATING to CLOSING when the world clock reads 20:00, CLOSING to
## SUMMARY when no trip is out; otherwise it freezes or thaws the shed (S4). _process() calls it a
## few times a second; a test calls it after moving the clock.
func poll() -> void:
	if not is_host() or _now() < _retry_at_msec:
		return
	match _phase:
		Phase.OPENING:
			if _now() - _phase_msec >= roundi(CompanyTuning.OPENING_REAL_SECONDS * 1000.0):
				_transition(Phase.OPERATING)
				return
		Phase.OPERATING:
			if _world_minute() >= float(CompanyTuning.DAY_END_MIN):
				_transition(Phase.CLOSING)
				return
		Phase.CLOSING:
			if _trips() == 0:
				_transition(Phase.SUMMARY)
				return
		_:
			return
	_poll_shed()


## Every peer, the host too: the host's day_phase (CompanyNet._apply_state()). Checked like any
## data from the network (rule 5: exactly the event's keys, the day and the minutes in range, the
## phase one of the four, a summary only in SUMMARY and shaped like DaySummary's), then the phase
## is set and, for a new phase, the day's EventBus signal is queued. A new day also sets
## company.day (every peer's copy changes through the event, never by itself). False, changing
## nothing, when the data doesn't fit. The signal waits for event_applied (_on_event_applied()).
func apply_phase(data: Dictionary) -> bool:
	var parsed: Dictionary = _checked(data, false)
	if parsed.is_empty():
		return false
	var phase: Phase = parsed["phase"]
	var day: int = parsed["day"]
	var is_new: bool = _set_state(parsed)
	if phase == Phase.OPENING and company != null and is_instance_valid(company):
		if int(company.get(&"day")) != day:
			company.set(&"day", day)
	if is_new:
		match phase:
			Phase.OPENING:
				_pending_facts.append([&"company_day_started", [day]])
				var notice: String = str(opening_notice.call()) if opening_notice.is_valid() else ""
				if not notice.is_empty():
					_pending_facts.append([&"depot_notice", [notice]])
			Phase.CLOSING:
				_pending_facts.append([&"company_day_closing", [day]])
			Phase.SUMMARY:
				_pending_facts.append([&"company_day_summary", [day, summary.duplicate(true)]])
	if not _has_net():
		_flush_facts()
	return true


func phase() -> Phase:
	return _phase


func phase_name() -> String:
	return PHASE_NAMES[_phase]


## The day being played (0 before the first is opened).
func current_day() -> int:
	return _day


func is_frozen() -> bool:
	return _frozen


## The shed's own minute (minutes since midnight, with their fraction): the world clock's, held
## back by the time the shed spent frozen, and still while it is frozen (S4).
func shed_minute() -> float:
	return _frozen_at if _frozen else maxf(_world_minute() - _lag, 0.0)


## Host: the clock restarts at 08:00 and day `day` starts as OPENING, with the shed thawed.
func _open(day: int) -> bool:
	if day < 1 or day > MAX_DAY:
		return false
	# The event first: if the state doesn't take it, the clock is not started for a day that
	# never opened. The clock_anchor follows it (seq order), so a listener of company_day_started
	# still reads the old time; the clock runs from 08:00 before the next frame.
	if not _publish(_event(day, Phase.OPENING, false, 0.0, 0.0)):
		return false
	if clock != null and is_instance_valid(clock):
		clock.start(float(CompanyTuning.DAY_START_MIN))
	return true


## Host: the next phase of this day, with the shed as it is. SUMMARY carries the day's summary and
## stops the clock after the event, so every peer has the summary before the time stops.
func _transition(next: Phase) -> bool:
	var data: Dictionary = _event(_day, next, _frozen, _lag, _frozen_at)
	if next == Phase.SUMMARY:
		data["summary"] = _bounded_summary(DaySummary.build(company, _day))
	if not _publish(data):
		return false
	if next == Phase.SUMMARY and clock != null and is_instance_valid(clock):
		clock.pause()
	return true


## Host (S4): the shed freezes when the crew leaves it and thaws when someone is back, one toggle
## per SHED_FREEZE_SETTLE_REAL_SECONDS.
func _poll_shed() -> void:
	var inside: bool = _crew_inside()
	var wants_frozen: bool = not inside
	if wants_frozen == _frozen:
		return
	var settle: int = roundi(CompanyTuning.SHED_FREEZE_SETTLE_REAL_SECONDS * 1000.0)
	if _toggle_msec >= 0 and _now() - _toggle_msec < settle:
		return
	if inside:
		_publish(_event(_day, _phase, false, maxf(_world_minute() - _frozen_at, 0.0), 0.0))
	else:
		_publish(_event(_day, _phase, true, _lag, shed_minute()))


## The event as it travels. `lag` and `frozen_at` are minutes: see the class comment.
func _event(day: int, phase_value: Phase, frozen: bool, lag: float, frozen_at: float) -> Dictionary:
	return {
		"day": day,
		"phase": PHASE_NAMES[phase_value],
		"frozen": frozen,
		"lag": lag,
		"frozen_at": frozen_at,
	}


## Host: the event goes through CompanyNet, which applies it here too (apply_phase()), or without
## one applies here at once.
func _publish(data: Dictionary) -> bool:
	var done: bool = net.publish(CompanyNet.DAY_PHASE, data) if _has_net() else apply_phase(data)
	if not done:
		_retry_at_msec = _now() + RETRY_MSEC
	return done


## Host: `built` (DaySummary.build()) as the event may carry it. Its reason tables are unbounded, so
## names are cut to MAX_REASON_LENGTH and a table over MAX_SUMMARY_REASONS keeps the biggest amounts
## (MAX_SUMMARY_REASONS - 1) and folds the rest into OTHER_REASON; then `truncated` is true.
static func _bounded_summary(built: Dictionary) -> Dictionary:
	var result: Dictionary = built.duplicate(true)
	for key: String in SUMMARY_REASON_KEYS:
		var table: Dictionary = result.get(key, {})
		var cut: Dictionary = {}
		for reason: Variant in table:
			var short: String = String(reason).left(MAX_REASON_LENGTH)
			cut[short] = int(cut.get(short, 0)) + int(table[reason])
		var changed: bool = cut.size() != table.size()
		for reason: Variant in table:
			changed = changed or String(reason).length() > MAX_REASON_LENGTH
		if cut.size() > MAX_SUMMARY_REASONS:
			changed = true
			var names: Array = cut.keys()
			names.sort_custom(func(a: String, b: String) -> bool:
				return a < b if cut[a] == cut[b] else cut[a] > cut[b])
			var kept: Dictionary = {}
			var rest: int = 0
			for index: int in range(names.size()):
				if index < MAX_SUMMARY_REASONS - 1:
					kept[names[index]] = cut[names[index]]
				else:
					rest += int(cut[names[index]])
			kept[OTHER_REASON] = int(kept.get(OTHER_REASON, 0)) + rest
			cut = kept
		result[key] = cut
		if changed:
			result["truncated"] = true
	return result


## Every peer: the facts the last events queued go out on EventBus now that CompanyNet is not
## applying (event_applied), so a host rule listening to them may publish or request.
func _on_event_applied(_seq: int, kind: StringName, _data: Dictionary) -> void:
	if kind == CompanyNet.DAY_PHASE:
		_flush_facts()


func _flush_facts() -> void:
	var facts: Array = _pending_facts
	_pending_facts = []
	for fact: Array in facts:
		_emit_fact(fact[0], fact[1])


## The checked state in place. True when it is a new phase or day (a toggle of the shed alone is
## not).
func _set_state(parsed: Dictionary) -> bool:
	var phase: Phase = parsed["phase"]
	var is_new: bool = phase != _phase or int(parsed["day"]) != _day
	if bool(parsed["frozen"]) != _frozen:
		_toggle_msec = _now()
	if is_new:
		_phase_msec = _now()
	_phase = phase
	_day = parsed["day"]
	_frozen = parsed["frozen"]
	_lag = parsed["lag"]
	_frozen_at = parsed["frozen_at"]
	summary = parsed["summary"] if phase == Phase.SUMMARY else {}
	return is_new


## Host: the phase a snapshot carries, in the event's shape (IDLE included, SUMMARY with its summary).
func _take_snapshot_part() -> Variant:
	var data: Dictionary = _event(_day, _phase, _frozen, _lag, _frozen_at)
	if _phase == Phase.SUMMARY:
		data["summary"] = summary.duplicate(true)
	return data


## Client: the snapshot's phase, taken without a signal (the closing screen redraws from
## company_state_restored and summary). False when it doesn't fit.
func _put_snapshot_part(value: Variant) -> bool:
	var parsed: Dictionary = _checked(value, true)
	if parsed.is_empty():
		return false
	_set_state(parsed)
	return true


## `data` as typed values {day, phase (Phase), frozen, lag, frozen_at[, summary]}, or {} when it is
## not exactly what the host writes. A snapshot may be IDLE (day 0); an event never is.
func _checked(data: Variant, from_snapshot: bool) -> Dictionary:
	if not data is Dictionary:
		return {}
	var raw: Dictionary = data
	var phase: int = _phase_of(raw.get("phase"), from_snapshot)
	if phase < 0 or not _fields_ok(raw, phase):
		return {}
	var parsed: Dictionary = {
		"day": int(raw["day"]),
		"phase": phase as Phase,
		"frozen": bool(raw["frozen"]),
		"lag": float(raw["lag"]),
		"frozen_at": float(raw["frozen_at"]),
	}
	if phase == Phase.SUMMARY:
		parsed["summary"] = (raw["summary"] as Dictionary).duplicate(true)
	return parsed


## The Phase a wire name stands for, or -1 for anything else (and for IDLE unless `allow_idle`).
static func _phase_of(kind: Variant, allow_idle: bool) -> int:
	if typeof(kind) != TYPE_STRING and typeof(kind) != TYPE_STRING_NAME:
		return -1
	var index: int = PHASE_NAMES.find(String(kind))
	return -1 if index == Phase.IDLE and not allow_idle else index


## `raw` has exactly the keys of its phase (KEYS, plus the summary in SUMMARY) with values in range.
static func _fields_ok(raw: Dictionary, phase: int) -> bool:
	for key: String in KEYS:
		if not raw.has(key):
			return false
	if raw.size() != KEYS.size() + (1 if phase == Phase.SUMMARY else 0):
		return false
	var day: Variant = raw["day"]
	if (
		typeof(day) != TYPE_INT
		or int(day) < (0 if phase == Phase.IDLE else 1)
		or int(day) > MAX_DAY
	):
		return false
	if (
		typeof(raw["frozen"]) != TYPE_BOOL
		or not _minute_ok(raw["lag"])
		or not _minute_ok(raw["frozen_at"])
	):
		return false
	return phase != Phase.SUMMARY or _summary_ok(raw["summary"], int(day))


## A minute of the shed's reckoning: a finite number from 0 up to the clock's own limit.
static func _minute_ok(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var minute: float = float(value)
	return is_finite(minute) and minute >= 0.0 and minute <= GameClock.MAX_MINUTE


## DaySummary.build()'s dictionary and nothing more: the day it closes, ints for the money, the
## two reason tables {short text: int} up to MAX_SUMMARY_REASONS and `truncated` a bool.
static func _summary_ok(value: Variant, day: int) -> bool:
	if not value is Dictionary:
		return false
	var shown: Dictionary = value
	var keys: int = 2 + SUMMARY_MONEY_KEYS.size() + SUMMARY_REASON_KEYS.size()
	if (
		shown.size() != keys
		or shown.get("day") != day
		or typeof(shown.get("truncated")) != TYPE_BOOL
	):
		return false
	for key: String in SUMMARY_MONEY_KEYS:
		if typeof(shown.get(key)) != TYPE_INT:
			return false
	for key: String in SUMMARY_REASON_KEYS:
		var table: Variant = shown.get(key)
		if not table is Dictionary or (table as Dictionary).size() > MAX_SUMMARY_REASONS:
			return false
		for reason: Variant in table:
			var is_text: bool = typeof(reason) == TYPE_STRING or typeof(reason) == TYPE_STRING_NAME
			if not is_text or String(reason).length() > MAX_REASON_LENGTH:
				return false
			if typeof(table[reason]) != TYPE_INT:
				return false
	return true


## The world clock's minute (08:00 without a clock).
func _world_minute() -> float:
	if clock == null or not is_instance_valid(clock):
		return float(CompanyTuning.DAY_START_MIN)
	return clock.minute_now()


func _trips() -> int:
	return maxi(int(trips_out.call()), 0) if trips_out.is_valid() else 0


func _crew_inside() -> bool:
	return bool(crew_in_shed.call()) if crew_in_shed.is_valid() else true


## Business facts go out on this peer's EventBus, reached by path so the script still loads where
## the autoload is missing (like CompanyState._emit_fact()).
func _emit_fact(fact: StringName, args: Array) -> void:
	if not is_inside_tree():
		return
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null and bus.has_signal(fact):
		bus.callv(&"emit_signal", [fact] + args)


func _now() -> int:
	return int(ticks.call()) if ticks.is_valid() else Time.get_ticks_msec()


func _has_net() -> bool:
	return net != null and is_instance_valid(net)
