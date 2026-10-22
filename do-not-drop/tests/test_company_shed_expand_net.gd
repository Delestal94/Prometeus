extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_shed_expand_net.gd
##
## Growing the shed over the network (D-0910.2: shed_expand / shed_expanded of CompanyLayoutNet through
## CompanyNet; contract docs/expansion-distritos/diseno/red-autoridad.md, row 26 and section 8), on the
## default shed (DefaultShed):
## - shed_expand is a request kind and shed_expanded an event kind of CompanyNet, neither critical nor a
##   host-only publish, and shed_expanded has its own branch in _apply_state() (read from the source);
## - solo (offline): growing pays CompanyTuning's price (WarehouseStages.price_for) with a warehouse_expand
##   wallet entry at the host's minute, moves warehouse_stage one up and leaves the layout as it was, in
##   one shed_expanded event {stage, minute, money} that is plain and small; the build checker takes the
##   bigger grid (a cell off the small floor is green after); up to the last stage, where it is max_stage;
## - the host refuses, changing nothing and spending no seq: no_money, fixed_area while the default
##   dispatch zone stands where the bigger shed's exit goes (BuildLayoutSave.misfit(): a layout the next
##   stage would not keep whole), wrong_stage for a stage that is not the next one (a second press),
##   bad_data for a stage that is not an int or missing; anyone but the host hears host_only;
## - an event whose data doesn't fit (a skipped or repeated stage, past the last one, a stage, money or
##   minute that is not an int, money missing or negative, a minute past the day) is not applied and
##   changes nothing;
## - the wallet travels absolute: a mirror whose wallet missed a movement ends the upgrade on the host's
##   money and entry balance, its entry takes the host's minute, its clock_minutes stays, and it flags the
##   drift once (take_drift());
## - CompanyShed.follow() redraws the shed of the new stage: grid, walls, the dock's and the exit's zones
##   at their new place, and the default shed's zones and carts kept where they were; a ShedBuilder
##   in the build mode takes the new grid and fixed areas for its cursor;
## - with a host and a client as ENet peers in one process (each with its CompanyNet and a CompanyShed
##   following it): the host moves the dispatch zone and grows the shed three times; after each event
##   both hold the same stage, layout, money, wallet history and stock and draw the same shed at the new
##   grid; a piece placed where only the big floor reaches is drawn on the client; the client asking
##   hears host_only, only it hears it, and the host's refusals spend no seq;
## - a third peer joins late: the snapshot brings the stage (CompanyState.to_dict()) and the whole layout
##   (BuildLayoutSave.sanitize() keeps every piece the host let grow), it draws the big shed and applies
##   the next upgrade; every peer's seqs have no gap or repeat.
## Expected in the log: CompanyLayoutNet's warning for the mirror's wallet set right.

const PORT: int = 24693
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const NET_SCRIPT: String = "res://scripts/core/company/company_net.gd"
## A clock_minutes no event may write (only the host's clock writes it).
const SENTINEL_MINUTE: int = 7
## Bytes a shed_expanded may take (var_to_bytes): three small ints.
const EVENT_BYTES_MAX: int = 200
## Where the default dispatch zone goes so that every stage keeps it (off each stage's exit).
const DISPATCH_SPOT: Vector2i = Vector2i(2, 0)

var _failures: int = 0
var _host: Peer
var _client: Peer
var _late: Peer


## One peer: its side of the session, its world (CompanyNet, CompanyShed), its company and what it heard.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var shed: CompanyShed
	var seqs: Array[int] = []
	var kinds: Array[StringName] = []
	var expansions: Array[Dictionary] = []
	var refusals: Array = []
	var restored: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_kinds()
	await _check_solo()
	_check_bad_events()
	_check_mirror()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: the host grows the shed, checked like the local upgrade, and every peer (a late"
			+ " joiner too) holds and draws the same bigger shed")
	quit(_failures)


# --- Kinds ---


func _check_kinds() -> void:
	_expect(CompanyNet.REQUEST_KINDS.has(CompanyLayoutNet.EXPAND)
		and CompanyLayoutNet.REQUEST_KINDS.has(CompanyLayoutNet.EXPAND),
		"shed_expand is a request kind of CompanyNet, handled by CompanyLayoutNet")
	_expect(CompanyNet.EVENT_KINDS.has(CompanyLayoutNet.EXPANDED)
		and CompanyLayoutNet.EVENT_KINDS.has(CompanyLayoutNet.EXPANDED),
		"shed_expanded is an event kind of CompanyNet and a layout event (CompanyShed redraws it)")
	_expect(not CompanyNet.CRITICAL_KINDS.has(CompanyLayoutNet.EXPAND)
		and not CompanyNet.HOST_EVENT_KINDS.has(CompanyLayoutNet.EXPANDED),
		"shed_expand is not critical and shed_expanded only follows a request (not a host publish)")
	var text: String = FileAccess.get_file_as_string(NET_SCRIPT)
	var start: int = text.find("\nfunc _apply_state(")
	var end: int = text.find("\nfunc ", start + 1)
	var branch: bool = false
	var catch_all: bool = false
	if start >= 0 and end > start:
		for line: String in text.substr(start, end - start).split("\n"):
			if not (line.begins_with("\t\t") and not line.begins_with("\t\t\t") and line.strip_edges().ends_with(":")):
				continue
			var tokens: Array = []
			for token: String in line.strip_edges().trim_suffix(":").split(","):
				tokens.append(token.strip_edges())
			branch = branch or tokens.has("CompanyLayoutNet.EXPANDED")
			catch_all = catch_all or tokens.has("_")
	_expect(branch and not catch_all,
		"_apply_state() has a branch that names CompanyLayoutNet.EXPANDED and no catch-all (branch %s)" % branch)


# --- Solo ---


func _check_solo() -> void:
	var state: Node = _new_state("SoloState")
	state.call(&"new_company", "Solo SRL")
	DefaultShed.load_default().apply_to(state)
	var net := CompanyNet.new()
	net.name = "SoloNet"
	net.company = state
	root.add_child(net)
	net.inventory = state.call(&"stock")
	var heard: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void: heard.append([rid, reason]))
	var events: Array[Dictionary] = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		if kind == CompanyLayoutNet.EXPANDED:
			events.append(data))
	var shed := CompanyShed.new()
	shed.name = "SoloShed"
	root.add_child(shed)
	shed.follow(net)
	shed.rebuild(state, net.inventory)
	var builder := ShedBuilder.new()
	builder.name = "SoloBuilder"
	root.add_child(builder)
	builder.setup(shed, net)
	_expect(builder.enter(), "The solo host enters the build mode on the small shed")
	state.set(&"clock_minutes", 600)

	var fridge: Dictionary = {"id": &"fridge", "x": 14, "z": 3, "turns": 0}
	_expect(net.build.check(state, net.inventory, CompanyLayoutNet.PLACE, fridge, true).get("reason")
		== BuildPlacement.REASON_OUT_OF_BOUNDS, "A fridge at (14, 3) is off the small floor")
	var before: Dictionary = _company(state)
	var seq: int = net.seq
	_expect(_ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 1}) == WarehouseStages.REFUSAL_NO_MONEY
		and _company(state) == before and net.seq == seq,
		"Growing with %d in the wallet (the medium shed costs %d) is no_money and changes nothing"
		% [int(state.get(&"money")), WarehouseStages.price_for(1)])
	state.call(&"earn", 2000, &"order_paid")
	before = _company(state)
	_expect(_ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 1}) == BuildPlacement.REASON_FIXED
		and _company(state) == before and net.seq == seq,
		"With the default dispatch zone where the medium shed's exit goes it is fixed_area and changes nothing")
	_expect(_ask(net, heard, CompanyLayoutNet.MOVE, {"uid": &"dispatch_1", "x": DISPATCH_SPOT.x, "z": DISPATCH_SPOT.y})
		== &"", "The host moves the dispatch zone to %s" % DISPATCH_SPOT)
	before = _company(state)
	seq = net.seq
	var refusals: Array = [
		[{"stage": 2}, CompanyLayoutNet.REASON_WRONG_STAGE, "a stage past the next one"],
		[{"stage": 0}, CompanyLayoutNet.REASON_WRONG_STAGE, "the stage it is at"],
		[{"stage": -1}, CompanyLayoutNet.REASON_WRONG_STAGE, "a negative stage"],
		[{"stage": 1.0}, CompanyLayoutNet.REASON_BAD_DATA, "a float stage"],
		[{"stage": &"1"}, CompanyLayoutNet.REASON_BAD_DATA, "a stage as text"],
		[{}, CompanyLayoutNet.REASON_BAD_DATA, "no stage"],
	]
	for case: Array in refusals:
		var got: StringName = _ask(net, heard, CompanyLayoutNet.EXPAND, case[0])
		_expect(got == case[1], "shed_expand with %s is refused with %s (got %s)" % [case[2], case[1], got])
	_expect(_company(state) == before and net.seq == seq,
		"...and none of them changed the company or spent a seq (seq %d)" % net.seq)
	_expect(net.build.check(state, net.inventory, CompanyLayoutNet.EXPAND, {"stage": 1}, false).get("reason")
		== CompanyLayoutNet.REASON_HOST_ONLY, "shed_expand from anyone but the host is host_only")

	var layout_before: Array = (state.get(&"layout") as Array).duplicate(true)
	var money: int = int(state.get(&"money"))
	_expect(_ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 1}) == &""
		and int(state.get(&"warehouse_stage")) == 1 and net.seq == seq + 1,
		"Solo, the host grows the shed to stage 1 (stage %d)" % int(state.get(&"warehouse_stage")))
	_expect(int(state.get(&"money")) == money - WarehouseStages.price_for(1),
		"...paying CompanyTuning's price (money %d)" % int(state.get(&"money")))
	var entry: Dictionary = _last_entry(state)
	_expect(entry.get("reason") == String(WarehouseStages.REASON_EXPAND) and int(entry.get("minute", -1)) == 600
		and int(entry.get("amount", 0)) == -WarehouseStages.price_for(1),
		"...with a warehouse_expand wallet entry at the host's minute (%s)" % [entry])
	_expect(state.get(&"layout") == layout_before, "...and the layout as it was")
	_expect(events.size() == 1 and events[0] == {"stage": 1, "minute": 600, "money": int(state.get(&"money"))},
		"...in one shed_expanded event {stage, minute, money} (%s)" % [events])
	for data: Dictionary in events:
		_expect(RpcGuard.dict_ok(data) and var_to_bytes(data).size() <= EVENT_BYTES_MAX,
			"shed_expanded is plain and small (%d bytes)" % var_to_bytes(data).size())
	_expect(net.build.placement_for(state).grid_size == WarehouseStages.grid_size_for(1)
		and net.build.check(state, net.inventory, CompanyLayoutNet.PLACE, fridge, true).get("reason") == &"",
		"The build checker takes the medium grid: the fridge at (14, 3) is green now")
	_expect_shed(shed, 1, "solo")
	_expect(builder.mode.grid_size == WarehouseStages.grid_size_for(1)
		and builder.cursor.placement.grid_size == WarehouseStages.grid_size_for(1)
		and builder.cursor.placement.fixed_blocked == WarehouseStages.fixed_rects(1),
		"The build mode's cursor takes the medium grid and its dock and exit (%s)" % builder.mode.grid_size)
	await process_frame
	_expect(builder.camera != null and is_instance_valid(builder.camera) and builder.camera.is_inside_tree(),
		"The build camera outlives the shed's redraw")
	builder.exit()
	_expect(_ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 1}) == CompanyLayoutNet.REASON_WRONG_STAGE
		and int(state.get(&"warehouse_stage")) == 1, "A second press for stage 1 is wrong_stage, not a second upgrade")

	state.call(&"earn", 10000, &"order_paid")
	_expect(_ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 2}) == &""
		and _ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 3}) == &""
		and int(state.get(&"warehouse_stage")) == WarehouseStages.stage_count() - 1,
		"The moved layout grows to the last stage (stage %d)" % int(state.get(&"warehouse_stage")))
	_expect_shed(shed, 3, "solo, at the last stage")
	before = _company(state)
	seq = net.seq
	_expect(_ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 4}) == WarehouseStages.REFUSAL_MAX_STAGE
		and _ask(net, heard, CompanyLayoutNet.EXPAND, {"stage": 3}) == WarehouseStages.REFUSAL_MAX_STAGE
		and _company(state) == before and net.seq == seq,
		"At the last stage shed_expand is max_stage and changes nothing")
	builder.free()
	shed.free()
	net.free()
	state.free()


## Rule 6: the event is applied as it comes, checked only as data.
func _check_bad_events() -> void:
	var state: Node = _new_state("BadState")
	state.call(&"new_company", "Bad SRL")
	state.set(&"money", 5000)
	var build := CompanyLayoutNet.new()
	var good: Dictionary = {"stage": 1, "minute": 600, "money": 4200}
	var bad: Array = [
		[_with(good, "stage", 2), "a skipped stage"],
		[_with(good, "stage", 0), "the stage it is at"],
		[_with(good, "stage", 1.0), "a float stage"],
		[_with(good, "stage", "1"), "a stage as text"],
		[_without(good, "stage"), "no stage"],
		[_without(good, "money"), "no money"],
		[_with(good, "money", -1), "a negative balance after the upgrade"],
		[_with(good, "money", 4200.0), "a float balance"],
		[_with(good, "money", CompanyWalletNet.MAX_MONEY + 1), "a balance past MAX_MONEY"],
		[_without(good, "minute"), "no minute"],
		[_with(good, "minute", CompanyTuning.MINUTES_PER_DAY), "a minute past the day"],
		[_with(good, "minute", 600.0), "a float minute"],
	]
	var before: Dictionary = _company(state)
	for case: Array in bad:
		_expect(not build.apply(state, CompanyLayoutNet.EXPANDED, case[0]),
			"A shed_expanded with %s is not applied" % case[1])
	_expect(_company(state) == before, "...and changed nothing")
	_expect(not build.take_drift(), "None of them touched the wallet (no drift)")
	state.set(&"warehouse_stage", WarehouseStages.stage_count() - 1)
	before = _company(state)
	_expect(not build.apply(state, CompanyLayoutNet.EXPANDED, _with(good, "stage", WarehouseStages.stage_count()))
		and _company(state) == before, "A shed_expanded past the last stage is not applied")
	state.free()


## A mirror (a client's copy, from the host's to_dict()) whose wallet missed a movement: the host's event
## carries its balance, so the mirror ends the upgrade on it; its clock_minutes is not written.
func _check_mirror() -> void:
	var host: Node = _new_state("MirrorHost")
	host.call(&"new_company", "Mirror SRL")
	host.call(&"earn", 2000, &"order_paid")
	var mirror: Node = _new_state("Mirror")
	mirror.call(&"from_dict", host.call(&"to_dict"))
	var host_build := CompanyLayoutNet.new()
	var mirror_build := CompanyLayoutNet.new()
	host.call(&"earn", 300, &"order_paid")
	host.set(&"clock_minutes", 615)
	mirror.set(&"clock_minutes", SENTINEL_MINUTE)
	var asked: Dictionary = host_build.check(host, host.call(&"stock"), CompanyLayoutNet.EXPAND, {"stage": 1}, true)
	var applied: bool = asked.get("reason") == &"" and host_build.apply(host, asked["kind"], asked["data"])
	applied = applied and mirror_build.apply(mirror, asked["kind"], asked["data"])
	_expect(applied and int(mirror.get(&"warehouse_stage")) == 1
		and int(mirror.get(&"money")) == int(host.get(&"money"))
		and _last_entry(mirror).get("balance") == _last_entry(host).get("balance"),
		"After the upgrade the mirror holds stage 1 and the host's money and entry balance (%s / %s, host %s / %s)"
		% [mirror.get(&"money"), _last_entry(mirror).get("balance"), host.get(&"money"),
			_last_entry(host).get("balance")])
	_expect(int(_last_entry(mirror).get("minute", -1)) == 615 and int(mirror.get(&"clock_minutes")) == SENTINEL_MINUTE,
		"...its entry carries the host's minute 615 and its clock_minutes stays %d" % SENTINEL_MINUTE)
	_expect(mirror_build.take_drift() and not mirror_build.take_drift() and not host_build.take_drift(),
		"The mirror flags the drift once; the host never drifts")
	host.free()
	mirror.free()


# --- Network ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	_late = _make_peer("LateSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var late := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 3) == OK
	_expect(up, "The test hosts an ENet session on localhost:%d" % PORT)
	_host.side.multiplayer.multiplayer_peer = server
	# What CompanyRoot does on the host: the company with its default shed, then the world.
	_host.state.call(&"new_company", "Expand SRL")
	DefaultShed.load_default().apply_to(_host.state)
	_add_world(_host)
	_host.net.inventory = _host.state.call(&"stock")
	_host.shed.rebuild(_host.state, _host.net.inventory)
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_world(_client)
	_client.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _client.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host")
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
	_expect_equal([_host, _client], "after the client's snapshot")
	_expect(_host.net.publish_wallet(1000, &"order_paid") and await _synced([_client]),
		"The host earns 1000 and the client follows")
	await _refused_by_host(CompanyLayoutNet.EXPAND, {"stage": 1}, BuildPlacement.REASON_FIXED,
		"growing with the dispatch zone where the medium shed's exit goes")
	await _step([CompanyLayoutNet.MOVE, {"uid": &"dispatch_1", "x": DISPATCH_SPOT.x, "z": DISPATCH_SPOT.y}], [_client])
	await _step([CompanyLayoutNet.EXPAND, {"stage": 1}], [_client])
	_expect(int(_client.state.get(&"warehouse_stage")) == 1
		and int(_client.state.get(&"money")) == CompanyTuning.STARTING_MONEY + 1000 - WarehouseStages.price_for(1)
		and _last_entry(_client.state).get("reason") == String(WarehouseStages.REASON_EXPAND),
		"The client holds stage 1, the host's money and the warehouse_expand entry (%s)" % [_last_entry(_client.state)])
	_expect(_client.net.build.placement_for(_client.state).grid_size == WarehouseStages.grid_size_for(1),
		"The client's build checker takes the medium grid with no snapshot")
	_expect_shed(_client.shed, 1, "on the client")

	await _check_client_asks()
	await _refused_by_host(CompanyLayoutNet.EXPAND, {"stage": 1}, CompanyLayoutNet.REASON_WRONG_STAGE, "a second press")
	await _refused_by_host(CompanyLayoutNet.EXPAND, {"stage": 2}, WarehouseStages.REFUSAL_NO_MONEY,
		"the large shed with %d in the wallet" % int(_host.state.get(&"money")))
	await _refused_by_host(CompanyLayoutNet.EXPAND, {"stage": 2.0}, CompanyLayoutNet.REASON_BAD_DATA, "a float stage")

	_expect(_host.net.publish_wallet(10000, &"order_paid") and await _synced([_client]),
		"The host earns 10000 and the client follows")
	await _step([CompanyLayoutNet.EXPAND, {"stage": 2}], [_client])
	_expect_shed(_client.shed, 2, "on the client")
	await _step([CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 20, "z": 3, "turns": 0}], [_client])
	_expect(_client.shed.piece_at(Vector2i(20, 3)) == &"fridge_1",
		"A fridge at (20, 3), only on the large floor, is drawn on the client (%s)"
		% _client.shed.piece_at(Vector2i(20, 3)))

	await _check_late_join(late)
	await _step([CompanyLayoutNet.EXPAND, {"stage": 3}], [_client, _late])
	_expect_shed(_client.shed, 3, "on the client")
	_expect_shed(_late.shed, 3, "on the late peer")
	await _refused_by_host(CompanyLayoutNet.EXPAND, {"stage": 4}, WarehouseStages.REFUSAL_MAX_STAGE,
		"past the last stage")
	_check_seqs()


## One request of the host's, applied on the host and on every follower; then every follower equals the host.
func _step(step: Array, followers: Array) -> void:
	var seq: int = _host.net.seq
	var reason: StringName = _ask(_host.net, _host.refusals, step[0], step[1])
	var synced: bool = await _synced(followers)
	_expect(reason == &"" and _host.net.seq == seq + 1 and synced,
		"%s %s goes through and reaches every peer (refused %s)" % [step[0], step[1], reason])
	_expect_equal([_host] + followers, "after %s %s" % [step[0], step[1]])


## A refused request of the host's: the reason, no seq, nothing anywhere.
func _refused_by_host(kind: StringName, data: Dictionary, reason: StringName, what: String) -> void:
	var seq: int = _host.net.seq
	var before: Dictionary = _company(_client.state)
	var got: StringName = _ask(_host.net, _host.refusals, kind, data)
	await process_frame
	await process_frame
	_expect(got == reason and _host.net.seq == seq and _client.net.seq == seq and _company(_client.state) == before,
		"The host asking %s %s is refused with %s, spending no seq and changing nothing (got %s)"
		% [kind, what, reason, got])


## The client may ask; only the host grows the shed: host_only, to the client only, nothing changes.
func _check_client_asks() -> void:
	var seq: int = _host.net.seq
	var host_heard: int = _host.refusals.size()
	var rid: int = _client.net.request(CompanyLayoutNet.EXPAND, {"stage": 2})
	var answered: bool = await _wait_for(func() -> bool: return _reason_heard(_client.refusals, rid) != &"")
	_expect(answered and _reason_heard(_client.refusals, rid) == CompanyLayoutNet.REASON_HOST_ONLY,
		"The client asking to grow the shed hears host_only (%s)" % _reason_heard(_client.refusals, rid))
	_expect(_host.refusals.size() == host_heard and _host.net.seq == seq and _client.net.seq == seq,
		"...only the client hears it and no seq is spent (seq %d)" % _host.net.seq)
	_expect_equal([_host, _client], "after the client's ask")


## A third peer joins at the large stage: the snapshot brings the stage and the whole layout.
func _check_late_join(late: ENetMultiplayerPeer) -> void:
	var up: bool = late.create_client("127.0.0.1", PORT) == OK
	_late.side.multiplayer.multiplayer_peer = late
	_add_world(_late)
	_late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return _late.side.multiplayer.get_peers().has(1) and _host.side.multiplayer.get_peers().size() == 2)
	_expect(up and connected, "A third peer connects late")
	if not connected:
		return
	_expect(await _join(_late) and _late.restored == [_host.net.seq] and _late.seqs.is_empty(),
		"The late peer's snapshot brings it to the host's seq %d (restored %s)" % [_host.net.seq, _late.restored])
	_expect_equal([_host, _client, _late], "after the late peer's snapshot")
	_expect((_late.state.get(&"layout") as Array).size() == (_host.state.get(&"layout") as Array).size(),
		"The late peer keeps every piece of the host's layout (%d)" % (_late.state.get(&"layout") as Array).size())
	_expect_shed(_late.shed, 2, "on the late peer")
	_expect(_late.shed.piece_at(Vector2i(20, 3)) == &"fridge_1", "...with the fridge on the large floor")


## Every peer applied each event once, in order, with no gap: the host from 1, a client from its snapshot on.
func _check_seqs() -> void:
	_expect(_host.seqs == _range(1, _host.net.seq), "The host's events are 1..%d with no gap (%s)"
		% [_host.net.seq, _host.seqs])
	for peer: Peer in [_client, _late]:
		var first: int = peer.restored[0] + 1 if not peer.restored.is_empty() else 1
		_expect(peer.seqs == _range(first, _host.net.seq),
			"%s applied %d..%d with no gap or repeat (%s)" % [peer.side.name, first, _host.net.seq, peer.seqs])
		_expect(peer.kinds == _host.kinds.slice(first - 1), "%s applied the host's kinds in its order" % peer.side.name)
	_expect(_client.expansions.size() == 3 and _late.expansions.size() == 1,
		"The client applied three shed_expanded and the late peer one (%d, %d)"
		% [_client.expansions.size(), _late.expansions.size()])
	for data: Dictionary in _client.expansions:
		_expect(RpcGuard.dict_ok(data) and var_to_bytes(data).size() <= EVENT_BYTES_MAX and data.size() == 3,
			"What reached the client is plain and small (%d bytes: %s)" % [var_to_bytes(data).size(), data])


# --- Helpers ---


## The shed drawn at `stage`: grid, the east wall just outside the floor, the dock's and exit's names at
## their place on that floor, a point past the small floor held, the default zones and the cart kept.
func _expect_shed(shed: CompanyShed, stage: int, where: String) -> void:
	var grid: Vector2i = WarehouseStages.grid_size_for(stage)
	_expect(shed.stage == stage and shed.grid == grid, "The shed %s is drawn at stage %d, %s (stage %d, %s)"
		% [where, stage, grid, shed.stage, shed.grid])
	var wall: Node3D = shed.get_node_or_null(^"Shell/WallRight") as Node3D
	var wall_x: float = grid.x * 0.5 * CompanyTuning.WAREHOUSE_GRID_M + CompanyShed.WALL_THICKNESS * 0.5
	_expect(wall != null and is_equal_approx(wall.position.x, wall_x),
		"...its east wall stands at x %.2f (%s)" % [wall_x, wall.position.x if wall != null else null])
	for zone: Array in [[&"dock", WarehouseStages.dock_rect(stage)], [&"exit", WarehouseStages.exit_rect(stage)]]:
		var label: Node3D = shed.get_node_or_null(NodePath("Zone_%s" % zone[0])) as Node3D
		var at: Vector3 = shed.cell_to_local(Vector2((zone[1] as Rect2i).get_center()) + Vector2(0.0, 0.2))
		_expect(label != null and is_equal_approx(label.position.x, at.x) and is_equal_approx(label.position.z, at.z),
			"...the %s's name is on its new place %s (%s)" % [zone[0], at, label.position if label != null else null])
	var past: float = (WarehouseStages.grid_size_for(0).x * 0.5 + 1.0) * CompanyTuning.WAREHOUSE_GRID_M
	_expect(shed.holds(shed.to_global(Vector3(past, 0.0, 0.0))) == (stage > 0),
		"...and it holds a point %.1f m east of the centre only when it is bigger than the small shed" % past)
	_expect(shed.get_node_or_null(^"Zone_reception") != null and shed.cart_views.has(&"cart_1"),
		"...keeping the default shed's zones and its picking cart")


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = _new_state(side_name + "State")
	return peer


## The world of one peer, as CompanyRoot builds it: CompanyNet and the shed following it.
func _add_world(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.shed = CompanyShed.new()
	peer.shed.name = "Shed"
	peer.side.add_child(peer.shed)
	peer.shed.follow(peer.net)
	peer.net.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		peer.seqs.append(seq)
		peer.kinds.append(kind)
		if kind == CompanyLayoutNet.EXPANDED:
			peer.expansions.append(data))
	peer.net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		peer.refusals.append([rid, reason]))
	peer.net.company_state_restored.connect(func(seq: int) -> void: peer.restored.append(seq))


## The host sends `peer` its snapshot as when that peer's world comes up
## (NetworkManager.peer_level_ready); true once it is in.
func _join(peer: Peer) -> bool:
	var id: int = peer.side.multiplayer.get_unique_id()
	var network: Node = root.get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_signal(&"peer_level_ready"):
		network.emit_signal(&"peer_level_ready", id)
	else:
		_host.net.send_snapshot(id)
	return await _wait_for(func() -> bool: return not peer.restored.is_empty() and peer.net.seq == _host.net.seq)


func _synced(followers: Array) -> bool:
	return await _wait_for(_all_at_host_seq.bind(followers))


func _all_at_host_seq(followers: Array) -> bool:
	for peer: Peer in followers:
		if peer.net.seq != _host.net.seq:
			return false
	return true


func _expect_equal(peers: Array, when: String) -> void:
	var first: Peer = peers[0]
	for peer: Peer in peers.slice(1):
		_expect(_shared(peer.state) == _shared(first.state),
			"%s has the host's company %s (stage %s, money %s, layout %s)" % [peer.side.name, when,
				peer.state.get(&"warehouse_stage"), peer.state.get(&"money"), peer.state.get(&"layout")])
		_expect(peer.net.inventory.to_dict() == first.net.inventory.to_dict(),
			"%s has the host's stock %s" % [peer.side.name, when])
		_expect(_shed_of(peer) == _shed_of(first), "%s draws the host's shed %s" % [peer.side.name, when])


## Asks `kind` on `net` and returns the refusal it heard for it at once (&"" when none: on the host a
## request is answered before request() returns).
func _ask(net: CompanyNet, heard: Array, kind: StringName, data: Dictionary) -> StringName:
	return _reason_heard(heard, net.request(kind, data))


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


static func _last_entry(state: Node) -> Dictionary:
	var ledger: Array = state.get(&"ledger")
	return ledger.back() if not ledger.is_empty() else {}


## Stage, grid and pieces drawn by a peer's shed.
static func _shed_of(peer: Peer) -> Array:
	var rows: Array = [peer.shed.stage, peer.shed.grid]
	for piece: Dictionary in peer.shed.pieces:
		rows.append([piece["uid"], piece["id"], piece["rect"]])
	return rows


## CompanyState.to_dict() without its stored stock.
static func _company(state: Node) -> Dictionary:
	var data: Dictionary = state.call(&"to_dict")
	data.erase("inventory")
	return data


## _company() as every peer holds it: clock_minutes is the host clock's to write (GameClock, D-0219).
static func _shared(state: Node) -> Dictionary:
	var data: Dictionary = _company(state)
	data.erase("clock_minutes")
	return data


static func _range(from: int, to: int) -> Array[int]:
	var numbers: Array[int] = []
	for number: int in range(from, to + 1):
		numbers.append(number)
	return numbers


static func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = data.duplicate()
	copy[key] = value
	return copy


static func _without(data: Dictionary, key: String) -> Dictionary:
	var copy: Dictionary = data.duplicate()
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
