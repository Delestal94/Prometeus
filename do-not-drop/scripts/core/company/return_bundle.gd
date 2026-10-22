class_name ReturnBundle
extends RefCounted
## The return bundle (D-0252, docs/expansion-distritos/diseno/guardado.md section 3): where a save
## puts every unit that was on its way, and where that bundle lies when the day loads.
##
## A save is always a day's opening, so nothing in it may be on its way (for_save()): what was in
## a hand (hands:<peer>), in a bundle on the floor (floor:<n>: their positions are not saved), in an
## open box on a packing table (box:<id>: the tables are not saved) or in a sealed package nobody
## dispatched (package:<id>: its order is gone the next day, so it goes back unpacked) lies in one
## bundle, CompanyRoot.SAVED_HANDS_LOCATION (floor:0), with the total of every product kept; and no
## order keeps a reservation (the day's orders are gone too). Shelves, pallets, carts and the dock
## keep their units: their stations come back with the layout and the pallets.
##
## When the host loads that day (CompanyRoot._add_net()), place() lays the bundle on the shed's
## floor (spot()): at CompanyTuning.RETURN_BUNDLE_SPOT, by the default packing tables, or at the
## nearest free cell when a piece of the layout covers it. FloorBundles then knows where it lies, the
## snapshot's "floor" takes that to every client, and it is taken with units_take like any bundle
## (D-2006). Static and pure: no node, no random roll, the same answer for the same layout.

## Where the units on their way lie in the live stock: what for_save() gathers in the bundle.
const ON_THE_WAY: Array[String] = [
	CompanyNet.HANDS_PREFIX, FloorBundles.PREFIX, CompanyTableNet.BOX_PREFIX, CompanyTableNet.PACKAGE_PREFIX,
]


## True for a location whose units are on their way (ON_THE_WAY).
static func on_the_way(location: StringName) -> bool:
	for prefix: String in ON_THE_WAY:
		if String(location).begins_with(prefix):
			return true
	return false


## A copy of `stock` as a save keeps it: every unit on its way (on_the_way()) in bundle `into`, the
## rest where it is, the total of each product the same and nothing reserved. `stock` itself
## (CompanyNet's live one) is not touched.
static func for_save(stock: Inventory, into: StringName) -> Inventory:
	var copy := Inventory.new()
	copy.from_dict({"stock": stock.to_dict()["stock"]})
	var by_product: Dictionary = copy.to_dict()["stock"]
	for product: Variant in by_product:
		var locations: Dictionary = by_product[product]
		for location: Variant in locations:
			var from := StringName(location)
			if from != into and on_the_way(from):
				copy.move(StringName(product), int(locations[location]), from, into)
	return copy


## Host, as a saved day loads (CompanyRoot._add_net()) and before the first snapshot: when `stock`
## holds units in bundle `where` (the return bundle), it lies at spot() in `bundles` from then on,
## the shed being of `stage` and furnished with `layout`. False, changing nothing, when it holds none.
static func place(bundles: FloorBundles, stock: Inventory, where: StringName, layout: Array, stage: int) -> bool:
	if stock.contents_at(where).is_empty():
		return false
	return bundles.place(stock, where, spot(layout, stage))


## Where the return bundle lies in a shed of `stage` furnished with `layout` (CompanyState.layout), in
## the world (the shed stands at its origin, CompanyShed) at floor height: RETURN_BUNDLE_SPOT, moved
## with its cell when the shed is bigger than the starting one (a stage keeps the cells of the one
## before, WarehouseStages), while that cell is free (free_cells()); else the middle of the free cell
## nearest to it, the lower row and then the lower column on a tie. With no free cell, the spot itself.
static func spot(layout: Array, stage: int) -> Vector3:
	var metres: float = CompanyTuning.WAREHOUSE_GRID_M
	var grid: Vector2i = WarehouseStages.grid_size_for(stage)
	var shift: Vector2 = Vector2(WarehouseStages.grid_size_for(0) - grid) * 0.5 * metres
	var fixed: Vector3 = CompanyTuning.RETURN_BUNDLE_SPOT + Vector3(shift.x, 0.0, shift.y)
	var home: Vector2 = Vector2(fixed.x, fixed.z) / metres + Vector2(grid) * 0.5
	var free: Dictionary = free_cells(layout, stage)
	if free.has(Vector2i(home.floor())):
		return fixed
	var best := Vector2i(-1, -1)
	var best_distance: float = INF
	for z: int in grid.y:
		for x: int in grid.x:
			var distance: float = (Vector2(x, z) + Vector2(0.5, 0.5)).distance_squared_to(home)
			if distance < best_distance and free.has(Vector2i(x, z)):
				best = Vector2i(x, z)
				best_distance = distance
	if best.x < 0:
		return fixed
	var middle: Vector2 = (Vector2(best) + Vector2(0.5, 0.5) - Vector2(grid) * 0.5) * metres
	return Vector3(middle.x, fixed.y, middle.y)


## Cells (Vector2i -> true) of a shed of `stage` furnished with `layout` where the return bundle may lie:
## on the floor, under no piece (a painted one either: the dispatch zone is no place for loose units),
## off the dock and exit areas, and one the crew walks to from those (WalkReachability, the walking the
## build mode keeps open), so whoever stands there has it within reach as any bundle (CompanyNet.within_reach()).
static func free_cells(layout: Array, stage: int) -> Dictionary:
	var entries: Array[Rect2i] = WarehouseStages.fixed_rects(stage)
	var free: Dictionary = WalkReachability.reachable_cells(WarehouseStages.grid_size_for(stage), layout, entries)
	var covered: Array[Rect2i] = entries.duplicate()
	for piece: Variant in layout:
		if not piece is Dictionary:
			continue
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str((piece as Dictionary).get("id", ""))))
		if def != null:
			covered.append(Rect2i(Vector2i(int(piece.get("x", 0)), int(piece.get("z", 0))),
				def.footprint_for(int(piece.get("turns", 0)))))
	for rect: Rect2i in covered:
		for x: int in range(rect.position.x, rect.end.x):
			for z: int in range(rect.position.y, rect.end.y):
				free.erase(Vector2i(x, z))
	return free
