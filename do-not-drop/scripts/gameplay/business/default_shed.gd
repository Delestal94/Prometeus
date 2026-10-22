class_name DefaultShed
extends Resource
## The shed a new company starts with (expansion D-0911 and D-0620, "Modo Empresa"): dock and
## reception by the loading gate, shelves with the starting stock, two packing tables and the
## dispatch zone by the exit, all as data (data/shed/default_shed.tres), nothing placed by hand.
##
## Pure logic over a CompanyState-shaped object (no node, no autoload: lesson N-919). The pieces
## go in through BuildPlacement.place() with `free`, the same checks the build mode uses (inside
## the floor, off the dock and exit areas, no overlap, every station reachable on foot), so a
## default that stops fitting shows up in problems() and in test_company_default_layout, and the
## build mode can move, turn or sell each piece afterwards. What the shed draws and where each
## piece sits is the layout; the units (shelf slots, starter pallets) are the stock. Both live in
## CompanyState, which the host owns and the snapshot carries (D-2004): a client never runs
## apply_to(), it draws what the snapshot brings. Deterministic: no random roll anywhere.
##
## A piece of the layout is {id, x, z, turns} (PlaceableShop) plus a `uid`, its name in the shed
## ("shelf_1", "table_2"): the shelf's units lie at shelf:<uid>_<slot> and a station's state is
## kept under its uid, so moving or turning a piece keeps its stock. Pieces added later (build
## mode) have no uid: piece_uid() names them "<id>_<n>" in layout order.

const DEFAULT_PATH: String = "res://data/shed/default_shed.tres"
const ROLE_RECEPTION: StringName = &"reception"
const ROLE_STORAGE: StringName = &"storage"
const ROLE_ASSEMBLY: StringName = &"assembly"

## Warehouse stage (WarehouseStages) the pieces below are laid out for.
@export var stage: int = 0
## Pieces placed for free at the start: {uid, id, x, z, turns}, cells of the stage's grid.
@export var pieces: Array[Dictionary] = []
## Starting units on the shelves and the labels of their slots: {shelf (uid), slot, product, qty}.
## A qty of 0 labels a slot that starts empty (the cold products wait in the first pallets).
@export var shelf_stock: Array[Dictionary] = []
## What the supplier's first truck brings, ordered "day 0" in the SupplierSchedule so the pallets
## of day 1 wait in reception when the company opens: {product, qty}.
@export var first_order: Array[Dictionary] = []
## Where those pallets stand, in cells (centre of each, Vector2), in the order of their ids.
@export var pallet_spots: Array[Vector2] = []
## Where the picking carts stand at the start, in cells (centre of each, Vector2); the cart at index i is
## "cart_<i + 1>" (D-0610.b).
@export var cart_spots: Array[Vector2] = []
## Painted floor zones without a piece or fixed area of their own: {role, rect (Rect2i, cells),
## label_at (Vector2, cell where the name is written)}. Dock, exit and dispatch come from
## WarehouseStages and the dispatch piece.
@export var zones: Array[Dictionary] = []


static func load_default() -> DefaultShed:
	return load(DEFAULT_PATH) as DefaultShed


## True while a company is still untouched and its shed empty: no piece, no unit, no money moved.
## A new company, and a save from before the default existed, start from the default; a company
## that sold its last shelf has a wallet entry for it and never comes back here.
static func needs_default(state: Object, data: DefaultShed = null) -> bool:
	var wanted: DefaultShed = data if data != null else load_default()
	if wanted == null or not state.layout.is_empty() or not state.ledger.is_empty():
		return false
	return int(state.warehouse_stage) == wanted.stage and state.stock().total_units() == 0


## Name of the piece at `index` of `layout`: its stored uid, or "<id>_<n>" (n counts the pieces
## of that id without a uid up to it, from 1).
static func piece_uid(layout: Array, index: int) -> StringName:
	var piece: Dictionary = layout[index]
	var stored: String = str(piece.get("uid", ""))
	if stored != "":
		return StringName(stored)
	var id: String = str(piece.get("id", ""))
	var nth: int = 0
	for i: int in range(index + 1):
		if str(layout[i].get("id", "")) == id and str(layout[i].get("uid", "")) == "":
			nth += 1
	return StringName("%s_%d" % [id, nth])


## Where the units of a shelf slot are counted in the Inventory.
static func shelf_location(uid: StringName, slot: int) -> StringName:
	return StringName("shelf:%s_%d" % [uid, slot])


## The pallets of the first truck, sealed, from the supplier calendar (SupplierSchedule).
func first_pallets() -> Array[Dictionary]:
	var calendar := SupplierSchedule.new()
	var lines: Array = []
	for line: Dictionary in first_order:
		lines.append({"product": line.get("product", &""), "qty": line.get("qty", 0)})
	var order_day: int = CompanyTuning.STARTING_DAY - 1
	if not calendar.place(order_day, lines):
		return []
	return calendar.pallets_for(SupplierSchedule.arrival_day(order_day))


## A placement checker set for the stage, as the world builds it: fixed areas and entries.
func placement() -> BuildPlacement:
	var checker := BuildPlacement.new()
	WarehouseStages.apply_to(stage, checker)
	return checker


## Puts the default in `state` (a CompanyState): the pieces in the layout, their units in the
## stock. Returns {placed, refused: [{uid, reason}], units}: a piece the build rules turn down is
## left out and reported, never forced. Nothing is paid.
func apply_to(state: Object) -> Dictionary:
	var checker: BuildPlacement = placement()
	var report: Dictionary = {"placed": 0, "refused": [], "units": 0}
	var placed_uids: Dictionary = {}
	for piece: Dictionary in pieces:
		var def: PlaceableDefinition = PlaceableShop.definition(StringName(str(piece.get("id", ""))))
		var uid: String = str(piece.get("uid", ""))
		var result: Dictionary = checker.place(state, def, int(piece.get("x", 0)),
			int(piece.get("z", 0)), int(piece.get("turns", 0)), true)
		if not bool(result["ok"]):
			(report["refused"] as Array).append({"uid": uid, "reason": result["reason"]})
			continue
		state.layout[state.layout.size() - 1]["uid"] = uid
		placed_uids[uid] = true
		report["placed"] = int(report["placed"]) + 1
	var stock: Inventory = state.stock()
	for entry: Dictionary in shelf_stock:
		var qty: int = int(entry.get("qty", 0))
		if placed_uids.has(str(entry.get("shelf", ""))) and qty > 0:
			stock.receive(StringName(str(entry["product"])), qty,
				shelf_location(StringName(str(entry["shelf"])), int(entry["slot"])))
			report["units"] = int(report["units"]) + qty
	for pallet: Dictionary in first_pallets():
		if Pallet.receive(stock, pallet):
			report["units"] = int(report["units"]) + int(pallet["qty"])
	state.store_stock(stock)
	return report


## Everything wrong with the data itself, one text each (empty: it is sound). Checked on a
## scratch company: a piece the build rules refuse, a station nobody can walk to, a shelf slot that
## does not exist or is labeled twice, an unknown product, a pallet without a spot.
func problems() -> Array[String]:
	var found: Array[String] = []
	var scratch := ScratchState.new()
	var report: Dictionary = apply_to(scratch)
	for refusal: Dictionary in report["refused"]:
		found.append("piece %s refused: %s" % [refusal["uid"], refusal["reason"]])
	var grid: Vector2i = WarehouseStages.grid_size_for(stage)
	var entries: Array[Rect2i] = placement().entry_areas
	for index: int in WalkReachability.unreachable_pieces(grid, scratch.layout, entries):
		found.append("piece %s cannot be walked to" % piece_uid(scratch.layout, index))
	if not WalkReachability.entries_connected(grid, scratch.layout, entries):
		found.append("the dock is cut off from the exit")
	var shelf_slots: Dictionary = {}
	for index: int in scratch.layout.size():
		var def: PlaceableDefinition = PlaceableShop.definition(
			StringName(str(scratch.layout[index]["id"])))
		if def != null and def.role == &"storage":
			shelf_slots[str(piece_uid(scratch.layout, index))] = def.slots
	var labeled: Dictionary = {}
	for entry: Dictionary in shelf_stock:
		var shelf: String = str(entry.get("shelf", ""))
		var slot: int = int(entry.get("slot", -1))
		var key: String = "%s_%d" % [shelf, slot]
		if not shelf_slots.has(shelf) or slot < 0 or slot >= int(shelf_slots[shelf]):
			found.append("shelf slot %s does not exist" % key)
		if labeled.has(key):
			found.append("shelf slot %s is labeled twice" % key)
		labeled[key] = true
		if not ResourceLoader.exists("res://data/products/%s.tres" % str(entry.get("product", ""))):
			found.append("unknown product %s" % entry.get("product", ""))
	if first_pallets().size() > pallet_spots.size():
		found.append("%d pallets but only %d spots" % [first_pallets().size(), pallet_spots.size()])
	return found


## A CompanyState stand-in for problems(): the fields and wallet calls the placement uses, no
## autoload and no node.
class ScratchState extends RefCounted:
	var money: int = 0
	var layout: Array[Dictionary] = []
	var ledger: Array[Dictionary] = []
	var warehouse_stage: int = 0
	var inventory: Dictionary = {}

	func can_afford(amount: int) -> bool:
		return amount >= 0 and money >= amount

	func spend(_amount: int, _reason: StringName) -> bool:
		return false

	func earn(_amount: int, _reason: StringName) -> bool:
		return false

	func stock() -> Inventory:
		var result := Inventory.new()
		result.from_dict(inventory)
		return result

	func store_stock(stock_in: Inventory) -> void:
		inventory = stock_in.to_dict()


## Until the order screen (D-0603) puts real orders in the calendar, the first order of the default shed arrives with
## the truck every day for `days` days from `first_day`, the same on every peer, so the truck can be seen driving in.
## It brings nothing: the stock stays what the shed started with.
static func seed_stand_in(schedule: SupplierSchedule, first_day: int, days: int) -> void:
	var data: DefaultShed = load_default()
	if data == null:
		return
	var lines: Array = []
	for line: Dictionary in data.first_order:
		lines.append({"product": line.get("product", &""), "qty": line.get("qty", 0)})
	for day: int in range(first_day, first_day + days):
		schedule.place(day - 1, lines)
