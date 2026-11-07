extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_save_50_days.gd
##
## A company save after 50 days stays small and loads fast (expansion D-2026; company_save.gd,
## company_state.gd, delivery_note.gd, company_tuning.gd DELIVERY_NOTE_DAYS_KEPT):
## - the generator (here, without playing) builds a synthetic company with everything that grows with
##   time, day after day: ORDERS_MAX_PER_DAY paid orders and their costs in the ledger every day, a
##   truck of every supplier ordered every day with all the products, the day's pallets loaded,
##   some put on the floor and the rest left on the bed as the truck goes (a short delivery note every
##   day), the biggest stage's shed filled with pieces up to WAREHOUSE_STAGE_MAX_PIECES (shelves with
##   their uids), every product on every shelf slot, pallet, cart, the dock and the floor bundle,
##   every vehicle, zone reputation and gate;
## - the 50-day save weighs under 2 MB and CompanySave.load_into() takes under 2 s (the worst of 3,
##   Time.get_ticks_usec), loading every piece, the ledger capped at LEDGER_MAX and the stock whole;
## - load -> save -> load gives the same CompanyState.to_dict();
## - the delivery note keeps only DELIVERY_NOTE_DAYS_KEPT days line by line, with every day's
##   missing units still in its totals (D-2026.2), so a 100-day save weighs no more than twice the
##   50-day one, and its note no more than the 50-day note.

const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
const DIR: String = "user://test_company_save_50_days"
const DAYS: int = 50
const MAX_BYTES: int = 2 * 1024 * 1024
const MAX_LOAD_USEC: int = 2_000_000
const LOAD_RUNS: int = 3
## The biggest stage (logistics center): the most pieces.
const STAGE: int = 3
## Pallets of each day's truck: one per product. Some go on the floor until FLOOR_PALLETS stand there.
const PALLET_UNITS: int = 12
const FLOOR_PER_DAY: int = 2
const FLOOR_PALLETS: int = 60
## Units of each product on each storage spot.
const UNITS_PER_SPOT: int = 9
const CARTS: int = 4
const CREW: int = 8
const ORDER_PRICE: int = 140
const ORDER_COST: int = 25
const RENT: int = 60

var _failures: int = 0
## Ids of each kind of data (products, suppliers...), from the file names: the save keeps ids only.
var _ids: Dictionary = {}
var _layout: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kind: StringName in CompanyCatalog.KINDS:
		_ids[kind] = _ids_of(kind)
	_layout = _full_layout()
	_clean()
	var fifty: Node = _company(DAYS)
	var hundred: Node = _company(DAYS * 2)
	_expect(CompanySave.save(fifty, "fifty", DIR), "The 50-day company saves")
	_expect(CompanySave.save(hundred, "hundred", DIR), "The 100-day company saves")
	var size_50: int = _bytes("fifty")
	var size_100: int = _bytes("hundred")
	print("D-2026 save: %d pieces, 50 days %d bytes, 100 days %d bytes" % [_layout.size(), size_50, size_100])
	_expect(size_50 > 0 and size_50 < MAX_BYTES, "The 50-day save weighs under 2 MB (got %d bytes)" % size_50)
	_expect(size_100 <= 2 * size_50,
		"A 100-day save weighs no more than twice the 50-day one (got %d vs %d bytes)" % [size_100, size_50])
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
	for day: int in range(1, days + 1):
		state.set(&"day", day)
		state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN)
		_play_day(state, day, products, suppliers, schedule, pallets, stock)
	state.set(&"day", days + 1)
	state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN)
	_fill_stock(stock, products)
	state.call(&"store_stock", stock)
	state.set(&"supplier_calendar", schedule.to_dict())
	state.set(&"pallets", pallets.to_save())
	_fill_company(state)
	return state


func _play_day(state: Node, day: int, products: Array[StringName], suppliers: Array[StringName],
		schedule: SupplierSchedule, pallets: CompanyPallets, stock: Inventory) -> void:
	for order: int in CompanyTuning.ORDERS_MAX_PER_DAY:
		state.set(&"clock_minutes", CompanyTuning.DAY_START_MIN + order * 30)
		state.call(&"earn", ORDER_PRICE + order, &"order_paid")
		state.call(&"charge", ORDER_COST, &"trip_fuel")
	state.call(&"charge", RENT, &"rent")
	# The truck of today comes with one pallet per product; a few go to the floor, the rest leaves.
	schedule.forget_before(day)
	var planned: Array = []
	for product: StringName in products:
		planned.append(Pallet.make(StringName("d%d_%s" % [day, product]), product, PALLET_UNITS))
	_expect(pallets.apply(stock, CompanyPallets.LOADED, {"day": day, "pallets": planned}),
		"Day %d: the truck's pallets load on the bed" % day)
	var on_floor: int = pallets.book.ids_at(PalletJack.AT_FLOOR).size()
	for n: int in FLOOR_PER_DAY:
		if on_floor >= FLOOR_PALLETS:
			break
		var id: StringName = (planned[n] as Dictionary)["id"]
		var spot := Vector2(float(on_floor % 10) * 1.3, float(on_floor / 10) * 0.9)
		pallets.apply(stock, CompanyPallets.PICKED, {"pallet": id})
		_expect(pallets.apply(stock, CompanyPallets.PLACED, {"pallet": id, "pos": spot}),
			"Day %d: a pallet stands on the floor" % day)
		on_floor += 1
	var lines: Array = []
	for product: StringName in products:
		lines.append({"product": String(product), "ordered": PALLET_UNITS * 2, "received": PALLET_UNITS})
	_expect(pallets.apply(stock, CompanyPallets.DEPARTED, {"day": day, "lines": lines}),
		"Day %d: the truck leaves with a short note" % day)
	# Tomorrow's trucks, one per supplier, every product.
	var order_lines: Array = []
	for product: StringName in products:
		order_lines.append({"product": product, "qty": PALLET_UNITS * 2})
	for supplier: StringName in suppliers:
		schedule.place(day, order_lines, supplier)


## Every product on every shelf slot, cart, the dock and the return bundle (pallets already hold theirs).
func _fill_stock(stock: Inventory, products: Array[StringName]) -> void:
	var spots: Array[StringName] = [&"dock", FloorBundles.location(0)]
	for cart: int in range(1, CARTS + 1):
		spots.append(PickingCart.location_of(StringName("cart_%d" % cart)))
	for piece: Dictionary in _layout:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(piece["id"]))
		for slot: int in def.slots:
			spots.append(StringName("shelf:%s_%d" % [piece["uid"], slot]))
	for product: StringName in products:
		for spot: StringName in spots:
			stock.receive(product, UNITS_PER_SPOT, spot)


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
