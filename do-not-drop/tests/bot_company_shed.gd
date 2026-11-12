extends RefCounted
## The shed stages of the company-day bot (tests/bot_company_day.gd, D-2016.4): receive_pallet, shelve_stock,
## take_orders, pack_boxes and dispatch, and the work of whoever stays in the shed while the van is out. Not a test:
## preloaded. Each stage answers {"status": "ok"|"fail", "reason"} and leaves in `ctx` what the next one needs.
##
## Everything the game can do, the bot does through the game: CompanyNet requests at the stations the world itself
## resolves (CompanyShed.station_for: a shelf slot is ShelfPicking.station_id(), a packing table is table:<uid>), a
## box carried in a player's hands (the package's own pick-up point, Player's drop) and the dispatch board (the
## shed's DispatchStation, DispatchBoardPanel's rows and Load). What the game cannot do yet is a shortcut the stage
## notes with CREW.stub(): it prints BOT_STUB and blocks BOT_OK (bot_company_crew.gd lists them with their tasks).
##   receive_pallet  the day's supplier pallets are in reception (in the stock and drawn) and a sealed one gives
##                   nothing. Stub pallet_unload: the bot opens them and takes the first handful itself
##   shelve_stock    a slot labelled for another product refuses the handful (wrong_product); then every unit of
##                   every pallet goes, a handful at a time and the actors taking turns, to the slot labelled for it
##                   (units_store at the game's own station; the cold ones to the fridge, before they spoil).
##                   Taking them off the pallet is still the stub
##   take_orders     the world plans the day at its OPENING and brings each order in as the shed's minute reaches
##                   it (D-0813.1). The bot jumps the clock to the arrival of the order that completes ctx.boxes_goal
##                   (BOT_SKIP) and keeps the first that many it can pack, oldest first: the shared book's own
##                   orders, copied nowhere
##   pack_boxes      one box per order, the actors taking turns, each at a table: box_start, the units from the
##                   shelves (units_take) into the box one by one (box_place), box_fill until no cell is free,
##                   box_label, the seals the order asks for (box_stamp) and box_tape; a table out of a supply is
##                   restocked (box_restock). The taped box is a DeliveryPackage under World/Packages carrying its
##                   order, its units are the package's in the stock. Stubs table_use (nothing in the game sends
##                   those requests) and order_claim (the bot says which order a table packs)
##   dispatch        each packer carries its box from the table to the dispatch zone and sets it down; the host's
##                   player uses the dispatch station, picks every box on the board and presses Load: the boxes
##                   go on the van's rack, the cargo is staged and the host's trip book learns the orders
## stay_behind(): with two players, while the first is out with the van the second packs the orders that keep
## coming in and carries each box to the zone, at a person's pace (CREW.STEP_SECONDS); stop_staying() ends it.

const CREW := preload("res://tests/bot_company_crew.gd")
const PRODUCTS_DIR: String = "res://data/products/"
## How long (real msec) the business tick may take to bring the day's orders in before take_orders fails: it runs
## every 250 ms.
const ORDER_WAIT_MSEC: int = 3000
## The dispatch zone as the bot fills it: a grid of this many spots, north row first.
const ZONE_COLUMNS: int = 3
const ZONE_ROWS: int = 2
## Physics frames a box set down may take to lie still inside the zone, and how many in a row it has to.
const REST_FRAMES: int = 300
const CALM_FRAMES: int = 12
## Frames the dispatch board may take to open.
const BOARD_FRAMES: int = 30
## box_fill requests one box may need (each pads what the table's padding allows; then it is restocked).
const FILL_ROUNDS: int = 4
## A player's origin stands this high over the floor (CompanyRoot.SPAWN).
const PLAYER_HEIGHT: float = 1.0


# --- Stages ---


## The supplier's pallets of the first truck (DefaultShed.first_pallets) wait in reception when the company opens:
## each one is in the stock and drawn at the dock, and sealed it gives nothing. Then the stub: the bot opens them
## and takes a handful of the first into the host's hands.
static func receive_pallet(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var net: CompanyNet = level.net
	var pallets: Array[Dictionary] = DefaultShed.load_default().first_pallets()
	if pallets.is_empty():
		return _fail("no_delivery")
	for pallet: Dictionary in pallets:
		var id: StringName = pallet["id"]
		var drawn: Node3D = level.shed.pallet_nodes.get(String(id)) as Node3D
		if Pallet.units_left(net.inventory, pallet) != int(pallet["qty"]):
			return _fail("pallet_not_in_stock")
		if drawn == null:
			return _fail("pallet_not_drawn")
		if Pallet.take(net.inventory, pallet, 1, &"hands:probe"):
			return _fail("sealed_pallet_gave_units")
		if not Pallet.open(net.inventory, pallet) or Pallet.open(net.inventory, pallet):
			return _fail("pallet_not_opened_once")
		(ctx["opened"] as Dictionary)[id] = pallet
		(ctx["pallet_spots"] as Dictionary)[id] = drawn.global_position
	CREW.stub(ctx, &"pallet_unload")
	var first: Dictionary = pallets[0]
	var actor: Dictionary = CREW.host(ctx)
	var qty: int = await _unload(tree, level, ctx, actor, first)
	if qty <= 0:
		return _fail("pallet_gave_nothing")
	if net.inventory.count(first["product"], Pallet.location(first["id"])) != int(first["qty"]) - qty:
		return _fail("pallet_not_emptied")
	ctx["hands"] = {"product": first["product"], "qty": qty, "pallet": first["id"]}
	return _ok()


## What the host holds goes to the slot labelled for it, after a slot labelled for another product refused it; then
## every pallet is emptied onto its slot, a handful at a time, the actors taking turns.
static func shelve_stock(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var net: CompanyNet = level.net
	var hands: Dictionary = ctx["hands"]
	if hands.is_empty():
		return _fail("nothing_in_hands")
	var host: Dictionary = CREW.host(ctx)
	var held: StringName = hands["product"]
	var stray: Dictionary = _slot_for(level, &"", held)
	if not stray.is_empty():
		var refused: StringName = await _units(tree, level, host, &"units_store", stray, held, 1)
		if refused != CompanyNet.REASON_WRONG_PRODUCT:
			return _fail("wrong_slot_%s" % refused)
	var why: String = await _shelve(tree, level, host, held, int(hands["qty"]))
	if why != "":
		return _fail(why)
	ctx["hands"] = {}
	var turn: int = 1
	var opened: Dictionary = ctx["opened"]
	for id: StringName in opened:
		var pallet: Dictionary = opened[id]
		while Pallet.units_left(net.inventory, pallet) > 0:
			var actor: Dictionary = CREW.actor_for(ctx, turn)
			turn += 1
			var qty: int = await _unload(tree, level, ctx, actor, pallet)
			if qty <= 0:
				return _fail("pallet_gave_nothing")
			why = await _shelve(tree, level, actor, pallet["product"], qty)
			if why != "":
				return _fail(why)
	for actor: Dictionary in ctx["crew"]:
		if not net.inventory.contents_at(CREW.hands_of(actor)).is_empty():
			return _fail("hands_not_empty")
	return _ok()


## The day's orders as the world brings them in (D-0813.1): planned at the OPENING from the company's seed and
## published by the host's business tick into the book every peer shares (CompanyNet.orders.book) once the shed's
## minute reaches each one. The bot moves the clock to the arrival of the order that completes ctx.boxes_goal and
## waits for the tick; the ones past due by then are LATE there. It keeps the first boxes_goal it can pack.
static func take_orders(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	if level.trips == null:
		return _fail("no_trips")
	var orders: CompanyOrdersNet = level.net.orders
	if orders.book.size() + orders.planned().size() == 0:
		return _fail("no_orders")
	if level.day_cycle.is_frozen():
		return _fail("shed_frozen")
	var goal: int = int(ctx["boxes_goal"])
	var planned: Array[Dictionary] = orders.planned()
	var missing: int = goal - orders.book.open_orders().size()
	if missing > 0 and not planned.is_empty():
		var target: int = int(planned[mini(missing, planned.size()) - 1]["created_min"])
		var shed_now: float = level.day_cycle.shed_minute()
		if float(target) > shed_now:
			var lag: float = level.clock.minute_now() - shed_now
			if not level.clock.start(float(target) + lag):
				return _fail("clock_not_started")
			CREW.skip(ctx, "take_orders", shed_now, float(target))
		var start: int = Time.get_ticks_msec()
		while _arrivals_due(orders, target) and Time.get_ticks_msec() - start < ORDER_WAIT_MSEC:
			await tree.process_frame
		if _arrivals_due(orders, target):
			return _fail("orders_not_in")
	var chosen: Array[Dictionary] = []
	for order: Dictionary in orders.book.open_orders():
		if chosen.size() < goal and _can_pack(level, ctx, order):
			chosen.append(order)
	if chosen.size() < goal:
		return _fail("only_%d_orders_to_pack" % chosen.size())
	for order: Dictionary in chosen:
		var problem: String = _order_problem(order)
		if problem != "":
			return _fail(problem)
		(ctx["taken"] as Dictionary)[order["id"]] = true
	ctx["orders"] = chosen
	return _ok()


## One box per order taken, the actors taking turns, each at its table (pack_order()).
static func pack_boxes(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var orders: Array = ctx["orders"]
	if orders.is_empty():
		return _fail("no_orders_taken")
	var tables: Array = _tables(level)
	if tables.is_empty():
		return _fail("no_packing_table")
	var crew: Array = ctx["crew"]
	for index: int in orders.size():
		var seat: int = index % crew.size()
		var done: Dictionary = await pack_order(
			tree, level, ctx, crew[seat], tables[seat % tables.size()], orders[index], 0.0)
		if done["reason"] != "":
			return _fail("%s_%s" % [orders[index]["id"], done["reason"]])
		ctx["assembly_errors"] = int(ctx["assembly_errors"]) + int(done["errors"])
		(ctx["packed"] as Array).append(done)
	return _ok()


## The packed boxes go from the tables to the dispatch zone in their packers' hands, the board lists them and the
## host's player loads them all on the van: they are on its rack, the cargo is staged, no trip has started.
static func dispatch(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	var packed: Array = ctx["packed"]
	if packed.is_empty():
		return _fail("nothing_packed")
	var board := level.get_node_or_null(^"Dispatch") as CompanyDispatch
	var area: AABB = CompanyDispatch.area_of(level.shed)
	if board == null or level.shed.dispatch_stations.is_empty() or not area.has_surface():
		return _fail("no_dispatch_zone")
	if not board.scan().boxes().is_empty():
		return _fail("box_dispatched_from_the_table")
	for entry: Dictionary in packed:
		var packer: Dictionary = _actor_of(ctx, int(entry["peer"]))
		var why: String = await carry_to_zone(tree, level, ctx, packer, entry["box_id"], 0.0)
		if why != "":
			return _fail("%s_%s" % [entry["box_id"], why])
	var zone: DispatchZone = board.scan()
	for entry: Dictionary in packed:
		if not zone.is_dispatched(entry["box_id"]) or zone.order_of(entry["box_id"]) != entry["order_id"]:
			return _fail("box_not_tied_to_order")
	var body: Node3D = board.available_vehicle()
	if body == null:
		return _fail("no_vehicle_in_the_yard")
	var loaded: String = await _load_on_board(tree, level, ctx, board)
	if loaded != "":
		return _fail(loaded)
	var vehicle_id := StringName(body.name)
	if not level.trips.has_cargo(vehicle_id) or level.trips.trips_out() != 0:
		return _fail("cargo_not_staged")
	for entry: Dictionary in packed:
		var package: DeliveryPackage = DispatchRack.package_of(level.packages, entry["box_id"])
		if package == null or not package.is_loaded or not DispatchRack.rides(body, package):
			return _fail("box_not_on_the_rack")
		var book: OrderBook = level.trips.book
		if book.state_of(entry["order_id"]) != Order.STATE_PACKED or book.box_of(entry["order_id"]) != entry["box_id"]:
			return _fail("order_not_packed")
	ctx["vehicle_id"] = vehicle_id
	ctx["zone_used"] = 0
	return _ok()


# --- A box, start to end ---


## `actor` packs `order` at the table `table` through CompanyNet (see the header) and the taped box becomes a
## package of the world. With `pace` > 0 it waits that many seconds between two things done with the hands and
## gives up ("stopped") once ctx.worker_on is off. {"reason": "" or why not, "order_id", "box_id", "peer", "table",
## "errors": what is wrong with the box, "quality": the package's}.
static func pack_order(
	tree: SceneTree, level: CompanyRoot, ctx: Dictionary, actor: Dictionary, table: StringName, order: Dictionary,
	pace: float
) -> Dictionary:
	var net: CompanyNet = level.net
	var products: Dictionary = products_of(ctx)
	var station := StringName(CompanyTableNet.TABLE_PREFIX + String(table))
	var seat: Dictionary = level.shed.station_for(station)
	var size: StringName = box_size_for(order, products)
	if seat.is_empty() or size == &"":
		return _why("no_table_station" if seat.is_empty() else "no_box_fits")
	CREW.stub(ctx, &"table_use")
	await CREW.go_to(tree, actor, seat["spot"])
	var money: int = int(net.company.get("money"))
	var reason: StringName = _table_ask(level, actor, station, table, CompanyTableNet.START, {"size": size},
		StationSupplies.box_kind(size))
	if reason != &"":
		return _why("box_start_%s" % reason)
	if not net.table.has_box(table) or int(net.company.get("money")) != money - int(CompanyTuning.BOX_COST[size]):
		return _why("box_not_started")
	CREW.stub(ctx, &"order_claim")
	_claim(level, ctx, table, order["id"])
	for item: Dictionary in order["items"]:
		var left: int = int(item["qty"])
		while left > 0:
			var slot: Dictionary = _slot_for(level, item["product"], &"", true)
			if slot.is_empty():
				return _why("no_stock_%s" % item["product"])
			var shelf: Shelf = level.shed.shelves[slot["uid"]]
			var qty: int = mini(mini(left, CompanyTuning.HAND_MAX_UNITS), shelf.count(net.inventory, int(slot["slot"])))
			reason = await _units(tree, level, actor, &"units_take", slot, item["product"], qty)
			if reason != &"":
				return _why("take_%s" % reason)
			if not await _pause(tree, level, ctx, pace):
				return _why("stopped")
			await CREW.go_to(tree, actor, seat["spot"])
			for _unit: int in qty:
				reason = _place(level, actor, station, table, products[item["product"]])
				if reason != &"":
					return _why("place_%s" % reason)
			left -= qty
			if not await _pause(tree, level, ctx, pace):
				return _why("stopped")
	return _finish_box(level, ctx, actor, station, table, order)


## The open box on `table` is padded until no cell is free, labelled, stamped with what the order asks for and
## taped: it leaves the table as a package of the world carrying its order, its units the package's in the stock.
static func _finish_box(
	level: CompanyRoot, ctx: Dictionary, actor: Dictionary, station: StringName, table: StringName, order: Dictionary
) -> Dictionary:
	var net: CompanyNet = level.net
	var box: PackedBox = net.table.station_of(table).box
	var reason: StringName = &""
	for _round: int in FILL_ROUNDS:
		var free: int = box.total_cells() - box.grid.size()
		if free <= 0:
			break
		reason = _table_ask(level, actor, station, table, CompanyTableNet.FILL,
			{"cells": mini(free, CompanyTableNet.MAX_FILL)}, StationSupplies.FILL)
		if reason != &"":
			return _why("fill_%s" % reason)
	if box.total_cells() - box.grid.size() > 0:
		return _why("box_not_padded")
	reason = _table_ask(level, actor, station, table, CompanyTableNet.LABEL, {})
	if reason != &"":
		return _why("label_%s" % reason)
	for kind: StringName in BoxSeals.required(order):
		reason = _table_ask(level, actor, station, table, CompanyTableNet.STAMP, {"stamp": kind})
		if reason != &"":
			return _why("stamp_%s_%s" % [kind, reason])
	var errors: int = BoxSeals.missing(box, order).size() + _content_errors(box, order)
	var wanted: Dictionary = box.contents()
	var box_id: StringName = net.table.box_of(table)
	reason = _table_ask(level, actor, station, table, CompanyTableNet.TAPE, {}, StationSupplies.TAPE)
	(ctx["table_orders"] as Dictionary).erase(table)
	if reason != &"":
		return _why("tape_%s" % reason)
	var package: DeliveryPackage = DispatchRack.package_of(level.packages, box_id)
	if net.table.has_box(table) or package == null:
		return _why("box_not_a_package")
	if StringName(package.get_meta(BoxToPackage.META_ORDER_ID, &"")) != order["id"]:
		return _why("package_without_order")
	if net.inventory.contents_at(CompanyTableNet.package_location(box_id)) != wanted:
		return _why("units_not_in_package")
	var plan: Dictionary = package.get_meta(BoxToPackage.META_TRAP_PLAN, {})
	return {
		"reason": "", "order_id": order["id"], "box_id": box_id, "peer": int(actor["peer"]), "table": table,
		"errors": errors, "quality": float(plan.get("quality", -1.0)),
	}


## `actor` takes the package of `box_id` in its hands where it lies (its own pick-up point), carries it to the
## next free spot of the dispatch zone and sets it down (Player's drop: just ahead of where it stands), then waits
## for it to lie still inside the zone. "" when it does, else why not ("stopped" as pack_order()).
static func carry_to_zone(
	tree: SceneTree, level: CompanyRoot, ctx: Dictionary, actor: Dictionary, box_id: StringName, pace: float
) -> String:
	var package: DeliveryPackage = DispatchRack.package_of(level.packages, box_id)
	var player := actor["player"] as Player
	if package == null:
		return "no_package"
	await CREW.go_to(tree, actor, package.global_position)
	var pickup := package.get_node_or_null(^"InteractionArea") as Interactable
	if pickup == null or not CREW.in_reach(actor, package.global_position):
		return "box_out_of_reach"
	pickup.interact(player)
	if player.carried_package != package or not package.is_held:
		return "box_not_picked_up"
	if not await _pause(tree, level, ctx, pace):
		return "stopped"
	var area: AABB = CompanyDispatch.area_of(level.shed)
	var spot: Vector3 = zone_spot(area, int(ctx["zone_used"]))
	ctx["zone_used"] = int(ctx["zone_used"]) + 1
	# Player sets a box down BODY_RADIUS + DROP_GAP + its half depth ahead: it stands that far south, looking north.
	var back: float = Player.BODY_RADIUS + Player.DROP_GAP + package.get_half_extents().z
	CREW.place(actor, Vector3(spot.x, spot.y + PLAYER_HEIGHT, spot.z + back), 0.0)
	await tree.physics_frame
	CREW.drop_box(actor)
	var calm: int = 0
	for _frame: int in REST_FRAMES:
		await tree.physics_frame
		var still: bool = not package.is_held and package.linear_velocity.length() < CompanyDispatch.REST_SPEED
		calm = calm + 1 if still and area.has_point(package.global_position) else 0
		if calm >= CALM_FRAMES:
			break
	if is_instance_valid(player.carried_package):
		return "box_not_set_down"
	return "" if calm >= CALM_FRAMES else "box_not_in_zone"


# --- Whoever stays in the shed ---


## With two players, while the first is out with the van: the second packs the orders that keep coming in, oldest
## first, at the second table, and carries each box to the dispatch zone, at a person's pace. It runs beside the
## driving stages (call it without await) until stop_staying(); what it packed goes to ctx.extra and a job that
## went wrong to ctx.worker_failure.
static func stay_behind(tree: SceneTree, level: CompanyRoot, ctx: Dictionary) -> void:
	var crew: Array = ctx["crew"]
	var tables: Array = _tables(level)
	if crew.size() < 2 or tables.is_empty() or bool(ctx["worker_on"]):
		return
	ctx["worker_on"] = true
	while await _pause(tree, level, ctx, CREW.STEP_SECONDS):
		var order: Dictionary = _next_order(level, ctx)
		if order.is_empty():
			_note_wait(level, ctx)
			continue
		(ctx["taken"] as Dictionary)[order["id"]] = true
		var done: Dictionary = await pack_order(
			tree, level, ctx, crew[1], tables[1 % tables.size()], order, CREW.STEP_SECONDS)
		var why: String = done["reason"]
		if why == "":
			(ctx["extra"] as Array).append(done)
			ctx["assembly_errors"] = int(ctx["assembly_errors"]) + int(done["errors"])
			why = await carry_to_zone(tree, level, ctx, crew[1], done["box_id"], CREW.STEP_SECONDS)
		if why == "stopped":
			return
		if why != "":
			ctx["worker_failure"] = "%s_%s" % [order["id"], why]
			ctx["worker_on"] = false
			return


## Whoever stays found nothing to pack this step: why, counted in ctx.stay_waits (the bot prints it as BOT_INFO, so a
## long idle stretch says whether the orders or the stock ran out). no_order: every order of the shared book that
## waits for a box is taken; no_stock: one waits, but the shelves do not hold what it asks for (or no box fits it).
static func _note_wait(level: CompanyRoot, ctx: Dictionary) -> void:
	var why: String = "no_order"
	for order: Dictionary in level.net.orders.book.open_orders():
		if not (ctx["taken"] as Dictionary).has(order["id"]):
			why = "no_stock"
			break
	var waits: Dictionary = ctx["stay_waits"]
	waits[why] = int(waits.get(why, 0)) + 1


## The van is back: whoever stayed stops where it is. "" when its work went well, else what went wrong.
static func stop_staying(ctx: Dictionary) -> String:
	ctx["worker_on"] = false
	return str(ctx["worker_failure"])


# --- Helpers ---


## ProductDefinition by id of the whole catalog, read once per run.
static func products_of(ctx: Dictionary) -> Dictionary:
	var found: Dictionary = ctx["products"]
	if found.is_empty():
		for file: String in DirAccess.get_files_at(PRODUCTS_DIR):
			var def := load(PRODUCTS_DIR + file) as ProductDefinition if file.ends_with(".tres") else null
			if def != null:
				found[def.id] = def
	return found


## The smallest box size that holds every unit of the order with PackedBox.first_fit, or &"".
static func box_size_for(order: Dictionary, products: Dictionary) -> StringName:
	for size: StringName in CompanyTuning.BOX_CELLS:
		var box := PackedBox.new(size)
		var fits: bool = true
		for item: Dictionary in order["items"]:
			var def: ProductDefinition = products.get(item["product"])
			for _unit: int in int(item["qty"]):
				var spot: Vector3i = box.first_fit(def) if def != null else PackedBox.NO_SPOT
				fits = fits and spot != PackedBox.NO_SPOT and box.place(def, spot)
		if fits:
			return size
	return &""


## Spot number `index` of the dispatch zone's floor `area` (they repeat past the last): the middle of a cell of
## its ZONE_COLUMNS x ZONE_ROWS grid, on the floor, the north row first.
static func zone_spot(area: AABB, index: int) -> Vector3:
	var cell: int = posmod(index, ZONE_COLUMNS * ZONE_ROWS)
	var column: int = cell % ZONE_COLUMNS
	var row: int = cell / ZONE_COLUMNS
	return Vector3(
		area.position.x + area.size.x * (float(column) + 0.5) / float(ZONE_COLUMNS),
		area.position.y + CompanyDispatch.AREA_SINK_M,
		area.position.z + area.size.z * (float(row) + 0.5) / float(ZONE_ROWS))


static func _ok() -> Dictionary:
	return {"status": "ok", "reason": ""}


static func _fail(reason: String) -> Dictionary:
	return {"status": "fail", "reason": reason}


## pack_order()'s answer when it could not: only the reason.
static func _why(reason: String) -> Dictionary:
	return {"reason": reason}


## Waits `pace` seconds (nothing at 0). False when the paced work has to stop: the world is gone or ctx.worker_on
## is off.
static func _pause(tree: SceneTree, level: CompanyRoot, ctx: Dictionary, pace: float) -> bool:
	if pace <= 0.0:
		return true
	await tree.create_timer(pace).timeout
	return is_instance_valid(level) and level.is_inside_tree() and bool(ctx["worker_on"])


static func _actor_of(ctx: Dictionary, peer: int) -> Dictionary:
	for actor: Dictionary in ctx["crew"]:
		if int(actor["peer"]) == peer:
			return actor
	return CREW.host(ctx)


## The packing tables of the shed, by name.
static func _tables(level: CompanyRoot) -> Array:
	var uids: Array = level.shed.stations.keys()
	uids.sort()
	return uids


## The stub pallet_unload: `actor` stands at the pallet and a handful of its units is in its hands. How many (0
## when the pallet gave none).
static func _unload(tree: SceneTree, level: CompanyRoot, ctx: Dictionary, actor: Dictionary, pallet: Dictionary) -> int:
	var net: CompanyNet = level.net
	var qty: int = mini(CompanyTuning.HAND_MAX_UNITS, Pallet.units_left(net.inventory, pallet))
	await CREW.go_to(tree, actor, (ctx["pallet_spots"] as Dictionary)[pallet["id"]])
	if qty <= 0 or not Pallet.take(net.inventory, pallet, qty, CREW.hands_of(actor)):
		return 0
	return qty


## `actor` stores the `qty` units of `product` it holds in the slot labelled for it. "" when they are there.
static func _shelve(tree: SceneTree, level: CompanyRoot, actor: Dictionary, product: StringName, qty: int) -> String:
	var slot: Dictionary = _slot_for(level, product)
	if slot.is_empty():
		return "no_labelled_slot_%s" % product
	var shelf: Shelf = level.shed.shelves[slot["uid"]]
	var before: int = shelf.count(level.net.inventory, int(slot["slot"]))
	var reason: StringName = await _units(tree, level, actor, &"units_store", slot, product, qty)
	if reason != &"":
		return "store_%s" % reason
	return "" if shelf.count(level.net.inventory, int(slot["slot"])) == before + qty else "slot_not_filled"


## The shelf slot labelled for `product` as {uid, slot} (with `stocked`, one that holds units), or, with `product`
## empty, the first slot labelled for anything but `other`. {} when there is none.
static func _slot_for(
	level: CompanyRoot, product: StringName, other: StringName = &"", stocked: bool = false
) -> Dictionary:
	var uids: Array = level.shed.shelves.keys()
	uids.sort()
	for uid: Variant in uids:
		var shelf: Shelf = level.shed.shelves[uid]
		for slot: int in shelf.slot_count():
			var label: StringName = shelf.label_of(slot)
			var wanted: bool = label != &"" and (label == product if product != &"" else label != other)
			if wanted and (not stocked or shelf.count(level.net.inventory, slot) > 0):
				return {"uid": StringName(uid), "slot": slot}
	return {}


## A units_take or units_store of `actor` at the shelf slot `where` ({uid, slot}), standing at it: the station is
## the game's own (ShelfPicking.station_id, resolved by CompanyShed.station_for). &"" when it went through.
static func _units(
	tree: SceneTree, level: CompanyRoot, actor: Dictionary, kind: StringName, where: Dictionary, product: StringName,
	qty: int
) -> StringName:
	var station: StringName = ShelfPicking.station_id(where["uid"], int(where["slot"]))
	var found: Dictionary = level.shed.station_for(station)
	if found.is_empty():
		return CompanyNet.REASON_NO_STATION
	await CREW.go_to(tree, actor, found["spot"])
	return CREW.ask(level, actor, kind, {"station": station, "product": product, "qty": qty})


## A box_* request of `actor` at `station` (the table `table`). When it uses up a `supply` the table has run out
## of, the table is restocked first (box_restock, as whoever packs would). &"" when it went through.
static func _table_ask(
	level: CompanyRoot, actor: Dictionary, station: StringName, table: StringName, kind: StringName, data: Dictionary,
	supply: StringName = &""
) -> StringName:
	var desk: Variant = level.net.table.station_of(table)
	if supply != &"" and desk != null and not desk.supplies.has(supply):
		var restocked: StringName = CREW.ask(
			level, actor, CompanyTableNet.RESTOCK, {"station": station, "supply": supply})
		if restocked != &"":
			return StringName("restock_%s" % restocked)
	return CREW.ask(level, actor, kind, data.merged({"station": station}, true))


## One unit of `def` from `actor`'s hands into the first cell of the box on `table` where it fits.
static func _place(
	level: CompanyRoot, actor: Dictionary, station: StringName, table: StringName, def: ProductDefinition
) -> StringName:
	var cell: Vector3i = PackedBox.from_dict(level.net.table.station_of(table).box.to_dict()).first_fit(def)
	if cell == PackedBox.NO_SPOT:
		return &"no_room_in_box"
	return CREW.ask(level, actor, CompanyTableNet.PLACE,
		{"station": station, "product": def.id, "cx": cell.x, "cy": cell.y, "cz": cell.z, "rot": 0})


## The stub order_claim: `table` packs the order `order_id` of the shared book from now on (the game's own hook,
## CompanyTableNet.order_of, set once per world to read ctx.table_orders).
static func _claim(level: CompanyRoot, ctx: Dictionary, table: StringName, order_id: StringName) -> void:
	var by_table: Dictionary = ctx["table_orders"]
	by_table[table] = level.net.orders.book.get_order(order_id)
	level.net.table.order_of = func(asked: StringName) -> Dictionary: return by_table.get(asked, {})


## Units missing from or left over in `box` against `order`'s lines.
static func _content_errors(box: PackedBox, order: Dictionary) -> int:
	var inside: Dictionary = box.contents()
	var wrong: int = 0
	var asked: Dictionary = {}
	for item: Dictionary in order["items"]:
		asked[item["product"]] = int(item["qty"])
		wrong += absi(int(item["qty"]) - int(inside.get(item["product"], 0)))
	for product: StringName in inside:
		wrong += 0 if asked.has(product) else int(inside[product])
	return wrong


## True while an order planned for `target` (a minute) or earlier has not come in yet.
static func _arrivals_due(orders: CompanyOrdersNet, target: int) -> bool:
	var planned: Array[Dictionary] = orders.planned()
	return not planned.is_empty() and int(planned[0]["created_min"]) <= target


## Whether the bot can pack `order` now: nobody took it, it waits for a box (open or late), a box size holds it
## and every product it asks for is on a labelled shelf slot in the quantity asked.
static func _can_pack(level: CompanyRoot, ctx: Dictionary, order: Dictionary) -> bool:
	if (ctx["taken"] as Dictionary).has(order["id"]):
		return false
	if order["state"] != Order.STATE_OPEN and order["state"] != Order.STATE_LATE:
		return false
	if box_size_for(order, products_of(ctx)) == &"":
		return false
	for item: Dictionary in order["items"]:
		var shelved: int = 0
		for shelf: Shelf in level.shed.shelves.values():
			shelved += shelf.total_of(level.net.inventory, item["product"])
		if shelved < int(item["qty"]):
			return false
	return true


## The oldest order of the shared book the bot can still pack, {} when there is none.
static func _next_order(level: CompanyRoot, ctx: Dictionary) -> Dictionary:
	for order: Dictionary in level.net.orders.book.open_orders():
		if _can_pack(level, ctx, order):
			return order
	return {}


## "" for an order as the day's plan writes them, else what is wrong with it.
static func _order_problem(order: Dictionary) -> String:
	if not Order.validate(order).is_empty():
		return "bad_order"
	for key: String in ["id", "customer", "zone", "house_id", "items", "due_min", "pay"]:
		if not order.has(key) or str(order[key]) == "":
			return "order_field_%s" % key
	if int(order["due_min"]) <= int(order["created_min"]) or int(order["pay"]) <= 0:
		return "order_numbers"
	return ""


## The host's player uses the dispatch station, picks every packed box on the board and presses Load. "" when
## they all went on the vehicle.
static func _load_on_board(tree: SceneTree, level: CompanyRoot, ctx: Dictionary, board: CompanyDispatch) -> String:
	var host: Dictionary = CREW.host(ctx)
	var station: DispatchStation = level.shed.dispatch_stations.values()[0]
	await CREW.go_to(tree, host, station.global_position)
	if not CREW.in_reach(host, station.global_position):
		return "board_out_of_reach"
	station.interact(host["player"])
	for _frame: int in BOARD_FRAMES:
		if board.is_open():
			break
		await tree.process_frame
	if not board.is_open():
		return "board_not_opened"
	var packed: Array = ctx["packed"]
	for entry: Dictionary in packed:
		var verdict: Dictionary = board.panel.toggle(entry["box_id"])
		if not bool(verdict["ok"]):
			board.close()
			return "%s_not_loadable_%s" % [entry["box_id"], verdict["key"]]
	var went: int = board.panel.confirm()
	board.close()
	return "" if went == packed.size() else "only_%d_loaded" % went
