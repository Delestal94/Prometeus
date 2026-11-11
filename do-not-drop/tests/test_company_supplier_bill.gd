extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_supplier_bill.gd
##
## Receiving a supplier pallet charges the company in the game (expansion D-0503.b: supplier_bill_hook.gd, hooked on
## the host by company_supplier_link.gd; PalletJack.take_received(), SupplierPurchase.bill()):
## - a CompanyNet with the hook: picking a pallet off the bed costs nothing; its first put-down charges its units
##   once, as one wallet_moved (reason `supplier`) right after the jack_placed; moving it again charges nothing; a
##   pallet of another supplier's truck pays that supplier's price (its price_factor); a pallet set on a rack (the
##   forklift's event) pays like one on the floor; a product the catalog does not know is not billed; the bill
##   goes through into the red; a client's hook (a fake peer connected as client 2, no socket) publishes nothing;
## - the real company world (company_root.tscn, solo), four sessions of one save slot, each loaded from its file:
##   a new company's day 1 has the hook, no truck and no bill (its first pallets are the shed's own) and the order
##   placed that day charges nothing; on day 2 the pallet the jack's point takes off the bed and puts down is
##   charged once, moving it again is free, the pallet left on the bed leaves with the truck unpaid, and the day's
##   close shows `supplier` next to the rent; loaded on day 3, moving the pallet paid the day before charges
##   nothing and the day's pallet is charged, into the red; that day cut short and loaded again starts from its
##   opening (the wallet before the bill, the pallet back on the truck) and pays it once;
## - a host and a client as two ENet peers in one process, each in CompanyRoot's supplier side (DockRoot: the
##   net, the day, the shed, the supplier link and the rent's hook): the client works the jack (the host asks on
##   its behalf, as the jack's point does) and both wallets, ledgers, books and stocks hold the same, charged
##   once; the client publishes nothing; the truck drives off with the rest and nobody pays it; the close's
##   summary on the client is the host's, with `supplier`.
## Expected in the log: SupplierBillHook's warning for the pallet of an unknown product.

const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_supplier_bill"
const PORT: int = 24753
const REASON: StringName = SupplierPurchase.REASON
const RENT: int = CompanyTuning.RENT_PER_DAY
const HEN: StringName = &"hen"
const LAMP: StringName = &"antique_lamp"
const HEN_QTY: int = 6
const LAMP_QTY: int = 2
const WAIT_SECONDS: float = 5.0

var _failures: int = 0
## What the catalog says a unit costs at list price.
var _hen: int = 0
var _lamp: int = 0
## Where the bare net's jack stands (_station()).
var _jack_at: Vector2 = Vector2.ZERO


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


## CompanyRoot's supplier side only, as the real root builds it and in its order: CompanyNet, the clock and the
## day (_start_company), the shed, the supplier link (the truck, the board and, on the host, the bill's hook) and
## the rent's hook. No player, map, fleet or UI.
class DockRoot extends CompanyRoot:
	func _ready() -> void:
		_start_company(company_state)
		_world = Node3D.new()
		_world.name = "World"
		add_child(_world)
		_add_shed()
		_add_supplier_truck()
		FixedCostsHook.attach(self, net)
		_open_company_day.call_deferred()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: CompanyCatalog = CompanyCatalog.load_all()
	_hen = catalog.product(HEN).buy_price
	_lamp = catalog.product(LAMP).buy_price
	_expect(_hen > 0 and _lamp > 0, "The catalog prices hens and lamps (%d, %d)" % [_hen, _lamp])
	_test_net()
	_test_into_the_red()
	_test_client_hook()
	await _test_root()
	await _test_two_peers()
	if _failures == 0:
		print("PASS: a supplier pallet is charged once, when its units enter the stock, on every peer")
	quit(_failures)


# --- A CompanyNet with the hook ---


## A solo host's company, net and hook under a node of their own; `kinds` lists every event applied, in order.
func _bare(label: String, money: int) -> Dictionary:
	var side := Node.new()
	side.name = label
	root.add_child(side)
	var state: Node = STATE_SCRIPT.new()
	state.call(&"reset")
	state.call(&"new_company", "Bill SRL")
	state.set(&"money", money)
	side.add_child(state)
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = state
	side.add_child(net)
	net.supplier.load_catalog(CompanyCatalog.load_all())
	net.stations = func(_id: StringName) -> Dictionary: return _station()
	net.player_origin = func(_peer: int) -> Variant: return Vector3.ZERO
	var kinds: Array[StringName] = []
	# Before the hook: an event the hook publishes from inside its listener is heard after the one that led to it.
	net.event_applied.connect(func(_seq: int, kind: StringName, _data: Dictionary) -> void: kinds.append(kind))
	var hook: SupplierBillHook = SupplierBillHook.attach(side, net)
	_expect(hook != null and SupplierBillHook.attach(side, null) == null, "The hook attaches to a CompanyNet")
	_jack_at = Vector2.ZERO
	return {"side": side, "state": state, "net": net, "hook": hook, "kinds": kinds}


## The jack's station as the shed would describe it: in reach of everyone, the truck parked beside it.
func _station() -> Dictionary:
	return {"location": &"jack:yard", "spot": Vector3.ZERO, "at": _jack_at,
		"floor": Rect2(-50.0, -50.0, 100.0, 100.0), "bed_open": true, "bed_at": _jack_at}


func _load_bed(net: CompanyNet, pallets: Array) -> void:
	_expect(net.publish(CompanyPallets.LOADED, {"day": 2, "pallets": pallets}), "The truck's pallets are on the bed")


## Peer 1 takes `id` on the jack and sets it down where the jack stands (`at`).
func _pick_and_put(net: CompanyNet, id: StringName, at: Vector2) -> void:
	net.request_for(1, CompanyPallets.PICK, {"pallet": String(id)})
	_jack_at = at
	net.request_for(1, CompanyPallets.PUT, {})


func _money(state: Node) -> int:
	return int(state.get(&"money"))


## The ledger's movements for `reason` (of `day` when given).
func _entries(state: Node, reason: StringName, day: int = -1) -> Array:
	return (state.get(&"ledger") as Array).filter(func(entry: Dictionary) -> bool:
		return StringName(entry.get("reason")) == reason and (day < 0 or int(entry.get("day", -1)) == day))


func _test_net() -> void:
	var parts: Dictionary = _bare("NetSide", 5000)
	var state: Node = parts["state"]
	var net: CompanyNet = parts["net"]
	var kinds: Array[StringName] = parts["kinds"]
	var book: PalletJack = net.pallets.book
	var market: SupplierDefinition = net.supplier.seller(&"mercado_del_campo")
	_expect(market != null and market.price_factor < 1.0, "The catalog has a cheaper supplier of hens")
	if market == null:
		_free(parts)
		return
	var market_id: StringName = StringName(String(SupplierIds.pallet_prefix(market.id, 2, HEN)) + "_1")
	_load_bed(net, [
		{"id": "d2_hen_1", "product": String(HEN), "qty": HEN_QTY},
		{"id": String(market_id), "product": String(HEN), "qty": 10},
		{"id": "d2_antique_lamp_1", "product": String(LAMP), "qty": LAMP_QTY},
		{"id": "d2_ghost_1", "product": "ghost", "qty": 3},
	])
	_expect(_money(state) == 5000 and net.inventory.total_units() == 0, "A truck at the dock costs nothing")

	# Off the bed: nothing. Down on the floor: the bill, once.
	net.request_for(1, CompanyPallets.PICK, {"pallet": "d2_hen_1"})
	_expect(book.carrying == &"d2_hen_1" and _money(state) == 5000 and _entries(state, REASON).is_empty(),
		"A pallet on the forks is not paid yet (money %d)" % _money(state))
	kinds.clear()
	var seq: int = net.seq
	net.request_for(1, CompanyPallets.PUT, {})
	var bill: int = _hen * HEN_QTY
	_expect(book.places[&"d2_hen_1"]["at"] == PalletJack.AT_FLOOR
		and net.inventory.count(HEN, &"pallet:d2_hen_1") == HEN_QTY, "Its first put-down brings its units in")
	_expect(_money(state) == 5000 - bill, "... and charges them at the supplier's price (money %d, bill %d)"
		% [_money(state), bill])
	var paid: Array = _entries(state, REASON)
	_expect(paid.size() == 1 and int(paid[0]["amount"]) == -bill and state.call(&"ledger_total", REASON) == -bill,
		"The ledger has one `supplier` movement of -%d (%s)" % [bill, paid])
	_expect(net.seq == seq + 2 and kinds == [CompanyPallets.PLACED, CompanyNet.WALLET],
		"It is one wallet_moved, right after the jack_placed (%s)" % [kinds])
	seq = net.seq
	_pick_and_put(net, &"d2_hen_1", Vector2(3.0, 0.0))
	_expect(net.seq == seq + 2 and book.places[&"d2_hen_1"]["pos"] == Vector2(3.0, 0.0)
		and _money(state) == 5000 - bill and _entries(state, REASON).size() == 1,
		"Moved again, it is not paid again (money %d)" % _money(state))

	# The price is the one of the supplier whose truck brought the pallet.
	var market_bill: int = market.unit_price(net.supplier.products[HEN]) * 10
	_expect(market_bill > 0 and market_bill != _hen * 10,
		"The other supplier's hens have another price (%d)" % market_bill)
	_pick_and_put(net, market_id, Vector2(6.0, 0.0))
	_expect(net.inventory.count(HEN, Pallet.location(market_id)) == 10 and _money(state) == 5000 - bill - market_bill,
		"A pallet of another supplier's truck pays that supplier's price (money %d)" % _money(state))

	# A product the catalog does not know has no price: received, not billed (and a warning).
	var before: int = _money(state)
	_pick_and_put(net, &"d2_ghost_1", Vector2(9.0, 0.0))
	_expect(net.inventory.count(&"ghost", &"pallet:d2_ghost_1") == 3 and _money(state) == before
		and _entries(state, REASON).size() == 2, "A pallet of an unknown product is not billed")

	# The forklift's put-down on a rack is the same event with a slot.
	net.request_for(1, CompanyPallets.PICK, {"pallet": "d2_antique_lamp_1"})
	var racked: StringName = net.call(&"_grant", {"reason": &"", "kind": CompanyPallets.PLACED,
		"data": {"pallet": &"d2_antique_lamp_1", "pos": Vector2(12.0, 0.0), "slot": "shelf_a-1"}})
	_expect(racked == &"" and book.places[&"d2_antique_lamp_1"]["at"] == PalletJack.AT_RACK
		and _money(state) == before - _lamp * LAMP_QTY and _entries(state, REASON).size() == 3,
		"A pallet set on a rack straight from the bed pays like one on the floor (money %d)" % _money(state))
	_free(parts)


func _test_into_the_red() -> void:
	var parts: Dictionary = _bare("RedSide", 50)
	var state: Node = parts["state"]
	_load_bed(parts["net"], [{"id": "d2_hen_1", "product": String(HEN), "qty": HEN_QTY}])
	_pick_and_put(parts["net"], &"d2_hen_1", Vector2.ZERO)
	_expect(_money(state) == 50 - _hen * HEN_QTY and _money(state) < 0,
		"The bill goes through into the red: the goods are already in the shed (money %d)" % _money(state))
	_free(parts)


func _test_client_hook() -> void:
	var parts: Dictionary = _bare("ClientHookSide", 500)
	var state: Node = parts["state"]
	var net: CompanyNet = parts["net"]
	_load_bed(net, [{"id": "d2_hen_1", "product": String(HEN), "qty": HEN_QTY}])
	net.request_for(1, CompanyPallets.PICK, {"pallet": "d2_hen_1"})
	var offline: MultiplayerPeer = root.multiplayer.multiplayer_peer
	root.multiplayer.multiplayer_peer = FakeClientPeer.new()
	_expect(not net.is_host(), "The net is a client's: connected, but not the server")
	var seq: int = net.seq
	# The host's jack_placed, as a client receives it.
	net.call(&"_receive", seq + 1, CompanyPallets.PLACED, {"pallet": &"d2_hen_1", "pos": Vector2.ZERO})
	_expect(net.inventory.count(HEN, &"pallet:d2_hen_1") == HEN_QTY and net.seq == seq + 1,
		"The client applies the put-down (seq +%d)" % (net.seq - seq))
	_expect(_money(state) == 500 and _entries(state, REASON).is_empty(),
		"... and its hook charges nothing: the bill is the host's wallet_moved (money %d)" % _money(state))
	_expect((parts["hook"] as SupplierBillHook).bill(&"d2_hen_1") == 0 and _money(state) == 500,
		"... not even asked straight")
	# Back to the tree's own offline peer: the real world below is a solo host on it.
	root.multiplayer.multiplayer_peer = offline
	_free(parts)


func _free(parts: Dictionary) -> void:
	(parts["side"] as Node).free()


# --- The real company world, solo ---


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var arrival: float = float(SupplierSchedule.arrival_minute())
	var lamp_bill: int = _lamp * LAMP_QTY
	var hen_bill: int = _hen * HEN_QTY

	# Day 1 of a new company: its first pallets are the shed's own, a gift; no truck, no bill.
	var level: CompanyRoot = await _open_root()
	var net: CompanyNet = level.net
	if net == null:
		_expect(false, "The company world has a net")
		return
	var opening: int = CompanyTuning.STARTING_MONEY
	_expect(level.get_node_or_null(^"SupplierBillHook") is SupplierBillHook, "The company world hooks the bill")
	_expect(int(state.get(&"day")) == 1 and _money(state) == opening and net.inventory.total_units() > 0,
		"A new company opens day 1 with its money and the shed's first stock (money %d)" % _money(state))
	level.clock.start(arrival + 20.0)
	for _frame: int in 3:
		await process_frame
	_expect(net.pallets.book.places.is_empty() and _money(state) == opening and _entries(state, REASON).is_empty(),
		"Day 1 has no truck and no bill: the first stock is free (money %d)" % _money(state))
	_expect(net.request_for(1, CompanySupplierNet.ORDER, {String(LAMP): LAMP_QTY, String(HEN): HEN_QTY})
		and level.supplier_schedule.has_delivery(2) and _money(state) == opening,
		"Ordering for tomorrow charges nothing (money %d)" % _money(state))
	_close_day(level)
	_expect(_money(state) == opening - RENT, "Day 1 closes paying only the rent (money %d)" % _money(state))
	await _leave(level, state)

	# Day 2, loaded from the slot: the truck comes; what is put down is paid, what stays on the bed is not.
	level = await _open_root()
	net = level.net
	var money: int = opening - RENT
	_expect(int(state.get(&"day")) == 2 and _money(state) == money,
		"Day 2 opens from the save (money %d)" % _money(state))
	await _truck_parks(level)
	var on_bed: Array[StringName] = net.pallets.book.ids_at(PalletJack.AT_BED)
	_expect(on_bed == [&"d2_antique_lamp_1", &"d2_hen_1"] and _money(state) == money,
		"The truck brings the two pallets ordered and charges nothing by coming (%s)" % [on_bed])
	var yard: PalletYardView = level.shed.yard
	var beside: Vector3 = Vector3(-1.2, 0.0, 0.0)
	yard.jack.work_point.used.emit(PalletJackPoint.ACTION_WORK, 1, yard.jack.global_position + beside)
	_expect(net.pallets.book.carrying == &"d2_antique_lamp_1" and _money(state) == money,
		"The jack's point takes the first pallet off the bed, unpaid (%s)" % net.pallets.book.carrying)
	yard.jack.work_point.used.emit(PalletJackPoint.ACTION_WORK, 1, yard.jack.global_position + beside)
	money -= lamp_bill
	_expect(net.inventory.count(LAMP, &"pallet:d2_antique_lamp_1") == LAMP_QTY and _money(state) == money
		and _entries(state, REASON, 2).size() == 1,
		"Put down, its units are in the stock and charged once (money %d, bill %d)" % [_money(state), lamp_bill])
	# Moved one step east: free.
	var seq: int = net.seq
	net.request_for(1, CompanyPallets.PICK, {"pallet": "d2_antique_lamp_1"})
	net.request_for(1, CompanyPallets.PUSH, {"dir": Vector2(1.0, 0.0)})
	net.request_for(1, CompanyPallets.PUT, {})
	_expect(net.seq == seq + 3 and net.pallets.book.places[&"d2_antique_lamp_1"]["at"] == PalletJack.AT_FLOOR
		and _money(state) == money, "Moved a step away it is not paid again (seq +%d, money %d)"
		% [net.seq - seq, _money(state)])
	level.clock.start(float(SupplierSchedule.departure_minute()) + 1.0)
	for _frame: int in 3:
		await process_frame
	_expect(net.pallets.departed_day == 2 and not net.pallets.book.places.has(&"d2_hen_1")
		and net.inventory.count(HEN, &"pallet:d2_hen_1") == 0 and _money(state) == money,
		"The truck takes the pallet nobody unloaded and nobody pays it (money %d)" % _money(state))
	_expect(net.request_for(1, CompanySupplierNet.ORDER, {String(HEN): HEN_QTY})
		and level.supplier_schedule.has_delivery(3), "Day 3's order is in the calendar")
	_close_day(level)
	money -= RENT
	var costs: Dictionary = level.day_cycle.summary.get("cost_by_reason", {})
	_expect(int(costs.get(String(REASON), 0)) == lamp_bill and int(costs.get("rent", 0)) == RENT
		and int(level.day_cycle.summary.get("closing", 0)) == money and _money(state) == money,
		"The day's close shows the supplier's bill next to the rent (%s, money %d)" % [costs, _money(state)])
	await _leave(level, state)

	# Day 3, loaded: the pallet paid yesterday is free to move; today's is charged, into the red.
	level = await _open_root()
	net = level.net
	_expect(int(state.get(&"day")) == 3 and _money(state) == money
		and net.pallets.book.places.has(&"d2_antique_lamp_1")
		and net.pallets.book.places[&"d2_antique_lamp_1"]["received"] == true,
		"Day 3 opens from the save with yesterday's pallet received (money %d)" % _money(state))
	seq = net.seq
	net.request_for(1, CompanyPallets.PICK, {"pallet": "d2_antique_lamp_1"})
	net.request_for(1, CompanyPallets.PUT, {})
	_expect(net.seq == seq + 2 and _money(state) == money and _entries(state, REASON, 3).is_empty(),
		"Loaded, a pallet paid before is not paid again (seq +%d, money %d)" % [net.seq - seq, _money(state)])
	await _receive_day_three(level, state, money, hen_bill)
	_expect(money - hen_bill < 0, "... which leaves this company in the red (%d)" % (money - hen_bill))
	# The day is cut short here: leaving marks it interrupted and the slot keeps its opening.
	await _leave(level, state)

	level = await _open_root()
	net = level.net
	_expect(int(state.get(&"day")) == 3 and _money(state) == money and not net.pallets.book.places.has(&"d3_hen_1")
		and net.inventory.count(HEN, &"pallet:d3_hen_1") == 0 and _entries(state, REASON, 3).is_empty(),
		"The day cut short opens again as it opened: the wallet before the bill, the pallet not here (money %d)"
		% _money(state))
	await _receive_day_three(level, state, money, hen_bill)
	level.queue_free()
	await process_frame
	state.call(&"reset")
	_clean()


## Day 3's truck parks and its hen pallet goes down at the jack's home: charged once.
func _receive_day_three(level: CompanyRoot, state: Node, money: int, bill: int) -> void:
	var net: CompanyNet = level.net
	await _truck_parks(level)
	_expect(net.pallets.book.ids_at(PalletJack.AT_BED) == [&"d3_hen_1"] and _money(state) == money,
		"Day 3's truck brings its pallet (%s)" % [net.pallets.book.ids_at(PalletJack.AT_BED)])
	# The jack stands a step east, where it left yesterday's pallet: back to its home, in reach of the bed.
	net.request_for(1, CompanyPallets.PUSH, {"dir": Vector2(-1.0, 0.0)})
	net.request_for(1, CompanyPallets.PICK, {"pallet": "d3_hen_1"})
	_expect(net.pallets.book.carrying == &"d3_hen_1" and _money(state) == money, "It goes on the forks unpaid")
	net.request_for(1, CompanyPallets.PUT, {})
	_expect(net.inventory.count(HEN, &"pallet:d3_hen_1") == HEN_QTY and _money(state) == money - bill
		and _entries(state, REASON, 3).size() == 1,
		"Put down, it is charged once (money %d, bill %d, %d movements)"
		% [_money(state), bill, _entries(state, REASON, 3).size()])


## The real scene, saving in DIR, with the player's reach at the jack wherever it stands.
func _open_root() -> CompanyRoot:
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	if level.net != null:
		level.net.player_origin = func(_peer: int) -> Variant:
			return level.shed.yard.jack.global_position + Vector3(-1.2, 1.5, 0.0)
	return level


## The world closes (it saves: the next opening after a summary, the same opening marked interrupted mid-day) and
## the company is dropped, so the next world loads it from the slot's file.
func _leave(level: CompanyRoot, state: Node) -> void:
	level.queue_free()
	await process_frame
	state.call(&"reset")


## The day's truck drives in with its pallets and parks, its bed open.
func _truck_parks(level: CompanyRoot) -> void:
	var arrival: float = float(SupplierSchedule.arrival_minute())
	level.clock.start(arrival - 3.0)
	await process_frame
	level.clock.start(arrival + 20.0)
	await process_frame


## The host's day goes to SUMMARY from wherever it stands (the rent is charged in CLOSING, the save made in SUMMARY).
func _close_day(level: CompanyRoot) -> void:
	var cycle: DayCycle = level.day_cycle
	for next: DayCycle.Phase in [DayCycle.Phase.OPERATING, DayCycle.Phase.CLOSING, DayCycle.Phase.SUMMARY]:
		if cycle.phase() < next:
			cycle.call(&"_transition", next)
	_expect(cycle.phase() == DayCycle.Phase.SUMMARY, "The day reaches SUMMARY (phase %s)" % cycle.phase_name())


# --- Host and client ---


func _test_two_peers() -> void:
	_clean()
	var host_side: Node = _side("HostSide")
	var client_side: Node = _side("ClientSide")
	var server := ENetMultiplayerPeer.new()
	var up: bool = server.create_server(PORT, 2) == OK
	host_side.multiplayer.multiplayer_peer = server
	var host_state: Node = STATE_SCRIPT.new()
	host_state.call(&"reset")
	host_state.call(&"new_company", "Host SRL")
	host_state.set(&"day", 2)
	var calendar := SupplierSchedule.new()
	calendar.place(1, [{"product": LAMP, "qty": LAMP_QTY}, {"product": HEN, "qty": HEN_QTY}])
	host_state.set(&"supplier_calendar", calendar.to_dict())
	host_side.add_child(host_state)
	var host: DockRoot = _dock_root(host_state)
	host_side.add_child(host)
	# The test drives the day's phases itself.
	host.business_tick.set_process(false)
	var client := ENetMultiplayerPeer.new()
	up = up and client.create_client("127.0.0.1", PORT) == OK
	client_side.multiplayer.multiplayer_peer = client
	var client_state: Node = STATE_SCRIPT.new()
	client_state.call(&"reset")
	client_side.add_child(client_state)
	var guest: DockRoot = _dock_root(client_state)
	client_side.add_child(guest)
	var connected: bool = await _wait_for(func() -> bool:
		return client_side.multiplayer.get_peers().has(1) and host_side.multiplayer.get_peers().size() == 1)
	_expect(up and connected, "The client connects to the host on localhost:%d" % PORT)
	if connected:
		var client_id: int = client_side.multiplayer.get_unique_id()
		host.net.send_snapshot(client_id)
		_expect(await _synced(host, guest), "The client takes the host's snapshot")
		await _play_pair(host, guest, host_state, client_state, client_id)
	for level: Node in [guest, host]:
		level.queue_free()
	await process_frame
	for peer: ENetMultiplayerPeer in [client, server]:
		peer.close()
	await process_frame
	for side: Node in [host_side, client_side]:
		set_multiplayer(null, side.get_path())
		side.free()
	RpcGuard.reset()
	_clean()


func _play_pair(host: DockRoot, guest: DockRoot, host_state: Node, client_state: Node, client_id: int) -> void:
	var opening: int = CompanyTuning.STARTING_MONEY
	var lamp_bill: int = _lamp * LAMP_QTY
	_expect(host.get_node_or_null(^"SupplierBillHook") is SupplierBillHook
		and guest.get_node_or_null(^"SupplierBillHook") == null, "Only the host's world hooks the bill")
	_expect(_money(host_state) == opening and _money(client_state) == opening,
		"Both peers open with the host's money (client %d)" % _money(client_state))
	host.net.player_origin = func(_peer: int) -> Variant:
		return host.shed.yard.jack.global_position + Vector3(-1.2, 1.5, 0.0)
	var arrival: float = float(SupplierSchedule.arrival_minute())
	host.clock.start(arrival - 3.0)
	_expect(await _wait_for(func() -> bool: return host.net.pallets.loaded_day == 2),
		"The host loads the day's truck")
	host.clock.start(arrival + 20.0)
	await process_frame
	_expect(await _synced(host, guest) and guest.net.pallets.book.ids_at(PalletJack.AT_BED).size() == 2,
		"The client sees the two pallets on the bed")
	# The client works the jack: the host asks on its behalf, as the jack's point does (CompanyRoot._on_jack_used).
	var from: Vector3 = host.shed.yard.jack.global_position + Vector3(-1.2, 0.0, 0.0)
	_expect(PalletJackUse.use(host.net, host.shed.yard, PalletJackPoint.ACTION_WORK, client_id, from)
		== PalletJackUse.RESULT_PICKED and _money(host_state) == opening,
		"The client takes a pallet off the bed, unpaid")
	_expect(PalletJackUse.use(host.net, host.shed.yard, PalletJackPoint.ACTION_WORK, client_id, from)
		== PalletJackUse.RESULT_PUT, "... and puts it down")
	var target: int = host.net.seq
	_expect(await _synced(host, guest), "The client gets every event (%d of %d)" % [guest.net.seq, target])
	_expect(_money(host_state) == opening - lamp_bill and _money(client_state) == opening - lamp_bill,
		"Both wallets paid the pallet once (host %d, client %d, bill %d)"
		% [_money(host_state), _money(client_state), lamp_bill])
	var host_paid: Array = _entries(host_state, REASON)
	var client_paid: Array = _entries(client_state, REASON)
	_expect(host_paid.size() == 1 and client_paid.size() == 1 and client_paid == host_paid,
		"Both ledgers have the same one `supplier` movement (host %s, client %s)" % [host_paid, client_paid])
	_expect(guest.net.inventory.to_dict() == host.net.inventory.to_dict()
		and guest.net.inventory.count(LAMP, &"pallet:d2_antique_lamp_1") == LAMP_QTY
		and guest.net.pallets.book.to_dict() == host.net.pallets.book.to_dict(),
		"... and hold the same stock and the same pallet book")
	for _frame: int in 3:
		await process_frame
	_expect(host.net.seq == target, "The client published nothing (host seq %d, was %d)" % [host.net.seq, target])
	# The truck leaves with the hens nobody unloaded.
	host.clock.start(float(SupplierSchedule.departure_minute()) + 1.0)
	_expect(await _wait_for(func() -> bool: return host.net.pallets.departed_day == 2), "The truck drives off")
	_expect(await _synced(host, guest) and guest.net.pallets.book.ids_at(PalletJack.AT_BED).is_empty()
		and _money(host_state) == opening - lamp_bill and _money(client_state) == opening - lamp_bill
		and _entries(client_state, REASON).size() == 1,
		"What the truck took back is paid by nobody (host %d, client %d)" % [_money(host_state), _money(client_state)])
	_close_day(host)
	_expect(await _synced(host, guest) and guest.day_cycle.phase() == DayCycle.Phase.SUMMARY,
		"The client follows the host to the day's close")
	var costs: Dictionary = guest.day_cycle.summary.get("cost_by_reason", {})
	_expect(guest.day_cycle.summary == host.day_cycle.summary and int(costs.get(String(REASON), 0)) == lamp_bill
		and int(costs.get("rent", 0)) == RENT and _money(client_state) == opening - lamp_bill - RENT,
		"The client's summary is the host's, with the supplier's bill and the rent (%s, money %d)"
		% [costs, _money(client_state)])


func _side(side_name: String) -> Node:
	var side := Node.new()
	side.name = side_name
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	return side


func _dock_root(state: Node) -> DockRoot:
	var level := DockRoot.new()
	level.name = "CompanyRoot"
	level.company_state = state
	level.save_dir = DIR
	level.save_slot = "net"
	level.dev_args = PackedStringArray()
	return level


func _synced(host: CompanyRoot, guest: CompanyRoot) -> bool:
	return await _wait_for(func() -> bool:
		return not guest.net.awaiting_snapshot() and guest.net.seq == host.net.seq)


func _wait_for(done: Callable, seconds: float = WAIT_SECONDS) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return bool(done.call())


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
