extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_table_restock_discard.gd
##
## Restocking a packing table and throwing its open box away over the network (D-0715.c,
## scripts/core/company/company_table_net.gd through CompanyNet; contract
## docs/expansion-distritos/diseno/red-autoridad.md section 2 rows 15a and 15b, and section 14):
## - solo (offline): a table out of tape can't tape its box (no_supply: stuck); box_restock {tape}
##   fills it back to capacity for free (box_restocked {table, supply, count}: no money, no wallet
##   entry, D-0718) and the box tapes; a full supply is supply_full, an unknown one or none bad_data,
##   one the day is short of (short_of, box_shortage) no_supply, a far table or a shelf the usual
##   reasons, and none of them changes anything or spends a seq;
## - box_discard {station}: the open box leaves the table, thrown away (padding, label and seals go
##   with it, nothing is refunded and no box goes back to the table's supplies) and the table opens
##   another size at once; its units go back to the sender's hands when they all fit there (one
##   product, hands empty or with that product, up to HAND_MAX_UNITS), else into one new floor
##   bundle at the table's spot, which units_take takes from; an empty box just goes; the order's
##   reservation stays; no_box at a free table, out_of_reach far;
## - events that don't fit this copy (an unknown supply, a count that isn't the capacity, a float
##   count, another box id, other contents, contents that aren't a dictionary, a shelf or two
##   products into the hands as destination, a bundle id that isn't floor:<n>, a bundle without a
##   finite pos or that already holds units, a table without a box) are not applied and change
##   nothing; the good one then puts the bundle in CompanyNet's floor_bundles;
## - host, client and a late joiner as ENet peers in one process: the client finds table_1 out of
##   tape (box_tape: no_supply), restocks it and the host tapes the box; the client throws away a box
##   with a hen and a puppy (the same floor bundle, at the same spot, on both) and, asked at once,
##   the host's discard of its own box goes through (into its hands) and the client's hears no_box;
##   the late peer gets the restocked table and the bundle by snapshot and empties the bundle with
##   units_take; every peer equal after every step (tables, stock, floor bundles, company) and every
##   peer's seqs with no gap or repeat.
## Expected in the log: nothing from CompanyNet or CompanyTableNet.

const PORT: int = 24695
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## CompanyTableNet, short: its kinds and reasons are on almost every line.
const T := preload("res://scripts/core/company/company_table_net.gd")
const TAKE: StringName = &"units_take"

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
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: a packing table restocks and throws its open box away through the host,"
			+ " the units back in the hands or on the floor, equal on host, client and a late joiner")
	quit(_failures)


# --- Solo ---


func _check_solo() -> void:
	var state: Node = _new_state("SoloState")
	state.call(&"new_company", "Solo SRL")
	state.set(&"clock_minutes", 600)
	var net := CompanyNet.new()
	net.name = "SoloNet"
	net.company = state
	root.add_child(net)
	net.inventory = Inventory.new()
	net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	var heard: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void:
		heard.append([rid, reason]))
	var events: Array = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void:
		events.append([kind, data]))
	_check_restock(net, state, heard, events)
	_check_discard(net, state, heard, events)
	_check_bad_events(net, state)
	net.free()
	state.free()


func _check_restock(net: CompanyNet, state: Node, heard: Array, events: Array) -> void:
	var stock: Inventory = net.inventory
	var hands: StringName = CompanyNet.hands_location(1)
	stock.receive(&"hen", 1, hands)
	var restock: Callable = func(supply: StringName) -> StringName:
		return _ask(net, heard, T.RESTOCK, {"station": &"table_1", "supply": supply})
	var before: Array = _solo_state(net, state)
	var seq: int = net.seq
	var cases: Array = [
		[{"station": &"table_1", "supply": &"tape"}, T.REASON_FULL, "a fresh table's tape"],
		[{"station": &"table_1", "supply": &"glue"}, T.REASON_BAD_DATA, "an unknown supply"],
		[{"station": &"table_1", "supply": 3}, T.REASON_BAD_DATA, "a number for a supply"],
		[{"station": &"table_1"}, T.REASON_BAD_DATA, "no supply"],
		[{"station": &"far_table", "supply": &"tape"}, CompanyNet.REASON_OUT_OF_REACH, "a far table"],
		[{"station": &"shelf", "supply": &"tape"}, CompanyNet.REASON_NO_STATION, "a shelf"],
	]
	for case: Array in cases:
		var got: StringName = _ask(net, heard, T.RESTOCK, case[0])
		_expect(got == case[1], "box_restock of %s is refused with %s (got %s)" % [case[2], case[1], got])
	_expect(_solo_state(net, state) == before and net.seq == seq,
		"...and no refusal changed anything or spent a seq (seq %d)" % net.seq)

	_expect(_ask(net, heard, T.START, {"station": &"table_1", "size": &"M"}) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen")) == &"", "table_1 opens a box with a hen")
	var desk: PackingStation = net.table.station_of(&"table_1")
	desk.supplies.take(StationSupplies.TAPE, desk.supplies.count(StationSupplies.TAPE))
	_expect(_ask(net, heard, T.TAPE, {"station": &"table_1"}) == T.REASON_NO_SUPPLY,
		"Out of tape the box can't be taped (no_supply): the table is stuck with it")
	var money: int = int(state.get(&"money"))
	var entries: int = (state.get(&"ledger") as Array).size()
	var tape_full: int = int(CompanyTuning.SUPPLY_CAPACITY[StationSupplies.TAPE])
	_expect(restock.call(StationSupplies.TAPE) == &""
		and desk.supplies.count(StationSupplies.TAPE) == tape_full,
		"box_restock {tape} fills the table's tape back to %d" % tape_full)
	var restocked: Array = events.back()
	_expect(restocked[0] == T.RESTOCKED
		and restocked[1] == {"table": &"table_1", "supply": StationSupplies.TAPE, "count": tape_full},
		"...as box_restocked {table, supply, count} (%s)" % [restocked])
	_expect(int(state.get(&"money")) == money and (state.get(&"ledger") as Array).size() == entries,
		"...for free: no money moves and no wallet entry (D-0718)")
	_expect(restock.call(StationSupplies.TAPE) == T.REASON_FULL, "...and once full it is supply_full")
	_expect(_ask(net, heard, T.TAPE, {"station": &"table_1"}) == &"" and not net.table.has_box(&"table_1"),
		"Restocked, the box tapes and leaves the table")

	desk.supplies.take(&"box_M", 2)
	desk.supplies.take(&"box_S", 1)
	net.table.short_of = func(supply: StringName) -> bool: return supply == &"box_M"
	seq = net.seq
	_expect(restock.call(&"box_M") == T.REASON_NO_SUPPLY and net.seq == seq
		and desk.supplies.count(&"box_M") == 3,
		"A day short of M boxes (box_shortage) refuses restocking them with no_supply")
	_expect(restock.call(&"box_S") == &"" and desk.supplies.count(&"box_S") == 6,
		"...while S boxes restock")
	net.table.short_of = Callable()
	_expect(restock.call(&"box_M") == &"" and desk.supplies.count(&"box_M") == 6,
		"With no shortage the M boxes restock too")


func _check_discard(net: CompanyNet, state: Node, heard: Array, events: Array) -> void:
	var stock: Inventory = net.inventory
	var hands: StringName = CompanyNet.hands_location(1)
	stock.receive(&"hen", 8, &"shelf:s_0")
	stock.receive(&"puppy", 2, &"shelf:s_1")
	stock.reserve(&"hen", 1, &"o1")
	var discard: Callable = func() -> StringName:
		return _ask(net, heard, T.DISCARD, {"station": &"table_2"})
	var seq: int = net.seq
	_expect(discard.call() == T.REASON_NO_BOX and net.seq == seq,
		"Throwing away a box at a table with none: no_box")
	_expect(_ask(net, heard, T.DISCARD, {"station": &"far_table"}) == CompanyNet.REASON_OUT_OF_REACH,
		"...at a far table: out_of_reach")

	var order: Dictionary = Order.make(&"o1", "Ana", &"centro", &"centro_house_12",
		[{"product": &"hen", "qty": 2}], 0, {})
	net.table.order_of = func(table: StringName) -> Dictionary:
		return order if table == &"table_2" else {}
	stock.move(&"hen", 4, &"shelf:s_0", hands)
	var packed: bool = _ask(net, heard, T.START, {"station": &"table_2", "size": &"M"}) == &"" \
		and _ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2")) == &"" \
		and _ask(net, heard, T.PLACE, _cell(0, 0, 1, &"hen", &"table_2")) == &"" \
		and _ask(net, heard, T.FILL, {"station": &"table_2", "cells": 3}) == &"" \
		and _ask(net, heard, T.STAMP, {"station": &"table_2", "stamp": &"fragile"}) == &"" \
		and _ask(net, heard, T.LABEL, {"station": &"table_2"}) == &""
	var desk: PackingStation = net.table.station_of(&"table_2")
	var box: StringName = net.table.box_of(&"table_2")
	_expect(packed and stock.count(&"hen", hands) == 2 and desk.box.label_order_id == &"o1",
		"table_2 packs %s: two hens, 3 cells of padding, a seal and o1's label" % box)
	var supplies: Dictionary = desk.supplies.to_dict()
	var money: int = int(state.get(&"money"))
	var entries: int = (state.get(&"ledger") as Array).size()
	_expect(discard.call() == &"" and not net.table.has_box(&"table_2"),
		"box_discard throws %s away: table_2 holds no box" % box)
	var thrown: Array = events.back()
	_expect(thrown[0] == T.DISCARDED and thrown[1] == {"table": &"table_2", "box": box,
		"contents": {&"hen": 2}, "to": hands},
		"...as box_discarded {table, box, contents, to: hands:1} (%s)" % [thrown])
	_expect(stock.count(&"hen", hands) == 4 and stock.contents_at(T.box_location(box)).is_empty()
		and stock.reserved_by(&"o1") == {&"hen": 1},
		"Its two hens are back in the hands, up to the limit of 4; o1's reservation stays (%s)"
		% [stock.reserved_by(&"o1")])
	_expect(desk.supplies.to_dict() == supplies and int(state.get(&"money")) == money
		and (state.get(&"ledger") as Array).size() == entries,
		"Nothing is refunded: no box or padding back to the table, no money, no wallet entry")
	_expect(_ask(net, heard, T.START, {"station": &"table_2", "size": &"S"}) == &""
		and net.table.station_of(&"table_2").box.box_size == &"S"
		and net.table.station_of(&"table_2").box.label_order_id == &"",
		"The table is free at once: it opens an S box, with no label or seal left from the old one")

	_check_discard_to_floor(net, heard, events)


## What doesn't fit in the hands goes into one new floor bundle at the table's spot.
func _check_discard_to_floor(net: CompanyNet, heard: Array, events: Array) -> void:
	var stock: Inventory = net.inventory
	var hands: StringName = CompanyNet.hands_location(1)
	var discard: Callable = func() -> StringName:
		return _ask(net, heard, T.DISCARD, {"station": &"table_2"})
	stock.move(&"hen", 3, hands, &"shelf:s_0")
	stock.move(&"puppy", 1, &"shelf:s_1", hands)
	_expect(discard.call() == &"" and _ask(net, heard, T.START, {"station": &"table_2", "size": &"M"}) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2")) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 1, &"puppy", &"table_2")) == &"",
		"The empty S box goes (nothing moves) and an M box takes a hen and a puppy")
	var spot: Vector3 = _stations()[&"table_2"]["spot"]
	_expect(discard.call() == &"" and events.back()[1].get("to") == &"floor:0"
		and events.back()[1].get("pos") == spot,
		"Two products don't fit in the hands: box_discarded goes to floor:0 at the table's spot (%s)"
		% [events.back()])
	_expect(stock.contents_at(&"floor:0") == {&"hen": 1, &"puppy": 1}
		and net.floor_bundles.position_of(&"floor:0") == spot and stock.contents_at(hands).is_empty(),
		"...the hen and the puppy lie in bundle floor:0, where CompanyNet's floor_bundles has it")
	_expect(_ask(net, heard, TAKE, {"station": &"floor:0", "product": &"puppy", "qty": 1}) == &""
		and stock.count(&"puppy", hands) == 1,
		"units_take takes the puppy back from the bundle")

	stock.move(&"hen", 1, &"shelf:s_0", hands)
	_expect(_ask(net, heard, T.START, {"station": &"table_2", "size": &"M"}) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2")) == &""
		and discard.call() == &"" and events.back()[1].get("to") == &"floor:1",
		"A hen into hands holding a puppy doesn't fit either: a new bundle, floor:1 (%s)"
		% [events.back()])
	stock.move(&"puppy", 1, hands, &"shelf:s_1")
	stock.move(&"hen", 5, &"shelf:s_0", hands)
	_expect(_ask(net, heard, T.START, {"station": &"table_2", "size": &"M"}) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2")) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 1, &"hen", &"table_2")) == &""
		and discard.call() == &"" and events.back()[1].get("to") == &"floor:2"
		and stock.count(&"hen", hands) == 3,
		"Two hens into hands holding three would pass the limit of 4: floor:2, the hands keep 3")
	stock.move(&"hen", 3, hands, &"shelf:s_0")


## Rule 6: an event is applied as it comes, checked only as data and against this copy.
func _check_bad_events(net: CompanyNet, state: Node) -> void:
	var stock: Inventory = net.inventory
	var hands: StringName = CompanyNet.hands_location(1)
	var heard: Array = []
	stock.move(&"hen", 1, &"shelf:s_0", hands)
	stock.move(&"puppy", 1, &"shelf:s_1", hands)
	_expect(_ask(net, heard, T.START, {"station": &"table_3", "size": &"M"}) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen", &"table_3")) == &""
		and _ask(net, heard, T.PLACE, _cell(0, 0, 1, &"puppy", &"table_3")) == &"",
		"table_3 holds a box with a hen and a puppy")
	stock.receive(&"hen", 1, &"floor:5")
	var box: StringName = net.table.box_of(&"table_3")
	var tape: Dictionary = {"table": &"table_3", "supply": StationSupplies.TAPE,
		"count": int(CompanyTuning.SUPPLY_CAPACITY[StationSupplies.TAPE])}
	var good: Dictionary = {"table": &"table_3", "box": box, "contents": {&"hen": 1, &"puppy": 1},
		"to": &"floor:7", "pos": Vector3.ONE}
	var no_pos: Dictionary = good.duplicate()
	no_pos.erase("pos")
	var bad: Array = [
		[T.RESTOCKED, _with(tape, "supply", &"glue"), "an unknown supply"],
		[T.RESTOCKED, _with(tape, "count", 9), "a count short of the capacity"],
		[T.RESTOCKED, _with(tape, "count", 10.0), "a float count"],
		[T.RESTOCKED, _with(tape, "table", 4), "a table that isn't an id"],
		[T.DISCARDED, _with(good, "box", &"box_99"), "another box id"],
		[T.DISCARDED, _with(good, "contents", {&"hen": 1}), "other contents"],
		[T.DISCARDED, _with(good, "contents", [&"hen", &"puppy"]), "contents that aren't a dictionary"],
		[T.DISCARDED, _with(good, "to", &"shelf:s_0"), "a shelf for a destination"],
		[T.DISCARDED, _with(no_pos, "to", hands), "two products into the hands"],
		[T.DISCARDED, _with(good, "to", &"floor:x"), "a bundle id that isn't floor:<n>"],
		[T.DISCARDED, no_pos, "a bundle without pos"],
		[T.DISCARDED, _with(good, "pos", Vector3(NAN, 0.0, 0.0)), "a bundle at NaN"],
		[T.DISCARDED, _with(good, "to", &"floor:5"), "a bundle that already holds units"],
		[T.DISCARDED, _with(good, "table", &"table_1"), "a table without a box"],
	]
	var before: Array = _solo_state(net, state)
	for case: Array in bad:
		_expect(not net.table.apply(state, stock, case[0], case[1]),
			"An event with %s is not applied" % case[2])
	_expect(_solo_state(net, state) == before, "...and changed nothing")
	_expect(net.table.apply(state, stock, T.DISCARDED, good) and not net.table.has_box(&"table_3")
		and stock.contents_at(&"floor:7") == {&"hen": 1, &"puppy": 1}
		and net.floor_bundles.position_of(&"floor:7") == Vector3.ONE,
		"The good box_discarded applies: the bundle floor:7 is in CompanyNet's floor_bundles")


# --- Network ---


func _check_network() -> void:
	_host = _make_peer("HostSide")
	_client = _make_peer("ClientSide")
	_late = _make_peer("LateSide")
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var late := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 3) == OK
	_host.side.multiplayer.multiplayer_peer = server
	_host.state.call(&"new_company", "Restock SRL")
	var stock := Inventory.new()
	stock.receive(&"hen", 8, &"shelf:s_0")
	stock.receive(&"puppy", 4, &"shelf:s_1")
	_host.state.call(&"store_stock", stock)
	_add_net(_host)
	_host.net.inventory = _host.state.call(&"stock")
	_host.net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	_host.net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	# table_1 ran out of tape before anyone joined: the client's snapshot brings it so.
	var no_tape: Dictionary = StationSupplies.full().to_dict()
	no_tape["tape"] = 0
	_host.net.table.put_snapshot({"serial": 0, "tables": {
		"table_1": {"box_id": "", "box": {}, "supplies": no_tape},
	}})
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
	_expect(await _join(_client),
		"The client gets the host's snapshot (restored %s)" % [_client.restored])
	_expect_equal([_host, _client], "after the client's snapshot")
	var opened: Array = [
		[_client, T.START, {"station": &"table_1", "size": &"M"}, "the client opens a box on table_1"],
		[_client, TAKE, _take(&"hen"), "takes a hen"],
		[_client, T.PLACE, _cell(0, 0, 0, &"hen"), "puts it in"],
		[_host, T.FILL, {"station": &"table_1", "cells": 2}, "the host pads 2 cells"],
	]
	await _steps(opened, [_client], [_host, _client])
	var seq: int = _host.net.seq
	_expect(await _do(_client, T.TAPE, {"station": &"table_1"}, [_client]) == T.REASON_NO_SUPPLY
		and _host.net.seq == seq, "The client can't tape it: table_1 has no tape (no_supply), no seq spent")
	var fixed: Array = [
		[_client, T.RESTOCK, {"station": &"table_1", "supply": StationSupplies.TAPE},
			"the client restocks table_1's tape"],
		[_host, T.TAPE, {"station": &"table_1"}, "the host tapes the box"],
	]
	await _steps(fixed, [_client], [_host, _client])
	_expect(_client.net.table.station_of(&"table_1").supplies.count(StationSupplies.TAPE)
		== int(CompanyTuning.SUPPLY_CAPACITY[StationSupplies.TAPE]) - 1
		and not _client.net.table.has_box(&"table_1"),
		"On the client too table_1 has its tape back, one roll used, and no box")
	var thrown: Array = [
		[_client, T.START, {"station": &"table_2", "size": &"M"}, "the client opens a box on table_2"],
		[_client, TAKE, _take(&"hen"), "takes a hen"],
		[_client, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2"), "puts it in"],
		[_client, TAKE, _take(&"puppy"), "takes a puppy"],
		[_client, T.PLACE, _cell(0, 0, 1, &"puppy", &"table_2"), "puts it on top"],
		[_host, T.STAMP, {"station": &"table_2", "stamp": &"fragile"}, "the host stamps it"],
		[_client, T.DISCARD, {"station": &"table_2"}, "the client throws the box away"],
	]
	await _steps(thrown, [_client], [_host, _client])
	var spot: Vector3 = _stations()[&"table_2"]["spot"]
	_expect(_client.net.inventory.contents_at(&"floor:0") == {&"hen": 1, &"puppy": 1}
		and _client.net.floor_bundles.position_of(&"floor:0") == spot
		and not _client.net.table.has_box(&"table_2"),
		"On the client the hen and the puppy lie in floor:0 at table_2's spot and the box is gone")
	await _check_clash()
	await _check_late_join(late)
	_check_seqs()


## The client's discard reaches the host after the host threw the same box away itself.
func _check_clash() -> void:
	var opened: Array = [
		[_host, TAKE, _take(&"hen"), "the host takes a hen"],
		[_host, T.START, {"station": &"table_2", "size": &"S"}, "opens an S box on table_2"],
		[_host, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2"), "puts the hen in"],
	]
	await _steps(opened, [_client], [_host, _client])
	var seq: int = _host.net.seq
	var heard: int = _host.refusals.size()
	var rid: int = _client.net.request(T.DISCARD, {"station": &"table_2"})
	var host_reason: StringName = _ask(_host.net, _host.refusals, T.DISCARD, {"station": &"table_2"})
	var answered: bool = await _wait_for(func() -> bool:
		return _reason_heard(_client.refusals, rid) != &"" and _client.net.seq == _host.net.seq)
	_expect(host_reason == &"" and answered and _reason_heard(_client.refusals, rid) == T.REASON_NO_BOX
		and _host.net.seq == seq + 1 and _host.refusals.size() == heard,
		"Both throw table_2's box away at once: the host's goes, only the client hears no_box")
	_expect(_host.net.inventory.count(&"hen", CompanyNet.hands_location(1)) == 1,
		"...and the host's hen is back in its hands")
	_expect_equal([_host, _client], "after the clashing discards")


## A third peer joins with the restocked table and the bundle on the floor, and empties it.
func _check_late_join(late: ENetMultiplayerPeer) -> void:
	var up: bool = late.create_client("127.0.0.1", PORT) == OK
	_late.side.multiplayer.multiplayer_peer = late
	_add_net(_late)
	_late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(_connected.bind(_late, 2))
	_expect(up and connected, "A third peer connects late")
	if not connected:
		return
	_expect(await _join(_late) and _late.restored == [_host.net.seq],
		"The snapshot brings it to seq %d (restored %s)" % [_host.net.seq, _late.restored])
	_expect_equal([_host, _client, _late], "after the late peer's snapshot")
	_expect(_late.net.floor_bundles.position_of(&"floor:0") == _stations()[&"table_2"]["spot"]
		and _late.net.table.station_of(&"table_1").supplies.count(StationSupplies.TAPE) > 0,
		"The late peer has the bundle where it lies and table_1's tape")
	var emptied: Array = [
		[_late, TAKE, {"station": &"floor:0", "product": &"puppy", "qty": 1}, "takes the puppy off floor:0"],
		[_late, &"units_store", {"station": &"shelf_puppy", "product": &"puppy", "qty": 1}, "shelves it"],
		[_late, TAKE, {"station": &"floor:0", "product": &"hen", "qty": 1}, "takes the hen"],
	]
	await _steps(emptied, [_client, _late], [_host, _client, _late])
	_expect(_late.net.floor_bundles.position_of(&"floor:0") == null
		and _client.net.floor_bundles.position_of(&"floor:0") == null,
		"Emptied, the bundle is gone on every peer")


## Every peer applied each event once, in order, with no gap: the host from 1, a client from its
## snapshot on.
func _check_seqs() -> void:
	_expect(_host.seqs == _range(1, _host.net.seq), "The host's events are 1..%d" % _host.net.seq)
	for peer: Peer in [_client, _late]:
		var first: int = peer.restored[0] + 1 if not peer.restored.is_empty() else 1
		_expect(peer.seqs == _range(first, _host.net.seq),
			"%s applied %d..%d with no gap or repeat (%s)"
			% [peer.side.name, first, _host.net.seq, peer.seqs])


# --- Helpers ---


static func _stations() -> Dictionary:
	return {
		&"table_1": {"location": &"table:table_1", "spot": Vector3(0.0, 0.0, 1.0)},
		&"table_2": {"location": &"table:table_2", "spot": Vector3(1.0, 0.0, 1.0)},
		&"table_3": {"location": &"table:table_3", "spot": Vector3(2.0, 0.0, 1.0)},
		&"far_table": {"location": &"table:table_9", "spot": Vector3(80.0, 0.0, 0.0)},
		&"shelf": {"location": &"shelf:s_0", "spot": Vector3(0.0, 0.0, -1.0)},
		&"shelf_hen": {"location": &"shelf:s_0", "spot": Vector3(0.0, 0.0, -1.0)},
		&"shelf_puppy": {"location": &"shelf:s_1", "spot": Vector3(0.5, 0.0, -1.0)},
	}


static func _cell(cx: int, cy: int, cz: int, product: StringName,
		station: StringName = &"table_1") -> Dictionary:
	return {"station": station, "cx": cx, "cy": cy, "cz": cz, "product": product, "rot": 0}


## units_take of one unit of `product` from its shelf.
static func _take(product: StringName) -> Dictionary:
	return {"station": StringName("shelf_%s" % product), "product": product, "qty": 1}


## True once `peer` sees the host and the host sees `peers` clients.
func _connected(peer: Peer, peers: int) -> bool:
	return peer.side.multiplayer.get_peers().has(1) \
		and _host.side.multiplayer.get_peers().size() == peers


static func _solo_state(net: CompanyNet, state: Node) -> Array:
	return [net.table.to_dict(), net.inventory.to_dict(), net.floor_bundles.to_dict(), _company(state)]


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
	return await _wait_for(func() -> bool:
		return not peer.restored.is_empty() and peer.net.seq == _host.net.seq)


## Each step [peer, kind, data, what] in turn: it goes through and `peers` end equal.
func _steps(steps: Array, followers: Array, peers: Array) -> void:
	for step: Array in steps:
		var reason: StringName = await _do(step[0], step[1], step[2], followers)
		_expect(reason == &"", "%s (refused %s)" % [step[3], reason])
		_expect_equal(peers, "after %s" % step[3])


## `peer` asks `kind`; returns the refusal it heard, or &"" once the host's event reached every
## follower.
func _do(peer: Peer, kind: StringName, data: Dictionary, followers: Array) -> StringName:
	var seq: int = _host.net.seq
	var rid: int = peer.net.request(kind, data)
	await _wait_for(func() -> bool:
		return (_reason_heard(peer.refusals, rid) != &""
			or (_host.net.seq > seq and _at_host_seq(followers))))
	return _reason_heard(peer.refusals, rid)


func _at_host_seq(followers: Array) -> bool:
	for peer: Peer in followers:
		if peer.net.seq != _host.net.seq:
			return false
	return true


func _expect_equal(peers: Array, when: String) -> void:
	var first: Peer = peers[0]
	for peer: Peer in peers.slice(1):
		_expect(peer.net.table.to_dict() == first.net.table.to_dict(),
			"%s has the host's tables %s (%s / %s)"
			% [peer.side.name, when, peer.net.table.to_dict(), first.net.table.to_dict()])
		_expect(peer.net.inventory.to_dict() == first.net.inventory.to_dict(),
			"%s has the host's stock %s" % [peer.side.name, when])
		_expect(peer.net.floor_bundles.to_dict() == first.net.floor_bundles.to_dict(),
			"%s has the host's floor bundles %s (%s)" % [peer.side.name, when, peer.net.floor_bundles.to_dict()])
		_expect(_shared(peer.state) == _shared(first.state),
			"%s has the host's company %s (money %s)"
			% [peer.side.name, when, peer.state.get(&"money")])


## Asks `kind` on `net` and returns the refusal heard for it at once (&"" when none: on the host
## a request is answered before request() returns).
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


## CompanyState.to_dict() without its stored stock.
static func _company(state: Node) -> Dictionary:
	var data: Dictionary = state.call(&"to_dict")
	data.erase("inventory")
	return data


## _company() as every peer holds it: clock_minutes is the host clock's to write.
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
