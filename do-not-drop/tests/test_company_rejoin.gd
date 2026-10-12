extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_rejoin.gd
##
## A client falls with units in its hands and comes back (expansion D-2006,
## scripts/core/company/company_net.gd and floor_bundles.gd; contract
## docs/expansion-distritos/diseno/red-autoridad.md, row 7 and "Un peer se va"):
## - FloorBundles alone: floor:<n> locations, positions_ok() refuses a "floor" that isn't a
##   Dictionary, ids that aren't floor:<n> text or are too long, values that aren't finite
##   Vector3s and more than MAX_BUNDLES; next_free() skips a bundle that holds units without a
##   position (a saved floor:0) and one with a position;
## - a client's apply_snapshot() takes the host's "floor" part, refuses a malformed one without
##   changing anything (no company_state_restored) and reads a snapshot without it as no bundles;
##   a units_moved into floor:<n> without a finite Vector3 `pos` doesn't apply;
## - solo (offline): units_drop through drop() applies at once into the next free bundle (floor:0
##   holds saved units without a position and is not reused), an empty hand is refused with
##   not_enough, and a leaver holding two products leaves one bundle per product at its last
##   known position, or at the origin when there is none;
## - two ENet peers in one process (a host and a client, each a CompanyNet): the client takes 2
##   hens into its hands, both peers mirror it; its player goes and it disconnects: on the host
##   its hands are empty and floor:1 holds the 2 hens where it last stood, floor:0 untouched, the
##   total unchanged, in one event; the client comes back under a new peer id and the snapshot
##   (NetworkManager.peer_level_ready) gives it the host's stock and floor positions;
## - units_drop from the client: within DROP_REACH at `pos`, 10 m away at its feet; taking a
##   bundle back (station = its floor:<n>) empties and forgets it; more than held, another
##   product, bad data (unknown product, qty 0 or float, no pos, a pos that isn't a Vector3) are
##   refused, and a NaN or out-of-world pos is dropped in silence, all changing nothing; storing
##   into a floor bundle is refused (no_station); with its request budget spent a drop still goes
##   through (critical reserve) while a take is dropped;
## - a peer that leaves the roster (NetworkManager.peer_removed) with its player still there
##   drops at the player's position, not its last request's; its later disconnect adds nothing;
##   a third client that joins sees every bundle where the host has it. No engine error.
## Expected in the log: RpcGuard's warning for the client's spent request budget.

const PORT: int = 24647

var _failures: int = 0
var _catcher := ErrorCatcher.new()
var _host_net: CompanyNet
var _client_net: CompanyNet
var _client_peer: ENetMultiplayerPeer
## Where the host sees each player ({peer: Vector3}); a missing peer has no player node.
var _positions: Dictionary = {}
var _client_refusals: Array = []
var _restored: Array[int] = []
## [kind, data] of every event the host applied, in order.
var _host_events: Array = []
var _total: int = 0


## Engine errors (not warnings) logged while peers come and go.
class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d in %s)"
			% [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = _messages.duplicate()
		_messages.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_floor_bundles()
	_check_snapshot_floor()
	_check_solo()

	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 4) == OK,
		"The test hosts an ENet session on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server
	_host_net = _add_net(host_side)
	_setup_host()
	OS.add_logger(_catcher)
	_catcher.take()

	var first: int = await _join(host_side, client_side)
	_expect(first > 1, "A client joins and gets the snapshot (peer %d)" % first)
	if first > 1:
		var second: int = await _check_fall_and_return(host_side, client_side, first)
		if second > 1:
			await _check_drops(second)
			await _check_critical_drop(second)
			await _check_roster_leave(host_side, client_side, second)

	var errors: Array[String] = _catcher.take()
	OS.remove_logger(_catcher)
	_expect(errors.is_empty(), "No engine error while peers fall, come back and drop (got %s)"
		% [errors])
	if _client_peer != null:
		_client_peer.close()
	server.close()
	await process_frame
	set_multiplayer(null, host_side.get_path())
	set_multiplayer(null, client_side.get_path())
	host_side.free()
	client_side.free()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: a client falls with 2 hens in hand: they stay on the host's floor where it"
			+ " stood, the stock unchanged, and it comes back to the same stock and floor;"
			+ " units_drop checked by the host, floor bundles taken back, leavers let go")
	quit(_failures)


func _add_net(side: Node) -> CompanyNet:
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	side.add_child(net)
	return net


## The host's stock: hens and puppies on pallets and 3 sourdough a saved day left in floor:0
## (CompanyRoot.SAVED_HANDS_LOCATION), with no position.
func _setup_host() -> void:
	_host_net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	_host_net.player_origin = func(peer: int) -> Variant: return _positions.get(peer)
	_host_net.inventory.receive(&"hen", 10, &"pallet:p1")
	_host_net.inventory.receive(&"puppy", 5, &"pallet:p2")
	_host_net.inventory.receive(&"sourdough", 3, &"floor:0")
	_total = _host_net.inventory.total_units()
	_positions[1] = Vector3(0.0, 0.0, 1.0)
	_host_net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		_host_events.append([kind, data]))


static func _stations() -> Dictionary:
	return {
		&"pallet_hen": {"location": &"pallet:p1", "spot": Vector3(0.0, 0.0, 0.0)},
		&"pallet_puppy": {"location": &"pallet:p2", "spot": Vector3(1.0, 0.0, 0.0)},
		&"slot_hen": {"location": &"shelf:a_0", "spot": Vector3(0.0, 0.0, 2.0), "accepts": &"hen"},
	}


## A client that connects as a fresh world would: a new CompanyNet waiting for the snapshot,
## which the host sends once NetworkManager says its world is up. Its peer id, 0 if it failed.
func _join(host_side: Node, client_side: Node) -> int:
	if _client_net != null:
		_client_net.free()
	_client_peer = ENetMultiplayerPeer.new()
	if _client_peer.create_client("127.0.0.1", PORT) != OK:
		return 0
	client_side.multiplayer.multiplayer_peer = _client_peer
	_client_net = _add_net(client_side)
	_client_net.wait_for_snapshot()
	_restored.clear()
	_client_refusals.clear()
	_client_net.company_state_restored.connect(func(at: int) -> void: _restored.append(at))
	_client_net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		_client_refusals.append([rid, reason]))
	var id: int = client_side.multiplayer.get_unique_id()
	var up: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().has(id) \
			and client_side.multiplayer.get_peers().has(1))
	if not up:
		return 0
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null:
		network.emit_signal(&"peer_level_ready", id)
	else:
		_host_net.send_snapshot(id)
	var restored: bool = await _wait_for(func() -> bool: return _restored.size() == 1)
	_expect(restored and _restored == [_host_net.seq] and _client_net.seq == _host_net.seq,
		"Peer %d gets the snapshot at the host's seq %d (restored %s)"
		% [id, _host_net.seq, _restored])
	_expect(_same(), "...with the host's stock and floor bundles (floor %s, host's %s)"
		% [_client_net.floor_bundles.to_dict(), _host_net.floor_bundles.to_dict()])
	return id if restored else 0


## The client takes 2 hens, its player goes and it drops out; it comes back as a new peer.
func _check_fall_and_return(host_side: Node, client_side: Node, first: int) -> int:
	_positions[first] = Vector3(0.5, 0.0, 0.5)
	var hands: StringName = CompanyNet.hands_location(first)
	_client_net.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 2})
	var taken: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", hands) == 2)
	_expect(taken and _host_net.inventory.count(&"hen", hands) == 2 and _same(),
		"The client holds 2 hens, on both peers")
	var where: Variant = _host_net.last_known_position(first)
	_expect(where == Vector3(0.5, 0.0, 0.5),
		"The host keeps where the client stood at its take (got %s)" % [where])

	var seq: int = _host_net.seq
	_host_events.clear()
	_positions.erase(first)
	_client_peer.close()
	var gone: bool = await _wait_for(func() -> bool:
		return not host_side.multiplayer.get_peers().has(first))
	var bundle: StringName = FloorBundles.location(1)
	_expect(gone and _host_net.inventory.count(&"hen", hands) == 0,
		"Once the client is gone its hands are empty on the host (%d)"
		% _host_net.inventory.count(&"hen", hands))
	_expect(_host_net.inventory.count(&"hen", bundle) == 2
		and _host_net.floor_bundles.position_of(bundle) == Vector3(0.5, 0.0, 0.5),
		"...and floor:1 holds the 2 hens where it last stood (at %s)"
		% [_host_net.floor_bundles.position_of(bundle)])
	_expect(_host_net.inventory.contents_at(&"floor:0") == {&"sourdough": 3}
		and _host_net.floor_bundles.position_of(&"floor:0") == null,
		"The saved floor:0 is not reused (holds %s)" % [_host_net.inventory.contents_at(&"floor:0")])
	_expect(_host_net.inventory.total_units() == _total,
		"The stock total is unchanged (%d, was %d)" % [_host_net.inventory.total_units(), _total])
	var event: Array = _host_events[0] if _host_events.size() == 1 else []
	var moved: Dictionary = event[1] if not event.is_empty() else {}
	_expect(_host_net.seq == seq + 1 and moved.get("from") == hands and moved.get("to") == bundle
		and moved.get("pos") == Vector3(0.5, 0.0, 0.5),
		"It is one units_moved hands -> floor:1 with its pos (events %s)" % [_host_events])
	_expect(_host_net.last_known_position(first) == null,
		"Where the leaver stood is forgotten (got %s)" % [_host_net.last_known_position(first)])

	var second: int = await _join(host_side, client_side)
	_expect(second > 1 and second != first,
		"The client comes back under a new peer id (%d, was %d)" % [second, first])
	if second > 1:
		_expect(_client_net.inventory.count(&"hen", bundle) == 2
			and _client_net.floor_bundles.position_of(bundle) == Vector3(0.5, 0.0, 0.5)
			and _client_net.inventory.total_units() == _total,
			"Back, it sees the 2 hens on the floor where it fell and the same total")
	return second


func _check_drops(peer: int) -> void:
	_positions[peer] = Vector3(1.0, 0.0, 1.0)
	var hands: StringName = CompanyNet.hands_location(peer)
	var one: StringName = FloorBundles.location(1)
	var two: StringName = FloorBundles.location(2)
	_client_net.request(&"units_take", {"station": one, "product": &"hen", "qty": 2})
	var taken: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", hands) == 2)
	_expect(taken and _host_net.inventory.count(&"hen", one) == 0
		and _host_net.floor_bundles.position_of(one) == null
		and _client_net.floor_bundles.position_of(one) == null and _same(),
		"Taking the whole bundle back (station floor:1) empties and forgets it on both")

	_client_net.drop(&"hen", 1, Vector3(2.0, 0.0, 1.0))
	var dropped: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", one) == 1)
	_expect(dropped and _client_net.floor_bundles.position_of(one) == Vector3(2.0, 0.0, 1.0)
		and _same(),
		"A drop 1 m away lands at its pos, in the free floor:1 (at %s)"
		% [_client_net.floor_bundles.position_of(one)])
	_client_net.drop(&"hen", 1, Vector3(11.0, 0.0, 1.0))
	dropped = await _wait_for(func() -> bool: return _client_net.inventory.count(&"hen", two) == 1)
	_expect(dropped and _client_net.floor_bundles.position_of(two) == Vector3(1.0, 0.0, 1.0)
		and _client_net.inventory.count(&"hen", hands) == 0 and _same(),
		"A drop 10 m away lands at its feet, in floor:2 (at %s)"
		% [_client_net.floor_bundles.position_of(two)])
	_expect(_client_refusals.is_empty(), "No drop was refused (%s)" % [_client_refusals])

	_client_net.request(&"units_take", {"station": two, "product": &"hen", "qty": 1})
	taken = await _wait_for(func() -> bool: return _client_net.inventory.count(&"hen", hands) == 1)
	_expect(taken and _client_net.floor_bundles.position_of(two) == null and _same(),
		"floor:2 taken back into the hand")
	await _check_drop_refusals(hands)


## Holding 1 hen: what the host refuses or drops, and that none of it changes anything.
func _check_drop_refusals(hands: StringName) -> void:
	var stock: Dictionary = _host_net.inventory.to_dict()
	var bundles: Dictionary = _host_net.floor_bundles.to_dict()
	var seq: int = _host_net.seq
	var at: Vector3 = Vector3(1.0, 0.0, 1.5)
	var cases: Array = [
		[{"product": &"hen", "qty": 2, "pos": at}, CompanyNet.REASON_NOT_ENOUGH, "more than held"],
		[{"product": &"puppy", "qty": 1, "pos": at}, CompanyNet.REASON_NOT_ENOUGH,
			"another product than the one held"],
		[{"product": &"unicorn", "qty": 1, "pos": at}, CompanyNet.REASON_BAD_DATA,
			"an unknown product"],
		[{"product": &"hen", "qty": 0, "pos": at}, CompanyNet.REASON_BAD_DATA, "qty 0"],
		[{"product": &"hen", "qty": 1.0, "pos": at}, CompanyNet.REASON_BAD_DATA, "a float qty"],
		[{"product": &"hen", "qty": 1}, CompanyNet.REASON_BAD_DATA, "no pos"],
		[{"product": &"hen", "qty": 1, "pos": Vector2(1.0, 1.0)}, CompanyNet.REASON_BAD_DATA,
			"a Vector2 pos"],
		[{"product": &"hen", "qty": 1, "pos": 3}, CompanyNet.REASON_BAD_DATA, "an int pos"],
	]
	for case: Array in cases:
		var rid: int = _client_net.request(CompanyNet.UNITS_DROP, case[0])
		var reason: StringName = await _await_refusal(rid)
		_expect(reason == case[1], "Dropping %s is refused with %s (got %s)"
			% [case[2], case[1], reason])
	var silent: Array[int] = [
		_client_net.drop(&"hen", 1, Vector3(NAN, 0.0, 0.0)),
		_client_net.drop(&"hen", 1, Vector3(2.0e6, 0.0, 0.0)),
	]
	var store: int = _client_net.request(
		&"units_store", {"station": FloorBundles.location(1), "product": &"hen", "qty": 1})
	var store_reason: StringName = await _await_refusal(store)
	_expect(store_reason == CompanyNet.REASON_NO_STATION,
		"Storing into a floor bundle is refused with no_station (got %s)" % store_reason)
	_expect(_refusal(silent[0]) == &"" and _refusal(silent[1]) == &"",
		"A NaN or out-of-world pos is dropped in silence (%s)" % [_client_refusals])
	_expect(_host_net.inventory.to_dict() == stock and _host_net.floor_bundles.to_dict() == bundles
		and _host_net.seq == seq and _client_net.inventory.count(&"hen", hands) == 1 and _same(),
		"No refused or dropped request changed the stock, the floor or the seq")


## A drop spends the critical reserve once the client's budget is gone; a take doesn't.
func _check_critical_drop(peer: int) -> void:
	var hands: StringName = CompanyNet.hands_location(peer)
	var pallet: int = _host_net.inventory.count(&"hen", &"pallet:p1")
	# Spent at a time ahead of the clock: no refill until the test gives the budget back.
	var ahead: int = Time.get_ticks_msec() + 60000
	for i: int in range(int(RpcGuard.REQUEST_BURST) + 1):
		RpcGuard.take_request(peer, ahead)
	var take: int = _client_net.request(
		&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 1})
	_client_net.drop(&"hen", 1, Vector3(1.0, 0.0, 1.0))
	var two: StringName = FloorBundles.location(2)
	var dropped: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", two) == 1)
	_expect(dropped and _client_net.inventory.count(&"hen", hands) == 0
		and _host_net.inventory.count(&"hen", &"pallet:p1") == pallet and _refusal(take) == &""
		and _same(),
		"Over budget the drop goes through (critical) and the take before it is dropped")
	RpcGuard.forget_peer(peer)


## The client leaves the roster while its player is still in the shed, then disconnects; a
## third client joins and sees every bundle.
func _check_roster_leave(host_side: Node, client_side: Node, peer: int) -> void:
	var hands: StringName = CompanyNet.hands_location(peer)
	_client_net.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 2})
	var taken: bool = await _wait_for(func() -> bool:
		return _client_net.inventory.count(&"hen", hands) == 2)
	_expect(taken and _host_net.last_known_position(peer) == Vector3(1.0, 0.0, 1.0),
		"The client holds 2 hens again, taken from where it stands")
	_positions[peer] = Vector3(4.0, 0.0, 4.0)
	var seq: int = _host_net.seq
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	_expect(network != null and network.has_signal(&"peer_removed"),
		"NetworkManager is there to say the peer left the roster")
	if network == null:
		return
	network.emit_signal(&"peer_removed", peer)
	var three: StringName = FloorBundles.location(3)
	_expect(_host_net.inventory.count(&"hen", hands) == 0
		and _host_net.inventory.count(&"hen", three) == 2
		and _host_net.floor_bundles.position_of(three) == Vector3(4.0, 0.0, 4.0)
		and _host_net.seq == seq + 1,
		"Off the roster with its player still there, its hens go to floor:3 at the player"
		+ " (at %s), not its last take" % [_host_net.floor_bundles.position_of(three)])
	_client_peer.close()
	var gone: bool = await _wait_for(func() -> bool:
		return not host_side.multiplayer.get_peers().has(peer))
	await process_frame
	_expect(gone and _host_net.seq == seq + 1 and _host_net.last_known_position(peer) == null,
		"Its disconnect afterwards adds nothing (seq %d)" % _host_net.seq)
	_expect(_host_net.inventory.total_units() == _total, "The stock total is still %d (got %d)"
		% [_total, _host_net.inventory.total_units()])

	var third: int = await _join(host_side, client_side)
	var expected: Dictionary = {
		FloorBundles.location(1): Vector3(2.0, 0.0, 1.0),
		FloorBundles.location(2): Vector3(1.0, 0.0, 1.0),
		three: Vector3(4.0, 0.0, 4.0),
	}
	_expect(third > 1 and _client_net.floor_bundles.to_dict() == expected,
		"A third client sees the 3 bundles where the host has them (got %s)"
		% [_client_net.floor_bundles.to_dict()])


func _check_floor_bundles() -> void:
	_expect(FloorBundles.location(4) == &"floor:4" and CompanyNet.FLOOR_PREFIX == "floor:"
		and FloorBundles.is_floor(&"floor:4") and not FloorBundles.is_floor(&"hands:4"),
		"Floor bundles are floor:<n> locations")
	var good: Dictionary = {&"floor:1": Vector3(1.0, 0.0, 2.0), "floor:2": Vector3.ZERO}
	_expect(FloorBundles.positions_ok(good) and FloorBundles.positions_ok({}),
		"Positions of floor:<n> ids (text or StringName) to finite Vector3s are fine")
	var crowd: Dictionary = {}
	for i: int in range(FloorBundles.MAX_BUNDLES + 1):
		crowd[FloorBundles.location(i)] = Vector3.ZERO
	var bad: Array = [
		[[1, 2], "an Array"],
		[{&"shelf:a_0": Vector3.ZERO}, "a shelf id"],
		[{7: Vector3.ZERO}, "an int id"],
		[{"floor:" + "9".repeat(40): Vector3.ZERO}, "a 46-character id"],
		[{&"floor:1": Vector2.ZERO}, "a Vector2"],
		[{&"floor:1": [1.0, 0.0, 2.0]}, "an Array position"],
		[{&"floor:1": Vector3(INF, 0.0, 0.0)}, "an infinite position"],
		[{&"floor:1": Vector3(0.0, NAN, 0.0)}, "a NaN position"],
		[{&"floor:1": Vector3(0.0, 0.0, 2.0e6)}, "a position out of the world"],
		[crowd, "%d bundles" % crowd.size()],
	]
	for case: Array in bad:
		_expect(not FloorBundles.positions_ok(case[0]), "Floor positions with %s are refused"
			% case[1])
	var stock := Inventory.new()
	stock.receive(&"sourdough", 3, &"floor:0")
	var bundles := FloorBundles.new()
	_expect(bundles.next_free(stock) == &"floor:1",
		"A saved floor:0 without a position is not free (got %s)" % bundles.next_free(stock))
	stock.receive(&"hen", 2, &"dock")
	_expect(bundles.apply_move(stock, &"hen", 2, &"dock", &"floor:1", Vector3(3.0, 0.0, 0.0))
		and bundles.next_free(stock) == &"floor:2",
		"A bundle with a position is not free either (got %s)" % bundles.next_free(stock))
	_expect(bundles.apply_move(stock, &"hen", 2, &"floor:1", &"dock", null)
		and bundles.position_of(&"floor:1") == null and bundles.next_free(stock) == &"floor:1",
		"Emptied, floor:1 is forgotten and free again")


## A client CompanyNet out of the tree: the snapshot's "floor" part.
func _check_snapshot_floor() -> void:
	var client := CompanyNet.new()
	var restored: Array[int] = []
	client.company_state_restored.connect(func(at: int) -> void: restored.append(at))
	var floor_part: Dictionary = {&"floor:1": Vector3(1.0, 0.0, 2.0)}
	var good: Dictionary = {
		"seq": 4,
		"inventory": {"stock": {&"hen": {&"floor:1": 2, &"dock": 3}}, "reserved": {}},
		"floor": floor_part,
	}
	_expect(client.apply_snapshot(good) and restored == [4]
		and client.floor_bundles.to_dict() == floor_part
		and client.inventory.count(&"hen", &"floor:1") == 2,
		"A snapshot's floor part puts the host's positions here (got %s)"
		% [client.floor_bundles.to_dict()])
	var bad: Array = [
		[7, "an int"],
		[{&"shelf:a": Vector3.ZERO}, "a shelf id"],
		[{&"floor:2": Vector3(NAN, 0.0, 0.0)}, "a NaN position"],
		[{&"floor:2": "here"}, "a text position"],
	]
	var other_stock: Dictionary = {"stock": {&"puppy": {&"dock": 1}}, "reserved": {}}
	for case: Array in bad:
		var snapshot: Dictionary = good.duplicate(true)
		snapshot["floor"] = case[0]
		snapshot["inventory"] = other_stock
		_expect(not client.apply_snapshot(snapshot) and restored.size() == 1,
			"A snapshot whose floor is %s is refused" % case[1])
	_expect(client.floor_bundles.to_dict() == floor_part
		and client.inventory.count(&"hen", &"floor:1") == 2,
		"...and the refused ones changed neither the stock nor the floor")
	var without: Dictionary = {"seq": 5, "inventory": other_stock}
	_expect(client.apply_snapshot(without) and client.floor_bundles.to_dict().is_empty(),
		"A snapshot without a floor part leaves no bundle positions")
	var stock: Dictionary = client.inventory.to_dict()
	var no_pos: Dictionary = {"product": &"puppy", "qty": 1, "from": &"dock", "to": &"floor:3"}
	var nan_pos: Dictionary = no_pos.duplicate()
	nan_pos["pos"] = Vector3(NAN, 0.0, 0.0)
	var flat_pos: Dictionary = no_pos.duplicate()
	flat_pos["pos"] = Vector2(1.0, 1.0)
	_expect(not client._apply_state(&"units_moved", no_pos)
		and not client._apply_state(&"units_moved", nan_pos)
		and not client._apply_state(&"units_moved", flat_pos)
		and client.inventory.to_dict() == stock and client.floor_bundles.to_dict().is_empty(),
		"A units_moved into floor:<n> without a finite Vector3 pos doesn't apply")
	client.free()


## Solo is a session of one: the same drop, applied at once; a leaver with two products.
func _check_solo() -> void:
	var solo := CompanyNet.new()
	solo.name = "SoloCompanyNet"
	root.add_child(solo)
	solo.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	solo.player_origin = func(peer: int) -> Variant:
		return Vector3(0.0, 0.0, 1.0) if peer == 1 else null
	solo.inventory.receive(&"hen", 5, &"pallet:p1")
	solo.inventory.receive(&"sourdough", 3, &"floor:0")
	var refusals: Array = []
	solo.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		refusals.append([rid, reason]))
	var rid: int = solo.drop(&"hen", 1, Vector3.ZERO)
	_expect(refusals == [[rid, CompanyNet.REASON_NOT_ENOUGH]] and solo.seq == 0,
		"Solo, dropping from an empty hand is refused at once (got %s)" % [refusals])
	solo.request(&"units_take", {"station": &"pallet_hen", "product": &"hen", "qty": 2})
	solo.drop(&"hen", 2, Vector3(0.5, 0.0, 1.0))
	_expect(solo.seq == 2 and solo.inventory.count(&"hen", &"floor:1") == 2
		and solo.floor_bundles.position_of(&"floor:1") == Vector3(0.5, 0.0, 1.0)
		and solo.inventory.count(&"sourdough", &"floor:0") == 3,
		"Solo, a drop applies at once into floor:1, floor:0 kept (seq %d)" % solo.seq)

	var total: int = solo.inventory.total_units()
	solo.inventory.receive(&"hen", 1, &"hands:7")
	solo.inventory.receive(&"puppy", 2, &"hands:7")
	solo._on_peer_disconnected(7)
	_expect(solo.seq == 4 and solo.inventory.contents_at(&"hands:7").is_empty()
		and solo.inventory.contents_at(&"floor:2") == {&"hen": 1}
		and solo.inventory.contents_at(&"floor:3") == {&"puppy": 2}
		and solo.floor_bundles.position_of(&"floor:2") == Vector3.ZERO
		and solo.floor_bundles.position_of(&"floor:3") == Vector3.ZERO,
		"A leaver with 2 products and no known position: a bundle each at the origin (%s)"
		% [solo.floor_bundles.to_dict()])
	solo.inventory.receive(&"hen", 1, &"hands:8")
	solo._last_origin[8] = Vector3(5.0, 0.0, 5.0)
	solo._on_peer_disconnected(8)
	_expect(solo.floor_bundles.position_of(&"floor:4") == Vector3(5.0, 0.0, 5.0)
		and solo.last_known_position(8) == null,
		"A leaver whose player is gone drops at its last known position (got %s)"
		% [solo.floor_bundles.position_of(&"floor:4")])
	_expect(solo.inventory.total_units() == total + 4,
		"Leavers' hands only move: the total is what was there (%d)" % solo.inventory.total_units())
	solo.free()


func _same() -> bool:
	return _host_net.inventory.to_dict() == _client_net.inventory.to_dict() \
		and _host_net.floor_bundles.to_dict() == _client_net.floor_bundles.to_dict()


func _await_refusal(rid: int) -> StringName:
	await _wait_for(func() -> bool: return _refusal(rid) != &"")
	return _refusal(rid)


func _refusal(rid: int) -> StringName:
	for entry: Array in _client_refusals:
		if int(entry[0]) == rid:
			return entry[1]
	return &""


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
