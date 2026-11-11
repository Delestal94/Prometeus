extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_fixed_costs_hook.gd
##
## The day's close charges the rent (expansion D-0509.b, FixedCostsHook), on a real CompanyNet, GameClock and
## DayCycle:
## - close_early() and the 20:00 transition charge it alike, on CLOSING: one wallet_moved, reason `rent`, before
##   SUMMARY, so DaySummary.build() shows it and the closing balance is the wallet's;
## - a repeated CLOSING event (the shed freezing is one) charges nothing more, and each new day charges again;
## - it goes through into the red, which makes the company bankrupt for the next day (D-0510);
## - a client's hook (a fake peer connected as client 2, no socket) publishes nothing;
## - host and client as two ENet peers in one process, both with the hook: the client's wallet, ledger and summary
##   are the host's, with the rent exactly once.
## test_company_root checks that CompanyRoot hooks it, after the supplier's automatic order.

const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
const PORT: int = 24737
const RENT: int = CompanyTuning.RENT_PER_DAY

var _failures: int = 0
var _now: int = 0


## A peer that is connected as client 2: not the server, so CompanyNet.is_host() is false. No socket.
class FakeClientPeer:
	extends MultiplayerPeerExtension

	func _poll() -> void:
		pass

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED

	func _get_unique_id() -> int:
		return 2

	func _is_server() -> bool:
		return false

	func _get_available_packet_count() -> int:
		return 0

	func _get_max_packet_size() -> int:
		return 1024

	func _get_packet_peer() -> int:
		return 1

	func _get_packet_channel() -> int:
		return 0

	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()

	func _put_packet_script(_buffer: PackedByteArray) -> Error:
		return OK

	func _set_target_peer(_peer: int) -> void:
		pass

	func _set_transfer_channel(_channel: int) -> void:
		pass

	func _get_transfer_channel() -> int:
		return 0

	func _set_transfer_mode(_mode: MultiplayerPeer.TransferMode) -> void:
		pass

	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _set_refuse_new_connections(_enable: bool) -> void:
		pass

	func _is_refusing_new_connections() -> bool:
		return false

	func _is_server_relay_supported() -> bool:
		return false

	func _disconnect_peer(_peer: int, _force: bool) -> void:
		pass

	func _close() -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_close_charges_once()
	_test_new_day_at_20()
	_test_into_the_red()
	_test_client_hook()
	await _test_two_peers()
	if _failures == 0:
		print("PASS: the day's close charges the rent")
	quit(_failures)


func _new_state(money: int) -> Node:
	var state: Node = STATE_SCRIPT.new()
	state.call(&"reset")
	state.call(&"new_company", "Rent SRL")
	state.set(&"money", money)
	return state


## A peer's world, under `side`: its CompanyState, CompanyNet, GameClock, DayCycle and hook.
func _build(side: Node, state: Node) -> Dictionary:
	side.add_child(state)
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
	_expect(clock.attach(net, state) and cycle.attach(net, clock, state), "clock and cycle attach")
	var hook: FixedCostsHook = FixedCostsHook.attach(side, net)
	_expect(hook != null, "the hook attaches")
	return {"state": state, "net": net, "clock": clock, "cycle": cycle, "hook": hook, "side": side}


## A solo host's day 1, OPERATING.
func _solo(label: String, money: int) -> Dictionary:
	var side := Node.new()
	side.name = label
	root.add_child(side)
	var parts: Dictionary = _build(side, _new_state(money))
	_to_operating(parts, 1)
	return parts


func _to_operating(parts: Dictionary, day: int) -> void:
	var cycle: DayCycle = parts["cycle"]
	_expect(cycle.open_day(day) if day == 1 else cycle.next_day(), "day %d opens" % day)
	_now += roundi(CompanyTuning.OPENING_REAL_SECONDS * 1000.0) + 1000
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.OPERATING, "day %d is OPERATING" % day)


## The ledger's movements for `reason`.
func _entries(state: Node, reason: StringName) -> Array:
	return (state.get(&"ledger") as Array).filter(
		func(entry: Dictionary) -> bool: return StringName(entry.get("reason")) == reason)


func _test_close_charges_once() -> void:
	var parts: Dictionary = _solo("CloseSide", 500)
	var state: Node = parts["state"]
	var net: CompanyNet = parts["net"]
	var cycle: DayCycle = parts["cycle"]
	var seq: int = net.seq
	_expect(int(state.get(&"money")) == 500 and _entries(state, FixedCosts.REASON_RENT).is_empty(),
		"nothing is charged while the day runs")
	_expect(cycle.close_early() and cycle.phase() == DayCycle.Phase.CLOSING, "the day is CLOSING")
	_expect(int(state.get(&"money")) == 500 - RENT and _entries(state, FixedCosts.REASON_RENT).size() == 1,
		"closing charges the rent (money %s)" % state.get(&"money"))
	_expect(net.seq == seq + 2, "the phase event and one wallet_moved (seq +%d)" % (net.seq - seq))
	net.event_applied.emit(net.seq, CompanyNet.DAY_PHASE, {"day": 1, "phase": "CLOSING", "frozen": true})
	_expect(int(state.get(&"money")) == 500 - RENT, "a repeated CLOSING charges nothing more")
	_now += 1000
	cycle.poll()
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY, "the day reaches SUMMARY")
	_expect(int(cycle.summary["cost_by_reason"].get("rent", 0)) == RENT, "the summary shows the rent")
	_expect(int(cycle.summary["closing"]) == 500 - RENT and int(cycle.summary["opening"]) == 500,
		"the summary closes on the wallet (%s)" % [cycle.summary])
	_expect(int(state.get(&"money")) == 500 - RENT, "SUMMARY charges nothing more")
	_free(parts)


func _test_new_day_at_20() -> void:
	var parts: Dictionary = _solo("TwoDaysSide", 500)
	var state: Node = parts["state"]
	var cycle: DayCycle = parts["cycle"]
	var clock: GameClock = parts["clock"]
	for day: int in [1, 2]:
		if day > 1:
			_to_operating(parts, day)
		_expect(clock.start(float(CompanyTuning.DAY_END_MIN)), "the clock reads 20:00")
		cycle.poll()
		_expect(cycle.phase() == DayCycle.Phase.CLOSING, "20:00 closes day %d" % day)
		_expect(int(state.get(&"money")) == 500 - RENT * day, "the 20:00 close charges day %d" % day)
		_now += 1000
		cycle.poll()
		_expect(int(cycle.summary["cost_by_reason"].get("rent", 0)) == RENT, "day %d's summary: one rent" % day)
	_free(parts)


func _test_into_the_red() -> void:
	var parts: Dictionary = _solo("RedSide", 30)
	var state: Node = parts["state"]
	_expect(not Bankruptcy.is_bankrupt(state), "30 is not bankrupt")
	_expect((parts["cycle"] as DayCycle).close_early(), "the day closes")
	_expect(int(state.get(&"money")) == 30 - RENT and Bankruptcy.is_bankrupt(state),
		"the rent goes through into the red and the company is bankrupt (money %s)" % state.get(&"money"))
	_free(parts)


func _test_client_hook() -> void:
	var parts: Dictionary = _solo("ClientHookSide", 500)
	var net: CompanyNet = parts["net"]
	root.multiplayer.multiplayer_peer = FakeClientPeer.new()
	_expect(not net.is_host(), "the net is a client's: connected, but not the server")
	var seq: int = net.seq
	net.event_applied.emit(seq, CompanyNet.DAY_PHASE, {"day": 1, "phase": "CLOSING", "frozen": false})
	_expect(net.seq == seq and int(parts["state"].get(&"money")) == 500, "a client's hook charges nothing")
	root.multiplayer.multiplayer_peer = null
	_free(parts)


func _test_two_peers() -> void:
	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 2) == OK, "the test hosts on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server
	var host: Dictionary = _build(host_side, _new_state(500))
	await process_frame
	_to_operating(host, 1)
	var client_peer := ENetMultiplayerPeer.new()
	_expect(client_peer.create_client("127.0.0.1", PORT) == OK, "the client starts joining")
	client_side.multiplayer.multiplayer_peer = client_peer
	var client: Dictionary = _build(client_side, _new_state(0))
	(client["net"] as CompanyNet).wait_for_snapshot()
	var client_net: CompanyNet = client["net"]
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "the client connects")
	if connected:
		_expect((host["net"] as CompanyNet).send_snapshot(client_side.multiplayer.get_unique_id()),
			"the host sends its snapshot")
		_expect(await _wait_for(func() -> bool: return not client_net.awaiting_snapshot()),
			"the client takes the snapshot")
		await _check_peers(host, client)
	client_peer.close()
	server.close()
	await process_frame
	set_multiplayer(null, host_side.get_path())
	set_multiplayer(null, client_side.get_path())
	host_side.free()
	client_side.free()
	RpcGuard.reset()


func _check_peers(host: Dictionary, client: Dictionary) -> void:
	var host_cycle: DayCycle = host["cycle"]
	var host_net: CompanyNet = host["net"]
	var client_net: CompanyNet = client["net"]
	var client_state: Node = client["state"]
	_expect(host_cycle.close_early(), "the host closes the day")
	_now += 1000
	host_cycle.poll()
	_expect(host_cycle.phase() == DayCycle.Phase.SUMMARY, "the host reaches SUMMARY")
	var target: int = host_net.seq
	_expect(await _wait_for(func() -> bool: return client_net.seq == target),
		"the client gets every event (%d of %d)" % [client_net.seq, target])
	_expect(int(client_state.get(&"money")) == 500 - RENT and int(host["state"].get(&"money")) == 500 - RENT,
		"both wallets paid the rent once (client %s)" % client_state.get(&"money"))
	_expect(_entries(client_state, FixedCosts.REASON_RENT).size() == 1, "the client's ledger has one rent")
	await process_frame
	_expect(host_net.seq == target, "the client's hook published nothing")
	_expect((client["cycle"] as DayCycle).summary == host_cycle.summary, "the client's summary is the host's")


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _free(parts: Dictionary) -> void:
	(parts["side"] as Node).free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
