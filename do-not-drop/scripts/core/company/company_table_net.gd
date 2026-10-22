class_name CompanyTableNet
extends RefCounted
## The packing tables over the network (expansion D-0715): opening a box, putting a product in its
## grid, taking one out, padding, labeling, stamping and taping are CompanyNet requests the host
## checks and events every peer applies the same way (contract
## docs/expansion-distritos/diseno/red-autoridad.md, section 2 rows 9 to 15, and section 9).
##
## A table has no owner (D-2001): whoever stands at it packs, and two players may work the same
## box, one putting products in and the other taping it. The host takes requests one at a time, so
## of two that clash (two boxes on one free table, two products in one cell) the second is refused
## with its reason. CompanyNet hands the table requests here (check(), host only, once the sender's
## reach to the table is measured, rule 4) and the table events (apply(), every peer); it lives
## there as CompanyNet.table. Nothing here sends anything or names an autoload.
##
## State: one PackingStation per table touched, named by its layout piece's uid (the station's
## location is table:<uid>), with its box, its supplies (D-0718) and the box's id (box_<n>, given
## by the host). An open box's units lie in the Inventory at box:<box id>; taping moves them to
## package:<box id> and lowers the order's reservation by them. The tables travel in CompanyNet's
## snapshot under SNAPSHOT_KEY (to_dict() on the host, put_snapshot() on a client). Staged products
## (PackingStation.staged) don't travel: over the network a unit goes from the hands to the grid.
##
## Requests (CompanyNet.request(kind, data); a cell as three ints, never a Vector3i, rule 5):
##   box_start     {station, size: S/M/L/XL}
##   box_place     {station, product, cx, cy, cz, rot: 0}  (no rotation in F1, D-0703)
##   box_take_out  {station, cx, cy, cz}                  (any cell of the product)
##   box_fill      {station, cells: 1..MAX_FILL}          (one padding kind in F1, D-0705)
##   box_label     {station}                              (with the table's order, order_of)
##   box_stamp     {station, stamp: a BoxSeals kind}
##   box_tape      {station}
## Events (`money` is the host's balance after the step, `minute` its clock minute for the wallet
## entry, as CompanyLayoutNet's: a copy whose wallet was off is set right and asks for a snapshot):
##   box_started   {table, size, box, money, minute}
##   box_placed    {table, product, cx, cy, cz, rot, from: hands:<peer>}
##   box_taken_out {table, cx, cy, cz, product, to: hands:<peer>}
##   box_filled    {table, cells, money, minute}
##   box_labeled   {table, order, money, minute}
##   box_stamped   {table, stamp, money, minute}
##   box_sealed    {table, order, package_id, node_name, trap, trap_intensity, contents, absorption,
##                  quality, pos, basis, money, minute}
## box_sealed takes the box off the table on every peer and puts the DeliveryPackage it became in
## the world, named node_name, at pos and basis (`packages`, CompanyPackages, D-0715.b); a peer
## checks those fields too before it changes anything. Refusals: bad_data, no_station,
## out_of_reach (CompanyNet's), not_enough, hands_busy, hands_full, no_room, no_money and the
## REASON_* below.

const START: StringName = &"box_start"
const PLACE: StringName = &"box_place"
const TAKE_OUT: StringName = &"box_take_out"
const FILL: StringName = &"box_fill"
const LABEL: StringName = &"box_label"
const STAMP: StringName = &"box_stamp"
const TAPE: StringName = &"box_tape"
const REQUEST_KINDS: Array[StringName] = [START, PLACE, TAKE_OUT, FILL, LABEL, STAMP, TAPE]
const STARTED: StringName = &"box_started"
const PLACED: StringName = &"box_placed"
const TAKEN_OUT: StringName = &"box_taken_out"
const FILLED: StringName = &"box_filled"
const LABELED: StringName = &"box_labeled"
const STAMPED: StringName = &"box_stamped"
const SEALED: StringName = &"box_sealed"
const EVENT_KINDS: Array[StringName] = [
	STARTED, PLACED, TAKEN_OUT, FILLED, LABELED, STAMPED, SEALED,
]
## Key of the tables in CompanyNet's snapshot (CompanyNet adds the part itself).
const SNAPSHOT_KEY: String = "packing"
const TABLE_PREFIX: String = "table:"
const BOX_PREFIX: String = "box:"
const PACKAGE_PREFIX: String = "package:"
const HANDS_PREFIX: String = "hands:"
## Box ids the host hands out: box_<n>.
const BOX_ID_PREFIX: String = "box_"

const REASON_BAD_DATA: StringName = &"bad_data"
const REASON_NO_STATION: StringName = &"no_station"
const REASON_NOT_ENOUGH: StringName = &"not_enough"
const REASON_HANDS_BUSY: StringName = &"hands_busy"
const REASON_HANDS_FULL: StringName = &"hands_full"
const REASON_NO_ROOM: StringName = &"no_room"
const REASON_NO_MONEY: StringName = &"no_money"
## box_start at a table that already holds a box.
const REASON_HAS_BOX: StringName = &"has_box"
## Any other step at a table without a box.
const REASON_NO_BOX: StringName = &"no_box"
## A step on a box already taped shut.
const REASON_SEALED: StringName = &"sealed"
## The table ran out of that supply: boxes of that size, tape or padding (D-0718).
const REASON_NO_SUPPLY: StringName = &"no_supply"
## box_place where the product sticks out of the box or lands on a product or padding.
const REASON_CELL_TAKEN: StringName = &"cell_taken"
## box_take_out at a cell with no product (empty or padding).
const REASON_EMPTY_CELL: StringName = &"empty_cell"
## box_place of a unit when every one left is promised to another order (row 10).
const REASON_RESERVED: StringName = &"reserved_for_other"
## box_label at a table with no order, or one that names no house.
const REASON_NO_ORDER: StringName = &"no_order"
## box_stamp of a seal the box already carries.
const REASON_STAMPED: StringName = &"already_stamped"
## box_tape of a box with no product.
const REASON_EMPTY_BOX: StringName = &"empty_box"

## Cells a request may name on each axis, from 0: past the biggest box (XL has 4).
const MAX_CELL: int = 15
## Cells one box_fill may ask to pad, and padded cells a box in a snapshot may carry (XL: 64).
const MAX_FILL: int = 64
## Most tables, and products in one box, a snapshot may carry (rule 5).
const MAX_TABLES: int = 256
const MAX_ITEMS: int = 64
const MAX_ID_LENGTH: int = RpcGuard.MAX_TEXT_LENGTH

## Host: the order a table packs for, as Callable(table: StringName) -> Dictionary (an Order
## dictionary, {} for none). Whoever ties orders to tables sets it (order_claim, row 8: D-0804 /
## D-0807). Unset, no table has an order: box_label is refused with no_order and box_place takes
## only units no order holds.
var order_of: Callable = Callable()
## The DeliveryPackage each box_sealed makes on this peer (D-0715.b). The world sets its `parent`
## (CompanyRoot: World/Packages); unset, no package is built and the event applies all the same.
var packages: CompanyPackages = CompanyPackages.new()

## {table: PackingStation} of every table touched; {table: box id} of each one holding a box.
var _tables: Dictionary = {}
var _box_ids: Dictionary = {}
## The highest n of a box_<n> handed out or applied here.
var _serial: int = 0
## True since an applied event found this copy's wallet off the host's (take_drift()).
var _drifted: bool = false
## ProductDefinition by id, loaded once.
static var _defs: Dictionary = {}


## The state of `table` (its box and supplies), null when nothing ever happened there (a free,
## fully stocked table). Read it, never write it: only events change it.
func station_of(table: StringName) -> PackingStation:
	return _tables.get(table)


## Id of the box on `table`, &"" when it holds none.
func box_of(table: StringName) -> StringName:
	return _box_ids.get(table, &"")


## True while `table` holds a box (CompanyNet then refuses to sell the table: not_empty).
func has_box(table: StringName) -> bool:
	return _box_ids.has(table)


## Forgets `table` once its piece is sold (layout_sold): a table placed later under the same uid
## starts free and full. One that holds a box is kept (false).
func forget(table: StringName) -> bool:
	return not has_box(table) and _tables.erase(table)


## True once, then false: an event applied since the last call found this copy's wallet off the
## host's balance (and set it right). The rest of what it missed needs a snapshot.
func take_drift() -> bool:
	var drifted: bool = _drifted
	_drifted = false
	return drifted


## The station a table request names, as CompanyNet looks it up ({station}), or {} when it is
## missing or not an id.
static func station_ask(data: Dictionary) -> Dictionary:
	var station: Variant = data.get("station")
	return {"station": StringName(station)} if _id_ok(station) else {}


## The table of a station's location (table:<uid> -> uid), &"" for any other location.
static func table_of(location: Variant) -> StringName:
	if not CompanyAsk.is_id(location) or not String(location).begins_with(TABLE_PREFIX):
		return &""
	var table: String = String(location).trim_prefix(TABLE_PREFIX)
	return StringName(table) if _id_ok(table) else &""


## Inventory location of an open box's units.
static func box_location(box: StringName) -> StringName:
	return StringName(BOX_PREFIX + String(box))


## Inventory location of a taped box's units (the package it became).
static func package_location(package: StringName) -> StringName:
	return StringName(PACKAGE_PREFIX + String(package))


## Host: a table request at `station` (CompanyNet looked it up and measured the sender's reach to
## it), as {reason} when it is refused or {reason: &"", kind, data} with its one event. `hands` is
## the sender's (hands:<peer>, built by the host, rule 3), `state` the company (its wallet pays each
## step) and `stock` the live Inventory.
func check(state: Object, stock: Inventory, kind: StringName, data: Dictionary,
		station: Dictionary, hands: StringName) -> Dictionary:
	var table: StringName = table_of(station.get("location"))
	if table == &"":
		return _refused(REASON_NO_STATION)
	if state == null or not is_instance_valid(state) or stock == null:
		return _refused(REASON_BAD_DATA)
	var desk: PackingStation = _desk(table)
	if kind == START:
		return _check_start(state, stock, desk, table, data)
	if not desk.has_box():
		return _refused(REASON_NO_BOX)
	if desk.box.taped:
		return _refused(REASON_SEALED)
	var asked: Dictionary = _refused(REASON_BAD_DATA)
	match kind:
		PLACE:
			asked = _check_place(stock, desk, table, data, hands)
		TAKE_OUT:
			asked = _check_take_out(stock, desk, table, data, hands)
		FILL:
			asked = _check_fill(state, desk, table, data)
		LABEL:
			asked = _check_label(state, desk, table)
		STAMP:
			asked = _check_stamp(state, desk, table, data)
		TAPE:
			asked = _check_tape(state, desk, table, station)
	return asked


## Every peer, the host too (CompanyNet._apply_state()): a table event in place with the same calls
## on every peer. Checked only as data (rule 6) and against this copy (a table holding the box the
## event names, the units where it says they are): false, changing nothing, when it doesn't fit.
## Every check comes before the first change.
func apply(state: Object, stock: Inventory, kind: StringName, data: Dictionary) -> bool:
	if state == null or not is_instance_valid(state) or stock == null:
		push_warning("CompanyTableNet: a %s event but no company here" % kind)
		return false
	var table: Variant = data.get("table")
	if not _id_ok(table):
		return false
	if kind == STARTED:
		return _apply_started(state, StringName(table), data)
	var desk: PackingStation = _tables.get(StringName(table))
	if desk == null or not desk.has_box() or desk.box.taped:
		return false
	var box_at: StringName = box_location(_box_ids[StringName(table)])
	var applied: bool = false
	match kind:
		PLACED:
			applied = _apply_placed(stock, desk, box_at, data)
		TAKEN_OUT:
			applied = _apply_taken_out(stock, desk, box_at, data)
		FILLED:
			applied = _apply_filled(state, desk, data)
		LABELED:
			applied = _apply_labeled(state, desk, data)
		STAMPED:
			applied = _apply_stamped(state, desk, data)
		SEALED:
			applied = _apply_sealed(state, stock, StringName(table), data)
	return applied


## The tables as plain data, what the snapshot carries and two peers compare:
## {serial, tables: {table: {box_id, box: PackedBox.to_dict() or {}, supplies}}}.
func to_dict() -> Dictionary:
	var tables: Dictionary = {}
	for table: StringName in _tables:
		var desk: PackingStation = _tables[table]
		tables[String(table)] = {
			"box_id": String(_box_ids.get(table, &"")),
			"box": desk.box.to_dict() if desk.has_box() else {},
			"supplies": desk.supplies.to_dict(),
		}
	return {"serial": _serial, "tables": tables}


## Client: puts the host's tables (to_dict()) in place of the ones here, firing nothing. Checked
## first as data from the network (rule 5, CompanySnapshot.tables_from()): false, changing
## nothing, when it doesn't fit.
func put_snapshot(value: Variant) -> bool:
	var got: Dictionary = CompanySnapshot.tables_from(value)
	if got.is_empty():
		return false
	_tables = got["tables"]
	_box_ids = got["boxes"]
	_serial = got["serial"]
	# The snapshot brings the host's wallet too: no drift left to report.
	_drifted = false
	return true


func _check_start(state: Object, stock: Inventory, desk: PackingStation, table: StringName,
		data: Dictionary) -> Dictionary:
	var size: Variant = data.get("size")
	if not (CompanyAsk.is_id(size) and BoxDispenser.SIZES.has(StringName(size))):
		return _refused(REASON_BAD_DATA)
	if desk.has_box():
		return _refused(REASON_HAS_BOX)
	if not desk.supplies.has(StationSupplies.box_kind(StringName(size))):
		return _refused(REASON_NO_SUPPLY)
	var cost: int = BoxDispenser.cost_of(StringName(size))
	if not state.can_afford(cost):
		return _refused(REASON_NO_MONEY)
	var started: Dictionary = {"table": table, "size": StringName(size), "box": _new_box_id(stock)}
	return _granted(STARTED, _paid(state, cost, started))


func _check_place(stock: Inventory, desk: PackingStation, table: StringName, data: Dictionary,
		hands: StringName) -> Dictionary:
	var def: ProductDefinition = _product(data.get("product"))
	var cell: Variant = _cell_of(data)
	var rot: Variant = data.get("rot", 0)
	if def == null or cell == null or typeof(rot) != TYPE_INT or int(rot) != 0:
		return _refused(REASON_BAD_DATA)
	if stock.count(def.id, hands) < 1:
		return _refused(REASON_NOT_ENOUGH)
	if not PackedBox.from_dict(desk.box.to_dict()).place(def, cell):
		return _refused(REASON_CELL_TAKEN)
	if not _may_take(stock, table, def.id):
		return _refused(REASON_RESERVED)
	var at: Vector3i = cell
	return _granted(PLACED, {
		"table": table, "product": def.id, "cx": at.x, "cy": at.y, "cz": at.z, "rot": 0,
		"from": hands,
	})


func _check_take_out(stock: Inventory, desk: PackingStation, table: StringName,
		data: Dictionary, hands: StringName) -> Dictionary:
	var cell: Variant = _cell_of(data)
	if cell == null:
		return _refused(REASON_BAD_DATA)
	var product: StringName = _product_at(desk.box, cell)
	if product == &"":
		return _refused(REASON_EMPTY_CELL)
	var held: Dictionary = stock.contents_at(hands)
	if held.size() > 1 or (held.size() == 1 and not held.has(product)):
		return _refused(REASON_HANDS_BUSY)
	if stock.count(product, hands) + 1 > CompanyTuning.HAND_MAX_UNITS:
		return _refused(REASON_HANDS_FULL)
	var at: Vector3i = cell
	return _granted(TAKEN_OUT, {
		"table": table, "cx": at.x, "cy": at.y, "cz": at.z, "product": product, "to": hands,
	})


## Pads as many free cells as asked, the table's padding and the box's free cells allow.
func _check_fill(state: Object, desk: PackingStation, table: StringName,
		data: Dictionary) -> Dictionary:
	var cells: Variant = data.get("cells")
	if typeof(cells) != TYPE_INT or int(cells) < 1 or int(cells) > MAX_FILL:
		return _refused(REASON_BAD_DATA)
	var free: int = desk.box.total_cells() - desk.box.grid.size()
	if free < 1:
		return _refused(REASON_NO_ROOM)
	var padded: int = mini(int(cells), mini(free, desk.supplies.count(StationSupplies.FILL)))
	if padded < 1:
		return _refused(REASON_NO_SUPPLY)
	var cost: int = PackagingSupplies.fill_cost(padded)
	if not state.can_afford(cost):
		return _refused(REASON_NO_MONEY)
	return _granted(FILLED, _paid(state, cost, {"table": table, "cells": padded}))


## The label of the table's order (order_of); the same order again is free (D-0707).
func _check_label(state: Object, desk: PackingStation, table: StringName) -> Dictionary:
	var order: Dictionary = _order(table)
	var id: Variant = order.get("id")
	if not _id_ok(id) or OrderLabel.address(order).is_empty():
		return _refused(REASON_NO_ORDER)
	var cost: int = 0 if desk.box.label_order_id == StringName(id) else CompanyTuning.LABEL_COST
	if not state.can_afford(cost):
		return _refused(REASON_NO_MONEY)
	return _granted(LABELED, _paid(state, cost, {"table": table, "order": StringName(id)}))


func _check_stamp(state: Object, desk: PackingStation, table: StringName,
		data: Dictionary) -> Dictionary:
	var stamp: Variant = data.get("stamp")
	if not (CompanyAsk.is_id(stamp) and BoxSeals.is_kind(StringName(stamp))):
		return _refused(REASON_BAD_DATA)
	if desk.box.stamps.has(StringName(stamp)):
		return _refused(REASON_STAMPED)
	if not state.can_afford(CompanyTuning.STAMP_COST):
		return _refused(REASON_NO_MONEY)
	var stamped: Dictionary = {"table": table, "stamp": StringName(stamp)}
	return _granted(STAMPED, _paid(state, CompanyTuning.STAMP_COST, stamped))


## Tapes the box and works out, on the host, what the package carries: the ruling product's trap,
## the quality against the order on its label (AssemblyQuality, with the tape on), the intensity
## (BoxTrap) and the absorption. It appears where the table's box sits (the station's spot).
func _check_tape(state: Object, desk: PackingStation, table: StringName,
		station: Dictionary) -> Dictionary:
	var box: PackedBox = desk.box
	if box.items.is_empty():
		return _refused(REASON_EMPTY_BOX)
	if not desk.supplies.has(StationSupplies.TAPE):
		return _refused(REASON_NO_SUPPLY)
	if not state.can_afford(CompanyTuning.TAPE_COST):
		return _refused(REASON_NO_MONEY)
	var shut: PackedBox = PackedBox.from_dict(box.to_dict())
	shut.taped = true
	var order: Dictionary = _order(table)
	if box.label_order_id == &"" or _order_id(table) != box.label_order_id:
		order = {}
	var products: Dictionary = {}
	for product: StringName in shut.contents():
		products[product] = _product(product)
	var main: ProductDefinition = BoxToPackage.ruling_product(shut, products)
	var quality: float = AssemblyQuality.score(shut, order, products)
	var id: StringName = box_of(table)
	return _granted(SEALED, _paid(state, CompanyTuning.TAPE_COST, {
		"table": table, "order": box.label_order_id, "package_id": id,
		"node_name": StringName("Package_%s" % id),
		"trap": main.trap_id if main != null else &"", "trap_intensity": BoxTrap.intensity(quality),
		"contents": box.contents(), "absorption": BoxToPackage.absorption(shut), "quality": quality,
		"pos": station.get("spot"), "basis": Basis.IDENTITY,
	}))


## Row 10: a unit put in the box on `table` comes out of its order's reservation first and else
## out of the units no order holds. False when neither is left: every unit of `product` outside the
## boxes and packages is promised to another order that still lacks it.
func _may_take(stock: Inventory, table: StringName, product: StringName) -> bool:
	var in_box: Dictionary = {}
	var boxed: int = 0
	for other: StringName in _box_ids:
		var units: int = stock.count(product, box_location(_box_ids[other]))
		var order: StringName = _order_id(other)
		in_box[order] = int(in_box.get(order, 0)) + units
		boxed += units
	var mine: StringName = _order_id(table)
	if mine != &"" and int(stock.reserved_by(mine).get(product, 0)) > int(in_box.get(mine, 0)):
		return true
	var whole: Dictionary = stock.to_dict()
	var owed: int = 0
	var reserved: Dictionary = whole["reserved"]
	for order: Variant in reserved:
		var held: int = int((reserved[order] as Dictionary).get(product, 0))
		owed += maxi(held - int(in_box.get(StringName(order), 0)), 0)
	var sealed: int = 0
	var where: Dictionary = (whole["stock"] as Dictionary).get(product, {})
	for location: Variant in where:
		if String(location).begins_with(PACKAGE_PREFIX):
			sealed += int(where[location])
	return stock.count(product) - boxed - sealed - owed >= 1


## Host: the next box id nobody uses, box_<n> past the last one handed out, skipping any whose units
## still lie somewhere (box:<id>, package:<id>: a loaded day keeps them, D-0206).
func _new_box_id(stock: Inventory) -> StringName:
	var used: Dictionary = {}
	var by_product: Dictionary = stock.to_dict()["stock"]
	for product: Variant in by_product:
		for location: Variant in by_product[product]:
			used[StringName(location)] = true
	var n: int = _serial + 1
	var id := StringName(BOX_ID_PREFIX + str(n))
	while _box_ids.values().has(id) or used.has(box_location(id)) or used.has(package_location(id)):
		n += 1
		id = StringName(BOX_ID_PREFIX + str(n))
	return id


func _apply_started(state: Object, table: StringName, data: Dictionary) -> bool:
	var size: Variant = data.get("size")
	var box: Variant = data.get("box")
	if not (CompanyAsk.is_id(size) and BoxDispenser.SIZES.has(StringName(size)) and _id_ok(box)):
		return false
	var desk: PackingStation = _desk(table)
	var kind: StringName = StationSupplies.box_kind(StringName(size))
	if not _wallet_ok(data) or _box_ids.values().has(StringName(box)) or desk.has_box():
		return false
	if not desk.supplies.has(kind):
		return false
	var cost: int = BoxDispenser.cost_of(StringName(size))
	_set_balance(state, int(data["money"]) + cost)
	if not BoxDispenser.dispense(desk, StringName(size), state as Node):
		return false
	_tables[table] = desk
	_box_ids[table] = StringName(box)
	_serial = maxi(_serial, _serial_of(StringName(box)))
	_entry_minute(state, cost, data["minute"])
	return true


func _apply_placed(stock: Inventory, desk: PackingStation, box_at: StringName,
		data: Dictionary) -> bool:
	var def: ProductDefinition = _product(data.get("product"))
	var cell: Variant = _cell_of(data)
	var from: Variant = data.get("from")
	var rot: Variant = data.get("rot")
	if def == null or cell == null or not _hands_ok(from) or typeof(rot) != TYPE_INT or rot != 0:
		return false
	if stock.count(def.id, StringName(from)) < 1 or not desk.box.place(def, cell):
		return false
	return stock.move(def.id, 1, StringName(from), box_at)


func _apply_taken_out(stock: Inventory, desk: PackingStation, box_at: StringName,
		data: Dictionary) -> bool:
	var cell: Variant = _cell_of(data)
	var product: Variant = data.get("product")
	var to: Variant = data.get("to")
	if cell == null or not _hands_ok(to) or not _id_ok(product):
		return false
	if _product_at(desk.box, cell) != StringName(product):
		return false
	if stock.count(StringName(product), box_at) < 1:
		return false
	desk.box.take_out(cell)
	return stock.move(StringName(product), 1, box_at, StringName(to))


func _apply_filled(state: Object, desk: PackingStation, data: Dictionary) -> bool:
	var cells: Variant = data.get("cells")
	if typeof(cells) != TYPE_INT or int(cells) < 1 or int(cells) > MAX_FILL or not _wallet_ok(data):
		return false
	var free: int = desk.box.total_cells() - desk.box.grid.size()
	if free < int(cells) or desk.supplies.count(StationSupplies.FILL) < int(cells):
		return false
	var cost: int = PackagingSupplies.fill_cost(int(cells))
	_set_balance(state, int(data["money"]) + cost)
	if desk.pad(int(cells), state) != int(cells):
		return false
	_entry_minute(state, cost, data["minute"])
	return true


func _apply_labeled(state: Object, desk: PackingStation, data: Dictionary) -> bool:
	var order: Variant = data.get("order")
	if not _id_ok(order) or not _wallet_ok(data):
		return false
	var cost: int = 0 if desk.box.label_order_id == StringName(order) else CompanyTuning.LABEL_COST
	_set_balance(state, int(data["money"]) + cost)
	if not PackagingSupplies.label(desk.box, StringName(order), state):
		return false
	_entry_minute(state, cost, data["minute"])
	return true


func _apply_stamped(state: Object, desk: PackingStation, data: Dictionary) -> bool:
	var stamp: Variant = data.get("stamp")
	if not (CompanyAsk.is_id(stamp) and BoxSeals.is_kind(StringName(stamp))):
		return false
	if not _wallet_ok(data) or desk.box.stamps.has(StringName(stamp)):
		return false
	_set_balance(state, int(data["money"]) + CompanyTuning.STAMP_COST)
	if not desk.stamp(StringName(stamp), state):
		return false
	_entry_minute(state, CompanyTuning.STAMP_COST, data["minute"])
	return true


## The box is taped and leaves the table; its units go from box:<id> to package:<id> and the
## order on its label holds that much less, and the package it became goes into the world on this
## peer (row 15, D-0715.b: `packages`). Its fields (name, pose, trap, quality...) are checked with
## the rest, and the package built from the taped box, before anything changes.
func _apply_sealed(state: Object, stock: Inventory, table: StringName, data: Dictionary) -> bool:
	var desk: PackingStation = _tables[table]
	var box_id: StringName = _box_ids[table]
	var contents: Variant = data.get("contents")
	var order: Variant = data.get("order")
	if not (_id_ok(data.get("package_id")) and StringName(data["package_id"]) == box_id):
		return false
	if not (_text_ok(order) and StringName(order) == desk.box.label_order_id and _wallet_ok(data)):
		return false
	if not CompanyPackages.fields_ok(data, box_id) or not packages.can_add(data["node_name"]):
		return false
	var box_at: StringName = box_location(box_id)
	var held: Dictionary = desk.box.contents()
	if held.is_empty() or not contents is Dictionary or contents != held \
			or not desk.supplies.has(StationSupplies.TAPE):
		return false
	for product: StringName in held:
		if stock.count(product, box_at) < int(held[product]):
			return false
	var shut: PackedBox = PackedBox.from_dict(desk.box.to_dict())
	shut.taped = true
	var package: DeliveryPackage = packages.make(shut, data)
	if packages.active() and package == null:
		return false
	_set_balance(state, int(data["money"]) + CompanyTuning.TAPE_COST)
	if not desk.seal(state):
		if package != null:
			package.free()
		return false
	_entry_minute(state, CompanyTuning.TAPE_COST, data["minute"])
	for product: StringName in held:
		stock.move(product, int(held[product]), box_at, package_location(box_id))
		if StringName(order) != &"":
			stock.unreserve(product, int(held[product]), StringName(order))
	desk.take_box()
	_box_ids.erase(table)
	packages.put(package)
	return true


## The host's balance before the event's movement: a copy that holds another missed something; it
## takes the host's (so the movement ends on the host's balance) and remembers it (take_drift()).
func _set_balance(state: Object, before: int) -> void:
	var here: int = int(state.get(&"money"))
	if here == before:
		return
	push_warning("CompanyTableNet: this wallet held %d, the host's %d; set to the host's"
		% [here, before])
	state.set(&"money", before)
	_drifted = true


## The wallet entry the event just wrote (if it cost anything) takes the host's minute;
## clock_minutes stays as it is.
static func _entry_minute(state: Object, cost: int, minute: int) -> void:
	var ledger: Array = state.get(&"ledger")
	if cost > 0 and not ledger.is_empty():
		ledger[ledger.size() - 1]["minute"] = minute


## A paid step's event: `data` with the host's balance after the step and its clock minute.
static func _paid(state: Object, cost: int, data: Dictionary) -> Dictionary:
	data["money"] = int(state.get(&"money")) - cost
	data["minute"] = int(state.get(&"clock_minutes"))
	return data


func _desk(table: StringName) -> PackingStation:
	var desk: PackingStation = _tables.get(table)
	return desk if desk != null else PackingStation.make(table)


func _order(table: StringName) -> Dictionary:
	if not order_of.is_valid():
		return {}
	var order: Variant = order_of.call(table)
	return order if order is Dictionary else {}


func _order_id(table: StringName) -> StringName:
	var id: Variant = _order(table).get("id")
	return StringName(id) if _id_ok(id) else &""


## The cell (cx, cy, cz) of a request or an event, null when one is missing, not an int or out of
## 0..MAX_CELL (rule 5: a Vector3i never travels).
static func _cell_of(data: Dictionary) -> Variant:
	var cell: Array[int] = []
	for key: String in ["cx", "cy", "cz"]:
		var value: Variant = data.get(key)
		if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > MAX_CELL:
			return null
		cell.append(int(value))
	return Vector3i(cell[0], cell[1], cell[2])


## The product whose block covers `cell`, &"" for an empty or padded cell.
static func _product_at(box: PackedBox, cell: Vector3i) -> StringName:
	var value: Variant = box.grid.get(cell, &"")
	return value if value is StringName and value != PackedBox.FILL else &""


## A product of the catalog (CompanyAsk.product_exists()), loaded once; null otherwise.
static func _product(id: Variant) -> ProductDefinition:
	if not (CompanyAsk.is_id(id) and CompanyAsk.product_exists(StringName(id))):
		return null
	if not _defs.has(StringName(id)):
		var path: String = CompanyAsk.PRODUCTS_DIR + String(id) + ".tres"
		_defs[StringName(id)] = load(path) as ProductDefinition
	return _defs[StringName(id)]


## n of a box_<n> id, 0 for any other.
static func _serial_of(box: StringName) -> int:
	var n: String = String(box).trim_prefix(BOX_ID_PREFIX)
	return int(n) if String(box).begins_with(BOX_ID_PREFIX) and n.is_valid_int() else 0


static func _wallet_ok(data: Dictionary) -> bool:
	var money: Variant = data.get("money")
	var minute: Variant = data.get("minute")
	return typeof(money) == TYPE_INT and int(money) >= 0 \
		and int(money) <= CompanyLayoutNet.MAX_MONEY and typeof(minute) == TYPE_INT \
		and int(minute) >= 0 and int(minute) < CompanyTuning.MINUTES_PER_DAY


static func _hands_ok(value: Variant) -> bool:
	return _id_ok(value) and String(value).begins_with(HANDS_PREFIX)


## Text up to MAX_ID_LENGTH, possibly empty.
static func _text_ok(value: Variant) -> bool:
	return CompanyAsk.is_id(value) and String(value).length() <= MAX_ID_LENGTH


## Text up to MAX_ID_LENGTH, not empty.
static func _id_ok(value: Variant) -> bool:
	return _text_ok(value) and not String(value).is_empty()


static func _refused(reason: StringName) -> Dictionary:
	return {"reason": reason}


static func _granted(kind: StringName, data: Dictionary) -> Dictionary:
	return {"reason": &"", "kind": kind, "data": data}
