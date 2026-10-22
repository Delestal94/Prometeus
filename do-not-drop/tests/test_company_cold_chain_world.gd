extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_cold_chain_world.gd
##
## The cold chain in the company's world (expansion D-0616.b: cold_chain_tick.gd, company_cold_net.gd, the
## additions to cold_chain.gd and company_state.gd; the logic alone is test_cold_chain):
## - ColdChain: age() counts without touching the stock and keeps reporting what is due until the caller
##   takes it out; places where units are worked on (hands, tables, boxes, packages) never age; note_moved()
##   carries and averages the clock after an event moved the units; from_dict() drops anything malformed;
## - CompanyColdNet: units_spoiled is an id, an id and a positive int; applying it takes the units out even
##   if reserved and trims the newest reservations; more than the place holds, bad ids and 0 are refused;
## - the tick (a host CompanyNet with a stand-in clock): milk on an ordinary shelf rots when 2 game hours
##   passed since it was put there, milk in the fridge and a vase never do; nothing ages while the shed's
##   minute stands still (pause, frozen shed) nor with the day closed, and a new day or a minute that went
##   back only moves the mark; the reserved orders that lose their milk are the newest; a unit moved through
##   a units_moved event takes its clock to the other shelf; the clocks go to the company for the save
##   (JSON round trip) and an old save without them loads with none;
## - two ENet peers in one process: the host's rot is one numbered event, the client's stock and
##   reservations end as the host's, the snapshot's company part has no cold_clocks, and a client that
##   joins later gets the rotten stock as it is;
## - the real CompanyRoot: it has its ColdChainTick as a step of the business tick, the milk of the first
##   pallets rots after 2 game hours of an open day (the fridge's does not), and leaving the root saves the
##   clocks.
## Expected in the log: the engine's leak notes at exit.

const PORT: int = 24711
const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DIR: String = "user://test_company_cold_chain_world"
const STATE_SCRIPT := preload("res://scripts/core/company/company_state.gd")
const SHELF: StringName = &"shelf:shelf_1_0"
const SHELF_B: StringName = &"shelf:shelf_2_0"
const FRIDGE: StringName = &"shelf:cold_1_0"
const FRIDGE_B: StringName = &"shelf:cold_1_1"

var _failures: int = 0
var _milk: StringName = &"milk_canister"
var _vase: StringName = &"porcelain_vase"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_test_chain()
	_test_net_event()
	await _test_tick()
	_test_state()
	await _test_peers()
	await _test_root()
	if _failures == 0:
		print("PASS: cold products rot in the company's world, the same on every peer")
	quit(_failures)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)


func _products() -> Dictionary:
	var milk: ProductDefinition = load("res://data/products/milk_canister.tres")
	var vase: ProductDefinition = load("res://data/products/porcelain_vase.tres")
	return {milk.id: milk, vase.id: vase}


# --- ColdChain additions ---


func _test_chain() -> void:
	var products: Dictionary = _products()
	var fridges: Dictionary = {&"cold_1": true}
	var limit: float = CompanyTuning.COLD_SPOIL_MINUTES
	_expect(ColdChain.ages_at(SHELF) and ColdChain.ages_at(&"pallet:p1") and ColdChain.ages_at(&"cart:1")
		and ColdChain.ages_at(&"floor:0"), "Shelves, pallets, carts and the floor age")
	for place: StringName in [&"hands:1", &"table:t1", &"box:b1", &"package:b1"]:
		_expect(not ColdChain.ages_at(place), "%s does not age" % place)

	var inv := Inventory.new()
	var chain := ColdChain.new()
	chain.receive(inv, _milk, 3, SHELF)
	chain.receive(inv, _milk, 2, &"hands:1")
	chain.receive(inv, _milk, 2, FRIDGE)
	_expect(chain.age(inv, products, fridges, limit - 1.0).is_empty(), "Nothing is due a minute early")
	_expect(chain.is_ticking(), "A clock is running")
	var due: Array[Dictionary] = chain.age(inv, products, fridges, 1.0)
	_expect(due.size() == 1 and due[0] == {"product": _milk, "location": SHELF, "qty": 3},
		"The shelf milk is due, the hand's and the fridge's are not (got %s)" % [due])
	_expect(inv.count(_milk) == 7, "age() takes nothing out of the stock")
	due = chain.age(inv, products, fridges, 5.0)
	_expect(due.size() == 1, "A due place is reported again until the caller takes it out")
	inv.discard(_milk, 3, SHELF)
	chain.forget_empty(inv)
	_expect(chain.age(inv, products, fridges, 600.0).is_empty() and is_zero_approx(chain.warm_minutes(_milk, SHELF)),
		"...and once taken out it has no clock and nothing is due")
	_expect(is_zero_approx(chain.warm_minutes(_milk, &"hands:1")), "Hands never get a clock")

	# note_moved(): the event already moved the units.
	inv = Inventory.new()
	chain = ColdChain.new()
	chain.receive(inv, _milk, 4, SHELF)
	chain.age(inv, products, fridges, 80.0)
	inv.receive(_milk, 2, SHELF_B)
	inv.move(_milk, 2, SHELF, SHELF_B)
	chain.note_moved(inv, _milk, 2, SHELF, SHELF_B)
	# 2 fresh (received) + 2 with 80 min joined: (0 * 2 + 80 * 2) / 4.
	_expect(is_equal_approx(chain.warm_minutes(_milk, SHELF_B), 40.0), "Joining averages the clock by units")
	_expect(is_equal_approx(chain.warm_minutes(_milk, SHELF), 80.0), "What stays keeps its own")
	inv.move(_milk, 2, SHELF, FRIDGE)
	chain.note_moved(inv, _milk, 2, SHELF, FRIDGE)
	_expect(is_equal_approx(chain.warm_minutes(_milk, FRIDGE), 80.0)
		and is_zero_approx(chain.warm_minutes(_milk, SHELF)),
		"A move that empties a place takes its clock and leaves none behind")
	chain.note_moved(inv, _milk, 9, SHELF, FRIDGE)
	chain.note_moved(inv, _milk, 0, SHELF_B, FRIDGE)
	_expect(is_equal_approx(chain.warm_minutes(_milk, FRIDGE), 80.0), "A move that does not fit changes nothing")

	# from_dict() takes anything.
	var copy := ColdChain.new()
	for junk: Variant in [null, 5, "x", [], {"warm": 3}, {"warm": {"milk_canister": "x"}},
			{"warm": {"milk_canister": {"shelf:a_0": "soon", "shelf:b_0": null, "shelf:c_0": -4.0}}},
			{"warm": {5: {"shelf:a_0": 4.0}}}, {"warm": {"milk_canister": {"shelf:a_0": NAN}}}]:
		copy.from_dict(junk)
		_expect(not copy.is_ticking(), "Garbage loads as no clocks (got %s)" % [junk])
	copy.from_dict({"warm": {"milk_canister": {"shelf:a_0": 30.0, "shelf:b_0": "x"}}})
	_expect(is_equal_approx(copy.warm_minutes(_milk, &"shelf:a_0"), 30.0), "A good entry next to a bad one loads")


# --- CompanyColdNet ---


func _test_net_event() -> void:
	_expect(CompanyColdNet.event_of({"product": _milk, "location": SHELF, "qty": 3})
		== {"product": _milk, "qty": 3, "location": SHELF}, "The event is product, qty and location")
	for bad: Dictionary in [{}, {"product": _milk, "location": SHELF}, {"product": _milk, "location": SHELF, "qty": 0},
			{"product": 4, "location": SHELF, "qty": 1}, {"product": _milk, "location": &"", "qty": 1}]:
		_expect(CompanyColdNet.event_of(bad).is_empty(), "Not an event: %s" % [bad])
	var inv := Inventory.new()
	inv.receive(_milk, 3, SHELF)
	inv.receive(_milk, 2, FRIDGE)
	inv.reserve(_milk, 2, &"o1")
	inv.reserve(_milk, 2, &"o2")
	var long_id: String = "x".repeat(CompanyNet.SNAPSHOT_MAX_ID_LENGTH + 1)
	for bad: Dictionary in [{"product": _milk, "qty": 4, "location": SHELF},
			{"product": _milk, "qty": 0, "location": SHELF},
			{"product": _milk, "qty": -1, "location": SHELF}, {"product": _milk, "qty": 3.0, "location": SHELF},
			{"product": _milk, "qty": 3}, {"product": long_id, "qty": 3, "location": SHELF},
			{"product": _milk, "qty": 3, "location": long_id}, {"product": _vase, "qty": 1, "location": SHELF}]:
		_expect(not CompanyColdNet.apply(inv, bad), "Refused: %s" % [bad])
	_expect(inv.count(_milk) == 5 and inv.reserved_total(_milk) == 4, "...and nothing changed")
	_expect(CompanyColdNet.apply(inv, {"product": _milk, "qty": 3, "location": SHELF}), "A real one applies")
	_expect(inv.count(_milk) == 2 and inv.reserved_by(&"o1").get(_milk, 0) == 2
		and not inv.reserved_by(&"o2").has(_milk),
		"The units went even if reserved; the newest order lost its milk, the oldest kept it")
	_expect(not CompanyColdNet.apply(null, {"product": _milk, "qty": 1, "location": FRIDGE}), "No stock, no event")


# --- The tick on a host CompanyNet ---


## A host: a CompanyNet with its company, a stock and a tick whose day is the dictionary `sim`.
func _host_side(side_name: String, sim: Dictionary, with_tick: bool = true) -> Dictionary:
	var side := Node.new()
	side.name = side_name
	root.add_child(side)
	set_multiplayer(SceneMultiplayer.new(), side.get_path())
	var company: Node = STATE_SCRIPT.new()
	company.name = "Company"
	company.new_company("Test")
	side.add_child(company)
	var net := CompanyNet.new()
	net.name = "CompanyNet"
	net.company = company
	side.add_child(net)
	var parts: Dictionary = {"side": side, "net": net, "company": company}
	if with_tick:
		var tick := ColdChainTick.new()
		tick.name = ColdChainTick.NODE_NAME
		tick.net = net
		tick.products = _products()
		tick.is_open = func() -> bool: return sim["open"]
		tick.shed_minute = func() -> float: return sim["minute"]
		tick.current_day = func() -> int: return sim["day"]
		tick.cold_shelves = func() -> Dictionary: return {&"cold_1": true}
		side.add_child(tick)
		parts["tick"] = tick
	return parts


func _test_tick() -> void:
	var sim: Dictionary = {"open": true, "minute": 480.0, "day": 1}
	var host: Dictionary = _host_side("TickSide", sim)
	var net: CompanyNet = host["net"]
	var tick: ColdChainTick = host["tick"]
	var inv: Inventory = net.inventory
	inv.receive(_milk, 3, SHELF)
	inv.receive(_milk, 2, FRIDGE)
	inv.receive(_vase, 4, SHELF)
	inv.reserve(_milk, 2, &"o1")
	inv.reserve(_milk, 2, &"o2")
	var kinds: Array = []
	net.event_applied.connect(func(_seq: int, kind: StringName, data: Dictionary) -> void: kinds.append([kind, data]))

	tick.poll()
	_expect(net.seq == 0, "The first poll only sets the mark")
	sim["minute"] = 480.5
	tick.poll()
	_expect(is_zero_approx(tick.chain.warm_minutes(_milk, SHELF)), "Less than a game minute does nothing yet")
	sim["minute"] = 540.0
	tick.poll()
	_expect(is_equal_approx(tick.chain.warm_minutes(_milk, SHELF), 60.0), "An hour later the milk is 60 minutes out")
	_expect(is_zero_approx(tick.chain.warm_minutes(_milk, FRIDGE)), "...the fridge's does not count")
	tick.poll()
	sim["minute"] = 599.0
	tick.poll()
	_expect(inv.count(_milk, SHELF) == 3 and net.seq == 0, "At 119 minutes it still holds, nothing published")

	# A paused clock, a frozen shed and a closed day: the minute stands still or the day is not open.
	tick.poll()
	tick.poll()
	_expect(inv.count(_milk, SHELF) == 3, "A minute that stands still ages nothing")
	sim["open"] = false
	sim["minute"] = 900.0
	tick.poll()
	sim["open"] = true
	tick.poll()
	_expect(inv.count(_milk, SHELF) == 3, "A closed day's time does not count, and the poll after it only sets a mark")
	sim["minute"] = 899.0
	tick.poll()
	_expect(inv.count(_milk, SHELF) == 3, "A minute that went back only moves the mark")
	sim["day"] = 2
	sim["minute"] = 480.0
	tick.poll()
	_expect(inv.count(_milk, SHELF) == 3, "A new day only moves the mark")

	# The minute it passes the limit: one event, the stock goes down, the newest order loses its milk.
	sim["minute"] = 481.0
	tick.poll()
	_expect(inv.count(_milk, SHELF) == 0 and net.seq == 1 and kinds.size() == 1,
		"At 120 minutes the shelf milk rots: one event")
	_expect(kinds[0][0] == CompanyColdNet.SPOILED and kinds[0][1] == {"product": _milk, "qty": 3, "location": SHELF},
		"...a units_spoiled with the product, its units and where (got %s)" % [kinds])
	_expect(inv.count(_milk, FRIDGE) == 2 and inv.count(_vase, SHELF) == 4, "The fridge's milk and the vase stay")
	_expect(inv.reserved_by(&"o1").get(_milk, 0) == 2 and not inv.reserved_by(&"o2").has(_milk),
		"The oldest order keeps its milk; the newest waits for stock")
	_expect(not tick.chain.is_ticking(), "The rotten place has no clock")
	sim["minute"] = 2000.0
	tick.poll()
	_expect(net.seq == 1 and inv.count(_milk, FRIDGE) == 2, "The fridge keeps its milk for any time")

	# A move through an event brings the clock along.
	inv.receive(_milk, 2, SHELF)
	sim["minute"] = 2060.0
	tick.poll()
	sim["minute"] = 2090.0
	tick.poll()
	_expect(is_equal_approx(tick.chain.warm_minutes(_milk, SHELF), 90.0), "Two units on a shelf for 90 minutes")
	var moved: Dictionary = {"product": _milk, "qty": 2, "from": SHELF, "to": FRIDGE_B}
	_expect(net._publish(&"units_moved", moved), "The units go into another fridge slot")
	_expect(is_equal_approx(tick.chain.warm_minutes(_milk, FRIDGE_B), 90.0)
		and is_zero_approx(tick.chain.warm_minutes(_milk, SHELF)),
		"...with their clock")
	sim["minute"] = 2600.0
	tick.poll()
	_expect(is_equal_approx(tick.chain.warm_minutes(_milk, FRIDGE_B), 90.0), "In the fridge the clock stops")
	_expect(net._publish(&"units_moved", {"product": _milk, "qty": 2, "from": FRIDGE_B, "to": SHELF_B}),
		"...and out again")
	sim["minute"] = 2629.0
	tick.poll()
	_expect(inv.count(_milk, SHELF_B) == 2, "29 more minutes still hold (the fridge didn't make it fresh)")
	sim["minute"] = 2630.0
	tick.poll()
	_expect(inv.count(_milk, SHELF_B) == 0, "...and the minute 120 rots it")

	# A pallet, a cart and the floor age as well; a hand does not.
	var other: Dictionary = {"open": true, "minute": 100.0, "day": 1}
	var second: Dictionary = _host_side("TickSide2", other)
	var net2: CompanyNet = second["net"]
	for place: StringName in [&"pallet:p1", &"cart:1", &"hands:1"]:
		net2.inventory.receive(_milk, 1, place)
	var tick2: ColdChainTick = second["tick"]
	tick2.poll()
	other["minute"] = 220.0
	tick2.poll()
	_expect(net2.inventory.count(_milk, &"pallet:p1") == 0 and net2.inventory.count(_milk, &"cart:1") == 0
		and net2.inventory.count(_milk, &"hands:1") == 1, "A pallet and a cart rot, what is in a hand does not")

	# The save: the clocks go to the company and come back.
	other["minute"] = 221.0
	tick2.poll()
	net2.inventory.receive(_milk, 2, SHELF)
	other["minute"] = 251.0
	tick2.poll()
	ColdChainTick.write_clocks(second["side"], second["company"])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(second["company"].call(&"to_dict")))
	var loaded: Node = STATE_SCRIPT.new()
	loaded.from_dict(saved)
	var clocks := ColdChain.new()
	clocks.from_dict(loaded.cold_clocks)
	_expect(is_equal_approx(clocks.warm_minutes(_milk, SHELF), 30.0),
		"The clock survives the save (got %s)" % [loaded.cold_clocks])
	loaded.free()
	for side_name: String in ["TickSide", "TickSide2"]:
		var side: Node = root.get_node_or_null(side_name)
		set_multiplayer(null, side.get_path())
		side.free()
	await process_frame


# --- CompanyState ---


func _test_state() -> void:
	var state: Node = STATE_SCRIPT.new()
	state.new_company("Cold")
	_expect(state.cold_clocks == {} and state.to_dict().has("cold_clocks"),
		"A new company has no clocks, and the save has the key")
	var data: Dictionary = state.to_dict()
	data["cold_clocks"] = {"warm": {"milk_canister": {"shelf:shelf_1_0": 45.0}}}
	var back: Node = STATE_SCRIPT.new()
	_expect(back.from_dict(JSON.parse_string(JSON.stringify(data))), "A save with clocks loads")
	var kept := ColdChain.new()
	kept.from_dict(back.cold_clocks)
	_expect(is_equal_approx(kept.warm_minutes(_milk, SHELF), 45.0), "...and keeps them (got %s)" % [back.cold_clocks])
	data.erase("cold_clocks")
	_expect(back.from_dict(data) and back.cold_clocks == {}, "An old save without the key loads with no clocks")
	for junk: Variant in ["broken", 7, [], {"warm": "x"}, {"warm": {"milk_canister": {"shelf:a_0": 9999.0}}}]:
		data["cold_clocks"] = junk
		_expect(back.from_dict(data) and back.cold_clocks == {},
			"A broken clocks entry loads as none (got %s)" % [junk])
	back.reset()
	_expect(back.cold_clocks == {}, "reset() forgets them")
	back.free()
	state.free()


# --- Two peers ---


func _test_peers() -> void:
	var sim: Dictionary = {"open": true, "minute": 480.0, "day": 1}
	var host: Dictionary = _host_side("HostSide", sim)
	var server := ENetMultiplayerPeer.new()
	_expect(server.create_server(PORT, 3) == OK, "The test hosts an ENet session on localhost:%d" % PORT)
	(host["side"] as Node).multiplayer.multiplayer_peer = server
	var host_net: CompanyNet = host["net"]
	var tick: ColdChainTick = host["tick"]
	host_net.inventory.receive(_milk, 3, SHELF)
	host_net.inventory.receive(_milk, 2, FRIDGE)
	host_net.inventory.receive(_vase, 4, SHELF)
	host_net.inventory.reserve(_milk, 2, &"o1")
	host_net.inventory.reserve(_milk, 2, &"o2")
	var client: Dictionary = _host_side("ClientSide", sim, false)
	var client_peer := ENetMultiplayerPeer.new()
	_expect(client_peer.create_client("127.0.0.1", PORT) == OK, "The client starts joining")
	(client["side"] as Node).multiplayer.multiplayer_peer = client_peer
	var client_net: CompanyNet = client["net"]
	client_net.wait_for_snapshot()
	var connected: bool = await _wait_for(func() -> bool:
		return host_net.multiplayer.get_peers().size() == 1 and client_net.multiplayer.get_peers().has(1))
	_expect(connected, "The client connects to the host")
	if connected:
		_expect(host_net.send_snapshot(client_net.multiplayer.get_unique_id()), "The host sends the snapshot")
		var joined: bool = await _wait_for(func() -> bool: return not client_net.awaiting_snapshot())
		_expect(joined and client_net.inventory.count(_milk, SHELF) == 3, "The client joins with the same stock")
		tick.poll()
		sim["minute"] = 600.0
		tick.poll()
		var seq: int = host_net.seq
		_expect(host_net.inventory.count(_milk, SHELF) == 0, "The host's shelf milk rotted")
		var arrived: bool = await _wait_for(func() -> bool: return client_net.seq == seq)
		_expect(arrived, "The event reaches the client")
		for net: CompanyNet in [host_net, client_net]:
			var who: String = "host" if net == host_net else "client"
			_expect(net.inventory.count(_milk, SHELF) == 0 and net.inventory.count(_milk, FRIDGE) == 2
				and net.inventory.count(_vase, SHELF) == 4,
				"On the %s the shelf milk is gone, the fridge's and the vase stay" % who)
			_expect(net.inventory.reserved_by(&"o1").get(_milk, 0) == 2
				and not net.inventory.reserved_by(&"o2").has(_milk),
				"On the %s the newest order lost its milk" % who)
		_expect(client_net.inventory.to_dict() == host_net.inventory.to_dict(),
			"Both stocks, reservations included, are equal")
		_expect(not client_net.awaiting_snapshot(), "The client did not need a new snapshot")
		_expect(not (host_net.snapshot()["company"] as Dictionary).has("cold_clocks"),
			"The snapshot's company part has no cold_clocks")
		var late: Dictionary = _host_side("LateSide", sim, false)
		var late_peer := ENetMultiplayerPeer.new()
		_expect(late_peer.create_client("127.0.0.1", PORT) == OK, "A late client starts joining")
		(late["side"] as Node).multiplayer.multiplayer_peer = late_peer
		var late_net: CompanyNet = late["net"]
		late_net.wait_for_snapshot()
		var late_up: bool = await _wait_for(func() -> bool: return host_net.multiplayer.get_peers().size() == 2)
		if late_up:
			host_net.send_snapshot(late_net.multiplayer.get_unique_id())
			await _wait_for(func() -> bool: return not late_net.awaiting_snapshot())
			_expect(late_net.inventory.to_dict() == host_net.inventory.to_dict(),
				"A late joiner gets the stock as it is")
		late_peer.close()
	client_peer.close()
	server.close()
	await process_frame
	for side_name: String in ["HostSide", "ClientSide", "LateSide"]:
		var side: Node = root.get_node_or_null(side_name)
		if side != null:
			set_multiplayer(null, side.get_path())
			side.free()
	RpcGuard.reset()


# --- The real root ---


func _test_root() -> void:
	_clean()
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = DIR
	root.add_child(level)
	await process_frame
	await physics_frame
	var net: CompanyNet = level.net
	var tick: ColdChainTick = level.get_node_or_null(ColdChainTick.NODE_NAME) as ColdChainTick
	_expect(tick != null and level.business_tick.has_step(ColdChainTick.STEP),
		"The root has its tick, a step of the business tick")
	_expect(not level.day_cycle.is_frozen() and (level.day_cycle.phase() == DayCycle.Phase.OPENING
		or level.day_cycle.phase() == DayCycle.Phase.OPERATING), "The day is open and the shed thawed")
	if tick == null:
		level.free()
		state.call(&"reset")
		_clean()
		return
	var places: Dictionary = net.inventory.locations_of(_milk)
	var on_pallets: Callable = func(place: StringName) -> bool: return String(place).begins_with("pallet:")
	_expect(not places.is_empty() and places.keys().all(on_pallets),
		"A new company's milk waits on its first pallets (got %s)" % [places])
	var total: int = net.inventory.count(_milk)
	net.inventory.receive(_milk, 2, FRIDGE)
	level.clock.start(float(CompanyTuning.DAY_START_MIN))
	tick.poll()
	level.clock.start(float(CompanyTuning.DAY_START_MIN) + 60.0)
	tick.poll()
	var pallet: StringName = places.keys()[0]
	var aged: float = tick.chain.warm_minutes(_milk, pallet)
	_expect(aged > 59.0 and aged < 61.0, "After an hour the pallet milk is an hour out (got %s)" % aged)
	var seq: int = net.seq
	level.clock.start(float(CompanyTuning.DAY_START_MIN) + 60.0 + CompanyTuning.COLD_SPOIL_MINUTES)
	tick.poll()
	_expect(net.inventory.count(_milk) == 2 and net.inventory.count(_milk, FRIDGE) == 2 and net.seq > seq,
		"Two game hours later the pallet milk (%d) rotted and the fridge's did not" % total)
	# What is left on a pallet goes to the save with its clock.
	net.inventory.receive(_milk, 1, pallet)
	level.clock.start(float(CompanyTuning.DAY_START_MIN) + 60.0 + CompanyTuning.COLD_SPOIL_MINUTES + 30.0)
	tick.poll()
	# The interrupted day writes nothing; the closed day does (save_closed_day()), through write_clocks().
	var to_save: Node = STATE_SCRIPT.new()
	ColdChainTick.write_clocks(level, to_save)
	level.free()
	CompanySave.save(to_save, CompanySave.DEFAULT_SLOT, DIR)
	to_save.free()
	var saved: Node = STATE_SCRIPT.new()
	CompanySave.load_into(saved, CompanySave.DEFAULT_SLOT, DIR)
	var clocks := ColdChain.new()
	clocks.from_dict(saved.cold_clocks)
	var kept: float = clocks.warm_minutes(_milk, pallet)
	_expect(kept > 29.0 and kept < 31.0, "Leaving the root saves the clocks (got %s)" % [saved.cold_clocks])
	saved.free()
	state.call(&"reset")
	_clean()


func _wait_for(done: Callable, seconds: float = 5.0) -> bool:
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
