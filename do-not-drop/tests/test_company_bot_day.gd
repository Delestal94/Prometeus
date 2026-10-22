extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_bot_day.gd
##
## Guards the company-day bot (tests/bot_company_day.gd, D-2016) so each stage keeps working:
## - the stage list and its order (receive_pallet ... close_day);
## - stage_line: not_implemented -> "BOT_FAIL not_implemented:<stage>", fail -> "BOT_FAIL
##   <stage>:<reason>", ok -> "" (the bot prints BOT_STAGE <stage> ok instead);
## - final_line is BOT_OK only when every stage is ok, else BOT_FAIL stages_missing=<n> (a bot that
##   always said OK would hide the missing stages);
## - summary_lines keys (return_bundle_units too, D-0252) and the BOT_COMPANY prefix;
## - integration: the bot's own open_world/wait_opening open the company world (company_root.tscn)
##   and the day reaches OPENING within the bounded wait; closing leaves no error behind;
## - the stages, run in order on that one world (run_stage): receive_pallet, shelve_stock,
##   take_orders, pack_boxes, dispatch, drive, deliver, return and close_day return ok, and what each leaves is checked
##   in the world (the pallets open and the stock on the labelled shelf slots, the day's whole plan
##   brought by the world into the shared book, CompanyNet.orders.book, and copied OPEN into
##   CompanyTrips' own book, D-0813.1; one order PACKED by a sealed box with no assembly error and
##   its packaging in the ledger, the cargo loaded with the trip not started, D-2016.2: the fleet's
##   van, the real node, driven by the player out of the yard under its own physics, so the gate
##   started its trip with the order OUT, the van outside and moved, the player at the wheel, then
##   DELIVERED at a house of the fixed map with the pay in the wallet and the ledger as order_paid,
##   reversed back into the yard with the trip closed, nothing failed or out and the player off the
##   wheel, the day in SUMMARY with the costs of the packing in its summary and saved); no stage is
##   pending any more (PENDING stays for the next one that is); a stage run out of order fails
##   with a reason, and so do a stage name that does not exist and a world that is not the
##   company's.

const BOT: String = "res://tests/bot_company_day.gd"
const DAY_CYCLE := preload("res://scripts/core/company/day_cycle.gd")
## The stages that run, and the ones that wait for a task: stage -> the reason they return.
const PENDING: Dictionary = {}

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
	await _check_world(bot)
	if _failures == 0:
		print("PASS: company bot contract, OPENING reached and its stages run")
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
	var final: String = bot.call(&"final_line", results)
	_expect(final == "BOT_OK", "All ok gives BOT_OK (got %s)" % final)
	results["drive"] = todo
	final = bot.call(&"final_line", results)
	_expect(final == "BOT_FAIL stages_missing=1", "One missing (got %s)" % final)
	final = bot.call(&"final_line", {})
	_expect(final == "BOT_FAIL stages_missing=9", "Nothing run (got %s)" % final)
	results["drive"] = {"status": "fail", "reason": "x"}
	final = bot.call(&"final_line", results)
	_expect(final != "BOT_OK", "A failed stage is not BOT_OK (got %s)" % final)

	var stats: Dictionary = {
		"players": 2, "money": 500, "deliveries": 0, "breaks": 0, "assembly_errors": 0, "return_bundle_units": 3,
		"stage_ms": {"drive": 7},
	}
	var lines: PackedStringArray = bot.call(&"summary_lines", stats)
	_expect(lines.size() == 6 + names.size(), "Summary line count (got %d)" % lines.size())
	_expect("BOT_COMPANY return_bundle_units=3" in lines, "Return bundle line (got %s)" % [lines])
	_expect(lines[0] == "BOT_COMPANY players=2", "First line (got %s)" % lines[0])
	_expect(lines[1] == "BOT_COMPANY money=500", "Money line (got %s)" % lines[1])
	_expect("BOT_COMPANY stage_ms_drive=7" in lines, "Stage ms line (got %s)" % [lines])
	_expect("BOT_COMPANY stage_ms_close_day=0" in lines, "Missing ms is 0 (got %s)" % [lines])
	for text: String in lines:
		_expect(text.begins_with("BOT_COMPANY ") and "=" in text, "Prefix and key=value (%s)" % text)


func _check_world(bot: GDScript) -> void:
	var level: Node3D = await bot.call(&"open_world", self)
	_expect(level is CompanyRoot, "The company world opens (got %s)" % level)
	var reached: bool = await bot.call(&"wait_opening", self, level, 10.0)
	_expect(reached, "The day reaches OPENING within the bounded wait")
	var cycle: Node = level.get("day_cycle") as Node
	var phase: int = int(cycle.call(&"phase")) if cycle != null else -1
	_expect(phase == DAY_CYCLE.Phase.OPENING, "Phase is OPENING (got %d)" % phase)
	await _check_out_of_order(bot, level)
	await _check_stages(bot, level)
	bot.call(&"close_world", self, level)
	await process_frame
	_expect(not is_instance_valid(level), "The world is freed on close")
	_expect(current_scene == null or current_scene != level, "No stale current scene")


## A stage that needs what an earlier one leaves fails, with its reason, and changes nothing: so
## the same world still runs them in order afterwards.
func _check_out_of_order(bot: GDScript, level: Node3D) -> void:
	var ctx: Dictionary = bot.call(&"new_context", 2)
	var money: int = _money(level)
	var cases: Dictionary = {
		"shelve_stock": "nothing_in_hands", "pack_boxes": "no_packable_order",
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
	var ctx: Dictionary = bot.call(&"new_context", 2)
	var money: int = _money(level)
	var start: int = Time.get_ticks_msec()
	for stage: String in bot.call(&"stage_names"):
		var result: Dictionary = await bot.call(&"run_stage", self, level, stage, ctx)
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
			"close_day":
				_check_closed(root_level, ctx)
	var seconds: float = (Time.get_ticks_msec() - start) / 1000.0
	# drive and return move the real van in real-time physics (about 2 s each).
	_expect(seconds < 15.0, "The stages run in a bounded time (took %.1f s)" % seconds)


func _check_received(level: CompanyRoot, ctx: Dictionary) -> void:
	var opened: Dictionary = ctx["opened"]
	_expect(opened.size() >= 2, "The day's pallets were opened (got %d)" % opened.size())
	for id: StringName in opened:
		_expect(opened[id]["state"] == &"open", "Pallet %s is open" % id)
	var hands: Dictionary = ctx["hands"]
	var location: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
	_expect(level.net.inventory.count(hands["product"], location) == hands["qty"],
		"The units taken from the pallet are in the bot's hands")


func _check_shelved(level: CompanyRoot, ctx: Dictionary) -> void:
	var location: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
	_expect(level.net.inventory.contents_at(location).is_empty(), "Nothing is left in the hands")
	var opened: Dictionary = ctx["opened"]
	for id: StringName in opened:
		var product: StringName = opened[id]["product"]
		var shelved: int = 0
		for shelf: Shelf in level.shed.shelves.values():
			shelved += shelf.total_of(level.net.inventory, product)
		_expect(shelved >= CompanyTuning.HAND_MAX_UNITS,
			"Units of %s are on the shelf slot labelled for it (got %d)" % [product, shelved])


func _check_orders(level: CompanyRoot, ctx: Dictionary) -> void:
	var book: OrderBook = level.trips.book
	var shared: OrderBook = level.net.orders.book
	var orders: Array = ctx["orders"]
	_expect(orders.size() >= 1 and level.net.orders.planned().is_empty() and shared.size() == orders.size(),
		"The world brought the whole day's plan into the shared book (got %d of %d, %d still planned)"
		% [shared.size(), orders.size(), level.net.orders.planned().size()])
	_expect(book != shared and book.size() == orders.size(),
		"The day's orders are copied into CompanyTrips' own book (got %d of %d)" % [book.size(), orders.size()])
	for order: Dictionary in orders:
		_expect(book.state_of(order["id"]) == Order.STATE_OPEN and shared.has(order["id"]),
			"Order %s is OPEN in CompanyTrips' book and in the shared one" % order["id"])


func _check_packed(level: CompanyRoot, ctx: Dictionary, money: int) -> void:
	var book: OrderBook = level.trips.book
	var order: Dictionary = ctx["order"]
	_expect(book.state_of(order["id"]) == Order.STATE_PACKED, "The packed order is PACKED")
	_expect(book.box_of(order["id"]) == ctx["box_id"], "The order knows its box")
	var box: PackedBox = ctx["box"]
	_expect(box != null and box.taped and box.label_order_id == order["id"],
		"The box is taped and labelled")
	_expect(int(ctx["assembly_errors"]) == 0, "The bot packs with no assembly error")
	_expect(_money(level) < money, "The box, padding and tape were paid from the wallet")
	var state: Node = level.net.company as Node
	_expect(int(state.call(&"ledger_total", &"boxes")) < 0, "The box is in the ledger as boxes")
	_expect(int(state.call(&"ledger_total", &"packaging")) < 0,
		"Tape is in the ledger as packaging")
	var in_package: StringName = StringName("package:%s" % ctx["box_id"])
	_expect(level.net.inventory.contents_at(in_package) == box.contents(),
		"The box's units are the package's in the stock")


func _check_dispatched(level: CompanyRoot, ctx: Dictionary) -> void:
	var order: Dictionary = ctx["order"]
	_expect(level.trips.book.state_of(order["id"]) == Order.STATE_PACKED,
		"The loaded order is still PACKED: it goes OUT when the vehicle leaves")
	_expect(level.trips.trips_out() == 0, "No trip started without a vehicle")


func _check_driven(level: CompanyRoot, ctx: Dictionary) -> void:
	var van := level.fleet.vehicle(String(ctx["vehicle_id"])) as VehicleBody3D
	var trip: Trip = ctx["trip"]
	_expect(van != null and trip != null and level.trips.trip_of(ctx["vehicle_id"]) == trip,
		"The fleet's van crossed the gate itself and its trip started")
	_expect(level.trips.book.state_of(ctx["order"]["id"]) == Order.STATE_OUT, "The loaded order is OUT")
	_expect(van != null and level.trips.gate.side_of(van.global_position) == TripGate.OUTSIDE
		and float(ctx["drive_m"]) > 2.0,
		"The van stands outside the yard, driven there (%.1f m)" % float(ctx["drive_m"]))
	_expect(van != null and int(van.get(&"driver_peer_id")) == level.player.get_multiplayer_authority(),
		"The player is at the wheel")


func _check_delivered(level: CompanyRoot, ctx: Dictionary, money: int) -> void:
	var order_id: StringName = ctx["order"]["id"]
	var trip: Trip = ctx["trip"]
	_expect(trip != null and trip.is_out() and level.trips.trips_out() == 1,
		"The van is out on its trip")
	_expect(level.trips.book.state_of(order_id) == Order.STATE_DELIVERED, "The order is DELIVERED")
	_expect(trip != null and order_id in trip.delivered_ids and trip.next_stop() == &"",
		"The trip recorded the delivery and has no stop left")
	var house: StringName = StringName(ctx["order"]["house_id"])
	_expect(HouseMap.load_default().spot(house) != null, "The order's house is on the fixed map")
	_expect(int(ctx["deliveries"]) >= 1, "The delivery is counted (got %d)" % int(ctx["deliveries"]))
	_expect(_money(level) > money, "The customer paid into the wallet")
	var state: Node = level.net.company as Node
	_expect(int(state.call(&"ledger_total", OrderSettlement.REASON_PAID)) > 0,
		"The pay is in the ledger as order_paid")


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


func _check_closed(level: CompanyRoot, ctx: Dictionary) -> void:
	var cycle: DayCycle = level.day_cycle
	_expect(cycle.phase() == DAY_CYCLE.Phase.SUMMARY,
		"The day is in SUMMARY (got %s)" % cycle.phase_name())
	_expect(cycle.summary.get("day") == cycle.current_day(), "The summary is of the day played")
	_expect(int(cycle.summary.get("costs", 0)) > 0, "The summary counts the day's costs")
	var path: String = CompanySave.path_for(level.save_slot, level.save_dir)
	_expect(FileAccess.file_exists(path), "The closed day was saved to the temp folder")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved := Inventory.new()
	if raw is Dictionary:
		saved.from_dict(((raw as Dictionary).get("company", {}) as Dictionary).get("inventory", {}))
	var left: int = CompanyAsk.units_at(saved, CompanyRoot.SAVED_HANDS_LOCATION)
	_expect(int(ctx.get("return_bundle_units", -1)) == left,
		"The bot counts the units the save left in the return bundle (D-0252) (got %s, saved %d)"
		% [ctx.get("return_bundle_units"), left])


func _money(level: Node3D) -> int:
	return int((level as CompanyRoot).net.company.get("money"))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
