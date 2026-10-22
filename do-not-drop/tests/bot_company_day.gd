extends SceneTree
## Bot that plays a whole Modo Empresa day (D-2016, the closing criterion of the F1 vertical
## slice D-0111). Not a test_*.gd: the runner does not pick it up. Run:
##   <godot> --headless --path do-not-drop --script res://tests/bot_company_day.gd -- --players=2
## Opens the company world (scenes/gameplay/company_root.tscn, like bench_company.gd), waits for
## the day to reach OPENING (bounded, 10 s) and runs the stages in STAGES order on that one world,
## each one using what the one before left. Each stage returns {"status": "ok"|"fail"|
## "not_implemented", "reason": String} and is timed in ms. D-2016.2 fills in the stages whose F1
## pieces exist:
##   receive_pallet  ok  the day's supplier pallets are in reception (drawn and in the stock), a
##                       sealed one gives nothing, the bot opens them (Pallet.open) and takes a
##                       handful with units_take through CompanyNet
##   shelve_stock    ok  carries the pallets to the slots labelled for each product with
##                       units_store (a slot labelled for another product refuses wrong_product)
##   take_orders     ok  the world brings the day's orders in (D-0813.1): planned at the OPENING
##                       from the company's seed, published by the business tick into the shared
##                       book (CompanyNet.orders.book) as the clock reaches the last arrival; the
##                       bot copies them, OPEN, into CompanyTrips' own book, the one packing and
##                       dispatch use until those are events, each with its fields
##   pack_boxes      ok  at a packing table: units from the shelves by units_take, box size by
##                       BoxDispenser, products in, padding, label, seals, tape; order is PACKED
##   dispatch        ok  DispatchZone ties the sealed box to its order, DispatchRules clears the
##                       van, load_into() stages the cargo in CompanyTrips (the trip starts
##                       when the van crosses the gate)
##   drive           ok  the fleet's van (CompanyFleet, parked frozen in the playon) gets a driver:
##                       the player opens the cab door and takes the wheel (SeatPoint.interact), the
##                       pedal is pressed (drive_accelerate) and the van leaves the yard under its own
##                       physics; CompanyTrips' gate, which follows the node every tick, starts the
##                       Trip (the order goes OUT). Then the autopilot (D-2016.3, tests/bot_company_van.gd
##                       and bot_company_trip.gd) drives it along the street graph (RoadNavigator.route
##                       over the company world's RoadGraph, pure pursuit with analog steering): a Bezier
##                       leg from the yard to the first avenue (the graph has no street through the
##                       playon) and then the route to the street point in front of the Trip's first
##                       stop's house (about 85 s to Centro). Fails if it does not get there or if the van
##                       leaves the roadway (off_road_max over VAN.OFF_ROAD_LIMIT_M, D-0304.3)
##   deliver         ok  at each stop of the Trip the van is at the house (the autopilot drives there if
##                       it is not; within HOUSE_REACH_M), the house is one of the fixed map's (HouseMap,
##                       D-0311) in the order's zone, the door settles each order (OrderSettlement: pay
##                       into the wallet, reputation) and the Trip records it (record_settled), until no
##                       stop is left. Not yet the house's own door: DeliveryHouse is the delivery run's
##                       (doorbell and carried package) and the company world has no delivery at it
##   return          ok  the autopilot takes the van back the way it came: a K-turn first if it stands
##                       facing away (VAN.turn_around, strokes forward and in reverse), the route to the
##                       avenue, the leg into the playon; the gate closes the Trip with nothing failed, no
##                       vehicle is out and TripResult reports the deliveries and the clock; the player
##                       gets out (leave_seat)
##   close_day       ok  the clock jumps to 20:00 and DayCycle goes OPERATING, CLOSING, SUMMARY;
##                       the summary holds the day's packaging costs and the closed day saves
##                       and loads back
## What is not a CompanyNet request yet (REQUEST_KINDS has only units_take, units_store,
## units_drop and the build ones) the bot does on the host's own objects, as the world will on the
## host: opening a pallet, the box and the table (PackingStation, BoxDispenser,
## PackagingSupplies), moving units hand -> box -> package in the Inventory, the order book and
## the dispatch zone. CompanyRoot does not set CompanyNet.stations yet (D-0611), so the bot
## installs its own lookup for pallets and shelf slots and walks (teleports) the player to each
## spot first, so the reach check is a real one. None of that is replicated to clients yet: this
## is a host-side run (the peers come with D-2017).
## Prints:
##   BOT_FAIL not_implemented:<stage>   a stage with nothing behind it yet (the run goes on)
##   BOT_FAIL <stage>:<reason>          a failed stage (the run stops there)
##   BOT_FAIL no_opening                the day never reached OPENING
##   BOT_STAGE <stage> ok               a stage that passed
## then a summary block, one `BOT_COMPANY key=value` line each (players, money, deliveries,
## breaks, assembly_errors, return_bundle_units: what the closed day's save left in the return bundle,
## D-0252; stage_ms_<stage>), and the final line: `BOT_OK` if every stage was
## ok, else `BOT_FAIL stages_missing=<n>`.
## The van's crossings are the real node's: nothing feeds the gate by hand (CompanyTrips.track).
## The day's clock runs in real time while the van drives (90 s an hour): the whole bot takes about 3.5 minutes
## and the day may reach 20:00 on the way (close_day accepts the phases it finds from there on).
## Exit codes: 0 BOT_OK, 1 any BOT_FAIL, 3 hard wall-clock timeout (`BOT_TIMEOUT`).
## Optional user args: -- --players=N (1..8, default 2; it sizes the day's orders through
## CompanyRoot.order_crew, the peers come with D-2017) --hard=<seconds> (the hard timeout, default 300).
## new_context(players, drive_cap_m): with drive_cap_m > 0 the autopilot drives only that many metres of
## street out of the yard instead of the whole way to the house (the way back is always the whole one from
## wherever the van is): test_company_bot_day uses it to keep the stages near 40 s; the bot run by hand does
## all of it (cap 0).
## The company saves into a temp folder (user://bot_company_day), never the game's slot.
## The pure parts (stage_names, stage_line, summary_lines, final_line), the world helpers
## (open_world, wait_opening, close_world) and the stages (new_context, run_stage) are static:
## tests/test_company_bot_day.gd drives them on its own tree.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const DAY_CYCLE: GDScript = preload("res://scripts/core/company/day_cycle.gd")
const SAVE_DIR: String = "user://bot_company_day"
const PREFIX: String = "BOT_COMPANY"
const STAGES: Array[String] = [
	"receive_pallet", "shelve_stock", "take_orders", "pack_boxes", "dispatch", "drive", "deliver",
	"return", "close_day",
]
## The stages with nothing behind them yet: stage -> the F1 tasks that are missing.
const PENDING: Dictionary = {}
const OPENING_WAIT_SECONDS: float = 10.0
const DEFAULT_PLAYERS: int = 2
const DEFAULT_HARD_SECONDS: float = 300.0

const PRODUCTS_DIR: String = "res://data/products/"
const ZONE_DIR: String = "res://data/zones/"
const GATE_DIR: String = "res://data/gates/"
const VAN_PATH: String = "res://data/vehicles/van_classic.tres"
## The bot's company seed (CompanyState.company_seed, D-0246): the same day of orders on every run.
const ORDERS_SEED: int = 2016
## How long (real msec) the business tick may take to bring the day's orders in before take_orders
## fails: it runs every 250 ms.
const ORDER_WAIT_MSEC: int = 3000
## The bot stands this far from a station's spot (meters) when it uses it, well inside the reach.
const STAND_OFFSET: Vector3 = Vector3(0.0, 0.5, 1.0)
## Frames a phase change may take (DayCycle moves one step per poll()) before the stage fails.
const PHASE_FRAMES: int = 120
## How far ahead the day's own timer is moved so OPENING does not make the bot wait its 5 s: the
## clock is jumped to 20:00 anyway.
const SKIP_OPENING_MSEC: int = 10000
## Drives the fleet's van out of the yard and back (drive and return).
const VAN := preload("res://tests/bot_company_van.gd")
## The stages that drive it (drive, deliver, return: the autopilot, D-2016.3).
const TRIP := preload("res://tests/bot_company_trip.gd")

var _players: int = DEFAULT_PLAYERS
var _hard_seconds: float = DEFAULT_HARD_SECONDS
var _finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


# --- Pure parts (static, no world) ---


static func stage_names() -> PackedStringArray:
	return PackedStringArray(STAGES)


## The line a stage prints: "" for ok (see stage_ok_line), BOT_FAIL ... otherwise.
static func stage_line(stage: String, result: Dictionary) -> String:
	var status: String = str(result.get("status", "fail"))
	match status:
		"ok":
			return ""
		"not_implemented":
			return "BOT_FAIL not_implemented:%s" % stage
		_:
			return "BOT_FAIL %s:%s" % [stage, str(result.get("reason", "unknown"))]


static func stage_ok_line(stage: String) -> String:
	return "BOT_STAGE %s ok" % stage


## One `BOT_COMPANY key=value` line per key: the fixed counters, then stage_ms_<stage> in order.
static func summary_lines(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for key: String in ["players", "money", "deliveries", "breaks", "assembly_errors", "return_bundle_units"]:
		lines.append("%s %s=%s" % [PREFIX, key, str(stats.get(key, 0))])
	var times: Dictionary = stats.get("stage_ms", {})
	for stage: String in STAGES:
		lines.append("%s stage_ms_%s=%s" % [PREFIX, stage, str(times.get(stage, 0))])
	return lines


## BOT_OK only when every stage in STAGES has an "ok" result; else BOT_FAIL stages_missing=<n>.
static func final_line(results: Dictionary) -> String:
	var missing: int = 0
	for stage: String in STAGES:
		var result: Dictionary = results.get(stage, {})
		if str(result.get("status", "")) != "ok":
			missing += 1
	return "BOT_OK" if missing == 0 else "BOT_FAIL stages_missing=%d" % missing


# --- The world (static: the test drives them on its own tree) ---


## The company world with its save folder pointed at a temp dir, before it enters the tree, on a new
## company of seed ORDERS_SEED (the same orders every run) whose orders are planned for `players` (0:
## the session's crew, one).
static func open_world(tree: SceneTree, players: int = 0) -> Node3D:
	clean_save_dir()
	var state: Node = tree.root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		state.call(&"new_company", "", ORDERS_SEED)
	var level := (load(SCENE) as PackedScene).instantiate() as CompanyRoot
	level.save_dir = SAVE_DIR
	level.order_crew = players
	tree.root.add_child(level)
	tree.current_scene = level
	await tree.process_frame
	return level


## Polls per frame until the day is OPENING; false after `max_seconds` of wall time.
static func wait_opening(tree: SceneTree, level: Node3D, max_seconds: float) -> bool:
	var start: int = Time.get_ticks_msec()
	while true:
		var cycle: Node = level.get("day_cycle") as Node
		if cycle != null and int(cycle.call(&"phase")) == DAY_CYCLE.Phase.OPENING:
			return true
		if (Time.get_ticks_msec() - start) / 1000.0 >= max_seconds:
			return false
		await tree.process_frame
	return false


## Leaving the world: its exit saves into the temp folder, which is then removed, and the company
## and the mouse go back to how a test leaves them.
static func close_world(tree: SceneTree, level: Node3D) -> void:
	tree.root.remove_child(level)
	level.free()
	clean_save_dir()
	var state: Node = tree.root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		state.call(&"reset")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func clean_save_dir() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR))


# --- The run ---


func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback


func _run() -> void:
	_players = clampi(int(_arg("players", str(DEFAULT_PLAYERS))), 1, 8)
	_hard_seconds = float(_arg("hard", str(DEFAULT_HARD_SECONDS)))
	create_timer(_hard_seconds, true, false, true).timeout.connect(_on_hard_timeout)

	var level: Node3D = await open_world(self, _players)
	if not await wait_opening(self, level, OPENING_WAIT_SECONDS):
		close_world(self, level)
		_end("BOT_FAIL no_opening", 1)
		return

	var ctx: Dictionary = new_context(_players)
	var results: Dictionary = {}
	var times: Dictionary = {}
	for stage: String in STAGES:
		var start: int = Time.get_ticks_msec()
		var result: Dictionary = await run_stage(self, level, stage, ctx)
		times[stage] = Time.get_ticks_msec() - start
		results[stage] = result
		var line: String = stage_line(stage, result)
		print(line if line != "" else stage_ok_line(stage))
		if str(result.get("status", "")) == "fail":
			break

	var money: int = 0
	var state: Node = root.get_node_or_null(^"/root/CompanyState")
	if state != null:
		money = int(state.get("money"))
	var stats: Dictionary = {
		"players": _players, "money": money, "deliveries": int(ctx["deliveries"]),
		"breaks": int(ctx["breaks"]), "assembly_errors": int(ctx["assembly_errors"]),
		"return_bundle_units": int(ctx["return_bundle_units"]), "stage_ms": times,
	}
	close_world(self, level)
	for line: String in summary_lines(stats):
		print(line)
	var final: String = final_line(results)
	_end(final, 0 if final == "BOT_OK" else 1)


func _end(message: String, code: int) -> void:
	if _finished:
		return
	_finished = true
	print(message)
	quit(code)


func _on_hard_timeout() -> void:
	if _finished:
		return
	_finished = true
	print("BOT_TIMEOUT after %.0f s" % _hard_seconds)
	quit(3)


# --- Stages (static: each takes the tree, the opened world and the run's context) ---


## What the stages hand to each other, and the counters of the summary. `players` sizes the orders.
static func new_context(players: int, drive_cap_m: float = 0.0) -> Dictionary:
	return {
		"players": players, "assembly_errors": 0, "breaks": 0, "deliveries": 0, "return_bundle_units": 0,
		# Pallets the bot opened: id -> the Pallet dictionary (state open).
		"opened": {},
		# What the bot holds after receive_pallet: {product, qty}.
		"hands": {},
		"orders": [], "order": {}, "box": null, "box_id": &"", "quality": -1.0,
		# The vehicle dispatch loaded, and the trip it is on (deliver -> return).
		"vehicle_id": &"", "trip": null,
		# Metres the van covered from its parking spot to where it stopped outside the yard.
		"drive_m": 0.0,
		# Autopilot (D-2016.3): 0 drives the whole way along the street graph to the houses of the trip and
		# back (about 85 s each way to Centro); > 0 (a test) ends the way out after that many metres of the
		# street past the yard's leg, short of the first house, and deliver does not drive nor check the
		# distance to the house. The way back is always the whole one, from wherever the van stands.
		"drive_cap_m": drive_cap_m,
		# Where the van stood parked and where it stopped outside the yard, with the way it looked.
		"park_point": Vector2.ZERO, "yard_exit": Vector2.ZERO, "yard_dir": Vector2.UP,
		# What the autopilot reported on each leg: stage -> drive_to()'s result (metres, off_road_max...).
		"autopilot": {},
	}


## Runs one stage by name on the world `level` (a CompanyRoot opened by open_world) and returns its
## result. A coroutine: the stages wait a frame after walking the player. An unknown name fails.
static func run_stage(
	tree: SceneTree, level: Node3D, stage: String, ctx: Dictionary
) -> Dictionary:
	if PENDING.has(stage):
		return _pending(str(PENDING[stage]))
	var missing: String = _missing_part(level)
	if missing != "":
		return _fail(missing)
	match stage:
		"receive_pallet":
			return await _receive_pallet(tree, level as CompanyRoot, ctx)
		"shelve_stock":
			return await _shelve_stock(tree, level as CompanyRoot, ctx)
		"take_orders":
			return await _take_orders(tree, level as CompanyRoot, ctx)
		"pack_boxes":
			return await _pack_boxes(tree, level as CompanyRoot, ctx)
		"dispatch":
			return _dispatch(level as CompanyRoot, ctx)
		"drive":
			return await TRIP.drive(tree, level as CompanyRoot, ctx)
		"deliver":
			return await TRIP.deliver(tree, level as CompanyRoot, ctx, _products())
		"return":
			return await TRIP.come_back(tree, level as CompanyRoot, ctx)
		"close_day":
			return await _close_day(tree, level as CompanyRoot, ctx)
	return _fail("unknown_stage")


## Supplier pallets: the first truck's (DefaultShed.first_order) are in reception when the company
## opens. The bot checks each one is in the stock and drawn at the dock, that a sealed one gives
## nothing, opens them and takes a handful of the first into its hands.
static func _receive_pallet(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var net: CompanyNet = level.net
	_install_stations(level)
	var pallets: Array[Dictionary] = DefaultShed.load_default().first_pallets()
	if pallets.is_empty():
		return _fail("no_delivery")
	for pallet: Dictionary in pallets:
		var id: StringName = pallet["id"]
		if Pallet.units_left(net.inventory, pallet) != int(pallet["qty"]):
			return _fail("pallet_not_in_stock")
		if not level.shed.pallet_nodes.has(String(id)):
			return _fail("pallet_not_drawn")
		if Pallet.take(net.inventory, pallet, 1, &"hands:probe"):
			return _fail("sealed_pallet_gave_units")
		if not Pallet.open(net.inventory, pallet):
			return _fail("pallet_not_opened")
		if Pallet.open(net.inventory, pallet):
			return _fail("pallet_opened_twice")
		(ctx["opened"] as Dictionary)[id] = pallet
	var first: Dictionary = pallets[0]
	var product: StringName = first["product"]
	var qty: int = mini(CompanyTuning.HAND_MAX_UNITS, int(first["qty"]))
	var reason: StringName = await _take_from(
		tree, level, "pallet_%s" % first["id"], product, qty)
	if reason != &"":
		return _fail("take_%s" % reason)
	var hands: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
	if net.inventory.count(product, hands) != qty:
		return _fail("hands_not_filled")
	if net.inventory.count(product, Pallet.location(first["id"])) != int(first["qty"]) - qty:
		return _fail("pallet_not_emptied")
	ctx["hands"] = {"product": product, "qty": qty, "pallet": first["id"]}
	return _ok()


## Carries what the bot holds, and then a handful of every other pallet, to the slot labelled for
## its product. First a store into a slot labelled for another product must be refused.
static func _shelve_stock(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var net: CompanyNet = level.net
	var hands: Dictionary = ctx["hands"]
	if hands.is_empty():
		return _fail("nothing_in_hands")
	var product: StringName = hands["product"]
	var stray: String = _slot_station(level, &"", product)
	if stray != "":
		var refused: StringName = await _store_at(tree, level, stray, product, 1)
		if refused != CompanyNet.REASON_WRONG_PRODUCT:
			return _fail("wrong_slot_%s" % refused)
	var shelved: int = 0
	var opened: Dictionary = ctx["opened"]
	for id: StringName in opened:
		var pallet: Dictionary = opened[id]
		var item: StringName = pallet["product"]
		var qty: int = int(hands["qty"]) if id == hands["pallet"] else mini(
			CompanyTuning.HAND_MAX_UNITS, Pallet.units_left(net.inventory, pallet))
		if id != hands["pallet"]:
			var taken: StringName = await _take_from(tree, level, "pallet_%s" % id, item, qty)
			if taken != &"":
				return _fail("take_%s" % taken)
		var slot: String = _slot_station(level, item)
		if slot == "":
			return _fail("no_labelled_slot")
		var location: StringName = StringName(_station_of(net, slot)["location"])
		var before: int = net.inventory.count(item, location)
		var reason: StringName = await _store_at(tree, level, slot, item, qty)
		if reason != &"":
			return _fail("store_%s" % reason)
		if net.inventory.count(item, location) != before + qty:
			return _fail("slot_not_filled")
		shelved += qty
	var hands_at: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
	if not net.inventory.contents_at(hands_at).is_empty():
		return _fail("hands_not_empty")
	ctx["hands"] = {}
	return _ok() if shelved > 0 else _fail("nothing_shelved")


## The day's orders as the world brings them in (D-0813.1): the host's world planned them at the OPENING
## from the company's seed, and its business tick publishes each one into the book every peer shares
## (CompanyNet.orders.book) once the shed's minute reaches it. The bot moves the clock so the shed's minute
## is the last arrival and waits for the tick (the ones already past due are LATE there by then). Then it
## copies them into CompanyTrips' own book, OPEN as OrderBook.add() leaves them: the book packing and
## dispatch work on, which doesn't become the shared one until marking packed, out and delivered are events.
static func _take_orders(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	if level.trips == null:
		return _fail("no_trips")
	var shared: OrderBook = level.net.orders.book
	if shared.size() + level.net.orders.planned().size() == 0:
		return _fail("no_orders")
	if level.day_cycle.is_frozen():
		return _fail("shed_frozen")
	var lag: float = level.clock.minute_now() - level.day_cycle.shed_minute()
	if not level.clock.start(float(CompanyTuning.ORDER_LAST_ARRIVAL_MIN) + lag):
		return _fail("clock_not_started")
	var start: int = Time.get_ticks_msec()
	while not level.net.orders.planned().is_empty() and Time.get_ticks_msec() - start < ORDER_WAIT_MSEC:
		await tree.process_frame
	if not level.net.orders.planned().is_empty():
		return _fail("orders_not_in")
	var orders: Array[Dictionary] = shared.open_orders()
	if orders.is_empty() or orders.size() != shared.size():
		return _fail("shared_book_size")
	var book: OrderBook = level.trips.book
	for order: Dictionary in orders:
		if not Order.validate(order).is_empty():
			return _fail("bad_order")
		if not book.add(order):
			return _fail("order_not_added")
	if book.size() != orders.size() or book.open_orders().size() != orders.size():
		return _fail("book_size")
	for order: Dictionary in orders:
		var stored: Dictionary = book.get_order(order["id"])
		for key: String in ["id", "customer", "zone", "house_id", "items", "due_min", "pay"]:
			if not stored.has(key) or str(stored[key]) == "":
				return _fail("order_field_%s" % key)
		if book.state_of(order["id"]) != Order.STATE_OPEN:
			return _fail("order_not_open")
		if int(stored["due_min"]) <= int(stored["created_min"]) or int(stored["pay"]) <= 0:
			return _fail("order_numbers")
	ctx["orders"] = orders
	return _ok()


## Packs the first order the shed can fill at a packing table, the way a player would: the units
## from the shelves into the hands, onto the table, into a box of the smallest size that holds
## them, then padding, label, seals and tape. The finished order is PACKED in the book.
static func _pack_boxes(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var net: CompanyNet = level.net
	var products: Dictionary = _products()
	var wallet: Node = net.company as Node
	var opened: Dictionary = ctx["opened"]
	var order: Dictionary = {}
	var size: StringName = &""
	var best: int = 0
	for candidate: Dictionary in ctx["orders"]:
		var fits: StringName = _box_size_for(candidate, products)
		var work: int = _work_of(candidate)
		if fits != &"" and work > best and _in_reach_of_hands(net, candidate, opened):
			order = candidate
			size = fits
			best = work
	if order.is_empty():
		return _fail("no_packable_order")
	var table_uid: StringName = _first_table(level)
	if table_uid == &"":
		return _fail("no_packing_table")
	var table: PackingStation = level.shed.stations[table_uid]
	var order_id: StringName = order["id"]
	var money: int = int(wallet.get("money"))
	if not BoxDispenser.dispense(table, size, wallet):
		return _fail("box_not_dispensed")
	if int(wallet.get("money")) != money - BoxDispenser.cost_of(size):
		return _fail("box_not_charged")
	var in_box: StringName = StringName("box:%s" % order_id)
	for item: Dictionary in order["items"]:
		var product: StringName = item["product"]
		for unit: int in int(item["qty"]):
			var source: Dictionary = _source_of(net, product, opened)
			if source.is_empty():
				return _fail("no_source_%s" % product)
			var reason: StringName = await _take_from(tree, level, source["station"], product, 1)
			if reason != &"":
				return _fail("take_%s" % reason)
			await _go_to_spot(tree, level, level.shed.use_points[table_uid].global_position)
			if not table.stage_product(product):
				return _fail("table_full")
			var hands: StringName = CompanyNet.hands_location(level.multiplayer.get_unique_id())
			if not net.inventory.move(product, 1, hands, in_box):
				return _fail("hands_empty")
			var def: ProductDefinition = products[product]
			var spot: Vector3i = table.box.first_fit(def)
			if spot == PackedBox.NO_SPOT or not table.put_in_box(def, spot):
				return _fail("no_room_in_box")
	return _finish_box(level, ctx, table, order, products)


## The box on the table is padded, labelled, stamped and taped; it leaves the table sealed, its
## units go from box:<order> to package:<id> and the order is PACKED. Counts what is wrong with it.
static func _finish_box(
	level: CompanyRoot, ctx: Dictionary, table: PackingStation, order: Dictionary,
	products: Dictionary
) -> Dictionary:
	var net: CompanyNet = level.net
	var wallet: Node = net.company as Node
	var book: OrderBook = level.trips.book
	var order_id: StringName = order["id"]
	var box: PackedBox = table.box
	table.pad(box.total_cells() - box.grid.size(), wallet)
	if not table.label_for(order, wallet):
		return _fail("label_refused")
	for kind: StringName in BoxSeals.required(order):
		if not table.stamp(kind, wallet):
			return _fail("stamp_%s_refused" % kind)
	var diff: Dictionary = table.content_errors(order)
	var errors: int = BoxSeals.missing(box, order).size()
	for part: String in ["missing", "extra"]:
		for qty: int in (diff[part] as Dictionary).values():
			errors += qty
	if not table.seal(wallet) or not table.is_sealed():
		return _fail("not_sealed")
	var sealed: PackedBox = table.dispatch()
	if sealed == null or table.has_box():
		return _fail("box_not_left_the_table")
	ctx["assembly_errors"] = int(ctx["assembly_errors"]) + errors
	ctx["quality"] = AssemblyQuality.score(sealed, order, products)
	var box_id: StringName = StringName("box_%s" % order_id)
	var in_box: StringName = StringName("box:%s" % order_id)
	var in_package: StringName = StringName("package:%s" % box_id)
	for product: StringName in sealed.contents():
		if not net.inventory.move(product, sealed.contents()[product], in_box, in_package):
			return _fail("units_not_in_package")
	if not net.inventory.contents_at(in_box).is_empty():
		return _fail("units_left_in_box")
	if not book.mark_packed(order_id, box_id) or book.state_of(order_id) != Order.STATE_PACKED:
		return _fail("order_not_packed")
	var package: DeliveryPackage = BoxToPackage.build(sealed, products, order)
	if package == null:
		return _fail("no_package")
	var carries: bool = StringName(package.get_meta(BoxToPackage.META_ORDER_ID)) == order_id
	package.free()
	if not carries:
		return _fail("package_without_order")
	ctx["order"] = order
	ctx["box"] = sealed
	ctx["box_id"] = box_id
	return _ok()


## The sealed box waits in the dispatch zone tied to its order (and is untied if it leaves), the
## dispatch rules clear the van for the order's zone, and loading hands the cargo to CompanyTrips.
static func _dispatch(level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var order: Dictionary = ctx["order"]
	var box: PackedBox = ctx["box"]
	if order.is_empty() or box == null:
		return _fail("nothing_packed")
	var book: OrderBook = level.trips.book
	var order_id: StringName = order["id"]
	var box_id: StringName = ctx["box_id"]
	var area: AABB = _dispatch_area(level)
	if not area.has_surface():
		return _fail("no_dispatch_zone")
	var zone := DispatchZone.new(area)
	var inside: Vector3 = area.get_center()
	var outside: Vector3 = inside + Vector3(area.size.x + 2.0, 0.0, 0.0)
	var none: StringName = DispatchZone.RESULT_NONE
	if zone.update_box(box_id, order_id, inside, false, true, book) != none:
		return _fail("open_box_dispatched")
	if zone.update_box(box_id, order_id, outside, true, true, book) != none:
		return _fail("box_outside_dispatched")
	if zone.update_box(box_id, order_id, inside, true, false, book) != none:
		return _fail("box_in_hands_dispatched")
	var tied: StringName = DispatchZone.RESULT_DISPATCHED
	if zone.update_box(box_id, order_id, inside, true, true, book) != tied:
		return _fail("box_not_dispatched")
	if not zone.is_dispatched(box_id) or zone.order_of(box_id) != order_id:
		return _fail("box_not_tied_to_order")
	var untied: StringName = DispatchZone.RESULT_UNDISPATCHED
	if zone.update_box(box_id, order_id, outside, true, true, book) != untied:
		return _fail("box_not_untied")
	if zone.update_box(box_id, order_id, inside, true, true, book) != tied:
		return _fail("box_not_dispatched_again")
	var van: VehicleDefinition = load(VAN_PATH) as VehicleDefinition
	var state: Node = level.net.company as Node
	var verdict: Dictionary = DispatchRules.check_order(
		order, van, _load_dir(ZONE_DIR), _load_dir(GATE_DIR), state.call(&"gate_owned"),
		state.get(&"opened_gates"))
	if not bool(verdict["ok"]):
		return _fail("rules_%s" % verdict["key"])
	if zone.load_into(level.trips, van.id) != 1 or not zone.boxes().is_empty():
		return _fail("cargo_not_loaded")
	if book.state_of(order_id) != Order.STATE_PACKED or level.trips.trips_out() != 0:
		return _fail("trip_started_early")
	ctx["vehicle_id"] = van.id
	return _ok()


## The day closes the way its clock does: 20:00 comes, OPERATING goes to CLOSING and, with no trip
## out, to SUMMARY. The summary must carry what the day cost and the closed day must save and load.
static func _close_day(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var cycle: DayCycle = level.day_cycle
	var state: Node = level.net.company as Node
	if not level.clock.start(float(CompanyTuning.DAY_END_MIN)):
		return _fail("clock_not_started")
	# The opening's 5 s of real time are skipped; the clock jump above is the same kind of skip.
	cycle.ticks = func() -> int: return Time.get_ticks_msec() + SKIP_OPENING_MSEC
	# The phase it starts from too: after a real drive the day may be OPERATING already.
	var seen: Array[int] = [int(cycle.phase())]
	var came: int = seen[0]
	for _frame: int in PHASE_FRAMES:
		cycle.poll()
		if seen.is_empty() or seen[seen.size() - 1] != int(cycle.phase()):
			seen.append(int(cycle.phase()))
		if cycle.phase() == DayCycle.Phase.SUMMARY:
			break
		await tree.process_frame
	var path: Array[int] = [
		DayCycle.Phase.OPERATING, DayCycle.Phase.CLOSING, DayCycle.Phase.SUMMARY]
	if cycle.phase() != DayCycle.Phase.SUMMARY:
		return _fail("no_summary")
	# The real clock runs while the van drives (90 s an hour): the day may be CLOSING, or closed, when it
	# gets here; the rest of the path must be walked, in order, from the phase it started from.
	if path.find(came) < 0 or seen != path.slice(path.find(came)):
		return _fail("phases_skipped")
	var summary: Dictionary = cycle.summary
	if int(summary.get("day", -1)) != int(state.get("day")):
		return _fail("summary_day")
	var costs: Dictionary = summary.get("cost_by_reason", {})
	if not costs.has("boxes") or not costs.has("packaging"):
		return _fail("summary_without_packing_costs")
	if int(summary.get("closing", -1)) != int(state.get("money")):
		return _fail("summary_money")
	return _save_and_load(level, state, ctx)


## What the closing screen's continue will do (D-0206's hook): the closed day is saved as a finished
## day and read back into a scratch company that must hold the same day, money, ledger and stock.
## The units the save leaves in the return bundle go to ctx (D-0252: with a full crew it may have to
## be one bundle per product).
static func _save_and_load(level: CompanyRoot, state: Node, ctx: Dictionary) -> Dictionary:
	var kept: Inventory = CompanyRoot.stock_for_save(level.net.inventory)
	ctx["return_bundle_units"] = CompanyAsk.units_at(kept, CompanyRoot.SAVED_HANDS_LOCATION)
	state.call(&"store_stock", kept)
	if not CompanySave.save(state, level.save_slot, level.save_dir):
		return _fail("save_failed")
	var scratch: Node = CompanyRoot.COMPANY_STATE.new()
	var loaded: int = CompanySave.load_into(scratch, level.save_slot, level.save_dir)
	var same: bool = (
		loaded == CompanySave.LoadResult.LOADED
		and int(scratch.get("money")) == int(state.get("money"))
		and int(scratch.get("day")) == int(state.get("day"))
		and (scratch.get("ledger") as Array).size() == (state.get("ledger") as Array).size()
		and (scratch.call(&"stock") as Inventory).total_units() == level.net.inventory.total_units()
	)
	scratch.free()
	return _ok() if same else _fail("saved_day_differs")


# --- Helpers of the stages ---


static func _ok() -> Dictionary:
	return {"status": "ok", "reason": ""}


static func _fail(reason: String) -> Dictionary:
	return {"status": "fail", "reason": reason}


static func _pending(tasks: String) -> Dictionary:
	return {"status": "not_implemented", "reason": tasks}


## "" when the world has what the stages drive, else the reason (a client has no trips).
static func _missing_part(level: Node3D) -> String:
	var root := level as CompanyRoot
	if root == null:
		return "no_company_world"
	if root.net == null or not root.net.is_host():
		return "not_host"
	if root.shed == null or root.player == null or root.trips == null:
		return "world_incomplete"
	if root.day_cycle == null or root.clock == null:
		return "no_day"
	return ""


static func _products() -> Dictionary:
	var found: Dictionary = {}
	for file: String in DirAccess.get_files_at(PRODUCTS_DIR):
		if file.ends_with(".tres"):
			var def := load(PRODUCTS_DIR + file) as ProductDefinition
			if def != null:
				found[def.id] = def
	return found


static func _load_dir(dir: String) -> Dictionary:
	var found: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			var res: Resource = load(dir + file)
			found[res.get("id")] = res
	return found


## The smallest box size that holds every unit of the order with PackedBox.first_fit, or &"".
static func _box_size_for(order: Dictionary, products: Dictionary) -> StringName:
	for size: StringName in BoxDispenser.SIZES:
		var box := PackedBox.new(size)
		var fits: bool = true
		for item: Dictionary in order["items"]:
			var def: ProductDefinition = products.get(item["product"])
			for unit: int in int(item["qty"]):
				var spot: Vector3i = box.first_fit(def) if def != null else PackedBox.NO_SPOT
				fits = fits and spot != PackedBox.NO_SPOT and box.place(def, spot)
		if fits:
			return size
	return &""


## How much there is to do in an order: its units plus its requirements (seals). The bot packs the
## one with the most, so padding, label and seals are exercised and not just one unit in a box.
static func _work_of(order: Dictionary) -> int:
	var units: int = 0
	for item: Dictionary in order["items"]:
		units += int(item["qty"])
	return units + (order["requirements"] as Array).size()


## True when every product of the order is on a shelf or an opened pallet, in the quantity asked.
static func _in_reach_of_hands(net: CompanyNet, order: Dictionary, opened: Dictionary) -> bool:
	for item: Dictionary in order["items"]:
		var total: int = 0
		for source: Dictionary in _sources(net, item["product"], opened):
			total += int(source["qty"])
		if total < int(item["qty"]):
			return false
	return true


## Where units of a product can be taken from: slots of the shed's shelves and opened pallets, as
## {station, location, qty}, shelves first, each group in name order.
static func _sources(
	net: CompanyNet, product: StringName, opened: Dictionary
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var by_location: Dictionary = net.inventory.to_dict().get("stock", {}).get(product, {})
	var places: Array = by_location.keys()
	places.sort()
	for place: Variant in places:
		var text: String = String(place)
		var qty: int = int(by_location[place])
		if text.begins_with("shelf:"):
			var station: String = "slot_%s" % text.trim_prefix("shelf:")
			if not _station_of(net, station).is_empty():
				found.append({"station": station, "location": text, "qty": qty})
	for place: Variant in places:
		var text: String = String(place)
		var id: StringName = StringName(text.trim_prefix("pallet:"))
		if text.begins_with("pallet:") and opened.has(id):
			found.append({
				"station": "pallet_%s" % id, "location": text, "qty": int(by_location[place]),
			})
	return found


static func _source_of(net: CompanyNet, product: StringName, opened: Dictionary) -> Dictionary:
	var sources: Array[Dictionary] = _sources(net, product, opened)
	return sources[0] if not sources.is_empty() else {}


## The first packing table of the shed, by name, or &"".
static func _first_table(level: CompanyRoot) -> StringName:
	var uids: Array = level.shed.stations.keys()
	uids.sort()
	return StringName(uids[0]) if not uids.is_empty() else &""


## The floor of the shed's dispatch piece in world coordinates (height 2 m), or an empty AABB.
static func _dispatch_area(level: CompanyRoot) -> AABB:
	for piece: Dictionary in level.shed.pieces:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece["id"])))
		if def == null or def.role != &"dispatch":
			continue
		var rect: Rect2i = piece["rect"]
		var from: Vector3 = level.shed.to_global(level.shed.cell_to_local(Vector2(rect.position)))
		var to: Vector3 = level.shed.to_global(level.shed.cell_to_local(Vector2(rect.end)))
		var low := Vector3(minf(from.x, to.x), 0.0, minf(from.z, to.z))
		return AABB(low, Vector3(absf(to.x - from.x), 2.0, absf(to.z - from.z)))
	return AABB()


## The id of the shelf slot labelled for `product` ("slot_<shelf>_<n>"), or, with `product` empty,
## the first slot labelled for anything but `other`. "" when there is none.
static func _slot_station(
	level: CompanyRoot, product: StringName, other: StringName = &""
) -> String:
	var uids: Array = level.shed.shelves.keys()
	uids.sort()
	for uid: Variant in uids:
		var shelf: Shelf = level.shed.shelves[uid]
		for slot: int in shelf.slot_count():
			var label: StringName = shelf.label_of(slot)
			var wanted: bool = label == product
			if product == &"":
				wanted = label != &"" and label != other
			if wanted:
				return "slot_%s_%d" % [uid, slot]
	return ""


## The bot's lookup for CompanyNet.stations (CompanyRoot sets none yet): `pallet_<id>` for a pallet
## drawn in reception, `slot_<shelf uid>_<n>` for a slot of a shelf (it takes its label's product).
## The spot is where the shed draws it: the pallet itself, the shelf's use point.
static func _station(shed: CompanyShed, id: StringName) -> Dictionary:
	var text: String = String(id)
	if text.begins_with("pallet_"):
		var pallet_id: String = text.trim_prefix("pallet_")
		var node: Node3D = shed.pallet_nodes.get(pallet_id) as Node3D
		if node == null:
			return {}
		return {"location": Pallet.location(StringName(pallet_id)), "spot": node.global_position}
	if not text.begins_with("slot_"):
		return {}
	var body: String = text.trim_prefix("slot_")
	var cut: int = body.rfind("_")
	if cut < 0 or not body.substr(cut + 1).is_valid_int():
		return {}
	var uid: StringName = StringName(body.left(cut))
	var slot: int = int(body.substr(cut + 1))
	var shelf: Shelf = shed.shelves.get(uid) as Shelf
	var point: Node3D = shed.use_points.get(uid) as Node3D
	if shelf == null or point == null or slot < 0 or slot >= shelf.slot_count():
		return {}
	var station: Dictionary = {
		"location": shelf.location(slot), "spot": point.global_position,
		"capacity": CompanyTuning.SHELF_SLOT_CAPACITY,
	}
	if shelf.label_of(slot) != &"":
		station["accepts"] = shelf.label_of(slot)
	return station


static func _install_stations(level: CompanyRoot) -> void:
	var shed: CompanyShed = level.shed
	level.net.stations = func(id: StringName) -> Dictionary: return _station(shed, id)


static func _station_of(net: CompanyNet, id: String) -> Dictionary:
	if not net.stations.is_valid():
		return {}
	return net.stations.call(StringName(id))


## The player stands next to a spot, as one walking up to it would.
static func _go_to_spot(tree: SceneTree, level: CompanyRoot, spot: Vector3) -> void:
	level.player.global_position = spot + STAND_OFFSET
	await tree.process_frame


## units_take of `qty` at `station`, standing at it. &"" when it went through, else the reason.
static func _take_from(
	tree: SceneTree, level: CompanyRoot, station: String, product: StringName, qty: int
) -> StringName:
	return await _units_request(tree, level, &"units_take", station, product, qty)


static func _store_at(
	tree: SceneTree, level: CompanyRoot, station: String, product: StringName, qty: int
) -> StringName:
	return await _units_request(tree, level, &"units_store", station, product, qty)


static func _units_request(
	tree: SceneTree, level: CompanyRoot, kind: StringName, station: String, product: StringName,
	qty: int
) -> StringName:
	var found: Dictionary = _station_of(level.net, station)
	if found.is_empty():
		return CompanyNet.REASON_NO_STATION
	await _go_to_spot(tree, level, found["spot"])
	return _ask(level.net, kind, {"station": StringName(station), "product": product, "qty": qty})


## A CompanyNet request as the host's own player makes it (solo: it goes through at once). &"" when
## an event came out of it, else the host's refusal; &"dropped" when nothing happened and nobody
## said so.
static func _ask(net: CompanyNet, kind: StringName, data: Dictionary) -> StringName:
	var refusals: Array[StringName] = []
	var on_refused: Callable = func(_rid: int, reason: StringName) -> void: refusals.append(reason)
	net.request_rejected.connect(on_refused)
	var before: int = net.seq
	var rid: int = net.request(kind, data)
	net.request_rejected.disconnect(on_refused)
	if rid == 0:
		return &"no_request"
	if not refusals.is_empty():
		return refusals[0]
	return &"" if net.seq > before else &"dropped"
