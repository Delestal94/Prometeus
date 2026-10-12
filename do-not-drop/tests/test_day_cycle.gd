extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_day_cycle.gd
##
## The company day's phases from the host (D-0203, scripts/core/company/day_cycle.gd; contract
## docs/expansion-distritos/diseno/red-autoridad.md, row "Fases del día"), with simulated time: the
## GameClock runs x100 and every node reads one tick the test moves, so a day takes no time.
## - Solo, one day goes OPENING, OPERATING, CLOSING, SUMMARY in order, one day_phase event each
##   (poll() moves one phase per call), with EventBus' company_day_started / closing / summary
##   emitted once each with the day; OPENING lasts OPENING_REAL_SECONDS of real time, OPERATING
##   until the clock reads 20:00; the summary is DaySummary.build() of the day (the money earned in
##   it) and stops the clock; next_day() opens day 2 (company.day too, the clock back at 08:00),
##   and opening twice or moving the day on outside SUMMARY is refused.
## - A trip out at 20:00 keeps the day in CLOSING (the clock keeps running) until trips_out() is 0,
##   and only then comes the summary.
## - A shed with nobody in it (S4) freezes: shed_minute() stands still while the world clock runs,
##   thaws from where it froze (world minute - shed minute = the time it was frozen), toggles at
##   most once per SHED_FREEZE_SETTLE_REAL_SECONDS, sends no EventBus signal, and does not hold
##   the day back: 20:00 still closes it. A new day thaws the shed.
## - A host and a client as two ENet peers in one process (each with its CompanyNet, GameClock,
##   DayCycle and CompanyState on its own SceneMultiplayer): the client joining mid-day gets the
##   phase in the snapshot without a signal; each phase reaches it as one event; the day number
##   reaches its company; a client can't open or move the day on; a snapshot at SUMMARY brings the
##   summary. (EventBus is one per process here, so a signal from each peer counts twice.)
## - Malformed day_phase data (event or snapshot part) is refused and changes nothing.
## Expected in the log: CompanyNet's warning for the day_phase applied with no day cycle.

const PORT: int = 24645
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Where the simulated tick starts (any value: a tick is local to its machine).
const START_TICK: int = 7_000_000
const SPEED: float = GameClock.DEFAULT_SPEED * 100.0
const PHASES: Array[String] = ["OPENING", "OPERATING", "CLOSING", "SUMMARY"]

var _failures: int = 0
## The simulated tick (msec) every node in this test reads.
var _now: int = START_TICK
## EventBus signals heard: [day] for started and closing, [day, summary] for summary.
var _started: Array = []
var _closing: Array = []
var _summaries: Array = []
var _trips: int = 0
var _inside: bool = true
var _host_net: CompanyNet
var _client_net: CompanyNet
var _host_clock: GameClock
var _host_cycle: DayCycle
var _client_cycle: DayCycle
var _host_state: Node
var _client_state: Node
var _restored: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	var bus: Node = root.get_node_or_null(^"EventBus")
	if bus == null:
		push_error("EventBus autoload missing")
		quit(1)
		return
	bus.connect(&"company_day_started", func(day: int) -> void: _started.append(day))
	bus.connect(&"company_day_closing", func(day: int) -> void: _closing.append(day))
	bus.connect(&"company_day_summary", func(day: int, summary: Dictionary) -> void:
		_summaries.append([day, summary]))
	await _check_solo()
	await _check_two_peers()
	if _failures == 0:
		print("PASS: the day goes OPENING, OPERATING, CLOSING, SUMMARY from the host, a trip out holds the"
			+ " summary, the empty shed's minute stands still and a client follows by event and snapshot")
	quit(_failures)


## One solo side (a CompanyNet in a host's role): returns its state, net, clock and cycle.
func _new_side(name_: String, state: Node) -> Dictionary:
	var side := Node.new()
	side.name = name_
	root.add_child(side)
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = state
	side.add_child(net)
	var clock := GameClock.new()
	clock.name = "GameClock"
	clock.ticks = func() -> int: return _now
	side.add_child(clock)
	var cycle := DayCycle.new()
	cycle.name = "DayCycle"
	cycle.ticks = func() -> int: return _now
	side.add_child(cycle)
	_expect(clock.attach(net, state) and cycle.attach(net, clock, state),
		"A clock and a day cycle attach to their peer's CompanyNet")
	return {"side": side, "net": net, "clock": clock, "cycle": cycle}


func _new_state(company_name: String) -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	state.call(&"new_company", company_name)
	return state


## Moves every tick `seconds` on and polls the host once.
func _advance(cycle: DayCycle, seconds: float) -> void:
	_now += roundi(seconds * 1000.0)
	cycle.poll()


func _check_solo() -> void:
	var state: Node = _new_state("Dias SRL")
	var parts: Dictionary = _new_side("SoloSide", state)
	parts["side"].add_child(state)
	var net: CompanyNet = parts["net"]
	var clock: GameClock = parts["clock"]
	var cycle: DayCycle = parts["cycle"]
	cycle.trips_out = func() -> int: return _trips
	cycle.crew_in_shed = func() -> bool: return _inside
	var phases: Array[String] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == CompanyNet.DAY_PHASE and (phases.is_empty() or phases[-1] != data["phase"]):
			phases.append(String(data["phase"])))
	await process_frame
	_expect(cycle.phase() == DayCycle.Phase.IDLE and cycle.current_day() == 0 and _started.is_empty(),
		"Before the first day opens the cycle is idle (phase %s)" % cycle.phase_name())
	_expect(not cycle.open_day(0) and not cycle.open_day(DayCycle.MAX_DAY + 1) and net.seq == 0,
		"A day out of 1..MAX_DAY doesn't open and nothing is sent (seq %d)" % net.seq)
	_expect(not cycle.next_day(), "next_day() does nothing before a day is over")
	_expect(clock.set_speed(SPEED), "The test runs the clock x100")
	var seq_before: int = net.seq
	state.call(&"earn", 50, &"order_paid")
	_expect(cycle.open_day(1) and cycle.phase() == DayCycle.Phase.OPENING and cycle.current_day() == 1,
		"open_day(1) is OPENING of day 1 (got %s %d)" % [cycle.phase_name(), cycle.current_day()])
	_expect(net.seq == seq_before + 2, "...as two events: the clock's anchor and the phase (seq %d)" % net.seq)
	_expect(_started == [1], "...with company_day_started(1) once (got %s)" % [_started])
	_expect(not clock.is_paused() and is_equal_approx(clock.minute_now(), 480.0),
		"...and the clock runs from 08:00 (got %.1f)" % clock.minute_now())
	_expect(not cycle.open_day(1), "A day already opened can't be opened again")
	cycle.poll()
	_advance(cycle, 4.0)
	_expect(cycle.phase() == DayCycle.Phase.OPENING and clock.minute_now() > 700.0,
		"OPENING lasts real seconds, not game time: after 4 s (%.0f min) it still is (got %s)"
		% [clock.minute_now(), cycle.phase_name()])
	_advance(cycle, 1.0)
	_expect(cycle.phase() == DayCycle.Phase.OPERATING and _closing.is_empty(),
		"After %.0f s it is OPERATING (got %s)" % [CompanyTuning.OPENING_REAL_SECONDS, cycle.phase_name()])
	_advance(cycle, 4.0)
	_expect(cycle.phase() == DayCycle.Phase.OPERATING and clock.minute_now() < 1200.0,
		"It stays OPERATING before 20:00 (%.0f min)" % clock.minute_now())
	_advance(cycle, 3.0)
	_expect(clock.minute_now() >= 1200.0 and cycle.phase() == DayCycle.Phase.CLOSING,
		"At 20:00 (%.0f min) it is CLOSING (got %s)" % [clock.minute_now(), cycle.phase_name()])
	_expect(_closing == [1] and _summaries.is_empty(),
		"...with company_day_closing(1) once and no summary yet (closing %s, summaries %d)"
		% [_closing, _summaries.size()])
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY and _closing == [1] and _summaries.size() == 1,
		"With no trip out the next poll is SUMMARY (got %s)" % cycle.phase_name())
	var shown: Dictionary = {}
	if _summaries.size() == 1:
		shown = _summaries[0][1]
		_expect(_summaries[0][0] == 1 and shown["day"] == 1 and shown["income"] == 50
			and shown["income_by_reason"] == {"order_paid": 50},
			"...with the day's summary: 50 earned from orders (got %s)" % [_summaries[0]])
	_expect(cycle.summary == shown and phases == PHASES,
		"The four states went by in order, one event each (got %s)" % [phases])
	_expect(clock.is_paused(), "The summary stops the clock")
	var stopped_at: float = clock.minute_now()
	_advance(cycle, 30.0)
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY and is_equal_approx(clock.minute_now(), stopped_at)
		and _summaries.size() == 1, "SUMMARY waits for the host's next_day() however long it takes")
	_expect(cycle.next_day() and cycle.current_day() == 2 and cycle.phase() == DayCycle.Phase.OPENING,
		"next_day() opens day 2 (got %s %d)" % [cycle.phase_name(), cycle.current_day()])
	_expect(int(state.get(&"day")) == 2 and _started == [1, 2] and cycle.summary.is_empty(),
		"...company.day is 2, company_day_started(2) came and the old summary is gone (started %s)" % [_started])
	_expect(not clock.is_paused() and is_equal_approx(clock.minute_now(), 480.0),
		"...and the clock is back at 08:00 (got %.1f)" % clock.minute_now())
	_expect(not cycle.next_day(), "next_day() outside SUMMARY does nothing")
	_check_trip(cycle, clock, net)
	_check_frozen_shed(cycle, clock, net)
	_check_bad_data(net)
	parts["side"].free()


## Day 2 is over at 20:00 with a trip out: CLOSING until it comes back.
func _check_trip(cycle: DayCycle, clock: GameClock, net: CompanyNet) -> void:
	_trips = 1
	_advance(cycle, 5.0)
	_advance(cycle, 11.0)
	_expect(cycle.phase() == DayCycle.Phase.CLOSING and _closing == [1, 2],
		"With a trip out at 20:00 (%.0f min) the day is CLOSING (got %s)" % [clock.minute_now(), cycle.phase_name()])
	var summaries: int = _summaries.size()
	var at: float = clock.minute_now()
	for i: int in range(5):
		_advance(cycle, 2.0)
	_expect(cycle.phase() == DayCycle.Phase.CLOSING and _summaries.size() == summaries
		and clock.minute_now() > at + 100.0 and not clock.is_paused(),
		"...and it stays there while the trip is out, the clock running (%.0f min, %s)"
		% [clock.minute_now(), cycle.phase_name()])
	var seq: int = net.seq
	_advance(cycle, 1.0)
	_expect(net.seq == seq, "...sending nothing while it waits (seq %d)" % net.seq)
	_trips = 0
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY and _summaries.size() == summaries + 1
		and _summaries[-1][0] == 2,
		"The trip comes back and the summary of day 2 follows (got %s)" % cycle.phase_name())
	_expect(cycle.next_day() and cycle.current_day() == 3, "Day 3 opens")


## Day 3: the shed freezes when nobody is in it (S4) and thaws from where it froze.
func _check_frozen_shed(cycle: DayCycle, clock: GameClock, net: CompanyNet) -> void:
	_advance(cycle, 5.0)
	_expect(cycle.phase() == DayCycle.Phase.OPERATING and not cycle.is_frozen(),
		"Day 3 is OPERATING with its crew inside (frozen %s)" % cycle.is_frozen())
	_expect(is_equal_approx(cycle.shed_minute(), clock.minute_now()),
		"...and the shed reads the world's minute (shed %.1f, world %.1f)" % [cycle.shed_minute(), clock.minute_now()])
	var signals: int = _started.size() + _closing.size() + _summaries.size()
	var seq: int = net.seq
	_inside = false
	cycle.poll()
	_expect(cycle.is_frozen() and net.seq == seq + 1,
		"With nobody inside the shed freezes, as one event (seq %d)" % net.seq)
	var frozen_at: float = cycle.shed_minute()
	_expect(is_equal_approx(frozen_at, clock.minute_now()), "...at the minute it was (%.1f)" % frozen_at)
	_inside = true
	cycle.poll()
	_expect(cycle.is_frozen() and net.seq == seq + 1,
		"Someone steps back in at once: it stays frozen (settle time), nothing is sent")
	_inside = false
	_advance(cycle, 2.0)
	_expect(clock.minute_now() > frozen_at + 100.0 and is_equal_approx(cycle.shed_minute(), frozen_at),
		"2 s later the world is at %.0f but the shed still reads %.1f" % [clock.minute_now(), cycle.shed_minute()])
	_expect(cycle.phase() == DayCycle.Phase.OPERATING and net.seq == seq + 1,
		"...and it sent nothing more (seq %d)" % net.seq)
	_inside = true
	_advance(cycle, 0.0)
	_expect(not cycle.is_frozen() and net.seq == seq + 2 and is_equal_approx(cycle.shed_minute(), frozen_at),
		"The crew is back: the shed thaws from %.1f (got %.1f)" % [frozen_at, cycle.shed_minute()])
	var lag: float = clock.minute_now() - cycle.shed_minute()
	_advance(cycle, 1.0)
	_expect(is_equal_approx(cycle.shed_minute(), frozen_at + SPEED)
		and is_equal_approx(clock.minute_now() - cycle.shed_minute(), lag),
		"...and runs on, behind the world by the time it was frozen (%.1f min)" % lag)
	_expect(_started.size() + _closing.size() + _summaries.size() == signals,
		"Freezing and thawing emit no EventBus signal")
	# Frozen again, the day still closes at 20:00 by the world clock.
	_inside = false
	_advance(cycle, 1.5)
	_expect(cycle.is_frozen(), "Nobody inside again: frozen")
	_advance(cycle, 5.0)
	_expect(cycle.phase() == DayCycle.Phase.CLOSING and cycle.is_frozen() and cycle.shed_minute() < 1200.0,
		"A frozen shed doesn't hold the day back: 20:00 closes it (shed %.0f, got %s)"
		% [cycle.shed_minute(), cycle.phase_name()])
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY, "...and the summary comes")
	_expect(cycle.next_day() and not cycle.is_frozen() and is_equal_approx(cycle.shed_minute(), clock.minute_now()),
		"A new day thaws the shed (frozen %s, shed %.1f, world %.1f)"
		% [cycle.is_frozen(), cycle.shed_minute(), clock.minute_now()])
	_inside = true


## Data that doesn't fit changes nothing, as an event or as a snapshot part.
func _check_bad_data(net: CompanyNet) -> void:
	var cycle := DayCycle.new()
	var good: Dictionary = {"day": 4, "phase": "OPERATING", "frozen": false, "lag": 0.0, "frozen_at": 0.0}
	var summary: Dictionary = DaySummary.build(null, 4)
	var with_summary: Dictionary = good.duplicate()
	with_summary["phase"] = "SUMMARY"
	with_summary["summary"] = summary
	var too_many: Dictionary = summary.duplicate(true)
	for i: int in range(DayCycle.MAX_SUMMARY_REASONS + 1):
		too_many["cost_by_reason"]["r%d" % i] = 1
	var long_reason: Dictionary = summary.duplicate(true)
	long_reason["income_by_reason"]["x".repeat(DayCycle.MAX_REASON_LENGTH + 1)] = 1
	var float_money: Dictionary = summary.duplicate(true)
	float_money["income"] = 1.5
	var extra_key: Dictionary = summary.duplicate(true)
	extra_key["tick"] = 3
	var other_day: Dictionary = summary.duplicate(true)
	other_day["day"] = 5
	var cases: Array = [
		[_with(good, "phase", "LUNCH"), "an unknown phase"],
		[_with(good, "phase", 2), "a phase that is a number"],
		[_with(good, "day", 0), "day 0"],
		[_with(good, "day", DayCycle.MAX_DAY + 1), "a day past MAX_DAY"],
		[_with(good, "day", "4"), "a day that is text"],
		[_with(good, "day", 4.0), "a day that is a float"],
		[_with(good, "frozen", "no"), "a frozen that is text"],
		[_with(good, "lag", NAN), "a NaN lag"],
		[_with(good, "lag", -1.0), "a negative lag"],
		[_with(good, "frozen_at", GameClock.MAX_MINUTE + 1.0), "a frozen_at past MAX_MINUTE"],
		[_with(good, "tick", 3), "an extra key"],
		[_without(good, "lag"), "a missing key"],
		[_with(good, "summary", summary), "a summary outside SUMMARY"],
		[_without(with_summary, "summary"), "SUMMARY without its summary"],
		[_with(with_summary, "summary", 7), "a summary that isn't a Dictionary"],
		[_with(with_summary, "summary", other_day), "a summary of another day"],
		[_with(with_summary, "summary", extra_key), "a summary with an extra key"],
		[_with(with_summary, "summary", float_money), "a summary with a float income"],
		[_with(with_summary, "summary", too_many), "a summary with too many reasons"],
		[_with(with_summary, "summary", long_reason), "a summary with a long reason"],
	]
	_expect(cycle.apply_phase(good) and cycle.current_day() == 4,
		"The test's well-formed event applies (day %d)" % cycle.current_day())
	var kept: Dictionary = cycle._take_snapshot_part()
	_expect(not cycle.apply_phase(_with(good, "phase", "IDLE")), "A day_phase event with IDLE is refused")
	for case: Array in cases:
		_expect(not cycle.apply_phase(case[0]), "A day_phase event with %s is refused" % case[1])
		_expect(not cycle._put_snapshot_part(case[0]), "...also as a snapshot part")
	_expect(cycle._take_snapshot_part() == kept and cycle.phase() == DayCycle.Phase.OPERATING,
		"...and none of them changed the cycle")
	_expect(not cycle._put_snapshot_part(7) and not cycle._put_snapshot_part({}),
		"A snapshot part that isn't a phase is refused")
	_expect(cycle._put_snapshot_part(_with(good, "phase", "IDLE")) and cycle.phase() == DayCycle.Phase.IDLE,
		"A snapshot may carry a day not opened yet (IDLE), an event may not")
	_expect(cycle.apply_phase(with_summary) and cycle.summary == summary,
		"A well-formed SUMMARY event applies and keeps its summary")
	_expect(not net._apply_state(&"made_up", good), "An unknown event kind is refused")
	var bare := CompanyNet.new()
	_expect(not bare._apply_state(CompanyNet.DAY_PHASE, good),
		"A CompanyNet without a day cycle refuses a day_phase")
	bare.free()
	cycle.free()


func _with(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	copy[key] = value
	return copy


func _without(source: Dictionary, key: String) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	copy.erase(key)
	return copy


func _check_two_peers() -> void:
	_started.clear()
	_closing.clear()
	_summaries.clear()
	_trips = 0
	_inside = true
	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 2) == OK, "The test hosts an ENet session on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server
	_host_state = _new_state("Host SRL")
	var host: Dictionary = _build_peer(host_side, _host_state)
	_host_net = host["net"]
	_host_clock = host["clock"]
	_host_cycle = host["cycle"]
	_host_cycle.trips_out = func() -> int: return _trips
	await process_frame
	_expect(_host_clock.set_speed(SPEED) and _host_cycle.open_day(1),
		"The host opens day 1 and the clock runs x100")
	_advance(_host_cycle, 5.0)
	_expect(_host_cycle.phase() == DayCycle.Phase.OPERATING and _started == [1],
		"The host is OPERATING after 5 s (got %s, started %s)" % [_host_cycle.phase_name(), _started])

	var client_peer := ENetMultiplayerPeer.new()
	_expect(client_peer.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	client_side.multiplayer.multiplayer_peer = client_peer
	_client_state = _new_state("Client SRL")
	_client_state.set(&"day", 9)
	var client: Dictionary = _build_peer(client_side, _client_state)
	_client_net = client["net"]
	_client_cycle = client["cycle"]
	_client_net.wait_for_snapshot()
	_client_net.company_state_restored.connect(func(seq: int) -> void: _restored.append(seq))
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		await _check_peers_follow(client_side)
	client_peer.close()
	server.close()
	await process_frame
	set_multiplayer(null, host_side.get_path())
	set_multiplayer(null, client_side.get_path())
	host_side.free()
	client_side.free()
	_host_state.free()
	_client_state.free()
	RpcGuard.reset()


func _build_peer(side: Node, state: Node) -> Dictionary:
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = state
	side.add_child(net)
	var clock := GameClock.new()
	clock.name = "GameClock"
	clock.ticks = func() -> int: return _now
	side.add_child(clock)
	var cycle := DayCycle.new()
	cycle.name = "DayCycle"
	cycle.ticks = func() -> int: return _now
	side.add_child(cycle)
	_expect(clock.attach(net, state) and cycle.attach(net, clock, state),
		"This peer's clock and day cycle attach to its CompanyNet")
	return {"net": net, "clock": clock, "cycle": cycle}


func _check_peers_follow(client_side: Node) -> void:
	_expect(_host_net.snapshot().has(DayCycle.SNAPSHOT_KEY),
		"The host's snapshot carries the day cycle's part")
	_expect(_host_net.send_snapshot(client_side.multiplayer.get_unique_id()),
		"The host sends the joiner its snapshot")
	var joined: bool = await _wait_for(func() -> bool:
		return _restored.size() == 1 and not _client_net.awaiting_snapshot())
	_expect(joined, "The client restores the host's snapshot (restored %s)" % [_restored])
	_expect(_client_cycle.phase() == DayCycle.Phase.OPERATING and _client_cycle.current_day() == 1,
		"The joiner is in the host's phase (got %s, day %d)"
		% [_client_cycle.phase_name(), _client_cycle.current_day()])
	_expect(_started == [1], "...and applying the snapshot fired no signal (started %s)" % [_started])
	_expect(int(_client_state.get(&"day")) == 1,
		"...its company has the host's day (got %s)" % _client_state.get(&"day"))
	_expect(not _client_cycle.open_day(1) and not _client_cycle.next_day(),
		"A client can't open the day or move it on")
	_client_cycle.poll()
	_now += 1_000
	_client_cycle.poll()
	_expect(_client_cycle.phase() == _host_cycle.phase() and _host_net.seq == _client_net.seq,
		"...and polling on a client changes and sends nothing (seq %d)" % _host_net.seq)

	_advance(_host_cycle, 10.0)
	await _wait_seq()
	_expect(_host_cycle.phase() == DayCycle.Phase.CLOSING and _client_cycle.phase() == DayCycle.Phase.CLOSING,
		"The host's CLOSING reaches the client (host %s, client %s)"
		% [_host_cycle.phase_name(), _client_cycle.phase_name()])
	_expect(_closing == [1, 1], "...and each peer emitted company_day_closing(1) once (got %s)" % [_closing])
	_trips = 1
	_advance(_host_cycle, 1.0)
	_expect(_host_cycle.phase() == DayCycle.Phase.CLOSING and _summaries.is_empty(),
		"A trip out holds the summary on the host")
	_trips = 0
	_host_cycle.poll()
	await _wait_seq()
	_expect(_client_cycle.phase() == DayCycle.Phase.SUMMARY and _summaries.size() == 2
		and _summaries[0][1] == _summaries[1][1],
		"The SUMMARY reaches the client with the same summary (summaries %d)" % _summaries.size())
	_expect(_client_cycle.summary == _host_cycle.summary and not _client_cycle.summary.is_empty(),
		"...and the closing screen can read it from the cycle")

	var client_id: int = client_side.multiplayer.get_unique_id()
	_client_cycle._put_snapshot_part({"day": 1, "phase": "OPERATING", "frozen": false, "lag": 0.0, "frozen_at": 0.0})
	_expect(_host_net.send_snapshot(client_id), "The host sends the snapshot again")
	var again: bool = await _wait_for(func() -> bool:
		return _restored.size() == 2 and not _client_net.awaiting_snapshot())
	_expect(again and _client_cycle.phase() == DayCycle.Phase.SUMMARY
		and _client_cycle.summary == _host_cycle.summary and _summaries.size() == 2,
		"A snapshot at SUMMARY brings the phase and the summary, with no signal (summaries %d)" % _summaries.size())

	_expect(_host_cycle.next_day(), "The host moves on to day 2")
	await _wait_seq()
	_expect(_client_cycle.phase() == DayCycle.Phase.OPENING and _client_cycle.current_day() == 2
		and int(_client_state.get(&"day")) == 2 and _started == [1, 2, 2],
		"The client follows to OPENING of day 2, its company too (got %s %d, started %s)"
		% [_client_cycle.phase_name(), _client_cycle.current_day(), _started])
	_expect(absf(_client_cycle.shed_minute() - _host_cycle.shed_minute()) <= 1.0,
		"Both shed clocks read the same within 1 minute (host %.1f, client %.1f)"
		% [_host_cycle.shed_minute(), _client_cycle.shed_minute()])

	# The host's cycle leaves its world: snapshots go without its part.
	_host_cycle.free()
	_expect(_host_net.day_cycle == null and not _host_net.snapshot().has(DayCycle.SNAPSHOT_KEY),
		"A day cycle that leaves the tree unhooks itself and its snapshot part")


## The client has applied every event the host sent.
func _wait_seq() -> void:
	var target: int = _host_net.seq
	var arrived: bool = await _wait_for(func() -> bool: return _client_net.seq == target)
	_expect(arrived, "The client received event %d (has %d)" % [target, _client_net.seq])


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
