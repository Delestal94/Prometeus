extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_game_clock.gd
##
## The company day's clock from the host (D-0219, scripts/core/company/game_clock.gd on the
## day_clock module; contract docs/expansion-distritos/diseno/red-autoridad.md, row "Reloj"),
## with simulated time: every clock reads one tick the test moves, so a minute takes no time.
## - Solo (offline) and without a CompanyNet the clock starts stopped at 08:00 and writes nothing;
##   start() runs it at S3's pace (90 real seconds per game hour), as one clock_anchor event when
##   there is a CompanyNet; it writes the whole minute into CompanyState.clock_minutes as it runs;
##   pause, a new speed while stopped and resume move it as said; a minute two days past the
##   close is still an anchor (the company keeps a day's last minute); a clock run past
##   MAX_MINUTE still pauses and its snapshot part still passes DayClock.anchor_ok(). publish()
##   sends only the host's own kinds (units_moved is refused). A CompanyNet without a clock
##   refuses a clock_anchor (with a warning), a clock attaches to one CompanyNet only once, and
##   one that leaves the tree unhooks itself and its snapshot part (another can attach).
## - A host and a client as two ENet peers in one process (each with its CompanyNet, GameClock and
##   CompanyState on its own SceneMultiplayer): the host opens the day at 08:00 and runs 30 s
##   alone; the client joins and gets the anchor in the snapshot, moved to the moment it was
##   taken: both read the same minute (within 1).
## - 60 simulated seconds later both read 09:00 within 1 minute, and nothing was sent while the
##   clock just ran (no seq moves over many frames).
## - The host's pause reaches the client as one event and stops both at the same minute for the
##   next 60 s; a second pause sends nothing. Resume and a doubled speed move both alike.
## - The client takes each anchor with its own tick minus half its ENet round trip to the host
##   (lead_msec); the host with 0.
## - A client can't change the pace (start, pause, resume and set_speed send nothing), the host
##   refuses a minute or speed out of range, and a malformed anchor (event or snapshot part)
##   changes nothing. Only the host's CompanyState gets the running minute; the client's keeps
##   the one its snapshot brought.
## - The host's clock leaves its world: the next snapshot goes without the clock part and the
##   client applies it (no waiting for another), keeping the anchor it had.
## Expected in the log: CompanyNet's warning for the clock_anchor applied with no clock.

const PORT: int = 24717
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Where the simulated tick starts (any value: a tick is local to its machine).
const START_TICK: int = 5_000_000

var _failures: int = 0
## The simulated tick (msec) every clock in this test reads.
var _now: int = START_TICK
var _host_net: CompanyNet
var _client_net: CompanyNet
var _host_clock: GameClock
var _client_clock: GameClock
var _host_state: Node
var _client_state: Node
var _client_peer: ENetMultiplayerPeer
var _client_id: int = 0
## Client: snapshots restored, clock events applied, and half its round trip to the host each
## time an anchor landed (what lead_msec should hold).
var _restored: Array[int] = []
var _client_anchors: int = 0
var _expected_lead: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	await _check_solo()
	_check_without_net()

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
	_host_state = _new_state()
	_host_state.call(&"new_company", "Reloj SRL")
	_host_net = _add_net(host_side, _host_state)
	_host_clock = _add_clock(host_side, _host_net, _host_state)
	await process_frame
	_check_host_opens()

	_client_peer = ENetMultiplayerPeer.new()
	_expect(_client_peer.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	client_side.multiplayer.multiplayer_peer = _client_peer
	_client_state = _new_state()
	_client_net = _add_net(client_side, _client_state)
	_client_clock = _add_clock(client_side, _client_net, _client_state)
	_client_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 \
			and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		_client_id = client_side.multiplayer.get_unique_id()
		_listen_client()
		await _check_late_join()
		await _check_sixty_seconds()
		await _check_pause()
		await _check_resume_and_speed()
		await _check_client_cannot()
		_check_bad_anchors()
		await _check_host_clock_leaves()

	_client_peer.close()
	server.close()
	await process_frame
	set_multiplayer(null, host_side.get_path())
	set_multiplayer(null, client_side.get_path())
	host_side.free()
	client_side.free()
	_host_state.free()
	_client_state.free()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: the host's clock anchor gives two ENet peers the same time after 60 s, the pause"
			+ " stops both, a late joiner gets it in the snapshot and nothing travels while it runs")
	quit(_failures)


func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	return state


func _add_net(side: Node, state: Node) -> CompanyNet:
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = state
	side.add_child(net)
	return net


func _add_clock(side: Node, net: CompanyNet, state: Node) -> GameClock:
	var clock := GameClock.new()
	clock.name = "GameClock"
	clock.ticks = func() -> int: return _now
	side.add_child(clock)
	_expect(clock.attach(net, state), "A clock attaches to its peer's CompanyNet")
	return clock


func _check_solo() -> void:
	var side := Node.new()
	side.name = "SoloSide"
	root.add_child(side)
	var state: Node = _new_state()
	state.call(&"new_company", "Solo SRL")
	state.set(&"clock_minutes", 600)
	var net: CompanyNet = _add_net(side, state)
	var clock: GameClock = _add_clock(side, net, state)
	var kinds: Array[StringName] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		kinds.append(kind))
	await process_frame
	_expect(clock.is_host() and clock.is_paused()
		and is_equal_approx(clock.minute_now(), float(CompanyTuning.DAY_START_MIN)),
		"Solo, a clock not started is stopped at 08:00 (got %.2f)" % clock.minute_now())
	_expect(int(state.get(&"clock_minutes")) == 600,
		"...and writes nothing into the company before it starts (got %s)" % state.get(&"clock_minutes"))
	_expect(not clock.attach(net, state), "A second clock part on the same CompanyNet is refused")
	_expect(clock.start() and net.seq == 1 and kinds == [CompanyNet.CLOCK_ANCHOR],
		"start() is one clock_anchor event (seq %d, kinds %s)" % [net.seq, kinds])
	_expect(is_equal_approx(clock.current_speed(), 60.0 / CompanyTuning.SECONDS_PER_GAME_HOUR),
		"It runs at S3's pace: a game hour every %.0f s (speed %.4f)"
		% [CompanyTuning.SECONDS_PER_GAME_HOUR, clock.current_speed()])
	_now += 90_000
	await process_frame
	_expect(is_equal_approx(clock.minute_now(), 540.0) and int(state.get(&"clock_minutes")) == 540,
		"90 s later it is 09:00 and the company says so (clock %.2f, company %s)"
		% [clock.minute_now(), state.get(&"clock_minutes")])
	_expect(clock.pause() and clock.is_paused() and not clock.pause() and net.seq == 2,
		"pause() stops it once; a second pause sends nothing (seq %d)" % net.seq)
	_expect(clock.set_speed(clock.current_speed() * 2.0) and clock.is_paused()
		and is_equal_approx(clock.minute_now(), 540.0),
		"A new speed while stopped keeps it stopped where it was (%.2f)" % clock.minute_now())
	_expect(not clock.set_speed(clock.current_speed()), "The same speed again sends nothing")
	_expect(clock.resume() and not clock.resume() and net.seq == 4,
		"resume() runs it once (seq %d)" % net.seq)
	_now += 30_000
	_expect(is_equal_approx(clock.minute_now(), 580.0),
		"At double speed 30 s are 40 minutes (got %.2f)" % clock.minute_now())
	_expect(clock.start(3000.0) and int(state.get(&"clock_minutes")) == CompanyTuning.MINUTES_PER_DAY - 1,
		"A clock left running two days past the close still takes its anchor; the company keeps"
		+ " the last minute of a day (got %s)" % state.get(&"clock_minutes"))
	var seq_before: int = net.seq
	var moved: Dictionary = {"product": &"hen", "qty": 1, "from": &"dock", "to": &"hands:1"}
	_expect(not net.publish(&"units_moved", moved) and not net.publish(&"made_up", {})
		and net.seq == seq_before,
		"publish() refuses units_moved and unknown kinds: only HOST_EVENT_KINDS (seq %d)" % net.seq)
	await _check_minute_cap(net, clock)
	var bare := CompanyNet.new()
	_expect(not bare._apply_state(CompanyNet.CLOCK_ANCHOR, clock.anchor()),
		"A CompanyNet without a clock refuses a clock_anchor")
	bare.free()
	clock.free()
	_expect(net.clock == null and not net.snapshot().has(GameClock.SNAPSHOT_KEY)
		and not net.remove_snapshot_part(GameClock.SNAPSHOT_KEY),
		"A clock that leaves the tree unhooks itself and its snapshot part (keys %s)" % [net.snapshot().keys()])
	var again: GameClock = _add_clock(side, net, state)
	_expect(net.clock == again and net.snapshot().has(GameClock.SNAPSHOT_KEY),
		"...and another clock can attach to that CompanyNet")
	side.free()
	state.free()


## A clock left running past MAX_MINUTE: the host can still pause it and the snapshot part (the
## anchor moved to now) is still one every peer takes.
func _check_minute_cap(net: CompanyNet, clock: GameClock) -> void:
	_expect(clock.start(GameClock.MAX_MINUTE - 1.0), "The clock starts a minute before MAX_MINUTE")
	_now += 60_000
	var part: Variant = net.snapshot().get(GameClock.SNAPSHOT_KEY)
	_expect(clock.minute_now() > GameClock.MAX_MINUTE
		and DayClock.anchor_ok(part, GameClock.MAX_MINUTE, GameClock.MAX_SPEED),
		"Run past MAX_MINUTE (%.1f), its snapshot part still passes anchor_ok (got %s)"
		% [clock.minute_now(), part])
	_expect(clock.pause() and clock.is_paused()
		and is_equal_approx(clock.minute_now(), GameClock.MAX_MINUTE),
		"...and the host can still pause it, at MAX_MINUTE (got %.1f)" % clock.minute_now())
	await process_frame


func _check_without_net() -> void:
	var clock := GameClock.new()
	clock.ticks = func() -> int: return _now
	_expect(clock.is_host() and clock.start(700.0) and not clock.is_paused(),
		"Without a CompanyNet the clock is this peer's: start() applies at once")
	_now += 9_000
	_expect(is_equal_approx(clock.minute_now(), 706.0), "...and runs (got %.2f)" % clock.minute_now())
	clock.free()


## The host opens the day before anyone joins, then runs 30 s alone.
func _check_host_opens() -> void:
	_expect(_host_clock.start() and _host_net.seq == 1 and _host_clock.lead_msec == 0,
		"The host opens the day: one event, taken with no lead (seq %d, lead %d)"
		% [_host_net.seq, _host_clock.lead_msec])
	_now += 30_000
	_expect(is_equal_approx(_host_clock.minute_now(), 500.0),
		"30 s after 08:00 the host reads 08:20 (got %.2f)" % _host_clock.minute_now())
	var part: Variant = _host_net.snapshot().get(GameClock.SNAPSHOT_KEY)
	_expect(part is Dictionary and DayClock.anchor_ok(part)
		and is_equal_approx(float((part as Dictionary).get("minute", -1.0)), 500.0),
		"The snapshot carries the anchor moved to when it is taken (got %s)" % [part])


func _listen_client() -> void:
	_client_net.company_state_restored.connect(func(seq: int) -> void:
		_restored.append(seq)
		_expected_lead = _half_round_trip())
	_client_net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void:
		if kind == CompanyNet.CLOCK_ANCHOR:
			_client_anchors += 1
			_expected_lead = _half_round_trip())


## What GameClock moves an anchor back on this client right now: half its ENet round trip.
func _half_round_trip() -> int:
	var round_trip: float = NetStats.round_trip_seconds(_client_peer, CompanyNet.HOST_ID)
	return clampi(roundi(round_trip * 500.0), 0, GameClock.MAX_LEAD_MSEC)


func _check_late_join() -> void:
	_expect(_client_clock.is_paused() and not _client_clock.is_host(),
		"Before the snapshot the joining client's clock is stopped and not the host")
	_expect(_host_net.send_snapshot(_client_id), "The host sends the joiner its snapshot")
	var restored: bool = await _wait_for(func() -> bool:
		return _restored.size() == 1 and not _client_net.awaiting_snapshot())
	_expect(restored and _restored == [1], "The client restores the snapshot at seq 1 (got %s)" % [_restored])
	_expect_same_time("After the snapshot")
	_expect(not _client_clock.is_paused()
		and is_equal_approx(_client_clock.current_speed(), _host_clock.current_speed()),
		"...running at the host's speed (%.4f)" % _client_clock.current_speed())
	_expect(_client_clock.lead_msec == _expected_lead and _host_clock.lead_msec == 0,
		"...taken with its own tick minus half the round trip (lead %d ms, expected %d)"
		% [_client_clock.lead_msec, _expected_lead])
	_expect(int(_client_state.get(&"clock_minutes")) == 500,
		"The client's company has the minute the snapshot brought (got %s)" % _client_state.get(&"clock_minutes"))


func _check_sixty_seconds() -> void:
	var host_seq: int = _host_net.seq
	_now += 60_000
	_expect(is_equal_approx(_host_clock.minute_now(), 540.0),
		"60 simulated seconds later the host reads 09:00 (got %.2f)" % _host_clock.minute_now())
	_expect_same_time("60 s later")
	for i: int in range(12):
		_now += 1_000
		await process_frame
	_expect(_host_net.seq == host_seq and _client_net.seq == host_seq and _client_anchors == 0,
		"Nothing is sent while the clock runs (host seq %d, client seq %d, anchors %d)"
		% [_host_net.seq, _client_net.seq, _client_anchors])
	_expect(int(_host_state.get(&"clock_minutes")) == floori(_host_clock.minute_now()),
		"The host's company follows the clock (company %s, clock %.2f)"
		% [_host_state.get(&"clock_minutes"), _host_clock.minute_now()])
	_expect(int(_client_state.get(&"clock_minutes")) == 500,
		"The client's company is never written by its clock (got %s)" % _client_state.get(&"clock_minutes"))


func _check_pause() -> void:
	_expect(_host_clock.pause(), "The host pauses the clock")
	var target: int = _host_net.seq
	var arrived: bool = await _wait_for(func() -> bool: return _client_net.seq == target)
	_expect(arrived and _client_anchors == 1, "The pause reaches the client as one event (%d)" % _client_anchors)
	_expect(_client_clock.lead_msec == _expected_lead,
		"...taken with its tick minus half the round trip (lead %d ms, expected %d)"
		% [_client_clock.lead_msec, _expected_lead])
	var stopped_at: float = _host_clock.minute_now()
	_now += 60_000
	_expect(_host_clock.is_paused() and _client_clock.is_paused()
		and is_equal_approx(_host_clock.minute_now(), stopped_at)
		and is_equal_approx(_client_clock.minute_now(), stopped_at),
		"The pause stops both at the same minute for 60 s (host %.3f, client %.3f, stopped at %.3f)"
		% [_host_clock.minute_now(), _client_clock.minute_now(), stopped_at])
	_expect(not _host_clock.pause() and _host_net.seq == target,
		"A second pause sends nothing (seq %d)" % _host_net.seq)


func _check_resume_and_speed() -> void:
	var stopped_at: float = _host_clock.minute_now()
	_expect(_host_clock.resume(), "The host resumes the clock")
	var target: int = _host_net.seq
	var arrived: bool = await _wait_for(func() -> bool: return _client_net.seq == target)
	_expect(arrived, "The resume reaches the client")
	_now += 30_000
	_expect(is_equal_approx(_host_clock.minute_now(), stopped_at + 20.0),
		"30 s after resuming the host is 20 minutes on (got %.2f)" % _host_clock.minute_now())
	_expect_same_time("After resuming")
	_expect(_host_clock.set_speed(GameClock.DEFAULT_SPEED * 2.0), "The host doubles the speed")
	target = _host_net.seq
	arrived = await _wait_for(func() -> bool: return _client_net.seq == target)
	_expect(arrived and is_equal_approx(_client_clock.current_speed(), GameClock.DEFAULT_SPEED * 2.0),
		"The client runs at the new speed (%.4f)" % _client_clock.current_speed())
	var before: float = _host_clock.minute_now()
	_now += 30_000
	_expect(is_equal_approx(_host_clock.minute_now(), before + 40.0),
		"At double speed 30 s are 40 minutes (got %.2f)" % (_host_clock.minute_now() - before))
	_expect_same_time("At double speed")


func _check_client_cannot() -> void:
	var host_seq: int = _host_net.seq
	var minute: float = _client_clock.minute_now()
	_expect(not _client_clock.start(600.0) and not _client_clock.pause()
		and not _client_clock.set_speed(1.0) and not _client_clock.resume(),
		"A client can't change the pace (start, pause, set_speed, resume)")
	for i: int in range(6):
		await process_frame
	_expect(_host_net.seq == host_seq and _client_net.seq == host_seq
		and is_equal_approx(_client_clock.minute_now(), minute) and not _host_clock.is_paused(),
		"...and nothing was sent or changed (host seq %d, client seq %d)" % [_host_net.seq, _client_net.seq])


func _check_bad_anchors() -> void:
	var host_seq: int = _host_net.seq
	_expect(not _host_clock.start(NAN) and not _host_clock.start(-1.0)
		and not _host_clock.start(GameClock.MAX_MINUTE + 1.0)
		and not _host_clock.set_speed(-1.0) and not _host_clock.set_speed(INF)
		and not _host_clock.set_speed(GameClock.MAX_SPEED * 2.0) and _host_net.seq == host_seq,
		"The host refuses a minute or speed out of range and sends nothing (seq %d)" % _host_net.seq)
	var anchor: Dictionary = _client_clock.anchor()
	var minute: float = _client_clock.minute_now()
	var bad_cases: Array = [
		[{"minute": NAN, "speed": 1.0, "paused": false}, "a NaN minute"],
		[{"minute": 600.0, "speed": GameClock.MAX_SPEED * 2.0, "paused": false}, "a speed over the cap"],
		[{"minute": GameClock.MAX_MINUTE + 1.0, "speed": 1.0, "paused": false}, "a minute past MAX_MINUTE"],
		[{"minute": 600.0, "speed": 1.0, "paused": "no"}, "a paused that is text"],
		[{"minute": 600.0, "speed": 1.0, "paused": false, "tick": 3}, "an extra key"],
	]
	for case: Array in bad_cases:
		_expect(not _client_net._apply_state(CompanyNet.CLOCK_ANCHOR, case[0]),
			"A clock_anchor event with %s is refused" % case[1])
	_expect(not _client_clock._put_snapshot_part(7) and not _client_clock._put_snapshot_part({}),
		"A snapshot part that isn't an anchor is refused")
	_expect(_client_clock.anchor() == anchor and is_equal_approx(_client_clock.minute_now(), minute),
		"...and none of them changed the client's clock (%.2f)" % _client_clock.minute_now())


## The host's clock leaves its world: snapshots go without it and the client still takes them.
func _check_host_clock_leaves() -> void:
	var anchor: Dictionary = _client_clock.anchor()
	_host_clock.free()
	_expect(_host_net.clock == null and not _host_net.snapshot().has(GameClock.SNAPSHOT_KEY),
		"The host's clock left: no clock on its CompanyNet and none in its snapshot")
	_expect(_host_net.send_snapshot(_client_id), "The host sends a snapshot without the clock part")
	var restored: bool = await _wait_for(func() -> bool:
		return _restored.size() == 2 and not _client_net.awaiting_snapshot())
	_expect(restored, "The client applies it and waits for no other (restored %s, waiting %s)"
		% [_restored, _client_net.awaiting_snapshot()])
	_expect(_client_clock.anchor() == anchor,
		"...keeping the anchor it had (got %s, had %s)" % [_client_clock.anchor(), anchor])


## Host and client read the same minute at the same simulated tick, within one game minute.
func _expect_same_time(when: String) -> void:
	var host: float = _host_clock.minute_now()
	var client: float = _client_clock.minute_now()
	_expect(absf(host - client) <= 1.0,
		"%s both read the same time within 1 minute (host %.3f, client %.3f)" % [when, host, client])


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
