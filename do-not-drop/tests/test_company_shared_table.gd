extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_shared_table.gd
##
## Shared packing tables over the network (D-0715, scripts/core/company/company_table_net.gd
## through CompanyNet; contract docs/expansion-distritos/diseno/red-autoridad.md section 2 rows 9
## to 15 and section 9):
## - solo (offline): open a box (pays BOX_COST, takes a box of that size from the table, box_1),
##   put two hens from the hands in the grid, take one out to the hands and put it back, pad, stamp,
##   label with the table's order (order_of) and tape: box_sealed carries the contract's fields
##   plus money and minute (the quality AssemblyQuality gives the taped box), the box leaves the
##   table, its units go from box:box_1 to package:box_1, the order's reservation drops by them and
##   tape and money are spent once; the next box is box_3 (box_2 is on the other table);
## - refusals change nothing and spend no seq: has_box, no_box, cell_taken (overlap, out of the
##   box), empty_cell, not_enough, hands_busy, hands_full, no_room, no_supply, no_money, no_order,
##   already_stamped, empty_box, reserved_for_other (the table's own order still goes through),
##   no_station (unknown, a shelf), out_of_reach and bad_data (size, product, path, seal, float or
##   negative cell, a rotation, cells 0); a cell sent as a Vector3i is dropped in silence;
## - the layout won't sell a table holding a box (not_empty); once its box is sealed it sells, and
##   the table's state is forgotten;
## - events that don't fit this copy (a table that holds a box, a box id in use, an unknown size, a
##   negative balance, a table without a box, units not in those hands, a source that isn't a
##   pair of hands, an empty cell, contents that differ) are not applied and change nothing;
## - the snapshot part: to_dict() through var_to_bytes and put_snapshot() gives the same tables;
##   a malformed one (not a dictionary, negative serial, overlapping products, an unknown product,
##   supplies over capacity, a box without its id, one box id twice) is refused, changing nothing;
## - host and client as ENet peers in one process, one shared table and no owner: the client opens
##   the box and puts a hen and a puppy in, the host stamps, pads and labels it and tapes it; after
##   every step both hold the same tables, Inventory and company (money, wallet entries with the
##   host's minute); the client asking to tape the box already sealed hears no_box;
## - the same thing asked twice at once: the client's box_start and box_place reach the host after
##   the host's own for that table and cell; the host's goes through, the client hears has_box and
##   cell_taken (only it), nothing else changes;
## - a third peer joins late with a box half packed: it holds the event that reaches it before its
##   snapshot, gets the tables from the snapshot's "packing" part, puts a hen in that box itself and
##   the client tapes it; the three end equal and every peer's seqs have no gap or repeat.
## Expected in the log: nothing from CompanyNet or CompanyTableNet.

const PORT: int = 24653
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## The host's clock minute in the network part; a client's clock_minutes is never written by it.
const HOST_MINUTE: int = 9 * 60 + 30
const SENTINEL_MINUTE: int = 7
## CompanyTableNet, short: its kinds and reasons are on almost every line.
const T := preload("res://scripts/core/company/company_table_net.gd")
const TAKE: StringName = &"units_take"
const HEN: String = "res://data/products/hen.tres"

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
	_check_snapshot_part()
	await _check_network()
	RpcGuard.reset()
	if _failures == 0:
		print("PASS: one packing table shared by every peer, checked by the host step by step,"
			+ " equal on host, client and a late joiner, clashing requests serialized")
	quit(_failures)


# --- Solo ---


func _check_solo() -> void:
	var state: Node = _new_state("SoloState")
	state.call(&"new_company", "Solo SRL")
	DefaultShed.load_default().apply_to(state)
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
	var events: Array[Dictionary] = []
	net.event_applied.connect(func(_seq: int, _kind: StringName, data: Dictionary) -> void:
		events.append(data))
	var hands: StringName = CompanyNet.hands_location(1)
	var stock: Inventory = net.inventory
	stock.receive(&"hen", 3, hands)
	stock.receive(&"hen", 8, &"shelf:s_0")
	stock.receive(&"puppy", 2, &"shelf:s_1")
	var money: int = int(state.get(&"money"))
	var m_cost: int = BoxDispenser.cost_of(&"M")

	_expect(_ask(net, heard, T.START, {"station": &"table_1", "size": &"M"}) == &""
		and net.table.box_of(&"table_1") == &"box_1" and int(state.get(&"money")) == money - m_cost,
		"Solo, box_start opens box_1 on table_1 and pays %d (money %s)"
		% [m_cost, state.get(&"money")])
	var desk: PackingStation = net.table.station_of(&"table_1")
	_expect(desk != null and desk.box.box_size == &"M" and desk.supplies.count(&"box_M") == 5
		and events.back().keys().size() == 5 and events.back()["money"] == money - m_cost
		and events.back()["minute"] == 600,
		"...an empty M box, one box_M less, and box_started {table, size, box, money, minute} (%s)"
		% [events.back()])
	var place: Callable = func(cx: int, cy: int, cz: int) -> StringName:
		return _ask(net, heard, T.PLACE, _cell(cx, cy, cz, &"hen"))
	_expect(place.call(0, 0, 0) == &"" and place.call(0, 0, 1) == &""
		and stock.count(&"hen", T.box_location(&"box_1")) == 2 and stock.count(&"hen", hands) == 1,
		"Two hens go from the hands into box:box_1 (%d in the box)"
		% stock.count(&"hen", T.box_location(&"box_1")))
	_expect(_ask(net, heard, T.TAKE_OUT, {"station": &"table_1", "cx": 1, "cy": 1, "cz": 1}) == &""
		and stock.count(&"hen", hands) == 2 and desk.box.items.size() == 1
		and desk.box.grid.size() == 4,
		"Taking out at any cell of the second hen frees its 4 cells and puts it back in the hands")
	_expect(place.call(0, 0, 1) == &"", "...and it goes back in")

	var before: Array = _solo_state(net, state)
	var seq: int = net.seq
	var cases: Array = [
		[T.START, {"station": &"table_1", "size": &"S"}, T.REASON_HAS_BOX, "a second box"],
		[T.PLACE, _cell(1, 0, 0, &"hen"), T.REASON_CELL_TAKEN, "a hen over another"],
		[T.PLACE, _cell(2, 0, 2, &"hen"), T.REASON_CELL_TAKEN, "a hen sticking out of the box"],
		[T.PLACE, _cell(0, 0, 2, &"puppy"), T.REASON_NOT_ENOUGH, "a puppy not in the hands"],
		[T.PLACE, _cell(0, 0, 2, &"unicorn"), T.REASON_BAD_DATA, "an unknown product"],
		[T.PLACE, _cell(0, 0, 2, &"../products/hen"), T.REASON_BAD_DATA, "a path"],
		[T.PLACE, _with(_cell(0, 0, 2, &"hen"), "cx", 0.0), T.REASON_BAD_DATA, "a float cell"],
		[T.PLACE, _with(_cell(0, 0, 2, &"hen"), "cy", -1), T.REASON_BAD_DATA, "a negative cell"],
		[T.PLACE, _with(_cell(0, 0, 2, &"hen"), "rot", 1), T.REASON_BAD_DATA, "a rotation"],
		[T.TAKE_OUT, _cell(2, 2, 2), T.REASON_EMPTY_CELL, "taking out of an empty cell"],
		[T.FILL, {"station": &"table_1", "cells": 0}, T.REASON_BAD_DATA, "padding 0 cells"],
		[T.STAMP, {"station": &"table_1", "stamp": &"glitter"}, T.REASON_BAD_DATA, "a fake seal"],
		[T.LABEL, {"station": &"table_1"}, T.REASON_NO_ORDER, "a label with no order"],
		[T.START, {"station": &"table_1", "size": &"XXL"}, T.REASON_BAD_DATA, "an unknown size"],
		[T.START, {"station": &"far_table", "size": &"M"}, CompanyNet.REASON_OUT_OF_REACH, "far"],
		[T.START, {"station": &"shelf", "size": &"M"}, CompanyNet.REASON_NO_STATION, "a shelf"],
		[T.START, {"station": &"nowhere", "size": &"M"}, CompanyNet.REASON_NO_STATION, "nowhere"],
		[T.START, {"size": &"M"}, CompanyNet.REASON_BAD_DATA, "no station"],
		[T.TAPE, {"station": &"table_3"}, T.REASON_NO_BOX, "taping at a table with no box"],
	]
	_refusals(net, heard, cases)
	stock.move(&"puppy", 1, &"shelf:s_1", hands)
	_expect(_ask(net, heard, T.TAKE_OUT, _cell(0, 0, 0)) == CompanyNet.REASON_HANDS_BUSY,
		"Taking a hen out into hands holding hens and a puppy is refused with hands_busy")
	stock.move(&"puppy", 1, hands, &"shelf:s_1")
	stock.move(&"hen", 3, &"shelf:s_0", hands)
	_expect(_ask(net, heard, T.TAKE_OUT, _cell(0, 0, 0)) == CompanyNet.REASON_HANDS_FULL,
		"...into hands at their limit with hands_full")
	stock.move(&"hen", 3, hands, &"shelf:s_0")
	var as_vector: Dictionary = {"station": &"table_1", "product": &"hen", "cell": Vector3i.ZERO}
	var rid: int = net.request(T.PLACE, as_vector)
	_expect(rid > 0 and _reason_heard(heard, rid) == &"",
		"A cell sent as a Vector3i is dropped in silence (rule 5: no refusal)")
	_expect(_solo_state(net, state) == before and net.seq == seq,
		"...and no refusal changed the tables, stock or company or spent a seq (seq %d)" % net.seq)

	_expect(_ask(net, heard, T.FILL, {"station": &"table_1", "cells": 5}) == &""
		and desk.supplies.count(StationSupplies.FILL) == 25 and desk.box.grid.size() == 13,
		"Padding 5 cells takes 5 of the table's padding (grid %d)" % desk.box.grid.size())
	var fragile: Dictionary = {"station": &"table_1", "stamp": &"fragile"}
	_expect(_ask(net, heard, T.STAMP, fragile) == &""
		and _ask(net, heard, T.STAMP, fragile) == T.REASON_STAMPED,
		"A seal goes on once; the same one again is already_stamped")
	var order: Dictionary = Order.make(&"o1", "Ana", &"centro", &"centro_house_12",
		[{"product": &"hen", "qty": 2}], 0, {})
	net.table.order_of = func(table: StringName) -> Dictionary:
		return order if table == &"table_1" else {}
	_expect(_ask(net, heard, T.LABEL, {"station": &"table_1"}) == &""
		and desk.box.label_order_id == &"o1", "With an order on table_1 the label is o1's")

	stock.reserve(&"hen", 2, &"o1")
	stock.reserve(&"hen", stock.available(&"hen"), &"o2")
	_expect(_ask(net, heard, T.START, {"station": &"table_2", "size": &"M"}) == &""
		and net.table.box_of(&"table_2") == &"box_2", "table_2 opens box_2")
	var free_place: Dictionary = _cell(0, 0, 0, &"hen", &"table_2")
	_expect(_ask(net, heard, T.PLACE, free_place) == T.REASON_RESERVED,
		"With every other hen promised to o2, table_2 (no order) can't take one:"
		+ " reserved_for_other")
	_expect(_ask(net, heard, T.TAPE, {"station": &"table_2"}) == T.REASON_EMPTY_BOX,
		"An empty box can't be taped: empty_box")
	_expect(_ask(net, heard, CompanyLayoutNet.SELL, {"uid": &"table_2"})
		== CompanyLayoutNet.REASON_NOT_EMPTY,
		"The layout won't sell table_2 while it holds box_2: not_empty")

	var shut := PackedBox.from_dict(desk.box.to_dict())
	shut.taped = true
	var quality: float = AssemblyQuality.score(shut, order, {&"hen": load(HEN)})
	_expect(_ask(net, heard, T.TAPE, {"station": &"table_1"}) == &"", "table_1's box is taped")
	var sealed: Dictionary = events.back()
	var keys: Array = ["table", "order", "package_id", "node_name", "trap", "trap_intensity",
		"contents", "absorption", "quality", "pos", "basis", "money", "minute"]
	_expect((sealed.keys() as Array).size() == keys.size() and sealed.has_all(keys),
		"box_sealed carries the contract's fields plus money and minute (%s)" % [sealed.keys()])
	_expect(sealed["package_id"] == &"box_1" and sealed["order"] == &"o1"
		and sealed["contents"] == {&"hen": 2} and sealed["trap"] == &"noisy"
		and is_equal_approx(sealed["quality"], quality) and sealed["pos"] == Vector3(0.0, 0.0, 1.0),
		"...box_1 for o1 with 2 hens, the hen's trap, the taped box's quality %.1f (%s)"
		% [quality, sealed])
	_expect(not net.table.has_box(&"table_1") and desk.supplies.count(StationSupplies.TAPE) == 9
		and stock.count(&"hen", T.package_location(&"box_1")) == 2
		and stock.count(&"hen", T.box_location(&"box_1")) == 0
		and stock.reserved_by(&"o1").is_empty(),
		"The box left the table, its hens are in package:box_1 and o1 holds no more (%s)"
		% [stock.reserved_by(&"o1")])
	var spent: int = 2 * m_cost + PackagingSupplies.fill_cost(5) + CompanyTuning.TAPE_COST \
		+ CompanyTuning.STAMP_COST + CompanyTuning.LABEL_COST
	_expect(int(state.get(&"money")) == money - spent,
		"Money paid each step once: %d (money %s)" % [spent, state.get(&"money")])
	_expect(_ask(net, heard, T.TAPE, {"station": &"table_1"}) == T.REASON_NO_BOX,
		"Taping again finds no box on table_1")

	stock.release(&"o2")
	desk.supplies.take(&"box_S", desk.supplies.count(&"box_S"))
	_expect(_ask(net, heard, T.START, {"station": &"table_1", "size": &"S"}) == T.REASON_NO_SUPPLY,
		"A table out of S boxes refuses one with no_supply")
	state.set(&"money", 1)
	_expect(_ask(net, heard, T.START, {"station": &"table_1", "size": &"L"}) == T.REASON_NO_MONEY,
		"A wallet of 1 refuses an L box with no_money")
	state.set(&"money", 400)
	_expect(_ask(net, heard, T.START, {"station": &"table_1", "size": &"M"}) == &""
		and net.table.box_of(&"table_1") == &"box_3"
		and _ask(net, heard, T.FILL, {"station": &"table_1", "cells": 30}) == &""
		and _ask(net, heard, T.FILL, {"station": &"table_1", "cells": 1}) == T.REASON_NO_SUPPLY,
		"The next box is box_3; padding takes what is left (25 of 27) and then there is no_supply")
	_expect(_ask(net, heard, T.PLACE, _cell(0, 0, 0, &"hen")) == T.REASON_CELL_TAKEN,
		"...and a padded cell takes no product")
	_expect(_ask(net, heard, CompanyLayoutNet.SELL, {"uid": &"table_1"})
		== CompanyLayoutNet.REASON_NOT_EMPTY, "table_1 holding box_3 isn't sold either")
	desk.supplies.restock_all()
	_expect(_ask(net, heard, T.FILL, {"station": &"table_1", "cells": 3}) == &""
		and _ask(net, heard, T.FILL, {"station": &"table_1", "cells": 1})
		== CompanyNet.REASON_NO_ROOM,
		"Restocked, the last 2 free cells are padded and the full box has no_room")
	_check_bad_events(net, state)
	stock.receive(&"hen", 1, hands)
	_expect(_ask(net, heard, T.PLACE, free_place) == &""
		and _ask(net, heard, T.TAPE, {"station": &"table_2"}) == &""
		and _ask(net, heard, CompanyLayoutNet.SELL, {"uid": &"table_2"}) == &""
		and net.table.station_of(&"table_2") == null,
		"With o2 gone table_2 takes a hen, tapes it, sells, and its state is forgotten")
	net.free()
	state.free()


## Rule 6: an event is applied as it comes, checked only as data and against this copy.
func _check_bad_events(net: CompanyNet, state: Node) -> void:
	var before: Array = _solo_state(net, state)
	var hands: StringName = CompanyNet.hands_location(1)
	var start: Dictionary = {"table": &"table_5", "size": &"M", "box": &"box_9", "money": 300,
		"minute": 600}
	var placed: Dictionary = {"table": &"table_2", "product": &"puppy", "cx": 2, "cy": 0, "cz": 2,
		"rot": 0, "from": hands}
	var bad: Array = [
		[T.STARTED, _with(start, "table", &"table_2"), "a table that holds a box"],
		[T.STARTED, _with(start, "box", &"box_2"), "a box id in use"],
		[T.STARTED, _with(start, "size", &"Q"), "an unknown size"],
		[T.STARTED, _with(start, "money", -1), "a negative balance"],
		[T.PLACED, _with(placed, "table", &"table_5"), "a table without a box"],
		[T.PLACED, placed, "a unit not in those hands"],
		[T.PLACED, _with(placed, "from", &"shelf:s_1"), "a source that isn't a pair of hands"],
		[T.TAKEN_OUT, {"table": &"table_2", "cx": 2, "cy": 2, "cz": 2, "product": &"hen",
			"to": hands}, "an empty cell"],
		[T.SEALED, {"table": &"table_1", "order": &"", "package_id": &"box_3",
			"contents": {&"hen": 1}, "money": 300, "minute": 600}, "contents the box doesn't hold"],
		[&"box_burned", {"table": &"table_1"}, "an unknown kind"],
	]
	for case: Array in bad:
		_expect(not net.table.apply(state, net.inventory, case[0], case[1]),
			"An event with %s is not applied" % case[2])
	_expect(_solo_state(net, state) == before, "...and changed nothing")
	_expect(not net.table.take_drift(), "None of them touched the wallet (no drift)")


## The snapshot part alone: a round trip, and malformed parts refused.
func _check_snapshot_part() -> void:
	var tables := CompanyTableNet.new()
	var box := PackedBox.new(&"M")
	box.place(load(HEN), Vector3i.ZERO)
	box.fill_free_cells(3)
	box.stamps.append(&"fragile")
	var good: Dictionary = {"serial": 4, "tables": {
		"table_1": {
			"box_id": "box_4", "box": box.to_dict(), "supplies": StationSupplies.full().to_dict(),
		},
		"table_2": {"box_id": "", "box": {}, "supplies": StationSupplies.new().to_dict()},
	}}
	var travelled: Variant = bytes_to_var(var_to_bytes(good))
	_expect(tables.put_snapshot(travelled) and tables.to_dict() == good
		and tables.box_of(&"table_1") == &"box_4" and not tables.has_box(&"table_2"),
		"The tables part comes back the same after var_to_bytes (%s)" % [tables.to_dict()])
	var overlap: Dictionary = box.to_dict()
	(overlap["items"] as Array).append((overlap["items"] as Array)[0].duplicate(true))
	var unknown: Dictionary = box.to_dict()
	unknown["items"][0]["product"] = "unicorn"
	var full: Dictionary = StationSupplies.full().to_dict()
	full["tape"] = 11
	var bad: Array = [
		[7, "not a dictionary"],
		[_with(good, "serial", -1), "a negative serial"],
		[_table(good, "box", overlap), "two products on one cell"],
		[_table(good, "box", unknown), "an unknown product"],
		[_table(good, "supplies", full), "tape over its capacity"],
		[_table(good, "box_id", ""), "a box without its id"],
		[_with(good, "tables", {"t1": good["tables"]["table_1"], "t2": good["tables"]["table_1"]}),
			"one box id on two tables"],
	]
	for case: Array in bad:
		_expect(not tables.put_snapshot(case[0]) and tables.to_dict() == good,
			"A tables part with %s is refused, changing nothing" % case[1])


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
	_host.state.call(&"new_company", "Table SRL")
	_host.state.set(&"clock_minutes", HOST_MINUTE)
	var stock := Inventory.new()
	stock.receive(&"hen", 8, &"shelf:s_0")
	stock.receive(&"puppy", 4, &"shelf:s_1")
	stock.reserve(&"hen", 1, &"o1")
	stock.reserve(&"puppy", 1, &"o1")
	_host.state.call(&"store_stock", stock)
	_add_net(_host)
	_host.net.inventory = _host.state.call(&"stock")
	_host.net.stations = func(id: StringName) -> Dictionary: return _stations().get(id, {})
	_host.net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	var order: Dictionary = Order.make(&"o1", "Bea", &"campo", &"campo_house_3",
		[{"product": &"hen", "qty": 1}, {"product": &"puppy", "qty": 1}], 0, {})
	_host.net.table.order_of = func(table: StringName) -> Dictionary:
		return order if table == &"table_1" else {}
	up = up and client.create_client("127.0.0.1", PORT) == OK
	_client.side.multiplayer.multiplayer_peer = client
	_add_net(_client)
	_client.state.set(&"clock_minutes", SENTINEL_MINUTE)
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
	_client.state.set(&"clock_minutes", SENTINEL_MINUTE)
	_expect_equal([_host, _client], "after the client's snapshot")
	var steps: Array = [
		[_client, T.START, {"station": &"table_1", "size": &"M"}, "the client opens a box"],
		[_client, TAKE, _take(&"hen"), "takes a hen"],
		[_client, T.PLACE, _cell(0, 0, 0, &"hen"), "puts it in"],
		[_host, T.STAMP, {"station": &"table_1", "stamp": &"fragile"}, "the host stamps it"],
		[_host, T.FILL, {"station": &"table_1", "cells": 4}, "pads 4 cells"],
		[_client, TAKE, _take(&"puppy"), "takes a puppy"],
		[_client, T.PLACE, _cell(0, 0, 1, &"puppy"), "the client puts the puppy on top"],
		[_host, T.LABEL, {"station": &"table_1"}, "the host labels it for o1"],
		[_host, T.TAPE, {"station": &"table_1"}, "and tapes it"],
	]
	for step: Array in steps:
		var reason: StringName = await _do(step[0], step[1], step[2], [_client])
		_expect(reason == &"", "On the shared table %s (refused %s)" % [step[3], reason])
		_expect_equal([_host, _client], "after %s" % step[3])
	var sealed_at: StringName = T.package_location(&"box_1")
	_expect(_client.net.inventory.contents_at(sealed_at) == {&"hen": 1, &"puppy": 1}
		and not _client.net.table.has_box(&"table_1")
		and _client.net.inventory.reserved_by(&"o1").is_empty(),
		"On the client too the box left table_1, its hen and puppy are in package:box_1 and o1"
		+ " holds nothing (%s)" % [_client.net.inventory.contents_at(sealed_at)])
	_expect(int(_client.state.get(&"clock_minutes")) == SENTINEL_MINUTE
		and int((_client.state.get(&"ledger") as Array).back().get("minute", -1)) == HOST_MINUTE,
		"The client's wallet entries carry the host's minute; its clock_minutes stays")
	var seq: int = _host.net.seq
	_expect(await _do(_client, T.TAPE, {"station": &"table_1"}, [_client]) == T.REASON_NO_BOX
		and _host.net.seq == seq,
		"The client taping the sealed box hears no_box and no seq is spent")
	await _check_clash()
	await _check_late_join(late)
	_check_seqs()


## Two requests for the same thing: the host takes its own first (it is answered at once), the
## client's arrives after it and is refused with the reason.
func _check_clash() -> void:
	var seq: int = _host.net.seq
	var heard: int = _host.refusals.size()
	var rid: int = _client.net.request(T.START, {"station": &"table_2", "size": &"S"})
	var host_reason: StringName = _ask(_host.net, _host.refusals, T.START,
		{"station": &"table_2", "size": &"M"})
	var answered: bool = await _wait_for(func() -> bool:
		return _reason_heard(_client.refusals, rid) != &"" and _client.net.seq == _host.net.seq)
	var heard_start: StringName = _reason_heard(_client.refusals, rid)
	_expect(host_reason == &"" and answered and heard_start == T.REASON_HAS_BOX
		and _host.net.seq == seq + 1
		and _host.net.table.station_of(&"table_2").box.box_size == &"M",
		"Both open a box on table_2 at once: the host's M is there, the client hears has_box")
	_expect(await _do(_client, TAKE, _take(&"hen"), [_client]) == &""
		and await _do(_host, TAKE, _take(&"hen"), [_client]) == &"", "Both take a hen")
	seq = _host.net.seq
	var client_cell: Dictionary = _cell(0, 0, 0, &"hen", &"table_2")
	rid = _client.net.request(T.PLACE, client_cell)
	host_reason = _ask(_host.net, _host.refusals, T.PLACE, _cell(0, 0, 0, &"hen", &"table_2"))
	answered = await _wait_for(func() -> bool:
		return _reason_heard(_client.refusals, rid) != &"" and _client.net.seq == _host.net.seq)
	_expect(host_reason == &"" and answered
		and _reason_heard(_client.refusals, rid) == T.REASON_CELL_TAKEN
		and _host.net.seq == seq + 1,
		"Both put a hen in the same cell: the host's goes in, the client hears cell_taken")
	_expect(_host.refusals.size() == heard
		and _client.net.inventory.count(&"hen", CompanyNet.hands_location(_client_id())) == 1,
		"...only the client heard a refusal and its hen is still in its hands")
	_expect_equal([_host, _client], "after the clashing requests")


## A third peer joins with table_2's box half packed: snapshot, then it packs too.
func _check_late_join(late: ENetMultiplayerPeer) -> void:
	var up: bool = late.create_client("127.0.0.1", PORT) == OK
	_late.side.multiplayer.multiplayer_peer = late
	_add_net(_late)
	_late.net.wait_for_snapshot()
	var connected: bool = await _wait_for(_connected.bind(_late, 2))
	_expect(up and connected, "A third peer connects late")
	if not connected:
		return
	var no_bend: Dictionary = {"station": &"table_2", "stamp": &"no_bend"}
	_expect(await _do(_host, T.STAMP, no_bend, [_client]) == &"",
		"The host stamps table_2's box before the third is up")
	var held: bool = await _wait_for(func() -> bool: return _late.net._held.size() == 1)
	_expect(held and _late.net.seq == 0 and _late.net.table.to_dict()["tables"].is_empty(),
		"The late peer holds that event and has no tables yet")
	_expect(await _join(_late) and _late.restored == [_host.net.seq] and _late.seqs.is_empty(),
		"...then the snapshot brings it to seq %d with the tables (restored %s)"
		% [_host.net.seq, _late.restored])
	_late.state.set(&"clock_minutes", SENTINEL_MINUTE)
	_expect_equal([_host, _client, _late], "after the late peer's snapshot")
	_expect(_late.net.table.box_of(&"table_2") == &"box_2"
		and _late.net.table.station_of(&"table_2").box.stamps == [&"no_bend"],
		"The late peer sees box_2 on table_2 with its hen and seal")
	var everyone: Array = [_client, _late]
	var steps: Array = [
		[_late, TAKE, _take(&"hen"), "takes a hen"],
		[_late, T.PLACE, _cell(0, 0, 1, &"hen", &"table_2"), "puts it in table_2's box"],
		[_client, T.TAPE, {"station": &"table_2"}, "the client tapes it"],
	]
	for step: Array in steps:
		var reason: StringName = await _do(step[0], step[1], step[2], everyone)
		_expect(reason == &"", "With three peers, %s (refused %s)" % [step[3], reason])
		_expect_equal([_host, _client, _late], "after %s" % step[3])
	_expect(_late.net.inventory.count(&"hen", T.package_location(&"box_2")) == 2,
		"box_2 left with the host's hen and the late peer's")


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


static func _cell(cx: int, cy: int, cz: int, product: StringName = &"",
		station: StringName = &"table_1") -> Dictionary:
	var data: Dictionary = {"station": station, "cx": cx, "cy": cy, "cz": cz}
	if product != &"":
		data["product"] = product
		data["rot"] = 0
	return data


## units_take of one unit of `product` from its shelf.
static func _take(product: StringName) -> Dictionary:
	return {"station": StringName("shelf_%s" % product), "product": product, "qty": 1}


## True once `peer` sees the host and the host sees `peers` clients.
func _connected(peer: Peer, peers: int) -> bool:
	return peer.side.multiplayer.get_peers().has(1) \
		and _host.side.multiplayer.get_peers().size() == peers


func _refusals(net: CompanyNet, heard: Array, cases: Array) -> void:
	for case: Array in cases:
		var got: StringName = _ask(net, heard, case[0], case[1])
		_expect(got == case[2],
			"%s with %s is refused with %s (got %s)" % [case[0], case[3], case[2], got])


static func _solo_state(net: CompanyNet, state: Node) -> Array:
	return [net.table.to_dict(), net.inventory.to_dict(), _company(state)]


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


func _client_id() -> int:
	return _client.side.multiplayer.get_unique_id()


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


## `good` with one field of its table_1 replaced.
static func _table(good: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = good.duplicate(true)
	copy["tables"]["table_1"][key] = value
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
