extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_save_stock.gd
##
## A save keeps no stock on its way (expansion D-0252, guardado.md section 3; return_bundle.gd,
## floor_bundles.gd, company_root.gd, company_tuning.gd RETURN_BUNDLE_SPOT):
## - CompanyRoot.stock_for_save() (ReturnBundle.for_save()) with units in two hands, in floor:0 and in
##   another floor bundle, in an open box (box:b1) and in a sealed package (package:p1), plus two
##   orders' reservations: all of them lie in SAVED_HANDS_LOCATION; shelf, pallet, cart and dock keep
##   theirs; every product's total is the same; nothing is reserved; the live stock is untouched;
## - FloorBundles.place() takes only a floor:<n> that holds units and a finite Vector3, and
##   next_free() never reuses the placed bundle;
## - ReturnBundle.spot(): in the default shed, RETURN_BUNDLE_SPOT, a free cell of the stage-0 floor next
##   to a packing table; a bigger stage keeps its cell; with a piece over it, the middle of the nearest
##   free cell the crew walks to (a nearer pocket that piece walls off is skipped); the layout's order
##   doesn't change the answer;
## - the round trip with a host CompanyRoot (solo, the default shed, a save folder of its own): units
##   in a hand, in two dropped bundles, in a box and in a package, hens reserved; the day closes and
##   its SUMMARY saves the next opening, the live stock as it was. A new company state entering again
##   loads day 2 with every unit on a shelf, pallet, cart, the dock or floor:0, the same totals, no
##   reservation, and floor:0 at RETURN_BUNDLE_SPOT (the snapshot's "floor" carries it): a player out
##   of reach is refused (out_of_reach), one within reach takes a unit from it (granted by the host);
## - a host entering with units in floor:0 and a piece over the spot lays the bundle where spot()
##   says for that layout.

const DIR: String = "user://test_company_save_stock"
const SLOT: String = "stock"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Real msec the DayCycle reads: far past the OPENING's few seconds.
const LATER_MSEC: int = 60_000
## Where the host's own player stands in the round trip (its feet for the drops).
const FEET: Vector3 = Vector3(-1.0, 1.0, 0.0)
## A shelf over the spot's cell (10, 1) of the default shed: it covers cells 10 x 0..1 and walls off the
## pocket 11 x 0..1 between itself, the east wall and table_1.
const COVER: Dictionary = {"id": "shelf", "uid": "shelf_cover", "x": 10, "z": 0, "turns": 1}
## The middle of cell (10, 2), the free cell nearest the covered spot that the crew walks to.
const COVERED_SPOT: Vector3 = Vector3(4.5, 0.0, -1.5)

var _failures: int = 0


## A CompanyRoot without its world (zones, shed, player): the business side, with the GameClock and
## DayCycle _add_day() gives it, and the host's day opened (as test_company_autosave's).
class LiveDayRoot extends CompanyRoot:
	func _ready() -> void:
		_start_company(company_state)
		_open_company_day.call_deferred()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RpcGuard.reset()
	_clean()
	_check_for_save()
	_check_place()
	_check_spot()
	await _check_round_trip()
	await _check_covered_load()
	RpcGuard.reset()
	_clean()
	if _failures == 0:
		print("PASS: a save puts hands, floor bundles, boxes and packages in the return bundle with no"
			+ " reservation, and a loaded day lays it by the packing tables (or the nearest free cell)"
			+ " where a player within reach takes from it")
	quit(_failures)


func _check_for_save() -> void:
	var live := Inventory.new()
	live.receive(&"hen", 6, &"shelf:shelf_2_0")
	live.receive(&"hen", 4, &"pallet:p1")
	live.receive(&"puppy", 2, &"cart:cart_1")
	live.receive(&"sourdough", 3, &"dock")
	live.move(&"hen", 2, &"shelf:shelf_2_0", &"hands:1")
	live.receive(&"puppy", 1, &"hands:7")
	live.receive(&"hen", 1, CompanyRoot.SAVED_HANDS_LOCATION)
	live.receive(&"sourdough", 2, &"floor:3")
	live.receive(&"puppy", 1, &"box:b1")
	live.receive(&"hen", 2, &"package:p1")
	live.receive(&"sourdough", 1, &"package:p1")
	_expect(live.reserve(&"hen", 3, &"order_9") and live.reserve(&"sourdough", 1, &"order_10"),
		"The live stock reserves 3 hens and 1 sourdough for two orders")
	var before: Dictionary = live.to_dict()
	var kept: Inventory = CompanyRoot.stock_for_save(live)
	_expect(live.to_dict() == before, "stock_for_save() leaves the live stock and its reservations as they were")
	_expect(kept.contents_at(CompanyRoot.SAVED_HANDS_LOCATION) == {&"hen": 5, &"puppy": 2, &"sourdough": 3},
		"Hands, floor bundles, the box and the package lie in %s (got %s)"
		% [CompanyRoot.SAVED_HANDS_LOCATION, kept.contents_at(CompanyRoot.SAVED_HANDS_LOCATION)])
	_expect(kept.count(&"hen", &"shelf:shelf_2_0") == 4 and kept.count(&"hen", &"pallet:p1") == 4
		and kept.count(&"puppy", &"cart:cart_1") == 2 and kept.count(&"sourdough", &"dock") == 3,
		"...shelf, pallet, cart and dock keep theirs (got %s)" % [kept.to_dict()])
	for product: StringName in [&"hen", &"puppy", &"sourdough"]:
		_expect(kept.count(product) == live.count(product),
			"...%s's total is the same (%d, live %d)" % [product, kept.count(product), live.count(product)])
	_expect(_stray_locations(kept).is_empty(),
		"...and no unit is anywhere without a station (got %s)" % [_stray_locations(kept)])
	_expect((kept.to_dict()["reserved"] as Dictionary).is_empty() and kept.reserved_total(&"hen") == 0,
		"Nothing is reserved in what a save keeps (got %s)" % [kept.to_dict()["reserved"]])
	for location: StringName in [&"hands:1", &"floor:3", &"box:b1", &"package:p1", &"floor:0"]:
		_expect(ReturnBundle.on_the_way(location), "%s is on its way" % location)
	for location: StringName in [&"shelf:shelf_1_0", &"pallet:p1", &"cart:cart_1", &"dock"]:
		_expect(not ReturnBundle.on_the_way(location), "%s is not on its way" % location)


func _check_place() -> void:
	var stock := Inventory.new()
	stock.receive(&"hen", 2, &"floor:0")
	var bundles := FloorBundles.new()
	_expect(not bundles.place(stock, &"floor:1", Vector3.ZERO), "place() refuses a bundle that holds nothing")
	_expect(not bundles.place(stock, &"floor:0", Vector3(NAN, 0.0, 0.0))
		and not bundles.place(stock, &"floor:0", Vector2.ZERO), "...a position that isn't a finite Vector3")
	stock.receive(&"hen", 1, &"shelf:shelf_2_0")
	_expect(not bundles.place(stock, &"shelf:shelf_2_0", Vector3.ZERO), "...and a location that isn't floor:<n>")
	_expect(bundles.to_dict().is_empty(), "...changing nothing (got %s)" % [bundles.to_dict()])
	_expect(bundles.place(stock, &"floor:0", Vector3(1.0, 0.0, 2.0))
		and bundles.position_of(&"floor:0") == Vector3(1.0, 0.0, 2.0),
		"place() lays a bundle that holds units at a finite Vector3")
	_expect(bundles.next_free(stock) == &"floor:1", "next_free() never reuses the placed bundle")


func _check_spot() -> void:
	var scratch := DefaultShed.ScratchState.new()
	DefaultShed.load_default().apply_to(scratch)
	var layout: Array = scratch.layout
	var spot: Vector3 = CompanyTuning.RETURN_BUNDLE_SPOT
	var half: Vector2 = WarehouseStages.floor_size_m(0) * 0.5
	_expect(absf(spot.x) < half.x and absf(spot.z) < half.y and is_zero_approx(spot.y),
		"RETURN_BUNDLE_SPOT lies on the starting shed's floor (got %s)" % spot)
	_expect(ReturnBundle.spot(layout, 0) == spot and ReturnBundle.spot([], 0) == spot,
		"In the default shed the bundle lies at RETURN_BUNDLE_SPOT (got %s)" % ReturnBundle.spot(layout, 0))
	_expect(ReturnBundle.free_cells(layout, 0).has(Vector2i(10, 1)), "...a free cell the crew walks to")
	_expect(_to_table(layout, spot) <= 1.5,
		"...next to a packing table (%.2f m from its nearest cell)" % _to_table(layout, spot))
	var grown: Vector3 = ReturnBundle.spot(layout, 1)
	_expect(grown == spot + Vector3(-3.0, 0.0, -2.0),
		"A bigger stage keeps the spot's cell, as it keeps every piece (got %s)" % grown)
	var covered: Array = layout.duplicate()
	covered.append(COVER)
	var free: Dictionary = ReturnBundle.free_cells(covered, 0)
	_expect(not free.has(Vector2i(10, 1)) and not free.has(Vector2i(11, 1)) and free.has(Vector2i(10, 2)),
		"A shelf over the spot covers its cell and walls off the pocket by the east wall")
	_expect(ReturnBundle.spot(covered, 0) == COVERED_SPOT,
		"...so the bundle lies in the nearest free cell the crew walks to (got %s)" % ReturnBundle.spot(covered, 0))
	var reversed: Array = covered.duplicate()
	reversed.reverse()
	_expect(ReturnBundle.spot(reversed, 0) == COVERED_SPOT and ReturnBundle.spot(covered, 0) == COVERED_SPOT,
		"...the same answer every time, whatever the order of the layout")


func _check_round_trip() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Return SRL")
	var host: LiveDayRoot = await _enter(state)
	var net: CompanyNet = host.net
	var hands: StringName = CompanyNet.hands_location(host.multiplayer.get_unique_id())
	net.player_origin = func(_peer: int) -> Variant: return FEET
	_expect(net.inventory.move(&"hen", 3, &"shelf:shelf_2_0", hands)
		and net.inventory.move(&"puppy", 1, &"shelf:shelf_2_1", &"box:b1")
		and net.inventory.move(&"sourdough", 2, &"shelf:shelf_1_3", &"package:p1")
		and net.inventory.reserve(&"hen", 2, &"order_9"),
		"The default shed's units go into a hand, a box and a package, and 2 hens are reserved")
	net.drop(&"hen", 1, FEET + Vector3(-0.5, -1.0, 0.5))
	net.drop(&"hen", 1, FEET + Vector3(0.5, -1.0, -0.5))
	var dropped: Dictionary = net.floor_bundles.to_dict()
	_expect(dropped.get(&"floor:0") is Vector3 and dropped.get(&"floor:1") is Vector3
		and net.inventory.count(&"hen", hands) == 1,
		"Two drops leave a hen in floor:0 and one in floor:1, with their positions (%s)" % [dropped])
	var totals: Dictionary = _totals(net.inventory)
	var live: Dictionary = net.inventory.to_dict()
	_close_day(host)
	_expect(host.day_cycle.phase() == DayCycle.Phase.SUMMARY and CompanySave.exists(SLOT, DIR),
		"The day reaches SUMMARY and its close is saved (phase %s)" % host.day_cycle.phase_name())
	_expect(net.inventory.to_dict() == live, "...without touching the live stock")
	var saved := Inventory.new()
	saved.from_dict((_raw().get("company", {}) as Dictionary).get("inventory", {}))
	_expect((saved.to_dict()["reserved"] as Dictionary).is_empty()
		and saved.contents_at(CompanyRoot.SAVED_HANDS_LOCATION) == {&"hen": 3, &"puppy": 1, &"sourdough": 2},
		"The file keeps no reservation and the return bundle holds the hand, both drops, the box and the"
		+ " package (got %s)" % [saved.to_dict()])
	await _leave(host)
	state.free()

	var loaded: Node = _new_state()
	var again: LiveDayRoot = await _enter(loaded)
	var stock: Inventory = again.net.inventory
	_expect(int(loaded.get(&"day")) == 2, "Entering again loads the close: day 2 (got %s)" % loaded.get(&"day"))
	_expect(_totals(stock) == totals,
		"...with every product's total (got %s, saved from %s)" % [_totals(stock), totals])
	_expect(_stray_locations(stock).is_empty(),
		"...every unit on a shelf, pallet, cart, the dock or floor:0 (strays %s)" % [_stray_locations(stock)])
	_expect((stock.to_dict()["reserved"] as Dictionary).is_empty(),
		"...and nothing reserved (got %s)" % [stock.to_dict()["reserved"]])
	var bundle: Variant = again.net.floor_bundles.position_of(CompanyRoot.SAVED_HANDS_LOCATION)
	_expect(bundle == CompanyTuning.RETURN_BUNDLE_SPOT,
		"The return bundle lies at RETURN_BUNDLE_SPOT (got %s)" % [bundle])
	var floor_part: Variant = again.net.snapshot().get("floor")
	_expect(FloorBundles.positions_ok(floor_part)
		and (floor_part as Dictionary).get(CompanyRoot.SAVED_HANDS_LOCATION) == CompanyTuning.RETURN_BUNDLE_SPOT,
		"...and the snapshot takes that to the clients (floor %s)" % [floor_part])
	_check_take(again)
	await _leave(again)
	loaded.free()
	_clean()


## The host's own player asks for a puppy of the return bundle: 10 m away it is refused, 1.5 m away
## it is granted and lands in its hands.
func _check_take(host: LiveDayRoot) -> void:
	var net: CompanyNet = host.net
	var hands: StringName = CompanyNet.hands_location(host.multiplayer.get_unique_id())
	var refusals: Array = []
	net.request_rejected.connect(func(rid: int, reason: StringName) -> void: refusals.append([rid, reason]))
	var ask: Dictionary = {"station": CompanyRoot.SAVED_HANDS_LOCATION, "product": &"puppy", "qty": 1}
	var spot: Vector3 = CompanyTuning.RETURN_BUNDLE_SPOT
	net.player_origin = func(_peer: int) -> Variant: return spot + Vector3(10.0, 1.0, 0.0)
	var far: int = net.request(&"units_take", ask)
	_expect(refusals == [[far, CompanyNet.REASON_OUT_OF_REACH]] and net.inventory.count(&"puppy", hands) == 0,
		"A player 10 m from the return bundle is refused out_of_reach (got %s)" % [refusals])
	refusals.clear()
	var seq: int = net.seq
	net.player_origin = func(_peer: int) -> Variant: return spot + Vector3(1.0, 1.0, 0.5)
	net.request(&"units_take", ask)
	_expect(refusals.is_empty() and net.seq == seq + 1 and net.inventory.count(&"puppy", hands) == 1
		and net.inventory.count(&"puppy", CompanyRoot.SAVED_HANDS_LOCATION) == 0,
		"One within reach takes a puppy from it, granted by the host (refusals %s, hands %s)"
		% [refusals, net.inventory.contents_at(hands)])
	_expect(net.floor_bundles.position_of(CompanyRoot.SAVED_HANDS_LOCATION) == spot,
		"...and the bundle, still holding hens and sourdough, stays where it lies")


func _check_covered_load() -> void:
	var state: Node = _new_state()
	state.call(&"new_company", "Cover SRL")
	DefaultShed.load_default().apply_to(state)
	(state.get(&"layout") as Array).append(COVER.duplicate())
	var stock: Inventory = state.call(&"stock")
	stock.receive(&"hen", 2, CompanyRoot.SAVED_HANDS_LOCATION)
	state.call(&"store_stock", stock)
	var host: LiveDayRoot = await _enter(state)
	var expected: Vector3 = ReturnBundle.spot(state.get(&"layout"), int(state.get(&"warehouse_stage")))
	var bundle: Variant = host.net.floor_bundles.position_of(CompanyRoot.SAVED_HANDS_LOCATION)
	_expect(expected == COVERED_SPOT and bundle == expected,
		"With a shelf over the spot the loaded bundle lies at the nearest free cell %s (got %s)" % [expected, bundle])
	await _leave(host)
	state.free()
	_clean()


## Every location of `stock` holding units where nothing would let a player take them back: not a
## shelf slot, a pallet, a cart, the dock or the return bundle.
func _stray_locations(stock: Inventory) -> Array:
	var strays: Array = []
	var by_product: Dictionary = stock.to_dict()["stock"]
	for product: Variant in by_product:
		for location: Variant in by_product[product]:
			var text := String(location)
			var kept: bool = text.begins_with("shelf:") or text.begins_with("pallet:") or text.begins_with("cart:") \
				or text == "dock" or StringName(location) == CompanyRoot.SAVED_HANDS_LOCATION
			if not kept and not strays.has(location):
				strays.append(location)
	return strays


## {product: total units} of `stock`.
func _totals(stock: Inventory) -> Dictionary:
	var totals: Dictionary = {}
	for product: Variant in stock.to_dict()["stock"]:
		totals[StringName(product)] = stock.count(StringName(product))
	return totals


## Metres from `spot` to the middle of the nearest cell of a packing table of `layout` (stage 0).
func _to_table(layout: Array, spot: Vector3) -> float:
	var nearest: float = INF
	var grid: Vector2 = Vector2(WarehouseStages.grid_size_for(0))
	for piece: Dictionary in layout:
		if str(piece.get("id", "")) != "assembly_table":
			continue
		var def: PlaceableDefinition = PlaceableShop.definition(&"assembly_table")
		var rect := Rect2i(Vector2i(int(piece["x"]), int(piece["z"])), def.footprint_for(int(piece.get("turns", 0))))
		for x: int in range(rect.position.x, rect.end.x):
			for z: int in range(rect.position.y, rect.end.y):
				var middle: Vector2 = (Vector2(x, z) + Vector2(0.5, 0.5) - grid * 0.5) * CompanyTuning.WAREHOUSE_GRID_M
				nearest = minf(nearest, middle.distance_to(Vector2(spot.x, spot.z)))
	return nearest


## OPENING, OPERATING, CLOSING and SUMMARY of the open day: the OPENING's seconds pass on the
## DayCycle's ticks, the clock jumps to 20:00, no trip is out.
func _close_day(host: LiveDayRoot) -> void:
	host.day_cycle.ticks = func() -> int: return Time.get_ticks_msec() + LATER_MSEC
	host.day_cycle.poll()
	host.clock.start(float(CompanyTuning.DAY_END_MIN))
	host.day_cycle.poll()
	host.day_cycle.poll()


func _enter(state: Node) -> LiveDayRoot:
	var host := LiveDayRoot.new()
	host.company_state = state
	host.save_slot = SLOT
	host.save_dir = DIR
	root.add_child(host)
	await process_frame
	await process_frame
	return host


func _leave(host: Node) -> void:
	host.queue_free()
	await process_frame


## A CompanyState of its own (not the autoload), in the tree so its facts reach EventBus.
func _new_state() -> Node:
	var state: Node = (load(STATE_SCRIPT) as GDScript).new()
	state.call(&"reset")
	root.add_child(state)
	return state


func _raw() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CompanySave.path_for(SLOT, DIR)))
	return raw if raw is Dictionary else {}


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
