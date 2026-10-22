extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_money_net.gd
##
## The company's money replicated (D-0517: CompanyNet.publish_wallet() and its wallet_moved event, applied by
## scripts/core/company/company_wallet_net.gd on every peer from the host's balance):
## - solo (offline, a session of one): publish_wallet() earns and charges once each, one ledger entry per call
##   with the amount, the reason, the balance after it and the host's minute; the event is exactly {amount,
##   reason, money, minute}, plain (RpcGuard.dict_ok) and under EVENT_BYTES_MAX bytes; a charge may take the
##   wallet into the red; 0, an amount over MAX_MONEY, a reason that isn't a short lowercase id (empty,
##   uppercase, a path, a space, a leading digit, too long), a balance that would leave the range and no
##   company publish nothing (no seq, no entry);
## - a mirror (CompanyWalletNet alone on a company): an event that doesn't fit (amount 0, a float, missing,
##   over MAX_MONEY; money a float, missing, out of range, or a balance before it out of range; minute a float,
##   negative, past the day, missing; reason missing, empty, a number, uppercase, a path; no company) is not
##   applied and changes nothing, with no drift; a mirror whose wallet missed movements ends on the host's
##   balance and entry balance, its entry takes the host's minute while its clock_minutes stays, and it flags
##   the drift once (take_drift()); a movement from a negative balance applies with no drift;
## - host and two clients as ENet peers in one process: after each wallet_moved (an income, an expense, a charge
##   that leaves the wallet in the red, an income still in the red, and a purchase after the host earned with no
##   event: a drift jump) money and the last ledger entry (its balance too) are the same on the three peers, and
##   the host's money moves by exactly the amount with exactly one entry more; the clients whose wallet was off
##   ask for a snapshot and end with the host's whole company, history included;
## - the second client joins late: it holds the wallet_moved that reaches it before its snapshot, then holds the
##   host's balance and history;
## - a client can't move the money: publish_wallet() and publish(wallet_moved) are false there, a request of that
##   kind is dropped in silence (not a request kind), and an _apply_event it sends the host is turned away
##   (authority RPC, RpcGuard.from_host); nothing changes on any peer and no seq is spent;
## - a malformed wallet_moved through a client's _apply_state() changes nothing;
## - every peer applied each event once, in order, with no gap.
## Expected in the log: CompanyWalletNet's warnings for a wallet set right (the mirror, the drift jump on both
## clients) and for the event with no company, and the engine's "RPC '_apply_event' is not allowed" for the
## client's forged event.

const PORT: int = 24687
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## The host's clock minute; a client's clock_minutes is never written by a wallet event.
const HOST_MINUTE: int = 10 * 60 + 15
const SENTINEL_MINUTE: int = 7
## A wallet_moved as var_to_bytes encodes it stays this small (four plain values).
const EVENT_BYTES_MAX: int = 160

var _failures: int = 0
var _host: Peer
var _client: Peer
var _late: Peer


## One peer: its side of the session, its company, its CompanyNet and what it heard.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var seqs: Array[int] = []
	var refusals: Array = []
	var restored: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_solo()
	_check_mirror()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: wallet_moved gives every peer the host's balance and history, once on the host, in the red,"
			+ " after a drift and for a late joiner; a client can't move the money")
	quit(_failures)


# --- Solo ---


func _check_solo() -> void:
	var state: Node = _new_state("SoloState")
	state.call(&"new_company", "Solo SRL")
	state.set(&"clock_minutes", HOST_MINUTE)
	var net := CompanyNet.new()
	net.name = "SoloNet"
	net.company = state
	root.add_child(net)
	var events: Array[Dictionary] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == CompanyNet.WALLET:
			events.append(data))
	var money: int = int(state.get(&"money"))
	_expect(net.publish_wallet(150, &"order_paid") and int(state.get(&"money")) == money + 150
		and _ledger(state).size() == 1 and net.seq == 1 and events.size() == 1,
		"Solo, publish_wallet(+150, order_paid) earns once (money %s, %d entries, seq %d)"
		% [state.get(&"money"), _ledger(state).size(), net.seq])
	var entry: Dictionary = _ledger(state).back()
	_expect(entry.get("amount") == 150 and str(entry.get("reason")) == "order_paid"
		and entry.get("balance") == money + 150 and entry.get("minute") == HOST_MINUTE,
		"...its entry carries the amount, the reason, the balance after it and the host's minute (%s)" % [entry])
	var sent: Dictionary = events.back() if not events.is_empty() else {}
	var expected: Dictionary = {"amount": 150, "reason": &"order_paid", "money": money + 150, "minute": HOST_MINUTE}
	var size: int = var_to_bytes(sent).size()
	_expect(sent == expected and RpcGuard.dict_ok(sent) and size <= EVENT_BYTES_MAX,
		"...and the event is {amount, reason, money, minute}, plain, %d bytes (%s)" % [size, sent])
	var red: int = -(money + 150 + 40)
	_expect(net.publish_wallet(red, &"rent") and int(state.get(&"money")) == -40
		and _ledger(state).size() == 2 and _ledger(state).back().get("balance") == -40
		and _ledger(state).back().get("amount") == red,
		"A charge of %d leaves the wallet in the red, -40, with one entry (money %s)" % [red, state.get(&"money")])

	var before: Array = _wallet_of(state)
	var seq: int = net.seq
	var refused: Array = [
		[0, &"tip", "a zero amount"],
		[CompanyWalletNet.MAX_MONEY + 1, &"tip", "an amount over MAX_MONEY"],
		[-CompanyWalletNet.MAX_MONEY - 1, &"rent", "a charge over MAX_MONEY"],
		[5, &"", "an empty reason"],
		[5, &"Order_Paid", "an uppercase reason"],
		[5, &"../rent", "a path"],
		[5, &"order paid", "a space"],
		[5, &"9lives", "a leading digit"],
		[5, StringName("a".repeat(CompanyWalletNet.MAX_REASON_LENGTH + 1)), "a reason too long"],
	]
	for case: Array in refused:
		_expect(not net.publish_wallet(case[0], case[1]),
			"publish_wallet() with %s publishes nothing" % case[2])
	state.set(&"money", CompanyWalletNet.MAX_MONEY - 1)
	_expect(not net.publish_wallet(5, &"tip"), "...nor with a balance that would go past MAX_MONEY")
	state.set(&"money", -40)
	net.company = null
	_expect(not net.publish_wallet(5, &"tip"), "...nor with no company")
	net.company = state
	_expect(_wallet_of(state) == before and net.seq == seq and events.size() == 2,
		"...and none of them moved the money, wrote an entry or spent a seq (seq %d)" % net.seq)
	net.free()
	state.free()


## Rule 6: an event is applied as it comes, checked only as data; the wallet travels absolute.
func _check_mirror() -> void:
	var state: Node = _new_state("MirrorState")
	state.call(&"new_company", "Mirror SRL")
	state.set(&"clock_minutes", SENTINEL_MINUTE)
	var wallet := CompanyWalletNet.new()
	var money: int = int(state.get(&"money"))
	var good: Dictionary = {"amount": -30, "reason": &"supplier", "money": money - 30, "minute": HOST_MINUTE}
	var low: Dictionary = _with(_with(good, "money", -CompanyWalletNet.MAX_MONEY), "amount", 5)
	var before: Array = _wallet_of(state)
	var bad: Array = [
		[_with(good, "amount", 0), "amount 0"],
		[_with(good, "amount", -30.0), "a float amount"],
		[_without(good, "amount"), "no amount"],
		[_with(good, "amount", -CompanyWalletNet.MAX_MONEY - 1), "an amount over MAX_MONEY"],
		[_with(good, "money", float(money - 30)), "a float balance"],
		[_without(good, "money"), "no balance"],
		[_with(good, "money", CompanyWalletNet.MAX_MONEY + 1), "a balance over MAX_MONEY"],
		[low, "a balance before it under -MAX_MONEY"],
		[_with(good, "minute", float(HOST_MINUTE)), "a float minute"],
		[_with(good, "minute", -1), "a negative minute"],
		[_with(good, "minute", CompanyTuning.MINUTES_PER_DAY), "a minute past the day"],
		[_without(good, "minute"), "no minute"],
		[_without(good, "reason"), "no reason"],
		[_with(good, "reason", &""), "an empty reason"],
		[_with(good, "reason", 7), "a reason that is a number"],
		[_with(good, "reason", &"Rent"), "an uppercase reason"],
		[_with(good, "reason", "res://rent"), "a path for a reason"],
	]
	for case: Array in bad:
		_expect(not wallet.apply(state, case[0]),
			"A wallet_moved with %s is not applied" % case[1])
	_expect(not wallet.apply(null, good), "...nor one with no company here")
	_expect(_wallet_of(state) == before and not wallet.take_drift(),
		"...and none of them changed the wallet or flagged a drift")

	state.set(&"money", money + 500)
	var entries: int = _ledger(state).size()
	var applied: bool = wallet.apply(state, good)
	var last: Dictionary = _ledger(state).back() if not _ledger(state).is_empty() else {}
	_expect(applied and int(state.get(&"money")) == money - 30 and _ledger(state).size() == entries + 1
		and last.get("balance") == money - 30 and last.get("amount") == -30 and str(last.get("reason")) == "supplier",
		"A mirror that missed +500 ends the expense on the host's balance %d (money %s, entry %s)"
		% [money - 30, state.get(&"money"), last])
	_expect(last.get("minute") == HOST_MINUTE and int(state.get(&"clock_minutes")) == SENTINEL_MINUTE,
		"...its entry takes the host's minute and its clock_minutes stays (%s)" % state.get(&"clock_minutes"))
	_expect(wallet.take_drift() and not wallet.take_drift(), "...and it flags the drift once")
	state.set(&"money", -100)
	var from_red: Dictionary = {"amount": 20, "reason": &"tip", "money": -80, "minute": 0}
	_expect(wallet.apply(state, from_red) and int(state.get(&"money")) == -80 and not wallet.take_drift(),
		"A movement from a negative balance applies with no drift (money %s)" % state.get(&"money"))
	state.free()


# --- Network ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	_late = _make_peer("LateSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var late := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	_host.side.multiplayer.multiplayer_peer = server
	_host.state.call(&"new_company", "Wallet SRL")
	_host.state.set(&"clock_minutes", HOST_MINUTE)
	_add_net(_host)
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_net(_client)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(_connected.bind(_client, 1))
	_expect(up and connected, "The client connects to the host on localhost:%d" % PORT)
	if connected:
		await _play(late)
	client.close()
	late.close()
	server.close()
	await process_frame
	for peer: Peer in [_host, _client, _late]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()
		peer.state.free()


func _play(late: ENetMultiplayerPeer) -> void:
	_expect(await _join(_client), "The client gets the host's snapshot (restored %s)" % [_client.restored])
	_client.state.set(&"clock_minutes", SENTINEL_MINUTE)
	_expect_equal([_host, _client], "after the client's snapshot")
	await _step(150, &"order_paid", "a first payment", [_client])
	if not await _check_late_join(late):
		return
	var everyone: Array = [_client, _late]
	await _step(300, &"order_paid", "an income", everyone)
	await _step(-120, &"supplier", "an expense", everyone)
	await _step(-(int(_host.state.get(&"money")) + 250), &"rent", "a charge into the red", everyone)
	_expect(int(_late.state.get(&"money")) == -250, "...the three hold -250 (%s)" % _late.state.get(&"money"))
	await _step(40, &"tip", "an income still in the red", everyone)
	_expect_equal([_host, _client, _late], "after four movements")
	await _check_drift_jump(everyone)
	await _check_client_cannot_move()
	var bad: Dictionary = {"amount": 12.5, "reason": &"tip", "money": 100, "minute": 0}
	var before: Array = _wallet_of(_late.state)
	var seq: int = _late.net.seq
	_expect(not _late.net._apply_state(CompanyNet.WALLET, bad) and _wallet_of(_late.state) == before
		and _late.net.seq == seq and not _late.net.is_applying(),
		"A malformed wallet_moved through a client's _apply_state() changes nothing")
	_check_seqs()


## A second client connects while the host keeps moving money: it holds the event that reaches it before its
## snapshot and then has the host's balance and history.
func _check_late_join(late: ENetMultiplayerPeer) -> bool:
	var up: bool = late.create_client("127.0.0.1", PORT) == OK
	_late.side.multiplayer.multiplayer_peer = late
	_add_net(_late)
	_late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(_connected.bind(_late, 2))
	_expect(up and connected, "A second client connects late")
	if not connected:
		return false
	await _step(25, &"tip", "a tip before the late client is up", [_client])
	var held: bool = await _wait_for(func() -> bool: return _late.net._held.size() == 1)
	_expect(held and _late.net.seq == 0 and _ledger(_late.state).is_empty()
		and int(_late.state.get(&"money")) != int(_host.state.get(&"money")),
		"The late client holds that event and still has its own wallet (money %s)" % _late.state.get(&"money"))
	_expect(await _join(_late) and _late.restored == [_host.net.seq] and _late.seqs.is_empty(),
		"...then the snapshot brings it to seq %d (restored %s)" % [_host.net.seq, _late.restored])
	_late.state.set(&"clock_minutes", SENTINEL_MINUTE)
	_expect(int(_late.state.get(&"money")) == int(_host.state.get(&"money"))
		and _ledger(_late.state) == _ledger(_host.state),
		"The late client sees the host's balance %s and its %d entries"
		% [_host.state.get(&"money"), _ledger(_host.state).size()])
	_expect_equal([_host, _client, _late], "after the late client's snapshot")
	return true


## The host's wallet moves with no event (what an unwired payment did before D-0517); its next wallet_moved sets
## every client right, and each one asks for a snapshot for the entry it missed.
func _check_drift_jump(everyone: Array) -> void:
	_host.state.call(&"earn", 500, &"tip")
	var restores: Array[int] = [_client.restored.size(), _late.restored.size()]
	await _step(-80, &"shop", "a purchase after the host earned 500 with no event", everyone)
	var resynced: bool = await _wait_for(func() -> bool:
		return _client.restored.size() > restores[0] and _late.restored.size() > restores[1] \
			and not _client.net.awaiting_snapshot() and not _late.net.awaiting_snapshot())
	_expect(resynced, "Both clients whose wallet was off asked for a snapshot and got it (restored %s / %s)"
		% [_client.restored, _late.restored])
	_expect(_ledger(_client.state) == _ledger(_host.state) and _ledger(_late.state) == _ledger(_host.state),
		"...and hold the host's whole history, the silent +500 included (%d entries)" % _ledger(_host.state).size())
	_expect_equal([_host, _client, _late], "after the drift jump's snapshot")


## A client tries every way to move the money: none reaches the host, nothing changes anywhere.
func _check_client_cannot_move() -> void:
	var peers: Array = [_host, _client, _late]
	var before: Array = []
	for peer: Peer in peers:
		before.append(_wallet_of(peer.state))
	var seq: int = _host.net.seq
	var money: int = int(_client.state.get(&"money"))
	var forged: Dictionary = {"amount": 999, "reason": &"tip", "money": money + 999, "minute": 0}
	_expect(not _client.net.publish_wallet(999, &"tip") and not _client.net.publish(CompanyNet.WALLET, forged),
		"On a client publish_wallet() and publish(wallet_moved) are false")
	var asked: int = _client.net.request(CompanyNet.WALLET, forged)
	_client.net._apply_event.rpc_id(1, seq + 1, CompanyNet.WALLET, forged)
	# Reliable and in order: once this one's refusal is back, the host took the two before it.
	var probe: int = _client.net.request(&"units_take", {"rid_only": true})
	var answered: bool = await _wait_for(func() -> bool: return _reason_heard(_client.refusals, probe) != &"")
	_expect(answered and _reason_heard(_client.refusals, probe) == CompanyNet.REASON_BAD_DATA,
		"A units_take with no station sent after them comes back bad_data: the host took them")
	_expect(asked > 0 and _reason_heard(_client.refusals, asked) == &"",
		"...the wallet_moved request was dropped in silence (not a request kind)")
	var after: Array = []
	for peer: Peer in peers:
		after.append(_wallet_of(peer.state))
	_expect(after == before and _host.net.seq == seq and _client.net.seq == seq and _late.net.seq == seq,
		"...and no peer's wallet moved nor any seq was spent (host seq %d)" % _host.net.seq)


## Every peer applied each event once, in order, with no gap: the host from 1, a client from its first snapshot on.
func _check_seqs() -> void:
	_expect(_host.seqs == _range(1, _host.net.seq), "The host's events are 1..%d" % _host.net.seq)
	for peer: Peer in [_client, _late]:
		var first: int = peer.restored[0] + 1 if not peer.restored.is_empty() else 1
		_expect(peer.seqs == _range(first, _host.net.seq),
			"%s applied %d..%d with no gap or repeat (%s)" % [peer.side.name, first, _host.net.seq, peer.seqs])


# --- Helpers ---


## The host publishes one wallet_moved and every follower applies it: the host's money moves by exactly `amount`
## with exactly one entry more, and every follower holds the host's money and last entry (balance included).
func _step(amount: int, reason: StringName, what: String, followers: Array) -> void:
	var money: int = int(_host.state.get(&"money"))
	var entries: int = _ledger(_host.state).size()
	var seq: int = _host.net.seq
	var sent: bool = _host.net.publish_wallet(amount, reason)
	var reached: bool = await _wait_for(_at_host_seq.bind(followers))
	_expect(sent and reached and _host.net.seq == seq + 1,
		"The host publishes %s (%d, %s) and every client applies it (seq %d)" % [what, amount, reason, _host.net.seq])
	var last: Dictionary = _ledger(_host.state).back() if not _ledger(_host.state).is_empty() else {}
	_expect(int(_host.state.get(&"money")) == money + amount and _ledger(_host.state).size() == entries + 1
		and last.get("amount") == amount and last.get("balance") == money + amount,
		"...on the host money moves by exactly %d with exactly one entry (money %s, entries %d -> %d)"
		% [amount, _host.state.get(&"money"), entries, _ledger(_host.state).size()])
	for peer: Peer in followers:
		var theirs: Dictionary = _ledger(peer.state).back() if not _ledger(peer.state).is_empty() else {}
		_expect(int(peer.state.get(&"money")) == int(_host.state.get(&"money")) and theirs == last
			and theirs.get("balance") == int(_host.state.get(&"money")),
			"%s holds the host's money and last entry after %s (money %s / %s, entry %s / %s)"
			% [peer.side.name, what, peer.state.get(&"money"), _host.state.get(&"money"), theirs, last])


## True once `peer` sees the host and the host sees `peers` clients.
func _connected(peer: Peer, peers: int) -> bool:
	return peer.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == peers


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = _new_state(side_name + "State")
	return peer


func _add_net(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.net.event_applied.connect(func(seq: int, _kind: StringName, _data: Dictionary) -> void:
		peer.seqs.append(seq))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))


## The host sends `peer` its snapshot as when that peer's world comes up; true once it is in.
func _join(peer: Peer) -> bool:
	var id: int = peer.side.multiplayer.get_unique_id()
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		network.emit_signal(&"peer_level_ready", id)
	else:
		_host.net.send_snapshot(id)
	return await _wait_for(func() -> bool: return not peer.restored.is_empty() and peer.net.seq == _host.net.seq)


func _at_host_seq(followers: Array) -> bool:
	for peer: Peer in followers:
		if peer.net.seq != _host.net.seq:
			return false
	return true


## What every peer must hold the same: the company without its stock and clock_minutes (the host clock's).
func _expect_equal(peers: Array, when: String) -> void:
	var first: Peer = peers[0]
	for peer: Peer in peers.slice(1):
		_expect(_shared(peer.state) == _shared(first.state),
			"%s has the host's company %s (money %s / %s)"
			% [peer.side.name, when, peer.state.get(&"money"), first.state.get(&"money")])


static func _reason_heard(heard: Array, rid: int) -> StringName:
	for entry: Array in heard:
		if entry[0] == rid:
			return entry[1]
	return &""


func _new_state(state_name: String) -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.name = state_name
	root.add_child(state)
	state.call(&"reset")
	return state


static func _ledger(state: Node) -> Array:
	return state.get(&"ledger")


## The wallet as two peers compare it: money and the whole ledger (a copy).
static func _wallet_of(state: Node) -> Array:
	return [int(state.get(&"money")), (state.get(&"ledger") as Array).duplicate(true)]


static func _shared(state: Node) -> Dictionary:
	var data: Dictionary = state.call(&"to_dict")
	data.erase("inventory")
	data.erase("clock_minutes")
	return data


static func _range(from: int, to: int) -> Array[int]:
	var numbers: Array[int] = []
	for number: int in range(from, to + 1):
		numbers.append(number)
	return numbers


static func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy[key] = value
	return copy


static func _without(data: Dictionary, key: String) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy.erase(key)
	return copy


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
