extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_save_50_days.gd
##
## A company save after 50 days stays small and loads fast (expansion D-2026; company_save.gd,
## company_state.gd, delivery_note.gd, company_tuning.gd DELIVERY_NOTE_DAYS_KEPT):
## - the generator (here, without playing) builds a synthetic company with everything that grows with
##   time, day after day: ORDERS_MAX_PER_DAY paid orders and their costs in the ledger every day, a
##   truck of every supplier ordered every day with all the products, the day's pallets loaded,
##   all but one put on the floor and that one left on the bed as the truck goes (a short delivery note
##   every day), the oldest floor pallets emptied and cleared off the book as the crew would (D-0607.b),
##   the biggest stage's shed filled with pieces up to WAREHOUSE_STAGE_MAX_PIECES (shelves with
##   their uids), every product on every shelf slot, pallet, cart, the dock and the floor bundles, the
##   cold products' clocks running wherever they lie, every vehicle, zone reputation and gate;
## - the 50-day save weighs under 2 MB, CompanySave.save() and load_into() each take under 2 s (the
##   worst of 3, Time.get_ticks_usec), loading every piece, the ledger capped at LEDGER_MAX, the stock
##   whole and the cold clocks;
## - load -> save -> load gives the same CompanyState.to_dict();
## - every truck of the 100 days puts all its pallets on its bed, and the pallet book never comes near
##   MAX_PALLETS: it holds what stands in the shed, not what ever came (D-0607.b);
## - the delivery note keeps only DELIVERY_NOTE_DAYS_KEPT days line by line, with every day's
##   missing units still in its totals (D-2026.2), so a 100-day save weighs no more than twice the
##   50-day one, under MAX_GROWTH_BYTES more than it (nothing grows with the days), and its note no more
##   than the 50-day note.

const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const DIR: String = "user://test_company_save_50_days"
const DAYS: int = 50
const MAX_BYTES: int = 2 * 1024 * 1024
## What 50 more days may add to the save: nothing grows with the days, only the ids get a digit longer.
const MAX_GROWTH_BYTES: int = 2048
const MAX_LOAD_USEC: int = 2_000_000
const MAX_SAVE_USEC: int = 2_000_000
const LOAD_RUNS: int = 3
## The biggest stage (logistics center): the most pieces.
const STAGE: int = 3
## Pallets of each day's truck: one per product, all but one go on the floor. The oldest are emptied so that
## the next truck's fit in FLOOR_PALLETS spots: the most that stand on the floor at once.
const PALLET_UNITS: int = 12
const FLOOR_PALLETS: int = 60
## Units of each product on each storage spot.
const UNITS_PER_SPOT: int = 9
const CARTS: int = 4
const FLOOR_BUNDLES: int = 8
## Minutes the cold products have been out of a fridge when the save is made.
const COLD_MINUTES: float = 30.0
const CREW: int = 8
const ORDER_PRICE: int = 140
const ORDER_COST: int = 25
const RENT: int = 60

var _failures: int = 0
## Ids of each kind of data (products, suppliers...), from the file names: the save keeps ids only.
var _ids: Dictionary = {}
var _layout: Array[Dictionary] = []
## The most pallets the book held in any day of any company built here.
var _book_peak: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kind: StringName in CompanyCatalog.KINDS:
		_ids[kind] = _ids_of(kind)
	_layout = _full_layout()
	_clean()
	var fifty: Node = _company(DAYS)
	var hundred: Node = _company(DAYS * 2)
	_expect(_book_peak > 0 and _book_peak <= CompanyPallets.MAX_PALLETS / 2,
		"The pallet book stays far from MAX_PALLETS in 100 days (peak %d)" % _book_peak)
	_check_save_time(fifty)
	_expect(CompanySave.save(hundred, "hundred", DIR), "The 100-day company saves")
	var size_50: int = _bytes("fifty")
	var size_100: int = _bytes("hundred")
	print("D-2026 save: %d pieces, 50 days %d bytes, 100 days %d bytes, book peak %d"
		% [_layout.size(), size_50, size_100, _book_peak])
	_expect(size_50 > 0 and size_50 < MAX_BYTES, "The 50-day save weighs under 2 MB (got %d bytes)" % size_50)
	_expect(size_100 <= 2 * size_50,
		"A 100-day save weighs no more than twice the 50-day one (got %d vs %d bytes)" % [size_100, size_50])
	_expect(size_100 - size_50 < MAX_GROWTH_BYTES,
		"50 more days add under %d bytes (got %d)" % [MAX_GROWTH_BYTES, size_100 - size_50])
	_check_load_time()
	_check_round_trip(fifty)
	_check_note(fifty, hundred)
	fifty.free()
	hundred.free()
	_clean()
	if _failures == 0:
		print("PASS: a 50-day company save stays under 2 MB, loads under 2 s and round-trips the same")
	quit(_failures)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + label)


## The worst of LOAD_RUNS saves of the 50-day company.
func _check_save_time(company: Node) -> void:
	var worst: int = 0
	for run: int in LOAD_RUNS:
		var started: int = Time.get_ticks_usec()
		_expect(CompanySave.save(company, "fifty", DIR), "Save %d of the 50-day company works" % run)
		worst = maxi(worst, Time.get_ticks_usec() - started)
	print("D-2026 save: worst of %d is %.1f ms" % [LOAD_RUNS, worst / 1000.0])
	_expect(worst < MAX_SAVE_USEC, "save() takes under 2 s, worst of %d (got %.1f ms)"
		% [LOAD_RUNS, worst / 1000.0])


## The worst of LOAD_RUNS loads of the 50-day file, each into a fresh state.
func _check_load_time() -> void:
	var worst: int = 0
	for run: int in LOAD_RUNS:
		var state: Node = _new_state()
		var started: int = Time.get_ticks_usec()
		var result: CompanySave.LoadResult = CompanySave.load_into(state, "fifty", DIR)
		worst = maxi(worst, Time.get_ticks_usec() - started)
		_expect(result == CompanySave.LoadResult.LOADED, "Load %d of the 50-day save works (got %s)" % [run, result])
		state.free()
	print("D-2026 load_into: worst of %d is %.1f ms" % [LOAD_RUNS, worst / 1000.0])
	_expect(worst < MAX_LOAD_USEC, "load_into() takes under 2 s, worst of %d (got %.1f ms)"
		% [LOAD_RUNS, worst / 1000.0])


## load -> save -> load gives the same to_dict(), and nothing the generator made was dropped on the way.
func _check_round_trip(source: Node) -> void:
	var first: Node = _new_state()
	_expect(CompanySave.load_into(first, "fifty", DIR) == CompanySave.LoadResult.LOADED, "The 50-day save loads")
	_expect(CompanySave.save(first, "again", DIR), "The loaded company saves again")
	var second: Node = _new_state()
	_expect(CompanySave.load_into(second, "again", DIR) == CompanySave.LoadResult.LOADED, "... and loads again")
	var a: String = JSON.stringify(first.call(&"to_dict"))
	var b: String = JSON.stringify(second.call(&"to_dict"))
	_expect(a == b, "load -> save -> load gives the same to_dict() (%d vs %d chars)" % [a.length(), b.length()])
	var layout: Array = first.get(&"layout")
	_expect(layout.size() == _layout.size(), "Every piece of the shed comes back (got %d of %d)"
		% [layout.size(), _layout.size()])
	_expect((first.get(&"ledger") as Array).size() == CompanyTuning.LEDGER_MAX,
		"The ledger holds LEDGER_MAX movements (got %d)" % (first.get(&"ledger") as Array).size())
	var stock_in: Inventory = source.call(&"stock")
	var stock_out: Inventory = first.call(&"stock")
	_expect(stock_out.total_units() == stock_in.total_units() and stock_in.total_units() > 0,
		"The whole stock comes back (got %d of %d units)" % [stock_out.total_units(), stock_in.total_units()])
	var clocks: Dictionary = source.get(&"cold_clocks")
	_expect(not clocks.is_empty() and JSON.stringify(first.get(&"cold_clocks")) == JSON.stringify(clocks),
		"The cold clocks come back")
	_expect(int(first.get(&"day")) == DAYS + 1 and int(first.get(&"money")) == int(source.get(&"money")),
		"Day and money come back (got day %s, money %s)" % [first.get(&"day"), first.get(&"money")])
	first.free()
	second.free()


## The note keeps DELIVERY_NOTE_DAYS_KEPT days and every day's missing units, after 50 and after 100 days.
func _check_note(fifty: Node, hundred: Node) -> void:
	var loaded: Node = _new_state()
	CompanySave.load_into(loaded, "hundred", DIR)
	var pallets := CompanyPallets.new()
	_expect(pallets.load_save(loaded.get(&"pallets")), "The 100-day pallets load")
	var kept: int = CompanyTuning.DELIVERY_NOTE_DAYS_KEPT
	_expect(pallets.note.days_kept() == kept, "The note keeps %d days line by line (got %d)"
		% [kept, pallets.note.days_kept()])
	var missing: int = PALLET_UNITS * (_ids[CompanyCatalog.PRODUCTS] as Array).size() * DAYS * 2
	var totals: Dictionary = pallets.note.missing_totals()
	var sum: int = 0
	for product: Variant in totals:
		sum += int(totals[product])
	_expect(sum == missing, "Every day's missing units are still in the totals (got %d of %d)" % [sum, missing])
	var note_50: int = JSON.stringify((fifty.get(&"pallets") as Dictionary)["note"]).length()
	var note_100: int = JSON.stringify((hundred.get(&"pallets") as Dictionary)["note"]).length()
	_expect(note_100 <= note_50 + 64, "The 100-day note is no bigger than the 50-day one (got %d vs %d chars)"
		% [note_100, note_50])
	loaded.free()


## A company played `days` days, built without playing: what each day adds, then the full shed.
func _company(days: int) -> Node:
	var state: Node = _new_state()
	state.call(&"new_company", "Cincuenta Dias", 4242)
	state.set(&"warehouse_stage", STAGE)
	state.set(&"layout", _layout.duplicate(true))
	var products: Array[StringName] = _ids[CompanyCatalog.PRODUCTS]
	var suppliers: Array[StringName] = _ids[CompanyCatalog.SUPPLIERS]
	var schedule := SupplierSchedule.new()
	var pallets := CompanyPallets.new()
	var stock := Inventory.new()
	var on_floor: Array[StringName] = []
	for day: int in range(1, days + 1):
		state.set(&"day", day)
		state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN)
		_play_day(state, day, products, suppliers, schedule, pallets, stock, on_floor)
	state.set(&"day", days + 1)
	state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN)
	_fill_stock(stock, products)
	state.set(&"cold_clocks", _cold_clocks(stock, products))
	state.call(&"store_stock", stock)
	state.set(&"supplier_calendar", schedule.to_dict())
	state.set(&"pallets", pallets.to_save())
	_fill_company(state)
	return state


func _play_day(state: Node, day: int, products: Array[StringName], suppliers: Array[StringName],
		schedule: SupplierSchedule, pallets: CompanyPallets, stock: Inventory,
		on_floor: Array[StringName]) -> void:
	for order: int in CompanyTuning.ORDERS_MAX_PER_DAY:
		state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN + order * 30)
		state.call(&"earn", ORDER_PRICE + order, &"order_paid")
		state.call(&"charge", ORDER_COST, &"trip_fuel")
	state.call(&"charge", RENT, &"rent")
	# The truck of today comes with one pallet per product; all but one go to the floor, that one leaves.
	schedule.forget_before(day)
	var planned: Array[Dictionary] = []
	for product: StringName in products:
		planned.append(Pallet.make(StringName("d%d_%s" % [day, product]), product, PALLET_UNITS))
	var loading: Dictionary = pallets.loaded_event(day, planned, stock)
	_expect((loading.get("pallets", []) as Array).size() == planned.size()
		and pallets.apply(stock, CompanyPallets.LOADED, loading),
		"Day %d: all the truck's pallets load on the bed" % day)
	_book_peak = maxi(_book_peak, pallets.book.places.size())
	var unloading: int = planned.size() - 1
	for n: int in unloading:
		var id: StringName = planned[n]["id"]
		# Taken by the day and the pallet, each stands on a spot the oldest ones left free.
		var spot_index: int = ((day - 1) * unloading + n) % FLOOR_PALLETS
		var spot := Vector2(float(spot_index % 10) * 1.3, float(spot_index / 10) * 0.9)
		pallets.apply(stock, CompanyPallets.PICKED, {"pallet": id})
		_expect(pallets.apply(stock, CompanyPallets.PLACED, {"pallet": id, "pos": spot}),
			"Day %d: a pallet stands on the floor" % day)
		on_floor.append(id)
	var lines: Array = []
	for product: StringName in products:
		lines.append({"product": String(product), "ordered": PALLET_UNITS * 2, "received": PALLET_UNITS})
	_expect(pallets.apply(stock, CompanyPallets.DEPARTED, {"day": day, "lines": lines}),
		"Day %d: the truck leaves with a short note" % day)
	# The crew empties the oldest pallets onto the dock, and the host clears them off the book.
	while on_floor.size() > FLOOR_PALLETS - unloading:
		var oldest: StringName = on_floor.pop_front()
		var product: StringName = pallets.book.places[oldest]["pallet"]["product"]
		stock.move(product, PALLET_UNITS, Pallet.location(oldest), &"dock")
	CompanyPallets.clear_empties(pallets, stock, func(kind: StringName, data: Dictionary) -> void:
		_expect(pallets.apply(stock, kind, data), "Day %d: the emptied pallets leave the book" % day))
	# Tomorrow's trucks, one per supplier, every product.
	var order_lines: Array = []
	for product: StringName in products:
		order_lines.append({"product": product, "qty": PALLET_UNITS * 2})
	for supplier: StringName in suppliers:
		schedule.place(day, order_lines, supplier)


## Every product on every shelf slot, cart, the dock and the floor bundles (pallets already hold theirs).
func _fill_stock(stock: Inventory, products: Array[StringName]) -> void:
	var spots: Array[StringName] = [&"dock"]
	for bundle: int in FLOOR_BUNDLES:
		spots.append(FloorBundles.location(bundle))
	for cart: int in range(1, CARTS + 1):
		spots.append(PickingCart.location_of(StringName("cart_%d" % cart)))
	for piece: Dictionary in _layout:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(piece["id"]))
		for slot: int in def.slots:
			spots.append(StringName("shelf:%s_%d" % [piece["uid"], slot]))
	for product: StringName in products:
		for spot: StringName in spots:
			stock.receive(product, UNITS_PER_SPOT, spot)


## ColdChain's clocks, as saved, with COLD_MINUTES gone by for the cold products wherever they lie.
func _cold_clocks(stock: Inventory, products: Array[StringName]) -> Dictionary:
	var defs: Dictionary = {}
	for product: StringName in products:
		defs[product] = load("%s/%s/%s.tres" % [CompanyCatalog.DATA_ROOT, CompanyCatalog.PRODUCTS, product])
	var chain := ColdChain.new()
	chain.age(stock, defs, {}, COLD_MINUTES)
	return chain.to_dict()


func _fill_company(state: Node) -> void:
	var fleet: Array[Dictionary] = []
	for vehicle: StringName in _ids[CompanyCatalog.VEHICLES] as Array[StringName]:
		fleet.append({"vehicle": String(vehicle)})
	state.set(&"fleet", fleet)
	var employees: Array[Dictionary] = []
	for n: int in CREW:
		employees.append({"id": "employee_%d" % n, "station": String((_layout[n] as Dictionary)["uid"])})
	state.set(&"employees", employees)
	var by_zone: Dictionary = {}
	for zone: StringName in _ids[CompanyCatalog.ZONES] as Array[StringName]:
		by_zone[zone] = 75.0
	state.set(&"district_reputation", by_zone)
	var gates: Array[StringName] = _ids[CompanyCatalog.GATES]
	state.set(&"opened_gates", gates)
	state.set(&"milestones_done", [&"first_delivery", &"first_week", &"shed_large"] as Array[StringName])
	state.set(&"equipment", [&"chains", &"winter_coat", &"thermal_suit"] as Array[StringName])


## The biggest stage's floor filled greedily, row by row, with the pieces the build mode would accept
## one after the other (BuildPlacement, the same check BuildLayoutSave.sanitize() replays on load).
func _full_layout() -> Array[Dictionary]:
	var placement := BuildPlacement.new()
	var grid: Vector2i = WarehouseStages.apply_to(STAGE, placement)
	var most: int = WarehouseStages.max_pieces_for(STAGE)
	var defs: Array[PlaceableDefinition] = []
	for id: StringName in [&"shelf", &"fridge", &"shelf", &"assembly_table", &"shelf", &"dispatch_zone"]:
		defs.append(PlaceableShop.definition(id))
	var layout: Array[Dictionary] = []
	for z: int in grid.y:
		for x: int in grid.x:
			if layout.size() >= most:
				return layout
			var def: PlaceableDefinition = defs[layout.size() % defs.size()]
			for turns: int in [0, 1]:
				if bool(placement.preview(layout, def, x, z, turns)["ok"]):
					layout.append({"id": String(def.id), "x": x, "z": z, "turns": turns,
						"uid": "%s_%d" % [def.id, layout.size()]})
					break
	return layout


## The ids of a data folder (data/<kind>/<id>.tres), without loading the resources.
func _ids_of(kind: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	for file: String in CompanyCatalog.tres_files(CompanyCatalog.DATA_ROOT.path_join(String(kind))):
		found.append(StringName(file.get_basename()))
	return found


func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	root.add_child(state)
	return state


func _bytes(slot: String) -> int:
	var file := FileAccess.open(CompanySave.path_for(slot, DIR), FileAccess.READ)
	return file.get_length() if file != null else 0


func _clean() -> void:
	for slot: String in ["fifty", "hundred", "again"]:
		CompanySave.delete(slot, DIR)
