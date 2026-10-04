extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_late_join.gd
##
## Late join and snapshot of the company mode (D-2004, scripts/core/company/company_net.gd;
## contract docs/expansion-distritos/diseno/red-autoridad.md section 3):
## - a shed of 300 units over 150 locations, with reservations, a full ledger and a layout,
##   packs into one chunk under 64 KB and unpacks to the same dictionary; a snapshot part
##   (add_snapshot_part) travels with it, a reserved or repeated key is refused, and a
##   malformed snapshot (old seq, stock of the wrong types, company not a Dictionary, a part
##   that refuses its value) is refused;
## - a host plays 50 events alone, then a client joins (two ENet peers in one process, the
##   client's CompanyNet waiting as CompanyRoot leaves it) and holds the 2 events that reach it
##   first; NetworkManager.peer_level_ready makes the host send the snapshot and 3 more events
##   follow: the client ends with the host's Inventory.to_dict() (reservations included),
##   CompanyState.to_dict() and seq, drops the 2 events the snapshot covers and applies the 3
##   after it in order, with one company_state_restored and no fact signal for the snapshot
##   (no event_applied, no Inventory.stock_changed);
## - a seq gap is recovered with the same snapshot, asked for by the client and cut into many
##   chunks over the network;
## - chunks out of order, repeated, of an older or finished snapshot or malformed (id, index,
##   total, size, empty or oversized bytes) don't break it; events that arrive while chunks
##   are missing are held and applied in order after it; bytes that don't decompress, a value
##   that isn't a Dictionary or a stock of bad types leave the client waiting for another.
## Expected in the log: CompanyNet's warnings for the snapshots it refuses (a part that
## doesn't fit, snapshots 6 to 8).

const PORT: int = 24634
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const PRODUCTS: Array[StringName] = [
	&"hen", &"puppy", &"sourdough", &"antique_lamp", &"fireworks_crate",
	&"glass_tower", &"milk_canister", &"porcelain_vase", &"raccoon_cage", &"wedding_cake",
]

var _failures: int = 0
var _host_net: CompanyNet
var _client_net: CompanyNet
var _host_state: Node
var _client_state: Node
var _client_id: int = 0
## What the client heard: seqs of event_applied, seqs of company_state_restored and, for each
## Inventory.stock_changed, how many restores had been heard then.
var _client_events: Array[int] = []
var _restored: Array[int] = []
var _stock_signals: Array[int] = []
var _snapshot_asks: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_size_and_parts()

	var host_side := Node.new()
	host_side.name = "HostSide"
	root.add_child(host_side)
	var client_side := Node.new()
	client_side.name = "ClientSide"
	root.add_child(client_side)
	set_multiplayer(SceneMultiplayer.new(), host_side.get_path())
	set_multiplayer(SceneMultiplayer.new(), client_side.get_path())
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 2) == OK,
		"The test hosts an ENet session on localhost:%d" % PORT)
	host_side.multiplayer.multiplayer_peer = server
	_host_state = _new_state()
	_host_net = _add_net(host_side, _host_state)
	_setup_host()
	await _check_host_alone()

	var client := ENetMultiplayerPeer.new()
	_expect(client.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	client_side.multiplayer.multiplayer_peer = client
	_client_state = _new_state()
	_client_net = _add_net(client_side, _client_state)
	# What CompanyRoot does on a client: nothing of its own, every event held until the snapshot.
	_client_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_side.multiplayer.get_peers().size() == 1 \
			and client_side.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		_client_id = client_side.multiplayer.get_unique_id()
		_listen_client()
		await _check_late_join()
		await _check_gap_recovery()
		_check_chunks()

	client.close()
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
		print("PASS: CompanyNet snapshot: late join after 50 events equal to the host, 300 units"
			+ " under 64 KB, gap recovery in chunks, bad chunks and snapshots refused")
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


## The host's company: money moves, a gate, district reputation, an order holding stock.
func _setup_host() -> void:
	_host_state.call(&"new_company", "Late Join SRL")
	_host_state.call(&"earn", 320, &"order_paid")
	_host_state.call(&"charge", 100, &"rent")
	_host_state.call(&"open_gate", &"gate_campo")
	_host_state.set(&"clock_minutes", 11 * 60 + 15)
	(_host_state.get(&"district_reputation") as Dictionary)[&"centro"] = 62.5
	_host_net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	_host_net.player_origin = func(_peer: int) -> Variant: return Vector3(0.0, 0.0, 1.0)
	_host_net.inventory = _host_state.call(&"stock")
	_host_net.inventory.receive(&"hen", 120, &"dock")
	_host_net.inventory.receive(&"puppy", 6, &"pallet:p2")
	_host_net.inventory.reserve(&"hen", 4, &"order_1")
	# A day under way: a ledger of 60 movements and 30 pallets, enough to cut in many chunks.
	for i: int in range(60):
		_host_state.call(&"earn", 17 + i * 3, &"order_paid")
	for i: int in range(30):
		_host_net.inventory.receive(PRODUCTS[i % PRODUCTS.size()], 1 + i % 5,
			StringName("pallet:p%d" % (10 + i)))
	_host_net.snapshot_requested.connect(func(peer: int) -> void: _snapshot_asks.append(peer))


static func _stations() -> Dictionary:
	return {
		&"dock": {"location": &"dock", "spot": Vector3(-1.0, 0.0, 0.0)},
		&"bin": {"location": &"cart:c1", "spot": Vector3(-1.0, 0.0, 1.0)},
	}


func _listen_client() -> void:
	_client_net.event_applied.connect(func(seq: int, _kind: StringName, _data: Dictionary) -> void:
		_client_events.append(seq))
	_client_net.company_state_restored.connect(func(seq: int) -> void: _restored.append(seq))
	_client_net.inventory.stock_changed.connect(
		func(_product: StringName, _location: StringName) -> void:
			_stock_signals.append(_restored.size()))


## 300 units over 150 locations, 20 reservations, a full ledger, gates, a layout of 40 pieces.
func _check_size_and_parts() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Galpón de 300")
	for i: int in range(CompanyTuning.LEDGER_MAX + 20):
		state.call(&"earn", 10 + i, &"order_paid")
	for gate: StringName in [&"gate_centro", &"gate_campo", &"gate_puerto"]:
		state.call(&"open_gate", gate)
	var layout: Array[Dictionary] = []
	for i: int in range(40):
		layout.append({"id": &"shelf_basic", "x": i % 8, "z": i % 5, "turns": i % 4})
	state.set(&"layout", layout)
	var fleet: Array[Dictionary] = [{"vehicle": &"van", "plate": "TMP-001"}]
	state.set(&"fleet", fleet)
	var host := CompanyNet.new()
	host.company = state
	for i: int in range(150):
		host.inventory.receive(PRODUCTS[i % PRODUCTS.size()], 2, StringName("shelf:rack_%03d" % i))
	for i: int in range(20):
		host.inventory.reserve(PRODUCTS[i % PRODUCTS.size()], 1, StringName("order_%d" % i))
	host.seq = 412
	_expect(host.inventory.total_units() == 300, "The shed holds 300 units (got %d)"
		% host.inventory.total_units())
	var data: Dictionary = host.snapshot()
	var packed: Dictionary = CompanyNet.pack_snapshot(data)
	var chunks: Array[PackedByteArray] = packed.get("chunks", [] as Array[PackedByteArray])
	var weight: int = chunks[0].size() if chunks.size() == 1 else -1
	_expect(chunks.size() == 1 and weight > 0 and weight < 64 * 1024,
		"A snapshot of 300 units is one chunk under 64 KB (%d chunks, %d bytes, %d uncompressed)"
		% [chunks.size(), weight, int(packed.get("size", 0))])
	var company_part: Dictionary = data.get("company", {})
	_expect(not company_part.is_empty() and not company_part.has("inventory"),
		"The company in the snapshot leaves its stored stock out: the live one is `inventory`")
	var back: Dictionary = CompanyNet.unpack_snapshot(chunks[0], int(packed.get("size", 0)))
	_expect(back == data, "It unpacks to the same dictionary")

	var floor_units: Dictionary = {"floor:1": {"product": &"hen", "qty": 2, "pos": Vector3(1, 0, 2)}}
	var take: Callable = func() -> Variant: return floor_units
	var nothing: Callable = func(_value: Variant) -> bool: return true
	_expect(host.add_snapshot_part("floor", take, nothing), "A snapshot part can be added")
	_expect(not host.add_snapshot_part("floor", take, nothing)
		and not host.add_snapshot_part("seq", take, nothing)
		and not host.add_snapshot_part("company", take, nothing)
		and not host.add_snapshot_part("orders", Callable(), nothing),
		"A repeated or reserved key, or an invalid callable, is refused")

	var client_state: Node = _new_state()
	var client := CompanyNet.new()
	client.company = client_state
	var received: Array = []
	client.add_snapshot_part("floor", take, func(value: Variant) -> bool:
		received.append(value)
		return value is Dictionary)
	var restored: Array[int] = []
	client.company_state_restored.connect(func(seq: int) -> void: restored.append(seq))
	var with_part: Dictionary = host.snapshot()
	_expect(client.apply_snapshot(with_part) and restored == [412] and client.seq == 412,
		"A client applies it: seq 412, one company_state_restored (got %s)" % [restored])
	_expect(client.inventory.to_dict() == host.inventory.to_dict()
		and client.inventory.reserved_by(&"order_3") == host.inventory.reserved_by(&"order_3"),
		"...the stock with its reservations is the host's")
	_expect(_company(client_state) == _company(state) and bool(client_state.call(&"is_active")),
		"...the company is the host's and switched on (money %s)" % client_state.get(&"money"))
	_expect((client_state.get(&"inventory") as Dictionary) == host.inventory.to_dict(),
		"...and the client's CompanyState mirror holds the live stock")
	_expect(received == [floor_units], "...and the part reached its put (got %s)" % [received])

	var good: Dictionary = host.snapshot()
	var bad_cases: Array = [
		[_with(good, "seq", 411), "a seq older than the one applied"],
		[_with(good, "seq", "412"), "a seq that isn't an int"],
		[_with(good, "inventory", {"stock": {&"hen": {&"dock": "3"}}}), "a qty that is text"],
		[_with(good, "inventory", {"stock": {&"hen": {&"dock": 0}}}), "a qty of 0"],
		[_with(good, "inventory", {"stock": [1, 2]}), "a stock that is an Array"],
		[_with(good, "inventory", {"stock": {}, "extra": {}}), "an unknown stock key"],
		[_with(good, "inventory", {"stock": {&"hen": {"x".repeat(300): 1}}}), "a huge location id"],
		[_with(good, "company", [1]), "a company that isn't a Dictionary"],
	]
	for case: Array in bad_cases:
		_expect(not client.apply_snapshot(case[0]) and restored.size() == 1,
			"A snapshot with %s is refused" % case[1])
	_expect(client.inventory.to_dict() == host.inventory.to_dict(),
		"...and the refused ones changed nothing")
	_expect(not client.apply_snapshot(_with(good, "floor", 7)) and restored.size() == 1
		and client.awaiting_snapshot(),
		"A part that refuses its value fails the snapshot and the client waits for another")
	client.free()
	host.free()
	state.free()
	client_state.free()


## Before anyone joins: 50 events, the host's own requests.
func _check_host_alone() -> void:
	var take: Dictionary = {"station": &"dock", "product": &"hen", "qty": 1}
	var store: Dictionary = {"station": &"bin", "product": &"hen", "qty": 1}
	for i: int in range(25):
		_host_net.request(&"units_take", take)
		_host_net.request(&"units_store", store)
	_expect(_host_net.seq == 50 and _host_net.inventory.count(&"hen", &"cart:c1") == 25,
		"The host plays 50 events alone (seq %d)" % _host_net.seq)
	_expect(not _host_net.send_snapshot(7) and not _host_net.send_snapshot(1),
		"The host sends no snapshot to an unknown peer or to itself")
	_expect(not _host_net.apply_snapshot(_host_net.snapshot()), "The host never applies a snapshot")
	await process_frame


func _check_late_join() -> void:
	var take: Dictionary = {"station": &"dock", "product": &"hen", "qty": 1}
	var store: Dictionary = {"station": &"bin", "product": &"hen", "qty": 1}
	# Two events reach the client before its world counts as ready: the snapshot covers them.
	_host_net.request(&"units_take", take)
	_host_net.request(&"units_store", store)
	var held: bool = await _wait_for(func() -> bool: return _client_net._held.size() == 2)
	_expect(held and _client_net.seq == 0 and _client_events.is_empty()
		and _client_net.inventory.total_units() == 0,
		"The joining client holds events 51 and 52 without applying them")
	var stock_at_snapshot: Dictionary = _host_net.inventory.to_dict()
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	_expect(network != null and network.has_signal(&"peer_level_ready"),
		"NetworkManager is there to say the client's world is up")
	if network != null:
		network.emit_signal(&"peer_level_ready", _client_id)
	else:
		_host_net.send_snapshot(_client_id)
	_host_net.request(&"units_take", take)
	_host_net.request(&"units_store", store)
	_host_net.request(&"units_take", take)
	var caught_up: bool = await _wait_for(func() -> bool:
		return _client_net.seq == 55 and not _restored.is_empty())
	_expect(caught_up and _host_net.seq == 55,
		"The client catches up with the host (client seq %d, host %d)"
		% [_client_net.seq, _host_net.seq])
	_expect(_restored == [52],
		"The snapshot was sent at seq 52 and restored once (got %s)" % [_restored])
	_expect(_client_events == [53, 54, 55],
		"Events 51 and 52 are dropped, 53 to 55 applied in order (got %s)" % [_client_events])
	_expect(_client_net.inventory.to_dict() == _host_net.inventory.to_dict(),
		"The client's stock is the host's, reservations included")
	_expect(_client_net.inventory.reserved_by(&"order_1") == {&"hen": 4},
		"The order's reservation came with it (got %s)"
		% [_client_net.inventory.reserved_by(&"order_1")])
	_expect(_company(_client_state) == _company(_host_state)
		and bool(_client_state.call(&"is_active")),
		"The client's CompanyState is the host's (money %s, clock %s)"
		% [_client_state.get(&"money"), _client_state.get(&"clock_minutes")])
	_expect((_client_state.get(&"inventory") as Dictionary) == stock_at_snapshot,
		"Its stock mirror is the host's live stock at the snapshot")
	_expect(_stock_signals.size() == 6 and not _stock_signals.has(0),
		"No stock_changed fired for the snapshot, only for the 3 events after it (%s)"
		% [_stock_signals])
	_expect(not _client_net.awaiting_snapshot() and _snapshot_asks.is_empty(),
		"The client stops waiting without ever asking: the host sent it when it was ready")


## An event the client never got: it asks, and a snapshot cut in many chunks puts it right.
func _check_gap_recovery() -> void:
	_host_net.snapshot_chunk_bytes = 512
	var pieces: int = (CompanyNet.pack_snapshot(_host_net.snapshot(), 512)["chunks"] as Array).size()
	_expect(pieces >= 3, "The host's snapshot takes %d chunks of 512 bytes" % pieces)
	var events_before: int = _client_events.size()
	_host_net.seq += 1
	_host_net.request(&"units_take", {"station": &"dock", "product": &"hen", "qty": 1})
	var restored: bool = await _wait_for(func() -> bool:
		return _restored.size() == 2 and _client_net.seq == _host_net.seq)
	_expect(restored and _snapshot_asks == [_client_id],
		"A seq gap makes the client ask and the host's snapshot arrive (asks %s, restored %s)"
		% [_snapshot_asks, _restored])
	_expect(_restored.back() == _host_net.seq and _client_events.size() == events_before,
		"It covers the event after the gap, which is not applied on its own (seq %d)"
		% _client_net.seq)
	_expect(_client_net.inventory.to_dict() == _host_net.inventory.to_dict()
		and not _client_net.awaiting_snapshot(),
		"After the chunked snapshot the client's stock is the host's")
	_host_net.request(&"units_store", {"station": &"bin", "product": &"hen", "qty": 1})
	var next: bool = await _wait_for(func() -> bool: return _client_net.seq == _host_net.seq)
	_expect(next and _client_events.size() == events_before + 1
		and _client_net.inventory.to_dict() == _host_net.inventory.to_dict(),
		"The next event applies as usual")
	_host_net.snapshot_chunk_bytes = CompanyNet.SNAPSHOT_CHUNK_BYTES


## The receiving side alone (a client CompanyNet out of the tree), chunk by chunk.
func _check_chunks() -> void:
	var data: Dictionary = _host_net.snapshot()
	var snap_seq: int = data["seq"]
	var packed: Dictionary = CompanyNet.pack_snapshot(data, 256)
	var chunks: Array[PackedByteArray] = packed["chunks"]
	var size: int = packed["size"]
	var count: int = chunks.size()
	_expect(count >= 4, "Cut every 256 bytes the snapshot takes %d chunks" % count)
	var state: Node = _new_state()
	var rx := CompanyNet.new()
	rx.company = state
	var restored: Array[int] = []
	var events: Array[int] = []
	rx.company_state_restored.connect(func(seq: int) -> void: restored.append(seq))
	rx.event_applied.connect(func(seq: int, _kind: StringName, _data: Dictionary) -> void:
		events.append(seq))
	var too_big := PackedByteArray()
	too_big.resize(CompanyNet.SNAPSHOT_CHUNK_BYTES + 1)
	var max_chunks: int = CompanyNet.SNAPSHOT_MAX_CHUNKS
	var bad: Array = [
		[0, 0, count, size, chunks[0], "id 0"],
		[5, count, count, size, chunks[0], "an index past the total"],
		[5, -1, count, size, chunks[0], "a negative index"],
		[5, 0, 0, size, chunks[0], "a total of 0"],
		[5, 0, max_chunks + 1, size, chunks[0], "a total over SNAPSHOT_MAX_CHUNKS"],
		[5, 0, count, 0, chunks[0], "a size of 0"],
		[5, 0, count, CompanyNet.SNAPSHOT_MAX_BYTES + 1, chunks[0], "a size over the limit"],
		[5, 0, count, size, PackedByteArray(), "no bytes"],
		[5, 0, count, size, too_big, "a chunk over SNAPSHOT_CHUNK_BYTES"],
	]
	for case: Array in bad:
		rx._snapshot(case[0], case[1], case[2], case[3], case[4])
	_expect(not rx.awaiting_snapshot() and rx._rx_id == 0,
		"Malformed chunks (%s) start nothing" % ", ".join(bad.map(func(c: Array) -> String:
			return c[5])))

	# Snapshot 5, last chunk first, one repeated, one of an older snapshot and one that
	# doesn't match in between; chunk 0 comes last.
	for index: int in range(count - 1, 0, -1):
		rx._snapshot(5, index, count, size, chunks[index])
		if index == count - 1:
			rx._snapshot(5, index, count, size, chunks[index])
			rx._snapshot(4, 0, 2, size, chunks[0])
			rx._snapshot(5, 0, count + 1, size, chunks[0])
	_expect(rx.awaiting_snapshot() and restored.is_empty() and rx.inventory.total_units() == 0,
		"With chunk 0 missing nothing is applied and the client holds events")
	# Events while chunks are missing: two after the snapshot (out of order), two it covers.
	var move: Dictionary = {"product": &"hen", "qty": 1, "from": &"dock", "to": &"cart:c1"}
	rx._apply_event(snap_seq + 2, &"units_moved", move)
	rx._apply_event(snap_seq + 1, &"units_moved", move)
	rx._apply_event(snap_seq, &"units_moved", move)
	rx._apply_event(snap_seq - 3, &"units_moved", move)
	var expected := Inventory.new()
	expected.from_dict(data["inventory"])
	expected.move(&"hen", 1, &"dock", &"cart:c1")
	expected.move(&"hen", 1, &"dock", &"cart:c1")
	rx._snapshot(5, 0, count, size, chunks[0])
	_expect(restored == [snap_seq] and events == [snap_seq + 1, snap_seq + 2],
		"The last chunk applies it once, then the 2 held events after it in order"
		+ " (restored %s, events %s)" % [restored, events])
	_expect(rx.inventory.to_dict() == expected.to_dict() and rx.seq == snap_seq + 2
		and not rx.awaiting_snapshot(),
		"...leaving the snapshot's stock plus those 2 moves (seq %d)" % rx.seq)
	_expect(_company(state) == _company(_host_state), "...and the host's company")

	rx._snapshot(5, 1, count, size, chunks[1])
	for index: int in range(count):
		rx._snapshot(3, index, count, size, chunks[index])
	_expect(restored.size() == 1 and not rx.awaiting_snapshot(),
		"A chunk of the finished snapshot or a whole older one changes nothing")

	var garbage := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	rx._snapshot(6, 0, 2, 1000, garbage)
	rx._snapshot(6, 1, 2, 1000, garbage)
	_expect(restored.size() == 1 and rx.awaiting_snapshot(),
		"Chunks that don't decompress are refused and the client waits for another snapshot")
	var list_bytes: PackedByteArray = var_to_bytes([1, 2, 3])
	rx._snapshot(7, 0, 1, list_bytes.size(),
		list_bytes.compress(CompanyNet.SNAPSHOT_COMPRESSION))
	_expect(restored.size() == 1 and rx.awaiting_snapshot(),
		"A snapshot that isn't a Dictionary is refused")
	var bad_stock: Dictionary = CompanyNet.pack_snapshot(
		_with(_with(data, "seq", rx.seq), "inventory", {"stock": {&"hen": {&"dock": 1.5}}}))
	rx._snapshot(8, 0, 1, bad_stock["size"], bad_stock["chunks"][0])
	_expect(restored.size() == 1 and rx.awaiting_snapshot(),
		"A snapshot whose stock has a float qty is refused")
	var good: Dictionary = CompanyNet.pack_snapshot(_with(data, "seq", rx.seq), 256)
	var good_chunks: Array[PackedByteArray] = good["chunks"]
	for index: int in range(good_chunks.size()):
		rx._snapshot(9, index, good_chunks.size(), good["size"], good_chunks[index])
	_expect(restored.size() == 2 and not rx.awaiting_snapshot()
		and rx.inventory.to_dict() == data["inventory"],
		"The next good snapshot puts it right (restored %s)" % [restored])
	rx.free()
	state.free()


## CompanyState.to_dict() without its stored stock: what must match across peers.
static func _company(state: Node) -> Dictionary:
	var data: Dictionary = state.call(&"to_dict")
	data.erase("inventory")
	return data


static func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate(true)
	copy[key] = value
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
