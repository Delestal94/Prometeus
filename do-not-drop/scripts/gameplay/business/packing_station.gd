class_name PackingStation
extends RefCounted
## State of one packing table (expansion D-0701, "Modo Empresa"): the open box in its hollow,
## and the products waiting on the table next to it.
##
## Pure data, like PackedBox and Shelf: no node, no autoload. The table node and the player
## interaction call this; the box itself is a PackedBox (D-0212). Choosing the size and paying
## for the box is D-0702, closing it with tape D-0706. One box at a time per table.

## Products that can wait on the table (the "hollows" for products).
const STAGING_SLOTS: int = 4

var id: StringName = &""
## The open box in the table's hollow; null when the table is free.
var box: PackedBox = null
## Product ids waiting on the table, in the order they were put (repeats allowed).
var staged: Array[StringName] = []
## Boxes, tape and padding on hand at this table (D-0718).
var supplies: StationSupplies = StationSupplies.full()


## A free table; null if the id is empty.
static func make(station_id: StringName) -> PackingStation:
	if station_id == &"":
		return null
	var station := PackingStation.new()
	station.id = station_id
	return station


func has_box() -> bool:
	return box != null


## Puts an empty box of that size in the hollow. False, changing nothing, if the table already
## has one or the size is unknown.
func start_box(size: StringName) -> bool:
	if box != null or not CompanyTuning.BOX_CELLS.has(size):
		return false
	box = PackedBox.new(size)
	return true


## Leaves a product on the table. False if there is no room (STAGING_SLOTS) or the id is empty.
func stage_product(product_id: StringName) -> bool:
	if product_id == &"" or staged.size() >= STAGING_SLOTS:
		return false
	staged.append(product_id)
	return true


## Takes one unit of a product back off the table (to the hands). False if it is not there.
func unstage_product(product_id: StringName) -> bool:
	var at: int = staged.find(product_id)
	if at < 0:
		return false
	staged.remove_at(at)
	return true


## Moves a staged product into the box with its lowest corner at `origin`. False, changing
## nothing, if there is no box, the product is not on the table, or it does not fit there.
func put_in_box(product: ProductDefinition, origin: Vector3i) -> bool:
	if box == null or product == null or not staged.has(product.id):
		return false
	if not box.place(product, origin):
		return false
	staged.erase(product.id)
	return true


## Takes the box off the table (it leaves to be closed or dispatched). Null if there is none.
func take_box() -> PackedBox:
	var out: PackedBox = box
	box = null
	return out


## True when the box on the table is taped shut (D-0706).
func is_sealed() -> bool:
	return box != null and box.taped


## Tapes the box on the table shut and pays the tape (PackagingSupplies.tape). False, changing
## nothing, if the table has no box, it is already taped or the wallet cannot pay.
## With `fill` over 0 (Armado asistido, D-1919, dificultad.md §2.1) it first pads that many free cells
## (assisted_cells() says how many) and marks the box assisted; the wallet must cover padding and tape
## together, so the padding's money never leaves the box open.
func seal(wallet: Object, fill: int = 0) -> bool:
	if box == null or box.taped or not supplies.has(StationSupplies.TAPE):
		return false
	if fill > 0:
		var cost: int = PackagingSupplies.fill_cost(fill) + CompanyTuning.TAPE_COST
		if fill > supplies.count(StationSupplies.FILL) or wallet == null or not wallet.call(&"can_afford", cost):
			return false
		if pad(fill, wallet) != fill:
			return false
		box.assisted = true
	if not PackagingSupplies.tape(box, wallet):
		return false
	supplies.take(StationSupplies.TAPE)
	return true


## Armado asistido (D-1919, dificultad.md §2.1): how many free cells the tape would pad with `money` in the
## wallet: the free cells, the padding on hand and what is left after the tape, the least of the three. 0
## without a box, with it taped or with no tape on the table.
func assisted_cells(money: int) -> int:
	if box == null or box.taped or not supplies.has(StationSupplies.TAPE):
		return 0
	var free: int = box.total_cells() - box.grid.size()
	var afford: int = maxi(money - CompanyTuning.TAPE_COST, 0) / maxi(CompanyTuning.FILL_COST_PER_CELL, 1)
	return maxi(mini(mini(free, supplies.count(StationSupplies.FILL)), afford), 0)


## Pads up to `cells` free cells of the box on the table and pays them (PackagingSupplies.pad),
## limited by the padding on hand. Returns how many it padded; 0, changing nothing, with no box,
## no padding left or a wallet that cannot cover them (D-0718).
func pad(cells: int, wallet: Object) -> int:
	if box == null:
		return 0
	var room: int = mini(cells, supplies.count(StationSupplies.FILL))
	var padded: int = PackagingSupplies.pad(box, room, wallet)
	supplies.take(StationSupplies.FILL, padded)
	return padded


## Sticks the label of `order` (an Order dictionary) on the box on the table and pays it
## (PackagingSupplies.label). False, changing nothing, if the table has no box, the order names
## no house or the wallet cannot pay. Relabeling for the same order is free (D-0707).
func label_for(order: Dictionary, wallet: Object) -> bool:
	if box == null or OrderLabel.address(order).is_empty():
		return false
	return PackagingSupplies.label(box, StringName(str(order["id"])), wallet)


## Stamps a seal (BoxSeals.KINDS) on the box on the table and pays it (PackagingSupplies.stamp).
## False, changing nothing, if the table has no box, the kind is unknown, the box already has
## that seal or the wallet cannot pay (D-0708).
func stamp(kind: StringName, wallet: Object) -> bool:
	return box != null and BoxSeals.is_kind(kind) and PackagingSupplies.stamp(box, kind, wallet)


## What is wrong with the box's content for `order`, before taping (D-0712): {missing, extra}
## as BoxContentCheck.diff. Only a warning: sealing a wrong box is allowed, the door pays 0.
## With no box on the table everything is missing.
func content_errors(order: Dictionary) -> Dictionary:
	return BoxContentCheck.diff(order, box)


## A second player checks the open box on the table against `order` (D-0734, BoxReview.review): the
## fault report, and the box is marked reviewed when it has none. The host passes who packed and who
## checks; the same person, a taped box or no box counts for nothing. Nothing is charged.
func review(order: Dictionary, packer: StringName, reviewer: StringName) -> Dictionary:
	return BoxReview.review(box, order, packer, reviewer)


## The order sheet for this table (D-0714): OrderSheet.build() with the box on the table.
func sheet_for(order: Dictionary, now_min: int, products: Dictionary = {}) -> Dictionary:
	return OrderSheet.build(order, box, now_min, products)


## Takes a badly packed box apart (D-0719): every product goes back to the table as far as the
## STAGING_SLOTS allow, the rest comes back in `overflow` (for the hands or the shelf). Padding,
## tape, label and stamps are lost (already paid, nothing is refunded); the empty open box stays
## on the table. Returns {staged, overflow} as product-id arrays; {}, changing nothing, with no box.
func disassemble() -> Dictionary:
	if box == null:
		return {}
	var staged_back: Array[StringName] = []
	var overflow: Array[StringName] = []
	for item: Dictionary in box.items:
		var product_id: StringName = item["product"]
		if stage_product(product_id):
			staged_back.append(product_id)
		else:
			overflow.append(product_id)
	box = PackedBox.new(box.box_size)
	return {"staged": staged_back, "overflow": overflow}


## Takes the box off the table to send it away. Null, leaving it in place, if it is not taped
## shut: an open box cannot be dispatched (D-0706).
func dispatch() -> PackedBox:
	if not is_sealed():
		return null
	return take_box()


## JSON-friendly copy: travels by network and lives in a save.
func to_dict() -> Dictionary:
	var waiting: Array = []
	for product_id: StringName in staged:
		waiting.append(String(product_id))
	return {
		"id": String(id),
		"box": box.to_dict() if box != null else {},
		"staged": waiting,
		"supplies": supplies.to_dict(),
	}


## Rebuilds a table from to_dict() (also after a JSON round trip); null for an empty id.
static func from_dict(d: Dictionary) -> PackingStation:
	var station: PackingStation = make(StringName(str(d.get("id", ""))))
	if station == null:
		return null
	var raw_box: Variant = d.get("box", {})
	if raw_box is Dictionary and not (raw_box as Dictionary).is_empty():
		station.box = PackedBox.from_dict(raw_box)
	for raw: Variant in d.get("staged", []):
		station.stage_product(StringName(str(raw)))
	var raw_supplies: Variant = d.get("supplies", {})
	if raw_supplies is Dictionary:
		station.supplies = StationSupplies.from_dict(raw_supplies)
	return station
