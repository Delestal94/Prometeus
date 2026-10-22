extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_shop_net.gd
##
## Only the host spends in the company shop (expansion D-0518, which merges D-0428: company_shop_net.gd
## through CompanyNet; contract docs/expansion-distritos/diseno/red-autoridad.md, row 25 and section 13):
## - CompanyShopNet alone: a request that is not the host's own is host_only, whatever it carries; the host's
##   for an enabled item of the catalog (a StringName or text) is one shop_bought {item, money: the balance
##   after it, minute} and checking writes nothing; an item that is not text, empty, too long, a path, of
##   another case, unknown or disabled (the real catalog's bike) is bad_data, and so is a missing company;
##   CompanyShop's refusals come back as its keys (WORLD_SHOP_WRONG_STAGE, _NEEDS_ITEM, _CANNOT_AFFORD,
##   _ALREADY_OWNED);
## - apply(): the purchase with CompanyShop.buy() (a machine into equipment, an expansion moves
##   warehouse_stage, a vehicle into fleet) and its ledger entry `shop` with the host's balance and minute;
##   a mirror whose wallet was off ends on the host's money and flags the drift once (take_drift()), its
##   clock_minutes untouched; an event that does not fit (a key missing or extra, an unknown or non-text
##   item, money negative, a float or past MAX_MONEY, a minute out of the day or as text, an item owned
##   already, a machine without what it requires, an expansion out of order, no company) is refused and
##   changes nothing;
## - solo (offline, the host is peer 1) with the real catalog (data/shop/): CompanyNet.request(shop_buy)
##   buys at once, one seq; buying it again is WORLD_SHOP_ALREADY_OWNED and a non-text item bad_data, both
##   with no seq; a nested field in the request is dropped without a word (RpcGuard.dict_ok); an item as
##   text buys too;
## - a host and a client by ENet in one process, then a late joiner (each its own CompanyNet and company,
##   all on one test catalog with an enabled vehicle): the client asking to buy hears host_only, also with
##   `peer: 1` in its data (rule 3) and with a non-text item; only it hears it, no seq is spent, nothing is
##   written on the client ahead of the host and nothing changes on either peer; a nested field from the
##   client is dropped with no answer; the host buys a machine, an expansion and a vehicle and both peers
##   end with the same money, equipment, warehouse_stage, fleet and ledger (the client's entries with the
##   host's minute, its clock_minutes untouched); the host short of money is refused with
##   WORLD_SHOP_CANNOT_AFFORD, an item it owns with _ALREADY_OWNED, an unknown or non-text one with bad_data,
##   a nested field dropped, and none changes anything; the host's wallet moved without an event (a bug
##   elsewhere) and its next purchase: the client ends it on the host's balance, asks for a snapshot and
##   gets it; a third peer joins late and gets every purchase from the snapshot's company part, then a
##   machine that requires one of them reaches all three; every peer applied the host's events in order
##   with no gap, and what reached the client is plain and small.
## Expected in the log: CompanyShopNet's warning for each wallet set right (the mirror check and the client
## after the host's silent earning) and its warning for the event with no company.

const PORT: int = 24685
const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
## A catalog of the test: four real items, the real bike enabled and a machine that requires the label reader.
const STARTED_BIKE: Array = [{"id": &"van_classic"}, {"vehicle": &"bike"}]
const CATALOG: String = "user://test_company_shop_net"
const COPIED: Array[String] = ["upgrade_1", "label_reader", "expansion_1", "expansion_2"]
const HOST_MINUTE: int = 9 * 60 + 30
const SENTINEL_MINUTE: int = 77
## Largest shop_bought, var_to_bytes (three short values).
const EVENT_BYTES_MAX: int = 200

var _failures: int = 0


class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var seqs: Array[int] = []
	var kinds: Array[StringName] = []
	var bought: Array[Dictionary] = []
	var refusals: Array = []
	var restored: Array[int] = []
	## {seq: [money, balance of the last ledger entry]} right after each event.
	var wallet_at: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_make_catalog()
	_test_helper()
	_test_solo()
	await _test_peers()
	_clean()
	if _failures == 0:
		print("PASS: only the host spends in the company shop; every peer and a late joiner end with its purchases")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)


func _make_catalog() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(CATALOG)
	for id: String in COPIED:
		var copy: ShopItem = (load("res://data/shop/%s.tres" % id) as ShopItem).duplicate()
		_expect(ResourceSaver.save(copy, CATALOG.path_join(id + ".tres")) == OK, "The test catalog takes %s" % id)
	var bike: ShopItem = (load("res://data/shop/vehicle_bike.tres") as ShopItem).duplicate()
	bike.enabled = true
	_expect(ResourceSaver.save(bike, CATALOG.path_join("vehicle_bike.tres")) == OK, "...and the bike, enabled")
	var sorter := ShopItem.new()
	sorter.id = &"test_sorter"
	sorter.display_key = "WORLD_SHOP_LABEL_READER"
	sorter.kind = &"machine"
	sorter.price = 100
	sorter.grant_key = &"test_sorter"
	sorter.requires = &"label_reader"
	_expect(ResourceSaver.save(sorter, CATALOG.path_join("test_sorter.tres")) == OK,
		"...and a machine that requires one")
	var ids: Array = CompanyShop.items(CATALOG).map(func(item: ShopItem) -> StringName: return item.id)
	_expect(ids == [&"expansion_1", &"expansion_2", &"label_reader", &"test_sorter", &"upgrade_1", &"vehicle_bike"],
		"The test catalog lists its six items (got %s)" % [ids])


func _new_state(money: int, minute: int = HOST_MINUTE) -> Node:
	var state: Node = STATE_SCRIPT.new()
	state.call(&"new_company", "Shop SRL")
	state.set(&"money", money)
	state.set(&"clock_minutes", minute)
	return state


# --- CompanyShopNet alone ---


func _test_helper() -> void:
	var shop := CompanyShopNet.new()
	shop.dir = CATALOG
	var state: Node = _new_state(1000)
	var before: Dictionary = state.call(&"to_dict")
	for data: Dictionary in [{"item": &"upgrade_1"}, {"item": 5}, {}]:
		_expect(shop.check(state, data, false) == {"reason": CompanyShopNet.REASON_HOST_ONLY},
			"A request that is not the host's own is host_only (%s)" % [data])
	var ask: Dictionary = shop.check(state, {"item": &"upgrade_1", "rid": 1}, true)
	var event: Dictionary = {"item": &"upgrade_1", "money": 550, "minute": HOST_MINUTE}
	_expect(ask == {"reason": &"", "kind": CompanyShopNet.BOUGHT, "data": event},
		"The host's request is one shop_bought with the balance after it and its minute (got %s)" % [ask])
	_expect(shop.check(state, {"item": "upgrade_1", "rid": 2}, true) == ask, "...the item as text too")
	_expect(state.call(&"to_dict") == before, "Checking writes nothing")
	var bad_items: Array = [5, 2.5, true, Vector3.ONE, null, "", "ghost", "x".repeat(RpcGuard.MAX_TEXT_LENGTH + 1),
		"res://data/shop/upgrade_1.tres", "UPGRADE_1", &"vehicle_van"]
	for item: Variant in bad_items:
		_expect(shop.check(state, {"item": item}, true) == {"reason": CompanyShopNet.REASON_BAD_DATA},
			"Item %s is bad_data" % [str(item).left(30)])
	_expect(shop.check(state, {}, true) == {"reason": CompanyShopNet.REASON_BAD_DATA}, "No item is bad_data")
	_expect(CompanyShopNet.new().check(state, {"item": &"vehicle_bike"}, true)
		== {"reason": CompanyShopNet.REASON_BAD_DATA}, "The real catalog's bike is disabled: bad_data")
	_expect(shop.check(null, {"item": &"upgrade_1"}, true) == {"reason": CompanyShopNet.REASON_BAD_DATA},
		"No company is bad_data")
	_expect(shop.check(state, {"item": &"expansion_2"}, true) == {"reason": CompanyShop.WRONG_STAGE},
		"An expansion out of order is WORLD_SHOP_WRONG_STAGE")
	_expect(shop.check(state, {"item": &"test_sorter"}, true) == {"reason": CompanyShop.NEEDS_ITEM},
		"A machine without what it requires is WORLD_SHOP_NEEDS_ITEM")
	state.set(&"money", 100)
	_expect(shop.check(state, {"item": &"upgrade_1"}, true) == {"reason": CompanyShop.CANNOT_AFFORD},
		"A short wallet is WORLD_SHOP_CANNOT_AFFORD")
	state.set(&"money", 1000)
	_expect(state.call(&"to_dict") == before, "No refusal changed anything")
	# Applied where it was checked (the host): the purchase, the entry with the host's minute.
	_expect(shop.apply(state, event) and int(state.get(&"money")) == 550
		and (state.get(&"equipment") as Array) == [&"upgrade_1"],
		"Applying it buys: 550 left, upgrade_1 in equipment (%s)" % [state.get(&"equipment")])
	_expect(_last_entry(state) == {"day": state.get(&"day"), "minute": HOST_MINUTE, "amount": -450, "reason": "shop",
		"balance": 550}, "...with its entry `shop` (%s)" % [_last_entry(state)])
	_expect(not shop.take_drift(), "...and the host never drifts")
	_expect(shop.check(state, {"item": &"upgrade_1"}, true) == {"reason": CompanyShop.ALREADY_OWNED},
		"Buying it again is WORLD_SHOP_ALREADY_OWNED")
	# A mirror whose wallet missed something ends on the host's balance and flags it once.
	var mirror: Node = _new_state(700, SENTINEL_MINUTE)
	var applied: bool = shop.apply(mirror, event)
	var entry: Dictionary = _last_entry(mirror)
	_expect(applied and int(mirror.get(&"money")) == 550 and int(entry.get("balance", -1)) == 550
		and int(entry.get("minute", -1)) == HOST_MINUTE and int(mirror.get(&"clock_minutes")) == SENTINEL_MINUTE,
		"A mirror holding 700 ends on the host's 550 and minute, its clock_minutes untouched (%s)" % [entry])
	_expect(shop.take_drift() and not shop.take_drift(), "...and flags the drift once")
	_check_broken_events(shop, state)
	var grown: Node = _new_state(800)
	_expect(shop.apply(grown, {"item": &"expansion_1", "money": 0, "minute": HOST_MINUTE})
		and int(grown.get(&"warehouse_stage")) == 1 and int(grown.get(&"money")) == 0,
		"An expansion moves warehouse_stage to 1 (%s)" % grown.get(&"warehouse_stage"))
	grown.set(&"money", 300)
	_expect(shop.apply(grown, {"item": &"vehicle_bike", "money": 50, "minute": HOST_MINUTE})
		and (grown.get(&"fleet") as Array) == STARTED_BIKE and int(grown.get(&"money")) == 50,
		"A vehicle goes into the fleet (%s)" % [grown.get(&"fleet")])
	_expect(not shop.take_drift(), "...and a wallet that matched the host's flags no drift")
	state.free()
	mirror.free()
	grown.free()


## Events that do not fit `state` (it owns upgrade_1, stage 0, no label reader) change nothing.
func _check_broken_events(shop: CompanyShopNet, state: Node) -> void:
	var before: Dictionary = state.call(&"to_dict")
	var broken: Array[Dictionary] = [
		{"item": &"label_reader", "money": 100},
		{"item": &"label_reader", "money": 100, "minute": HOST_MINUTE, "extra": 1},
		{"item": &"ghost", "money": 100, "minute": HOST_MINUTE},
		{"item": 7, "money": 100, "minute": HOST_MINUTE},
		{"item": &"label_reader", "money": -1, "minute": HOST_MINUTE},
		{"item": &"label_reader", "money": 100.0, "minute": HOST_MINUTE},
		{"item": &"label_reader", "money": CompanyShopNet.MAX_MONEY + 1, "minute": HOST_MINUTE},
		{"item": &"label_reader", "money": 100, "minute": CompanyTuning.MINUTES_PER_DAY},
		{"item": &"label_reader", "money": 100, "minute": str(HOST_MINUTE)},
		{"item": &"upgrade_1", "money": 100, "minute": HOST_MINUTE},
		{"item": &"test_sorter", "money": 100, "minute": HOST_MINUTE},
		{"item": &"expansion_2", "money": 100, "minute": HOST_MINUTE},
	]
	for event: Dictionary in broken:
		_expect(not shop.apply(state, event) and state.call(&"to_dict") == before, "apply() refuses %s" % [event])
	_expect(not shop.apply(null, {"item": &"label_reader", "money": 100, "minute": HOST_MINUTE}),
		"apply() with no company refuses")
	_expect(not shop.take_drift(), "No refused event set the wallet (no drift)")


# --- Solo ---


func _test_solo() -> void:
	var state: Node = _new_state(2000)
	state.name = "SoloCompany"
	root.add_child(state)
	var solo := CompanyNet.new()
	solo.name = "SoloShopNet"
	solo.company = state
	root.add_child(solo)
	var refusals: Array = []
	solo.request_rejected.connect(func(rid: int, reason: StringName) -> void: refusals.append([rid, reason]))
	_expect(solo.is_host() and solo.multiplayer.get_unique_id() == 1, "Offline, this peer is the host, peer 1")
	solo.request(CompanyShopNet.BUY, {"item": &"upgrade_1"})
	_expect(refusals.is_empty() and solo.seq == 1 and int(state.get(&"money")) == 1550
		and (state.get(&"equipment") as Array) == [&"upgrade_1"] and _last_entry(state).get("reason") == "shop",
		"Solo, buying the real catalog's upgrade_1 applies at once as event 1 (money %d, refusals %s)"
		% [state.get(&"money"), refusals])
	var again: int = solo.request(CompanyShopNet.BUY, {"item": &"upgrade_1"})
	var odd: int = solo.request(CompanyShopNet.BUY, {"item": 5})
	_expect(refusals == [[again, CompanyShop.ALREADY_OWNED], [odd, CompanyShopNet.REASON_BAD_DATA]] and solo.seq == 1,
		"Buying it again is WORLD_SHOP_ALREADY_OWNED and a non-text item bad_data, no seq (got %s)" % [refusals])
	var nested: int = solo.request(CompanyShopNet.BUY, {"item": &"label_reader", "extra": {"a": 1}})
	_expect(nested > 0 and refusals.size() == 2 and solo.seq == 1 and int(state.get(&"money")) == 1550,
		"A nested field is dropped without a word (refusals %s, seq %d)" % [refusals, solo.seq])
	solo.request(CompanyShopNet.BUY, {"item": "label_reader"})
	_expect(solo.seq == 2 and int(state.get(&"money")) == 950
		and (state.get(&"equipment") as Array).has(&"label_reader"),
		"An item as text buys too (money %d)" % state.get(&"money"))
	solo.free()
	state.free()


# --- Two peers and a late joiner ---


func _make_peer(side_name: String, money: int) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = _new_state(money)
	peer.state.name = "Company"
	peer.side.add_child(peer.state)
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.net.shop.dir = CATALOG
	peer.side.add_child(peer.net)
	peer.net.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		peer.seqs.append(seq)
		peer.kinds.append(kind)
		peer.wallet_at[seq] = [int(peer.state.get(&"money")), int(_last_entry(peer.state).get("balance", 0))]
		if kind == CompanyShopNet.BOUGHT:
			peer.bought.append(data))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void: peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))
	return peer


func _test_peers() -> void:
	var host: Peer = _make_peer("HostSide", 1500)
	var client: Peer = _make_peer("ClientSide", 0)
	var late: Peer = _make_peer("LateSide", 0)
	var server := ENetMultiplayerPeer.new()
	var client_peer := ENetMultiplayerPeer.new()
	var late_peer := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 3) == OK
	_expect(up, "The test hosts an ENet session on localhost:%d" % PORT)
	host.side.multiplayer.multiplayer_peer = server
	up = up and client_peer.create_client("127.0.0.1", PORT) == OK
	client.side.multiplayer.multiplayer_peer = client_peer
	client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host.side.multiplayer.get_peers().size() == 1 and client.side.multiplayer.get_peers().has(1))
	_expect(up and connected, "The client connects to the host")
	if connected and await _join(host, client):
		_expect(_wallet(client) == _wallet(host), "The client's company is the host's after the snapshot")
		await _check_client_asks(host, client)
		await _check_host_buys(host, client)
		await _check_host_refusals(host, client)
		await _check_silent_money(host, client)
		await _check_late_join(host, client, late, late_peer)
		_check_seqs(host, [client, late])
	client_peer.close()
	late_peer.close()
	server.close()
	await process_frame
	for peer: Peer in [host, client, late]:
		set_multiplayer(null, peer.side.get_path())
		peer.side.free()
	RpcGuard.reset()


## The host sends `peer` its snapshot (as when that peer's world comes up); true once it is in.
func _join(host: Peer, peer: Peer) -> bool:
	_expect(host.net.send_snapshot(peer.side.multiplayer.get_unique_id()),
		"The host sends %s its snapshot" % peer.side.name)
	var joined: bool = await _wait_for(func() -> bool:
		return not peer.net.awaiting_snapshot() and peer.net.seq == host.net.seq)
	_expect(joined, "%s joins at the host's seq %d" % [peer.side.name, host.net.seq])
	return joined


## The client may ask; only the host spends: host_only to the client only, nothing changes anywhere.
func _check_client_asks(host: Peer, client: Peer) -> void:
	var seq: int = host.net.seq
	var host_before: Dictionary = _wallet(host)
	var client_before: Dictionary = _wallet(client)
	var heard: int = host.refusals.size()
	var asks: Array[Dictionary] = [{"item": &"upgrade_1"}, {"item": &"upgrade_1", "peer": 1}, {"item": 5}]
	var rids: Array[int] = []
	for ask: Dictionary in asks:
		rids.append(client.net.request(CompanyShopNet.BUY, ask))
	_expect(not rids.has(0) and _wallet(client) == client_before,
		"The client's requests go and nothing is written on the client ahead of the host (rids %s)" % [rids])
	var answered: bool = await _wait_for(func() -> bool: return client.refusals.size() >= asks.size())
	var reasons: Array = rids.map(func(rid: int) -> StringName: return _heard(client.refusals, rid))
	_expect(answered and reasons == [CompanyShopNet.REASON_HOST_ONLY, CompanyShopNet.REASON_HOST_ONLY,
			CompanyShopNet.REASON_HOST_ONLY],
		"The client hears host_only, also with peer: 1 in its data and a non-text item (got %s)" % [reasons])
	# A nested field: the host's RpcGuard.dict_ok drops it. The next request (same reliable channel) is
	# answered only after the host went past it.
	var nested: int = client.net.request(CompanyShopNet.BUY, {"item": &"upgrade_1", "extra": {"a": 1}})
	var next: int = client.net.request(CompanyShopNet.BUY, {"item": &"label_reader"})
	var after: bool = await _wait_for(func() -> bool: return _heard(client.refusals, next) != &"")
	_expect(after and nested > 0 and _heard(client.refusals, nested) == &""
		and _heard(client.refusals, next) == CompanyShopNet.REASON_HOST_ONLY,
		"A nested field from the client is dropped with no answer (refusals %s)" % [client.refusals])
	_expect(host.refusals.size() == heard and host.net.seq == seq and client.net.seq == seq,
		"...only the client hears anything and no seq is spent (seq %d)" % host.net.seq)
	_expect(_wallet(host) == host_before and _wallet(client) == client_before,
		"...and nothing changed on either peer")


## The host buys a machine, an expansion and a vehicle: both peers end equal, the client's entries with the
## host's minute.
func _check_host_buys(host: Peer, client: Peer) -> void:
	host.state.set(&"clock_minutes", HOST_MINUTE)
	client.state.set(&"clock_minutes", SENTINEL_MINUTE)
	for item: StringName in [&"upgrade_1", &"expansion_1", &"vehicle_bike"]:
		var seq: int = host.net.seq
		var reason: StringName = _ask(host, {"item": item})
		var synced: bool = await _synced(host, [client])
		_expect(reason == &"" and host.net.seq == seq + 1 and synced,
			"The host buys %s and the client follows (refused %s)" % [item, reason])
		_expect(_wallet(client) == _wallet(host), "...both peers hold the same company after %s" % item)
	var bought: Dictionary = _wallet(host)
	_expect(bought["money"] == 0 and bought["equipment"] == [&"upgrade_1"] and bought["warehouse_stage"] == 1
		and bought["fleet"] == STARTED_BIKE,
		"1500 spent on upgrade_1, expansion_1 and the bike (%s)" % [bought])
	var entries: Array = (client.state.get(&"ledger") as Array).slice(-3)
	_expect(entries.map(func(entry: Dictionary) -> Array: return [entry["amount"], entry["reason"], entry["minute"]])
		== [[-450, "shop", HOST_MINUTE], [-800, "shop", HOST_MINUTE], [-250, "shop", HOST_MINUTE]],
		"The client's entries are `shop` with the host's minute (%s)" % [entries])
	_expect(int(client.state.get(&"clock_minutes")) == SENTINEL_MINUTE,
		"...and its clock_minutes is never written (%d)" % client.state.get(&"clock_minutes"))


## The host's refused requests: CompanyShop's key or bad_data, no seq, nothing anywhere.
func _check_host_refusals(host: Peer, client: Peer) -> void:
	var seq: int = host.net.seq
	var before: Dictionary = _wallet(host)
	var cases: Array = [
		[{"item": &"label_reader"}, CompanyShop.CANNOT_AFFORD],
		[{"item": &"upgrade_1"}, CompanyShop.ALREADY_OWNED],
		[{"item": &"ghost"}, CompanyShopNet.REASON_BAD_DATA],
		[{"item": &"vehicle_van"}, CompanyShopNet.REASON_BAD_DATA],
		[{"item": 5}, CompanyShopNet.REASON_BAD_DATA],
	]
	for case: Array in cases:
		var got: StringName = _ask(host, case[0])
		_expect(got == case[1], "The host buying %s is refused with %s (got %s)" % [case[0], case[1], got])
	var heard: int = host.refusals.size()
	host.net.request(CompanyShopNet.BUY, {"item": &"upgrade_1", "extra": {"a": 1}})
	_expect(host.refusals.size() == heard, "A nested field from the host is dropped without a word")
	for _frame: int in range(5):
		await process_frame
	_expect(host.net.seq == seq and client.net.seq == seq and _wallet(host) == before and _wallet(client) == before,
		"...none spends a seq or changes anything on either peer (seq %d)" % client.net.seq)


## The host's wallet moves without an event (a bug elsewhere): its next purchase still ends the client's
## wallet on the host's balance, and the client asks for a snapshot for the history it missed.
func _check_silent_money(host: Peer, client: Peer) -> void:
	host.state.call(&"earn", 1000, &"order_paid")
	var restores: int = client.restored.size()
	var seq: int = host.net.seq
	var reason: StringName = _ask(host, {"item": &"label_reader"})
	var resynced: bool = await _wait_for(func() -> bool:
		return client.restored.size() == restores + 1 and client.net.seq == host.net.seq,
		2.0 * CompanyNet.SNAPSHOT_INTERVAL_MSEC / 1000.0 + 2.0)
	var seen: Array = client.wallet_at.get(seq + 1, [])
	_expect(reason == &"" and seen == [400, 400] and int(host.state.get(&"money")) == 400,
		"After the host's silent earning the client ends the purchase on the host's 400 (%s)" % [seen])
	_expect(resynced and client.restored.back() == seq + 1,
		"...then asks for a snapshot and gets it at seq %d (restored %s)" % [seq + 1, client.restored])
	_expect(_wallet(client) == _wallet(host), "...and holds the host's company, the earning's entry too")


## A third peer joins late: the snapshot's company part brings every purchase; then one more reaches all three.
func _check_late_join(host: Peer, client: Peer, late: Peer, late_peer: ENetMultiplayerPeer) -> void:
	var up: bool = late_peer.create_client("127.0.0.1", PORT) == OK
	late.side.multiplayer.multiplayer_peer = late_peer
	late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host.side.multiplayer.get_peers().size() == 2 and late.side.multiplayer.get_peers().has(1))
	_expect(up and connected, "A third peer connects late")
	if not connected or not await _join(host, late):
		return
	var seen: Dictionary = _wallet(late)
	_expect(seen == _wallet(host) and seen["equipment"] == [&"upgrade_1", &"label_reader"]
		and seen["warehouse_stage"] == 1 and seen["fleet"] == STARTED_BIKE,
		"The late peer gets every purchase from the snapshot's company part (%s)" % [seen])
	_expect(_ask(host, {"item": &"test_sorter"}) == &"" and await _synced(host, [client, late]),
		"The host buys a machine that requires the label reader and both followers apply it")
	_expect(_wallet(client) == _wallet(host) and _wallet(late) == _wallet(host)
		and (late.state.get(&"equipment") as Array).has(&"test_sorter"), "...the three hold the same company")


## Every peer applied each event once, in order, with no gap; what reached the client is plain and small.
func _check_seqs(host: Peer, followers: Array) -> void:
	_expect(host.seqs == _range(1, host.net.seq), "The host's events are 1..%d (%s)" % [host.net.seq, host.seqs])
	for peer: Peer in followers:
		var first: int = peer.restored[0] + 1 if not peer.restored.is_empty() else 1
		_expect(peer.seqs == _range(first, host.net.seq) and peer.kinds == host.kinds.slice(first - 1),
			"%s applied the host's events %d..%d in order (%s)" % [peer.side.name, first, host.net.seq, peer.seqs])
	var client: Peer = followers[0]
	_expect(client.bought.size() == 5, "Five purchases reached the client (%d)" % client.bought.size())
	for data: Dictionary in client.bought:
		_expect(RpcGuard.dict_ok(data) and var_to_bytes(data).size() <= EVENT_BYTES_MAX,
			"What reached the client is plain and small (%d bytes: %s)" % [var_to_bytes(data).size(), data])


# --- Helpers ---


## The host's own request: the reason it was refused with, &"" when it went through.
func _ask(peer: Peer, data: Dictionary) -> StringName:
	return _heard(peer.refusals, peer.net.request(CompanyShopNet.BUY, data))


func _heard(refusals: Array, rid: int) -> StringName:
	for refusal: Array in refusals:
		if refusal[0] == rid:
			return refusal[1]
	return &""


## What a purchase changes, as plain data: money, equipment, fleet, stage and ledger.
func _wallet(peer: Peer) -> Dictionary:
	var data: Dictionary = peer.state.call(&"to_dict")
	return {
		"money": data["money"], "equipment": data["equipment"], "fleet": data["fleet"],
		"warehouse_stage": data["warehouse_stage"], "ledger": data["ledger"],
	}


func _last_entry(state: Node) -> Dictionary:
	var ledger: Array = state.get(&"ledger")
	return ledger.back() if not ledger.is_empty() else {}


func _synced(host: Peer, followers: Array) -> bool:
	return await _wait_for(func() -> bool:
		for peer: Peer in followers:
			if peer.net.seq != host.net.seq:
				return false
		return true)


func _range(first: int, last: int) -> Array[int]:
	var out: Array[int] = []
	for value: int in range(first, last + 1):
		out.append(value)
	return out


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _clean() -> void:
	var dir := DirAccess.open(CATALOG)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CATALOG))
