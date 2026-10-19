extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_layout_net.gd
##
## The shed layout built over the network (D-0910, scripts/core/company/company_layout_net.gd through
## CompanyNet; contract docs/expansion-distritos/diseno/red-autoridad.md section 2, "Construir el
## galpón"), on the default shed (DefaultShed):
## - solo (offline): placing pays the price and names the piece "<id>_<n>" (the lowest n free),
##   moving and turning are free, selling pays the refund; every event is a few plain values (under
##   EVENT_BYTES_MAX bytes, RpcGuard.dict_ok) and the wallet entry carries the host's minute;
## - the wallet travels absolute: a mirror whose wallet missed a movement (the host earned without an
##   event) ends a purchase and a sale on the host's money and entry balance, takes the entry's
##   minute without its clock_minutes being written (a sentinel stays), and flags the drift
##   (take_drift()) so CompanyNet asks for a snapshot;
## - the host refuses, changing nothing, with BuildPlacement's own reasons (overlap, fixed_area on the
##   dock, out_of_bounds, blocks_path, no_money), not_empty for a shelf with units, no_piece for an
##   unknown uid and bad_data for a path or a wrong-case id, a float or huge cell, turns out of range;
##   a request that is not the host's own is host_only (only the host builds, D-0910.1 is the vote);
## - pieces saved without a uid get their names stored before a layout event, so selling the first
##   shelf does not rename the second (its units stay under shelf:shelf_2_<slot>); a name two pieces
##   share gives the later one a fresh "<id>_<n>", and the host names a new piece after that;
## - an event whose data doesn't fit (unknown placeable, uid in use or unknown, float cell, turns or
##   minute out of range, money missing, negative or a float) is not applied and changes nothing,
##   not even the names of pieces saved without a uid (every check comes before the first change);
## - every kind of CompanyNet.EVENT_KINDS has its own branch in _apply_state() (read from the source:
##   no catch-all `_:` branch);
## - with a host and a client as ENet peers in one process (each with its CompanyNet, DayCycle and
##   CompanyShed following it): 8 placements, turns, moves and sales by the host, in a thawed and in
##   a frozen shed, reach the client in order; the layout, money, wallet history, stock, day phase and
##   frozen shed are equal on both after each one, a layout event leaves the day as it was, and the
##   client's CompanyShed redraws each change (CompanyShed.follow());
## - the host's refused requests (overlap, dock, no money) change nothing on either peer and spend
##   no seq; the client asking to place, move, turn or sell hears host_only for each, only it hears
##   it, and nothing changes anywhere; the client's clock_minutes is never written by a layout event;
## - the host earns money without an event and then buys: the client ends that purchase on the host's
##   money and balance, asks for a snapshot and ends equal to the host, wallet history included;
## - a third peer joins late: it holds the event that reaches it before its snapshot, gets the
##   host's layout from the snapshot (CompanyState.layout in its `company` part), draws it, and
##   applies the event after it; the three end equal and every peer's seqs have no gap or repeat.
## Expected in the log: CompanyLayoutNet's warning for each wallet set right (the mirror check and the
## client after the host's silent earning).

const PORT: int = 24651
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const NET_SCRIPT: String = "res://scripts/core/company/company_net.gd"
const LAYOUT_SCRIPT: String = "res://scripts/core/company/company_layout_net.gd"
## A clock_minutes no event may write (only the host's clock writes it).
const SENTINEL_MINUTE: int = 7
## Bytes a layout event's data may take (var_to_bytes): a few small ints and two short ids.
const EVENT_BYTES_MAX: int = 200

var _failures: int = 0
## Ticks every DayCycle of the test reads, and whether the host sees the crew in the shed.
var _now: int = 100000
var _crew_inside: bool = true
var _host: Peer
var _client: Peer
var _late: Peer


## One peer: its side of the session, its world (CompanyNet, DayCycle, CompanyShed), its company and
## what it heard.
class Peer:
	extends RefCounted
	var side: Node
	var state: Node
	var net: CompanyNet
	var day: DayCycle
	var shed: CompanyShed
	var seqs: Array[int] = []
	var kinds: Array[StringName] = []
	var layout_events: Array[Dictionary] = []
	var refusals: Array = []
	var restored: Array[int] = []
	## {seq: [money, balance of the last wallet entry]} as each event was applied.
	var wallet_at: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_check_solo()
	_check_mirror()
	_check_legacy_names()
	_check_event_branches()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: the shed layout is built by the host only, checked like the build mode,"
			+ " equal on host, client and a late joiner, small events without gaps")
	quit(_failures)


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
		if CompanyLayoutNet.EVENT_KINDS.has(kind):
			events.append(data))
	var pieces: int = _layout(state).size()

	state.set(&"clock_minutes", 600)
	var reason: StringName = _ask(net, heard, CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 5, "z": 3, "turns": 0})
	var placed: int = CompanyLayoutNet.piece_index(_layout(state), &"fridge_1")
	_expect(reason == &"" and _layout(state).size() == pieces + 1 and placed == pieces,
		"Solo, the host places a fridge named fridge_1 (refused %s, %d pieces)" % [reason, _layout(state).size()])
	_expect(int(state.get(&"money")) == CompanyTuning.STARTING_MONEY - 200,
		"...paying its price (money %d)" % int(state.get(&"money")))
	var entry: Dictionary = _last_entry(state)
	_expect(entry.get("reason") == "placeable_buy" and int(entry.get("minute", -1)) == 600,
		"...with a placeable_buy wallet entry at the host's minute (%s)" % [entry])
	_expect(net.seq == 1 and events.size() == 1 and events[0].get("uid") == &"fridge_1"
		and events[0].get("minute") == 600 and events[0].get("money") == CompanyTuning.STARTING_MONEY - 200
		and (events[0].keys() as Array).size() == 7,
		"...in one layout_placed event {id, x, z, turns, uid, minute, money} (%s)" % [events])

	_expect(_ask(net, heard, CompanyLayoutNet.PLACE, {"id": &"shelf", "x": 8, "z": 3, "turns": 0}) == &""
		and CompanyLayoutNet.piece_index(_layout(state), &"shelf_4") >= 0,
		"A new shelf is shelf_4: the default shed has shelf_1 to shelf_3")
	_expect(_ask(net, heard, CompanyLayoutNet.ROTATE, {"uid": &"shelf_4", "turns": 1}) == &""
		and _piece(state, &"shelf_4").get("turns") == 1,
		"Turning shelf_4 a quarter turn goes through (%s)" % [_piece(state, &"shelf_4")])
	_expect(_ask(net, heard, CompanyLayoutNet.MOVE, {"uid": &"fridge_1", "x": 3, "z": 3}) == &""
		and _piece(state, &"fridge_1").get("x") == 3 and _piece(state, &"fridge_1").get("z") == 3,
		"Moving fridge_1 to (3, 3) goes through (%s)" % [_piece(state, &"fridge_1")])
	_expect(int(state.get(&"money")) == CompanyTuning.STARTING_MONEY - 280,
		"...and neither turning nor moving costs money (money %d)" % int(state.get(&"money")))

	var before: Dictionary = _company(state)
	var seq: int = net.seq
	var refusals: Array = [
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 11, "z": 2}, BuildPlacement.REASON_OVERLAP, "on table_1"],
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 5, "z": 6}, BuildPlacement.REASON_FIXED, "on the dock"],
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 12, "z": 0}, BuildPlacement.REASON_OUT_OF_BOUNDS,
			"off the floor"],
		[CompanyLayoutNet.PLACE, {"id": &"shelf", "x": 1, "z": 0, "turns": 1}, BuildPlacement.REASON_BLOCKS_PATH,
			"walling shelf_1 in"],
		[CompanyLayoutNet.MOVE, {"uid": &"table_2", "x": 11, "z": 2}, BuildPlacement.REASON_OVERLAP,
			"moving table_2 onto table_1"],
		[CompanyLayoutNet.ROTATE, {"uid": &"table_1", "turns": 1}, BuildPlacement.REASON_OUT_OF_BOUNDS,
			"turning table_1 through the east wall"],
		[CompanyLayoutNet.SELL, {"uid": &"shelf_1"}, CompanyLayoutNet.REASON_NOT_EMPTY, "selling a shelf with units"],
		[CompanyLayoutNet.SELL, {"uid": &"shelf_99"}, CompanyLayoutNet.REASON_NO_PIECE,
			"selling a piece that isn't there"],
		[CompanyLayoutNet.MOVE, {"uid": &"nobody", "x": 3, "z": 2}, CompanyLayoutNet.REASON_NO_PIECE, "moving one"],
		[CompanyLayoutNet.PLACE, {"id": &"../products/hen", "x": 3, "z": 5}, CompanyLayoutNet.REASON_BAD_DATA,
			"a path"],
		[CompanyLayoutNet.PLACE, {"id": &"Fridge", "x": 3, "z": 5}, CompanyLayoutNet.REASON_BAD_DATA,
			"a wrong-case id"],
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 3.0, "z": 5}, CompanyLayoutNet.REASON_BAD_DATA, "a float cell"],
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 4294967299, "z": 5}, CompanyLayoutNet.REASON_BAD_DATA,
			"a cell a Vector2i would wrap onto the floor"],
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 3, "z": 5, "turns": 4}, CompanyLayoutNet.REASON_BAD_DATA,
			"turns past 3"],
		[CompanyLayoutNet.ROTATE, {"uid": &"table_1", "turns": 0}, CompanyLayoutNet.REASON_BAD_DATA, "a zero turn"],
		[CompanyLayoutNet.MOVE, {"uid": &"table_1", "x": 3}, CompanyLayoutNet.REASON_BAD_DATA, "a move without z"],
		[CompanyLayoutNet.SELL, {"uid": 7}, CompanyLayoutNet.REASON_BAD_DATA, "a uid that isn't text"],
	]
	for case: Array in refusals:
		var got: StringName = _ask(net, heard, case[0], case[1])
		_expect(got == case[2], "%s %s is refused with %s (got %s)" % [case[0], case[3], case[2], got])
	_expect(_company(state) == before and net.seq == seq,
		"...and none of them changed the company or spent a seq (seq %d)" % net.seq)

	_expect(_ask(net, heard, CompanyLayoutNet.SELL, {"uid": &"shelf_4"}) == &""
		and CompanyLayoutNet.piece_index(_layout(state), &"shelf_4") < 0
		and int(state.get(&"money")) == CompanyTuning.STARTING_MONEY - 280 + 40,
		"Selling the empty shelf_4 takes it out and pays its refund (money %d)" % int(state.get(&"money")))
	_expect(_ask(net, heard, CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 6, "z": 4}) == &""
		and int(state.get(&"money")) == 60,
		"A second fridge leaves 60 (money %d)" % int(state.get(&"money")))
	before = _company(state)
	_expect(_ask(net, heard, CompanyLayoutNet.PLACE, {"id": &"shelf", "x": 8, "z": 5}) == BuildPlacement.REASON_NO_MONEY
		and _company(state) == before,
		"A shelf of 80 with 60 in the wallet is refused with no_money, changing nothing")

	for kind: StringName in CompanyLayoutNet.REQUEST_KINDS:
		var asked: Dictionary = net.build.check(state, net.inventory, kind, {"uid": &"fridge_1", "x": 4, "z": 4}, false)
		_expect(asked.get("reason") == CompanyLayoutNet.REASON_HOST_ONLY,
			"%s from anyone but the host is refused with host_only (%s)" % [kind, asked])
	for data: Dictionary in events:
		_expect(RpcGuard.dict_ok(data) and var_to_bytes(data).size() <= EVENT_BYTES_MAX,
			"A layout event is plain and small (%d bytes: %s)" % [var_to_bytes(data).size(), data])

	_check_bad_events(net, state)
	net.free()
	state.free()


## Rule 6: the event is applied as it comes, checked only as data.
func _check_bad_events(net: CompanyNet, state: Node) -> void:
	var before: Dictionary = _company(state)
	var place: Dictionary = {
		"id": &"fridge", "x": 9, "z": 5, "turns": 0, "uid": &"fridge_9", "minute": 600, "money": 10,
	}
	var bad: Array = [
		[CompanyLayoutNet.PLACED, _with(place, "id", &"rocket"), "an unknown placeable"],
		[CompanyLayoutNet.PLACED, _with(place, "uid", &"table_1"), "a uid in use"],
		[CompanyLayoutNet.PLACED, _with(place, "x", 9.0), "a float cell"],
		[CompanyLayoutNet.PLACED, _with(place, "turns", 4), "turns past 3"],
		[CompanyLayoutNet.PLACED, _with(place, "minute", CompanyTuning.MINUTES_PER_DAY), "a minute past the day"],
		[CompanyLayoutNet.PLACED, _without(place, "minute"), "no minute"],
		[CompanyLayoutNet.PLACED, _without(place, "money"), "no money"],
		[CompanyLayoutNet.PLACED, _with(place, "money", -1), "a negative balance after a purchase"],
		[CompanyLayoutNet.PLACED, _with(place, "money", 10.0), "a float balance"],
		[CompanyLayoutNet.SOLD, {"uid": &"table_1", "minute": 600}, "a sale without money"],
		[CompanyLayoutNet.MOVED, {"uid": &"nobody", "x": 1, "z": 1, "turns": 0}, "a move of an unknown piece"],
		[CompanyLayoutNet.MOVED, {"uid": &"table_1", "x": 1, "z": 1}, "a move without turns"],
		[CompanyLayoutNet.SOLD, {"uid": &"nobody", "minute": 600}, "a sale of an unknown piece"],
		[&"layout_burned", {"uid": &"table_1"}, "an unknown kind"],
	]
	for case: Array in bad:
		_expect(not net.build.apply(state, case[0], case[1]), "An event with %s is not applied" % case[2])
	_expect(_company(state) == before, "...and changed nothing")
	_expect(not net.build.take_drift(), "None of them touched the wallet (no drift)")


## Pieces saved without a uid keep their names: selling the first shelf does not make the second
## one shelf_1 (its units stay under shelf:shelf_2_0).
func _check_legacy_names() -> void:
	var state: Node = _new_state("LegacyState")
	state.call(&"new_company", "Legacy SRL")
	var pieces: Array[Dictionary] = [
		{"id": "shelf", "x": 3, "z": 2, "turns": 0}, {"id": "shelf", "x": 3, "z": 4, "turns": 0},
	]
	state.set(&"layout", pieces)
	var net := CompanyNet.new()
	net.name = "LegacyNet"
	net.company = state
	root.add_child(net)
	net.inventory.receive(&"hen", 3, DefaultShed.shelf_location(&"shelf_2", 0))
	var heard: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void: heard.append([rid, reason]))
	_expect(_ask(net, heard, CompanyLayoutNet.SELL, {"uid": &"shelf_1"}) == &"",
		"The first of two shelves without a uid (shelf_1) is sold")
	var layout: Array = _layout(state)
	_expect(layout.size() == 1 and DefaultShed.piece_uid(layout, 0) == &"shelf_2" and layout[0].get("uid") == "shelf_2"
		and int(layout[0].get("z")) == 4,
		"...and the other keeps its name shelf_2, now stored (%s)" % [layout])
	_expect(_ask(net, heard, CompanyLayoutNet.SELL, {"uid": &"shelf_2"}) == CompanyLayoutNet.REASON_NOT_EMPTY,
		"...still holding its units: it can't be sold")
	net.free()
	state.free()

	# A refused event stores no name: every check comes before the first change.
	var unnamed: Node = _new_state("UnnamedState")
	unnamed.call(&"new_company", "Unnamed SRL")
	var bare: Array[Dictionary] = [
		{"id": "shelf", "x": 3, "z": 2, "turns": 0}, {"id": "shelf", "x": 3, "z": 4, "turns": 0},
	]
	unnamed.set(&"layout", bare)
	var build := CompanyLayoutNet.new()
	var taken_uid: Dictionary = {
		"id": &"fridge", "x": 6, "z": 3, "turns": 0, "uid": &"shelf_2", "minute": 600, "money": 300,
	}
	_expect(not build.apply(unnamed, CompanyLayoutNet.PLACED, taken_uid)
		and not (_layout(unnamed)[0] as Dictionary).has("uid") and not (_layout(unnamed)[1] as Dictionary).has("uid"),
		"A layout_placed with a uid in use is refused before any piece gets its name stored (%s)" % [_layout(unnamed)])
	unnamed.free()

	# A name two pieces share: the later one gets a fresh one, and a new piece is named after that.
	var shared: Node = _new_state("SharedState")
	shared.call(&"new_company", "Shared SRL")
	var twins: Array[Dictionary] = [
		{"id": "shelf", "x": 3, "z": 2, "turns": 0, "uid": "shelf_1"}, {"id": "shelf", "x": 3, "z": 4, "turns": 0},
	]
	shared.set(&"layout", twins)
	var asked: Dictionary = build.check(shared, Inventory.new(), CompanyLayoutNet.PLACE,
		{"id": &"shelf", "x": 6, "z": 3, "turns": 0}, true)
	var placed: bool = asked.get("reason") == &"" and build.apply(shared, asked["kind"], asked["data"])
	var names: Array = []
	for index: int in _layout(shared).size():
		names.append(String(DefaultShed.piece_uid(_layout(shared), index)))
	_expect(placed and names == ["shelf_1", "shelf_2", "shelf_3"],
		"Two shelves both called shelf_1: the second becomes shelf_2 and the new one shelf_3 (%s, %s)"
		% [names, asked])
	shared.free()


## A mirror (a client's copy, from the host's to_dict()) whose wallet missed a movement: the host's
## events carry its balance, so the mirror ends each movement on it; its clock_minutes is not written.
func _check_mirror() -> void:
	var host: Node = _new_state("MirrorHost")
	host.call(&"new_company", "Mirror SRL")
	DefaultShed.load_default().apply_to(host)
	var mirror: Node = _new_state("Mirror")
	mirror.call(&"from_dict", host.call(&"to_dict"))
	var host_build := CompanyLayoutNet.new()
	var mirror_build := CompanyLayoutNet.new()
	host.call(&"earn", 300, &"order_paid")
	host.set(&"clock_minutes", 615)
	mirror.set(&"clock_minutes", SENTINEL_MINUTE)
	var stock: Inventory = host.call(&"stock")
	var steps: Array = [
		[CompanyLayoutNet.PLACE, {"id": &"shelf", "x": 8, "z": 3, "turns": 0}, "a purchase"],
		[CompanyLayoutNet.SELL, {"uid": &"shelf_4"}, "a sale"],
	]
	var drifts: Array[bool] = []
	for step: Array in steps:
		var asked: Dictionary = host_build.check(host, stock, step[0], step[1], true)
		var granted: bool = asked.get("reason") == &""
		var applied: bool = granted and host_build.apply(host, asked["kind"], asked["data"])
		applied = applied and mirror_build.apply(mirror, asked["kind"], asked["data"])
		_expect(applied and int(mirror.get(&"money")) == int(host.get(&"money"))
			and _last_entry(mirror).get("balance") == _last_entry(host).get("balance"),
			"After %s the mirror holds the host's money and entry balance (%s / %s, host %s / %s)"
			% [step[2], mirror.get(&"money"), _last_entry(mirror).get("balance"), host.get(&"money"),
				_last_entry(host).get("balance")])
		_expect(int(_last_entry(mirror).get("minute", -1)) == 615
			and int(mirror.get(&"clock_minutes")) == SENTINEL_MINUTE,
			"...its entry carries the host's minute 615 and its clock_minutes stays %d (%s, %s)"
			% [SENTINEL_MINUTE, _last_entry(mirror).get("minute"), mirror.get(&"clock_minutes")])
		drifts.append(mirror_build.take_drift())
		_expect(not host_build.take_drift(), "...and the host never drifts")
	_expect(drifts == [true, false], "The mirror flags the drift once, then it is in step (%s)" % [drifts])
	host.free()
	mirror.free()


## Every event kind has its own branch in _apply_state(): a kind added later can't fall into the
## layout's (or anyone's) catch-all.
func _check_event_branches() -> void:
	var text: String = FileAccess.get_file_as_string(NET_SCRIPT)
	var start: int = text.find("\nfunc _apply_state(")
	var end: int = text.find("\nfunc ", start + 1)
	_expect(start >= 0 and end > start, "_apply_state() is in %s" % NET_SCRIPT)
	if start < 0 or end <= start:
		return
	var net_consts: Dictionary = (load(NET_SCRIPT) as GDScript).get_script_constant_map()
	var layout_consts: Dictionary = (load(LAYOUT_SCRIPT) as GDScript).get_script_constant_map()
	var covered: Array[StringName] = []
	var catch_all: bool = false
	for line: String in text.substr(start, end - start).split("\n"):
		if not (line.begins_with("\t\t") and not line.begins_with("\t\t\t") and line.strip_edges().ends_with(":")):
			continue
		var pattern: String = line.strip_edges().trim_suffix(":")
		catch_all = catch_all or pattern == "_"
		for token: String in pattern.split(","):
			var name_: String = token.strip_edges()
			if name_.begins_with("&\""):
				covered.append(StringName(name_.trim_prefix("&\"").trim_suffix("\"")))
			elif name_.begins_with("CompanyLayoutNet.") and layout_consts.has(name_.trim_prefix("CompanyLayoutNet.")):
				covered.append(layout_consts[name_.trim_prefix("CompanyLayoutNet.")])
			elif net_consts.has(name_):
				covered.append(net_consts[name_])
	var missing: Array[StringName] = []
	for kind: StringName in CompanyNet.EVENT_KINDS:
		if not covered.has(kind):
			missing.append(kind)
	_expect(missing.is_empty() and not catch_all and covered.size() == CompanyNet.EVENT_KINDS.size(),
		"Every EVENT_KINDS kind has its own branch in _apply_state() (missing %s, catch-all %s, branches %s)"
		% [missing, catch_all, covered])


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
	_host.state.call(&"new_company", "Layout SRL")
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
	_expect(_shed_of(_client) == _shed_of(_host) and _shed_of(_client).size() == _layout(_host.state).size(),
		"The client's shed draws the host's default layout from the snapshot (%d pieces)" % _shed_of(_client).size())
	_host.day.open_day(CompanyTuning.STARTING_DAY)
	_expect(await _synced([_client]) and _client.day.phase() == DayCycle.Phase.OPENING,
		"The host opens the day and the client follows (phase %s)" % _client.day.phase_name())

	var thawed: Array = [
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 5, "z": 3, "turns": 0}],
		[CompanyLayoutNet.PLACE, {"id": &"shelf", "x": 8, "z": 3, "turns": 0}],
		[CompanyLayoutNet.ROTATE, {"uid": &"shelf_4", "turns": 1}],
		[CompanyLayoutNet.MOVE, {"uid": &"fridge_1", "x": 3, "z": 3}],
	]
	await _build_all(thawed, [_client], "in a thawed shed")
	_expect(_client.shed.piece_at(Vector2i(3, 3)) == &"fridge_1" and _client.shed.piece_at(Vector2i(5, 3)) == &""
		and _client.shed.piece_at(Vector2i(8, 4)) == &"shelf_4",
		"The client's shed redrew each change: fridge_1 at (3, 3), shelf_4 turned over (8, 3)-(8, 4)")

	_crew_inside = false
	_host.day.poll()
	_expect(await _synced([_client]) and _host.day.is_frozen() and _client.day.is_frozen(),
		"With the crew out the shed freezes on both peers")
	_host.state.set(&"clock_minutes", 9 * 60 + 15)
	_client.state.set(&"clock_minutes", SENTINEL_MINUTE)
	var frozen: Array = [
		[CompanyLayoutNet.MOVE, {"uid": &"shelf_2", "x": 2, "z": 2}],
		[CompanyLayoutNet.SELL, {"uid": &"shelf_4"}],
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 6, "z": 4, "turns": 0}],
	]
	await _build_all(frozen, [_client], "in a frozen shed")
	_expect(_host.day.is_frozen() and _client.day.is_frozen(), "...and the shed is still frozen after them")
	_expect(int(_last_entry(_client.state).get("minute", -1)) == 9 * 60 + 15
		and int(_client.state.get(&"clock_minutes")) == SENTINEL_MINUTE,
		"The client's wallet entry for the fridge carries the host's minute 09:15 and its clock_minutes"
		+ " stays %d (%s, %s)" % [SENTINEL_MINUTE, _last_entry(_client.state), _client.state.get(&"clock_minutes")])
	_expect(_client.shed.piece_at(Vector2i(2, 2)) == &"shelf_2" and _client.shed.shelves.has(&"shelf_2")
		and _units_on(_client, &"shelf_2") == _units_on(_host, &"shelf_2") and _units_on(_host, &"shelf_2") > 0,
		"shelf_2 moved to (2, 2) keeps its name and its units on the client (%d units)"
		% _units_on(_client, &"shelf_2"))

	_now += 1500
	_crew_inside = true
	_host.day.poll()
	_expect(await _synced([_client]) and not _client.day.is_frozen(), "The crew back in, the shed thaws on both")
	await _build_all([[CompanyLayoutNet.ROTATE, {"uid": &"table_1", "turns": 2}]], [_client], "after the thaw")

	await _check_host_refusals()
	await _check_client_asks()
	await _check_silent_money()
	await _check_late_join(late)
	_check_seqs()


## The host's own requests, each applied on the host and on every follower; between them every
## follower is equal to the host, and a layout event leaves the day as it was.
func _build_all(steps: Array, followers: Array, when: String) -> void:
	for step: Array in steps:
		var days: Array = []
		for peer: Peer in [_host] + followers:
			days.append(_day_of(peer))
		var seq: int = _host.net.seq
		var reason: StringName = _ask(_host.net, _host.refusals, step[0], step[1])
		var synced: bool = await _synced(followers)
		_expect(reason == &"" and _host.net.seq == seq + 1 and synced,
			"%s %s %s goes through and reaches every peer (refused %s)" % [step[0], step[1], when, reason])
		var after: Array = []
		for peer: Peer in [_host] + followers:
			after.append(_day_of(peer))
		_expect(after == days, "...leaving the day as it was (%s, before %s)" % [after, days])
		_expect_equal([_host] + followers, "after %s %s" % [step[0], step[1]])


## Refused requests of the host: no seq, nothing anywhere.
func _check_host_refusals() -> void:
	var seq: int = _host.net.seq
	var before: Dictionary = _company(_client.state)
	var cases: Array = [
		[{"id": &"fridge", "x": 11, "z": 2}, BuildPlacement.REASON_OVERLAP],
		[{"id": &"fridge", "x": 5, "z": 6}, BuildPlacement.REASON_FIXED],
		[{"id": &"shelf", "x": 8, "z": 5}, BuildPlacement.REASON_NO_MONEY],
	]
	for case: Array in cases:
		var got: StringName = _ask(_host.net, _host.refusals, CompanyLayoutNet.PLACE, case[0])
		_expect(got == case[1], "The host placing %s is refused with %s (got %s)" % [case[0], case[1], got])
	await process_frame
	await process_frame
	_expect(_host.net.seq == seq and _client.net.seq == seq and _company(_client.state) == before,
		"...spending no seq and changing nothing on the client (seq %d)" % _client.net.seq)
	_expect_equal([_host, _client], "after the host's refusals")


## The client may ask; only the host builds: host_only, to the client only, nothing changes.
func _check_client_asks() -> void:
	var seq: int = _host.net.seq
	var host_heard: int = _host.refusals.size()
	var asks: Array = [
		[CompanyLayoutNet.PLACE, {"id": &"fridge", "x": 9, "z": 5, "turns": 0}],
		[CompanyLayoutNet.MOVE, {"uid": &"fridge_1", "x": 4, "z": 2}],
		[CompanyLayoutNet.ROTATE, {"uid": &"table_2", "turns": 2}],
		[CompanyLayoutNet.SELL, {"uid": &"fridge_2"}],
	]
	var rids: Array[int] = []
	for ask: Array in asks:
		rids.append(_client.net.request(ask[0], ask[1]))
	var answered: bool = await _wait_for(func() -> bool: return _client.refusals.size() >= asks.size())
	var reasons: Array = []
	for rid: int in rids:
		reasons.append(_reason_heard(_client.refusals, rid))
	_expect(answered and reasons == [CompanyLayoutNet.REASON_HOST_ONLY, CompanyLayoutNet.REASON_HOST_ONLY,
			CompanyLayoutNet.REASON_HOST_ONLY, CompanyLayoutNet.REASON_HOST_ONLY],
		"The client asking to place, move, turn and sell hears host_only for each (%s)" % [reasons])
	_expect(_host.refusals.size() == host_heard and _host.net.seq == seq and _client.net.seq == seq,
		"...only the client hears it and no seq is spent (seq %d)" % _host.net.seq)
	_expect_equal([_host, _client], "after the client's asks")


## The host's wallet moves without an event (a bug elsewhere): the next purchase still ends the
## client's wallet on the host's balance, and the client asks for a snapshot for the history it missed.
func _check_silent_money() -> void:
	_host.state.call(&"earn", 300, &"order_paid")
	var restores: int = _client.restored.size()
	var seq: int = _host.net.seq
	var reason: StringName = _ask(_host.net, _host.refusals, CompanyLayoutNet.PLACE,
		{"id": &"shelf", "x": 8, "z": 5, "turns": 0})
	# The host grants one snapshot request per peer per SNAPSHOT_INTERVAL_MSEC; the client asks again after it.
	var resynced: bool = await _wait_for(func() -> bool:
		return _client.restored.size() == restores + 1 and _client.net.seq == _host.net.seq,
		2.0 * CompanyNet.SNAPSHOT_INTERVAL_MSEC / 1000.0 + 2.0)
	var seen: Array = _client.wallet_at.get(seq + 1, [])
	_expect(reason == &"" and seen.size() == 2 and seen[0] == int(_host.state.get(&"money"))
		and seen[1] == int(_last_entry(_host.state).get("balance", -1)),
		"After the host's silent earning the client ends the purchase on the host's money and balance"
		+ " (%s, host %s)" % [seen, _host.state.get(&"money")])
	_expect(resynced and _client.restored.back() == seq + 1,
		"...then asks for a snapshot and gets it at seq %d (restored %s)" % [seq + 1, _client.restored])
	_expect_equal([_host, _client], "after the snapshot that followed the drift")


## A third peer joins: one event reaches it before its snapshot (held, then dropped), one after.
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
	await _build_all([[CompanyLayoutNet.ROTATE, {"uid": &"fridge_1", "turns": 1}]], [_client], "before the third is up")
	var held: bool = await _wait_for(func() -> bool: return _late.net._held.size() == 1)
	_expect(held and _late.net.seq == 0 and _layout(_late.state).is_empty() and _late.shed.pieces.is_empty(),
		"The late peer holds that event and has no layout yet")
	_expect(await _join(_late) and _late.restored == [_host.net.seq] and _late.seqs.is_empty(),
		"...then the snapshot brings it to the host's seq %d, without applying the held event (restored %s)"
		% [_host.net.seq, _late.restored])
	_expect_equal([_host, _client, _late], "after the late peer's snapshot")
	_expect(_shed_of(_late) == _shed_of(_host) and _late.shed.piece_at(Vector2i(6, 4)) == &"fridge_2",
		"The late peer's shed draws the host's layout from the snapshot (%d pieces)" % _shed_of(_late).size())
	await _build_all([[CompanyLayoutNet.MOVE, {"uid": &"fridge_2", "x": 7, "z": 4}]], [_client, _late],
		"with three peers")
	_expect(_late.shed.piece_at(Vector2i(7, 4)) == &"fridge_2" and _client.shed.piece_at(Vector2i(7, 4)) == &"fridge_2",
		"...and both followers redraw it")


## Every peer applied each event once, in order, with no gap: the host from 1, a client from its
## snapshot on; the client saw the host's kinds in the host's order.
func _check_seqs() -> void:
	_expect(_host.seqs == _range(1, _host.net.seq), "The host's events are 1..%d with no gap (%s)"
		% [_host.net.seq, _host.seqs])
	for peer: Peer in [_client, _late]:
		var first: int = peer.restored[0] + 1 if not peer.restored.is_empty() else 1
		_expect(peer.seqs == _range(first, _host.net.seq),
			"%s applied %d..%d with no gap or repeat (%s)" % [peer.side.name, first, _host.net.seq, peer.seqs])
		_expect(peer.kinds == _host.kinds.slice(first - 1),
			"%s applied the host's kinds in its order" % peer.side.name)
	var layout_events: int = 0
	for kind: StringName in _host.kinds:
		if CompanyLayoutNet.EVENT_KINDS.has(kind):
			layout_events += 1
	_expect(layout_events >= 10, "The host published %d layout events" % layout_events)
	for data: Dictionary in _client.layout_events:
		_expect(RpcGuard.dict_ok(data) and var_to_bytes(data).size() <= EVENT_BYTES_MAX,
			"What reached the client is plain and small (%d bytes: %s)" % [var_to_bytes(data).size(), data])


# --- Helpers ---


func _make_peer(side_name: String) -> Peer:
	var peer := Peer.new()
	peer.side = Node.new()
	peer.side.name = side_name
	root.add_child(peer.side)
	set_multiplayer(SceneMultiplayer.new(), peer.side.get_path())
	peer.state = _new_state(side_name + "State")
	return peer


## The world of one peer, as CompanyRoot builds it: CompanyNet, the day hooked to it and the shed
## following it.
func _add_world(peer: Peer) -> void:
	peer.net = CompanyNet.new()
	peer.net.name = "CompanyNet"
	peer.net.company = peer.state
	peer.side.add_child(peer.net)
	peer.day = DayCycle.new()
	peer.day.name = "DayCycle"
	peer.side.add_child(peer.day)
	peer.day.set_process(false)
	peer.day.ticks = func() -> int: return _now
	peer.day.crew_in_shed = func() -> bool: return _crew_inside
	peer.day.attach(peer.net, null, peer.state)
	peer.shed = CompanyShed.new()
	peer.shed.name = "Shed"
	peer.side.add_child(peer.shed)
	peer.shed.follow(peer.net)
	peer.net.event_applied.connect(func(seq: int, kind: StringName, data: Dictionary) -> void:
		peer.seqs.append(seq)
		peer.kinds.append(kind)
		peer.wallet_at[seq] = [int(peer.state.get(&"money")), int(_last_entry(peer.state).get("balance", 0))]
		if CompanyLayoutNet.EVENT_KINDS.has(kind):
			peer.layout_events.append(data))
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
			"%s has the host's company %s (layout %s, money %s)"
			% [peer.side.name, when, _layout(peer.state), peer.state.get(&"money")])
		_expect(peer.net.inventory.to_dict() == first.net.inventory.to_dict(),
			"%s has the host's stock %s" % [peer.side.name, when])
		_expect(_day_of(peer) == _day_of(first),
			"%s has the host's day %s (%s)" % [peer.side.name, when, _day_of(peer)])
		_expect(_shed_of(peer) == _shed_of(first), "%s draws the host's shed %s" % [peer.side.name, when])


## Asks `kind` on `net` and returns the refusal it heard for it at once (&"" when none: on the
## host a request is answered before request() returns).
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


static func _layout(state: Node) -> Array:
	return state.get(&"layout")


static func _piece(state: Node, uid: StringName) -> Dictionary:
	var index: int = CompanyLayoutNet.piece_index(_layout(state), uid)
	return _layout(state)[index] if index >= 0 else {}


static func _last_entry(state: Node) -> Dictionary:
	var ledger: Array = state.get(&"ledger")
	return ledger.back() if not ledger.is_empty() else {}


## Units in the slots of shelf `uid` on that peer.
static func _units_on(peer: Peer, uid: StringName) -> int:
	var total: int = 0
	for slot: int in range(8):
		for qty: int in peer.net.inventory.contents_at(DefaultShed.shelf_location(uid, slot)).values():
			total += qty
	return total


static func _day_of(peer: Peer) -> Array:
	return [peer.day.phase_name(), peer.day.current_day(), peer.day.is_frozen(), peer.day.shed_minute()]


static func _shed_of(peer: Peer) -> Array:
	var rows: Array = []
	for piece: Dictionary in peer.shed.pieces:
		rows.append([piece["uid"], piece["id"], piece["rect"]])
	return rows


## CompanyState.to_dict() without its stored stock: what must match across peers.
static func _company(state: Node) -> Dictionary:
	var data: Dictionary = state.call(&"to_dict")
	data.erase("inventory")
	return data


## _company() as every peer holds it: clock_minutes is the host clock's to write (GameClock, D-0219),
## a client reads the time from its own clock; the wallet entries carry the host's minute.
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
