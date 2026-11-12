extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bot_day.gd
##
## Guards the company-day bot (tests/bot_company_day.gd, D-2016; its shed stages bot_company_shed.gd, its crew
## bot_company_crew.gd, its driving bot_company_trip.gd) so each stage keeps playing through the game's own paths:
## - the stage list and its order (receive_pallet ... close_day);
## - stage_line: not_implemented -> "BOT_FAIL not_implemented:<stage>", fail -> "BOT_FAIL <stage>:<reason>", ok ->
##   "" (the bot prints BOT_STAGE <stage> ok instead);
## - final_line is BOT_OK only when every stage is ok AND the day was played for real: a shortcut taken (BOT_STUB),
##   a profit of 0 or less, an engine error, a player idle over 120 s or nothing measured each give BOT_FAIL with
##   what failed (D-2016.4: a bot that always said OK would hide the shortcuts it still takes);
## - stub_lines prints BOT_STUB <stage> <id> [<tasks>] for each shortcut; summary_lines carries profit, boxes,
##   engine_errors, return_bundle_units and idle_max_s_<peer> per player, with the BOT_COMPANY prefix;
## - the crew's idle watch: a player with nothing in the hands for longer than the limit is reported, and on the
##   played world one with units in the hands is busy (no stretch while they are there, it starts once they go);
## - integration: open_world/wait_opening open the company world and the day reaches OPENING; the world's own
##   station lookup (CompanyShed.station_for, set by CompanyRoot) is the one CompanyNet uses and resolves a packing
##   table (table:<uid>: D-0715's box_* requests reach a station in the company world);
## - the stages, run in order on that one world with two players (the host's and a second one of the crew):
##   receive_pallet (the pallets in reception, opened by the stub pallet_unload), shelve_stock (every unit on its
##   labelled slot through units_store, both players' hands empty), take_orders (six orders of the shared book, none
##   copied into CompanyTrips' book), pack_boxes (six boxes through the box_* requests, each a DeliveryPackage under
##   World/Packages carrying its order and its units, the packaging charged through events, both players packed),
##   dispatch (each box carried by hand into the dispatch zone, loaded with the board's Load: on the van's rack, the
##   cargo staged, the trip book learnt the orders PACKED through CompanyDispatch, no trip out), drive (the van out of
##   the yard under its own physics, every order OUT, the autopilot 20 m into the street), deliver (every order
##   DELIVERED with its own box, the pay in the wallet, the stub door_settle), return (the van back in the yard, the
##   trip closed, the guide's day-1 objectives ticked) and close_day (SUMMARY with packing costs and rent, the game's
##   own save of the closed day: day + 1, read back by the bot) return ok; afterwards the run's stubs are exactly
##   pallet_unload, table_use, order_claim and door_settle, both players have an idle number and final_line is not
##   BOT_OK while those stubs are left;
## - a stage run out of order fails with a reason, and so do a stage name that does not exist and a world that is not
##   the company's.

const BOT: String = "res://tests/bot_company_day.gd"
const CREW := preload("res://tests/bot_company_crew.gd")
const DAY_CYCLE := preload("res://scripts/core/company/day_cycle.gd")
## The stages that run, and the ones that wait for a task: stage -> the reason they return.
const PENDING: Dictionary = {}
## Metres of street the autopilot drives out in this test (the bot by hand drives the whole way).
const DRIVE_CAP_M: float = 20.0
## The shortcuts the day still takes (D-2016.4 part 2 removes them with D-0607.c, D-0340 + D-0815.b, D-0701.b and
## order_claim).
const STUBS_LEFT: Array[StringName] = [&"pallet_unload", &"table_use", &"order_claim", &"door_settle"]
## Wall-clock bound of the nine stages here (six boxes packed and carried, the van out 20 m and back).
const STAGES_SECONDS: float = 90.0
## _check_busy: a peer no player of the run uses, and a product id only it holds (so no reservation is touched).
const BUSY_PEER: int = 99
const BUSY_PRODUCT: StringName = &"bot_idle_probe"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bot: GDScript = load(BOT) as GDScript
	_expect(bot != null, "The bot script loads (got %s)" % bot)
	if bot == null:
		quit(1)
		return
	_check_pure(bot)
	_check_idle_watch()
	await _check_world(bot)
	if _failures == 0:
		print("PASS: company bot contract, OPENING reached and its stages run through the game")
	quit(_failures)


func _check_pure(bot: GDScript) -> void:
	var expected := PackedStringArray([
		"receive_pallet", "shelve_stock", "take_orders", "pack_boxes", "dispatch", "drive",
		"deliver", "return", "close_day",
	])
	var names: PackedStringArray = bot.call(&"stage_names")
	_expect(names == expected, "Stages in order (got %s)" % names)

	var todo: Dictionary = {"status": "not_implemented", "reason": "D-2016.2"}
	var line: String = bot.call(&"stage_line", "drive", todo)
	_expect(line == "BOT_FAIL not_implemented:drive", "not_implemented line (got %s)" % line)
	line = bot.call(&"stage_line", "deliver", {"status": "fail", "reason": "no_house"})
	_expect(line == "BOT_FAIL deliver:no_house", "fail line (got %s)" % line)
	line = bot.call(&"stage_line", "drive", {"status": "ok", "reason": ""})
	_expect(line == "", "ok prints no BOT_FAIL line (got %s)" % line)
	line = bot.call(&"stage_ok_line", "drive")
	_expect(line == "BOT_STAGE drive ok", "ok stage line (got %s)" % line)

	var results: Dictionary = {}
	for stage: String in names:
		results[stage] = {"status": "ok", "reason": ""}
	var good: Dictionary = {"stubs": [], "profit": 120, "engine_errors": 0, "idle": {1: 30.0, 2: 80.0}}
	var final: String = bot.call(&"final_line", results, good)
	_expect(final == "BOT_OK", "All ok and a real day gives BOT_OK (got %s)" % final)
	var cases: Dictionary = {
		"stubs=1": {"stubs": [&"door_settle"]}, "profit=0": {"profit": 0}, "profit=-5": {"profit": -5},
		"engine_errors=2": {"engine_errors": 2}, "idle_2=121": {"idle": {1: 3.0, 2: 121.0}},
		"idle_unmeasured": {"idle": {}},
	}
	for problem: String in cases:
		final = bot.call(&"final_line", results, good.merged(cases[problem], true))
		_expect(final == "BOT_FAIL " + problem, "%s blocks BOT_OK (got %s)" % [problem, final])
	final = bot.call(&"final_line", results, {})
	_expect(final.begins_with("BOT_FAIL") and "engine_errors=-1" in final,
		"A run that measured nothing is no BOT_OK (got %s)" % final)
	results["drive"] = todo
	final = bot.call(&"final_line", results, good)
	_expect(final == "BOT_FAIL stages_missing=1", "One missing (got %s)" % final)
	final = bot.call(&"final_line", {}, good)
	_expect(final == "BOT_FAIL stages_missing=9", "Nothing run (got %s)" % final)

	var stubs: PackedStringArray = bot.call(&"stub_lines", [&"pallet_unload", &"door_settle"])
	_expect(stubs.size() == 2 and stubs[0].begins_with("BOT_STUB receive_pallet pallet_unload [D-0607.c]")
		and stubs[1].begins_with("BOT_STUB deliver door_settle [D-0340"), "BOT_STUB lines (got %s)" % [stubs])

	var stats: Dictionary = {
		"players": 2, "money": 500, "profit": 40, "deliveries": 6, "boxes": 7, "breaks": 0, "assembly_errors": 0,
		"engine_errors": 0, "return_bundle_units": 3, "idle": {2: 12.5, 1: 4.0}, "stage_ms": {"drive": 7},
	}
	var lines: PackedStringArray = bot.call(&"summary_lines", stats)
	_expect(lines.size() == 9 + 2 + names.size(), "Summary line count (got %d)" % lines.size())
	_expect(lines[0] == "BOT_COMPANY players=2", "First line (got %s)" % lines[0])
	_expect(lines[1] == "BOT_COMPANY money=500", "Money line (got %s)" % lines[1])
	for wanted: String in [
		"BOT_COMPANY profit=40", "BOT_COMPANY boxes=7", "BOT_COMPANY engine_errors=0",
		"BOT_COMPANY return_bundle_units=3", "BOT_COMPANY idle_max_s_1=4.0", "BOT_COMPANY idle_max_s_2=12.5",
		"BOT_COMPANY stage_ms_drive=7", "BOT_COMPANY stage_ms_close_day=0",
	]:
		_expect(wanted in lines, "Summary has %s (got %s)" % [wanted, lines])
	_expect(lines.find("BOT_COMPANY idle_max_s_1=4.0") < lines.find("BOT_COMPANY idle_max_s_2=12.5"),
		"Idle lines in peer order")
	for text: String in lines:
		_expect(text.begins_with("BOT_COMPANY ") and "=" in text, "Prefix and key=value (%s)" % text)


## The idle watch alone: a player with nothing is idle for as long as it lasts, the stop counts up to then.
func _check_idle_watch() -> void:
	var watch := CREW.IdleWatch.new()
	var nobody := Player.new()
	watch.restart([{"peer": 7, "player": nobody}], 1000)
	watch.sample(31000)
	watch.stop(151500)
	watch.sample(400000)
	var report: Dictionary = watch.report()
	_expect(is_equal_approx(float(report.get(7, -1.0)), 150.5),
		"An idle player is reported for its whole stretch, up to the stop (got %s)" % [report])
	watch.free()
	nobody.free()


func _check_world(bot: GDScript) -> void:
	# D-1901: the guide starts from a profile that never saw it (a run before this one may have ticked it).
	var unlocks: Node = root.get_node_or_null(^"/root/UnlockManager")
	if unlocks != null:
		for id: StringName in CompanyOnboarding.KEYS:
			(unlocks.get(&"seen_tips") as Dictionary).erase(CompanyOnboarding.tip_id(id))
	var level: Node3D = await bot.call(&"open_world", self, 2)
	_expect(level is CompanyRoot, "The company world opens (got %s)" % level)
	var reached: bool = await bot.call(&"wait_opening", self, level, 10.0)
	_expect(reached, "The day reaches OPENING within the bounded wait")
	var cycle: Node = level.get("day_cycle") as Node
	var phase: int = int(cycle.call(&"phase")) if cycle != null else -1
	_expect(phase == DAY_CYCLE.Phase.OPENING, "Phase is OPENING (got %d)" % phase)
	_check_stations(level as CompanyRoot)
	await _check_out_of_order(bot, level)
	await _check_stages(bot, level)
	_check_busy(level as CompanyRoot)
	bot.call(&"close_world", self, level)
	await process_frame
	_expect(not is_instance_valid(level), "The world is freed on close")
	_expect(current_scene == null or current_scene != level, "No stale current scene")


## The idle watch on the world: units in a player's hands keep it busy (no stretch while they are there), and the
## stretch starts once they are gone. A peer no player uses (BUSY_PEER) so the day's own hands stay as they were.
func _check_busy(level: CompanyRoot) -> void:
	if level == null:
		return
	var watch := CREW.IdleWatch.new()
	watch.level = level
	var hands: StringName = CompanyNet.hands_location(BUSY_PEER)
	var stock: Inventory = level.net.inventory
	_expect(stock.contents_at(hands).is_empty(), "Nobody holds anything in hands:%d" % BUSY_PEER)
	watch.restart([{"peer": BUSY_PEER, "player": level.player}], 0)
	stock.receive(BUSY_PRODUCT, 2, hands)
	_expect(watch.is_busy({"peer": BUSY_PEER, "player": level.player}), "Units in the hands make a player busy")
	watch.sample(200000)
	_expect(is_zero_approx(float(watch.report().get(BUSY_PEER, -1.0))),
		"No idle stretch while units are in the hands (got %s)" % [watch.report()])
	stock.discard(BUSY_PRODUCT, 2, hands)
	watch.sample(260000)
	_expect(is_equal_approx(float(watch.report().get(BUSY_PEER, -1.0)), 60.0),
		"Once the hands are empty the stretch counts from the last busy look (got %s)" % [watch.report()])
	watch.free()


## CompanyNet asks the world's own lookup (the bot never replaces it), and that lookup knows a packing table.
func _check_stations(level: CompanyRoot) -> void:
	var lookup: Callable = level.net.stations
	_expect(lookup.get_object() == level.shed and lookup.get_method() == &"station_for",
		"CompanyNet.stations is the shed's own station_for")
	var tables: Array = level.shed.stations.keys()
	_expect(not tables.is_empty(), "The shed has a packing table")
	if tables.is_empty():
		return
	var id := StringName(CompanyTableNet.TABLE_PREFIX + String(tables[0]))
	var found: Dictionary = lookup.call(id)
	_expect(found.get("location") == id and found.get("spot") is Vector3,
		"A packing table is a station of the world (got %s)" % [found])
	var spot: Vector3 = found.get("spot", Vector3.ZERO)
	var use: Vector3 = (level.shed.use_points[tables[0]] as Node3D).global_position
	_expect(Vector2(spot.x - use.x, spot.z - use.z).length() < 3.0 and spot.y > CompanyShed.TABLE_TOP,
		"...its spot over the table, near its use point (got %s, use point %s)" % [spot, use])
	_expect(lookup.call(&"table:nope").is_empty(), "A table that is not in the shed is no station")


## A stage that needs what an earlier one leaves fails, with its reason, and changes nothing: so the same world
## still runs them in order afterwards.
func _check_out_of_order(bot: GDScript, level: Node3D) -> void:
	var ctx: Dictionary = bot.call(&"new_context", 2)
	var money: int = _money(level)
	var cases: Dictionary = {
		"shelve_stock": "nothing_in_hands", "pack_boxes": "no_orders_taken",
		"dispatch": "nothing_packed", "drive": "nothing_loaded", "deliver": "nothing_loaded",
		"return": "no_trip_out",
		"no_such_stage": "unknown_stage",
	}
	for stage: String in cases:
		var result: Dictionary = await bot.call(&"run_stage", self, level, stage, ctx)
		_expect(result.get("status") == "fail" and result.get("reason") == cases[stage],
			"%s out of order fails with %s (got %s)" % [stage, cases[stage], result])
	_expect(_money(level) == money, "A stage that failed early charged nothing")
	var stranger := Node3D.new()
	var foreign: Dictionary = await bot.call(&"run_stage", self, stranger, "take_orders", ctx)
	_expect(foreign.get("reason") == "no_company_world",
		"A world that is not the company's is refused (got %s)" % [foreign])
	stranger.free()


func _check_stages(bot: GDScript, level: Node3D) -> void:
	var root_level := level as CompanyRoot
	# The autopilot drives only DRIVE_CAP_M of the street (the whole way to Centro is about 85 s each way; the bot
	# run by hand does it all): the way back is the whole one from where the van stood.
	var ctx: Dictionary = bot.call(&"new_context", 2, DRIVE_CAP_M)
	var money: int = _money(level)
	var start: int = Time.get_ticks_msec()
	var results: Dictionary = {}
	for stage: String in bot.call(&"stage_names"):
		var result: Dictionary = await bot.call(&"run_stage", self, level, stage, ctx)
		results[stage] = result
		if PENDING.has(stage):
			var waits: bool = result.get("status") == "not_implemented"
			_expect(waits and result.get("reason") == PENDING[stage],
				"%s waits for %s (got %s)" % [stage, PENDING[stage], result])
			continue
		_expect(result.get("status") == "ok", "Stage %s is ok (got %s)" % [stage, result])
		if result.get("status") != "ok":
			return
		match stage:
			"receive_pallet":
				_check_received(root_level, ctx)
			"shelve_stock":
				_check_shelved(root_level, ctx)
			"take_orders":
				_check_orders(root_level, ctx)
			"pack_boxes":
				_check_packed(root_level, ctx, money)
			"dispatch":
				_check_dispatched(root_level, ctx)
				money = _money(level)
			"drive":
				_check_driven(root_level, ctx)
			"deliver":
				_check_delivered(root_level, ctx, money)
			"return":
				_check_returned(root_level, ctx)
				_check_onboarding(root_level)
			"close_day":
				_check_closed(root_level, ctx)
	var seconds: float = (Time.get_ticks_msec() - start) / 1000.0
	print("company bot: the nine stages took %.1f s" % seconds)
	_expect(seconds < STAGES_SECONDS, "The stages run in a bounded time (took %.1f s)" % seconds)
	_check_run(bot, root_level, ctx, results)


## After the day: the shortcuts left are exactly the four of part 2, each player has its idle number and the final
## line is not BOT_OK while any shortcut is left.
func _check_run(bot: GDScript, level: CompanyRoot, ctx: Dictionary, results: Dictionary) -> void:
	var taken: Array = ctx["stubs"]
	_expect(taken.size() == STUBS_LEFT.size(), "The run took the four shortcuts left (got %s)" % [taken])
	for id: StringName in STUBS_LEFT:
		_expect(taken.has(id), "The run notes the shortcut %s" % id)
	var stats: Dictionary = bot.call(&"stats_of", level, ctx)
	stats["engine_errors"] = 0
	var idle: Dictionary = stats["idle"]
	_expect(idle.has(1) and idle.has(CREW.SECOND_PEER), "Both players have an idle number (got %s)" % [idle])
	_expect(int(stats["boxes"]) >= 6, "Six boxes or more were packed (got %d)" % int(stats["boxes"]))
	var final: String = bot.call(&"final_line", results, stats)
	_expect(final.begins_with("BOT_FAIL") and "stubs=%d" % STUBS_LEFT.size() in final,
		"No BOT_OK while a shortcut is left (got %s)" % final)


## D-1901: the first week's guide followed the bot's day 1 on the real world and ticked the whole loop.
func _check_onboarding(level: CompanyRoot) -> void:
	var tracker: CompanyOnboardingTracker = level.get_node_or_null(^"Onboarding") as CompanyOnboardingTracker
	_expect(tracker != null, "The world carries the first week's guide")
	if tracker == null:
		return
	tracker.refresh()
	for id: StringName in CompanyOnboarding.DAY_ONE:
		_expect(tracker.is_done(id), "The bot's day 1 ticked the guide's %s" % id)
	_expect(tracker.line().is_empty(), "...and no day-1 line is left (got %s)" % [tracker.line()])


func _check_received(level: CompanyRoot, ctx: Dictionary) -> void:
	var opened: Dictionary = ctx["opened"]
	_expect(opened.size() >= 2, "The day's pallets were opened (got %d)" % opened.size())
	for id: StringName in opened:
		_expect(opened[id]["state"] == &"open", "Pallet %s is open" % id)
	var hands: Dictionary = ctx["hands"]
	var location: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
	_expect(level.net.inventory.count(hands["product"], location) == hands["qty"],
		"The units taken from the pallet are in the host's hands")
	_expect((ctx["stubs"] as Array).has(&"pallet_unload"), "Opening the pallets is noted as a shortcut")
	_expect((ctx["crew"] as Array).size() == 2, "Two players play (got %d)" % (ctx["crew"] as Array).size())


func _check_shelved(level: CompanyRoot, ctx: Dictionary) -> void:
	for actor: Dictionary in ctx["crew"]:
		_expect(level.net.inventory.contents_at(CREW.hands_of(actor)).is_empty(),
			"Nothing is left in the hands of player %d" % int(actor["peer"]))
	var opened: Dictionary = ctx["opened"]
	for id: StringName in opened:
		var pallet: Dictionary = opened[id]
		_expect(Pallet.units_left(level.net.inventory, pallet) == 0, "Pallet %s was emptied" % id)
		var shelved: int = 0
		for shelf: Shelf in level.shed.shelves.values():
			shelved += shelf.total_of(level.net.inventory, pallet["product"])
		_expect(shelved >= int(pallet["qty"]),
			"Units of %s are on the shelf slots (got %d of %d)" % [pallet["product"], shelved, int(pallet["qty"])])


func _check_orders(level: CompanyRoot, ctx: Dictionary) -> void:
	var orders: Array = ctx["orders"]
	var shared: OrderBook = level.net.orders.book
	_expect(orders.size() == 6, "Six orders taken (got %d)" % orders.size())
	for order: Dictionary in orders:
		var state: StringName = shared.state_of(order["id"])
		_expect(state == Order.STATE_OPEN or state == Order.STATE_LATE,
			"Order %s waits for a box in the shared book (got %s)" % [order["id"], state])
	_expect(level.trips.book.size() == 0, "No order is copied into CompanyTrips' book by the bot")


func _check_packed(level: CompanyRoot, ctx: Dictionary, money: int) -> void:
	var packed: Array = ctx["packed"]
	_expect(packed.size() == 6, "Six boxes packed (got %d)" % packed.size())
	var packers: Dictionary = {}
	for entry: Dictionary in packed:
		packers[int(entry["peer"])] = true
		var package: DeliveryPackage = DispatchRack.package_of(level.packages, entry["box_id"])
		_expect(package != null and package.get_parent() == level.packages,
			"Box %s is a package under World/Packages" % entry["box_id"])
		if package == null:
			continue
		_expect(StringName(package.get_meta(BoxToPackage.META_ORDER_ID, &"")) == entry["order_id"],
			"...carrying its order %s" % entry["order_id"])
		var units: Dictionary = level.net.inventory.contents_at(CompanyTableNet.package_location(entry["box_id"]))
		_expect(not units.is_empty(), "...with its units in the stock")
		_expect(not level.net.table.has_box(entry["table"]), "...and its table is free")
	_expect(packers.size() == 2, "Both players packed (got %s)" % [packers.keys()])
	_expect(int(ctx["assembly_errors"]) == 0, "The bot packs with no assembly error")
	_expect(_money(level) < money, "Boxes, padding and tape were paid from the wallet")
	var state: Node = level.net.company as Node
	_expect(int(state.call(&"ledger_total", &"boxes")) < 0, "The boxes are in the ledger as boxes")
	_expect(int(state.call(&"ledger_total", &"packaging")) < 0, "Tape and padding are in the ledger as packaging")
	for id: StringName in [&"table_use", &"order_claim"]:
		_expect((ctx["stubs"] as Array).has(id), "Packing notes the shortcut %s" % id)


func _check_dispatched(level: CompanyRoot, ctx: Dictionary) -> void:
	var body: Node3D = level.fleet.vehicle(String(ctx["vehicle_id"]))
	for entry: Dictionary in ctx["packed"]:
		var package: DeliveryPackage = DispatchRack.package_of(level.packages, entry["box_id"])
		_expect(package != null and DispatchRack.rides(body, package), "Box %s rides the van's rack" % entry["box_id"])
		_expect(level.trips.book.state_of(entry["order_id"]) == Order.STATE_PACKED
			and level.trips.book.box_of(entry["order_id"]) == entry["box_id"],
			"The trip book learnt order %s PACKED in its box (through the board)" % entry["order_id"])
	_expect(level.trips.has_cargo(ctx["vehicle_id"]), "The cargo is staged on the van")
	_expect(level.trips.trips_out() == 0, "No trip started without the van leaving")


func _check_driven(level: CompanyRoot, ctx: Dictionary) -> void:
	var van := level.fleet.vehicle(String(ctx["vehicle_id"])) as VehicleBody3D
	var trip: Trip = ctx["trip"]
	_expect(van != null and trip != null and level.trips.trip_of(ctx["vehicle_id"]) == trip,
		"The fleet's van crossed the gate itself and its trip started")
	for entry: Dictionary in ctx["packed"]:
		_expect(level.trips.book.state_of(entry["order_id"]) == Order.STATE_OUT, "Order %s is OUT" % entry["order_id"])
	_expect(van != null and level.trips.gate.side_of(van.global_position) == TripGate.OUTSIDE
		and float(ctx["drive_m"]) > 2.0,
		"The van stands outside the yard, driven there (%.1f m)" % float(ctx["drive_m"]))
	_expect(van != null and int(van.get(&"driver_peer_id")) == level.player.get_multiplayer_authority(),
		"The player is at the wheel")
	var piloted: Dictionary = (ctx["autopilot"] as Dictionary).get("drive", {})
	_expect(not piloted.is_empty() and piloted["reason"] == "" and piloted["metres"] > 60.0,
		"The autopilot drove the leg and the street (%s)" % [piloted])
	_expect(not piloted.is_empty() and piloted["off_road_max"] <= 1.0,
		"... without leaving the roadway (off_road_max %s m)" % piloted.get("off_road_max"))


func _check_delivered(level: CompanyRoot, ctx: Dictionary, money: int) -> void:
	var trip: Trip = ctx["trip"]
	_expect(trip != null and trip.is_out() and level.trips.trips_out() == 1, "The van is out on its trip")
	for entry: Dictionary in ctx["packed"]:
		_expect(level.trips.book.state_of(entry["order_id"]) == Order.STATE_DELIVERED,
			"Order %s is DELIVERED" % entry["order_id"])
		_expect(trip != null and entry["order_id"] in trip.delivered_ids, "...and recorded on the trip")
	_expect(trip != null and trip.next_stop() == &"", "The trip has no stop left")
	_expect(int(ctx["deliveries"]) == (ctx["packed"] as Array).size(),
		"Every box is a delivery (got %d)" % int(ctx["deliveries"]))
	_expect(_money(level) > money, "The customers paid into the wallet")
	var state: Node = level.net.company as Node
	_expect(int(state.call(&"ledger_total", OrderSettlement.REASON_PAID)) > 0, "The pay is in the ledger as order_paid")
	_expect((ctx["stubs"] as Array).has(&"door_settle"), "Settling by hand is noted as a shortcut")


func _check_returned(level: CompanyRoot, ctx: Dictionary) -> void:
	var trip: Trip = ctx["trip"]
	_expect(trip != null and not trip.is_out() and trip.failed_ids.is_empty(),
		"The trip closed on return with nothing failed")
	_expect(level.trips.trips_out() == 0, "No vehicle is out: the day may close")
	_expect(level.trips.closed_trips().size() == 1, "One closed trip")
	var van := level.fleet.vehicle(String(ctx["vehicle_id"])) as VehicleBody3D
	_expect(van != null and level.trips.gate.side_of(van.global_position) == TripGate.INSIDE,
		"The van was driven back into the yard")
	_expect(van != null and int(van.get(&"driver_peer_id")) == 0, "Nobody is left at the wheel")
	var back: Dictionary = (ctx["autopilot"] as Dictionary).get("return", {})
	_expect(not back.is_empty() and back["reason"] == "" and back["off_road_max"] <= 1.0,
		"The autopilot brought it back in the street (%s)" % [back])


func _check_closed(level: CompanyRoot, ctx: Dictionary) -> void:
	var cycle: DayCycle = level.day_cycle
	_expect(cycle.phase() == DAY_CYCLE.Phase.SUMMARY, "The day is in SUMMARY (got %s)" % cycle.phase_name())
	_expect(cycle.summary.get("day") == cycle.current_day(), "The summary is of the day played")
	_expect(int(cycle.summary.get("costs", 0)) > 0, "The summary counts the day's costs")
	var path: String = CompanySave.path_for(level.save_slot, level.save_dir)
	_expect(FileAccess.file_exists(path), "The game saved the closed day to the temp folder")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var company: Dictionary = (raw as Dictionary).get("company", {}) if raw is Dictionary else {}
	_expect(int(company.get("day", -1)) == cycle.current_day() + 1,
		"The save is the next day's opening (got day %s)" % company.get("day"))
	var saved := Inventory.new()
	saved.from_dict(company.get("inventory", {}))
	var left: int = CompanyAsk.units_at(saved, CompanyRoot.SAVED_HANDS_LOCATION)
	_expect(int(ctx.get("return_bundle_units", -1)) == left,
		"The bot counts the units the save left in the return bundle (D-0252) (got %s, saved %d)"
		% [ctx.get("return_bundle_units"), left])
	_expect(ctx["money_close"] != null and int(ctx["money_close"]) == int(cycle.summary.get("closing", -1)),
		"The closing money is the summary's")


func _money(level: Node3D) -> int:
	return int((level as CompanyRoot).net.company.get("money"))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
