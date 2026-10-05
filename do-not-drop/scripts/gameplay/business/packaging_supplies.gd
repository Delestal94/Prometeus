class_name PackagingSupplies
extends RefCounted
## What packing a box consumes (expansion D-0504, "Modo Empresa"): padding, tape, label and
## stamps, on top of the empty box that BoxDispenser sells.
##
## Static and stateless over a PackedBox and a company wallet (CompanyState or anything with the
## same can_afford / spend API). Each step is paid when it is done, so abandoning a box costs
## only what was already used. A step the wallet cannot cover changes nothing. Prices live in
## CompanyTuning (FILL_COST_PER_CELL, TAPE_COST, LABEL_COST, STAMP_COST).

## What the wallet movements are called in the ledger.
const REASON: StringName = &"packaging"


## Cost of padding n cells.
static func fill_cost(cells: int) -> int:
	return maxi(cells, 0) * CompanyTuning.FILL_COST_PER_CELL


## Pads up to n free cells and pays for the ones actually padded. Returns how many it padded;
## 0, changing nothing, if the wallet cannot cover them all (all or none).
static func pad(box: PackedBox, cells: int, wallet: Object) -> int:
	if box == null or wallet == null or cells <= 0:
		return 0
	var free: int = box.total_cells() - box.grid.size()
	var n: int = mini(cells, free)
	if n <= 0 or not _pay(wallet, fill_cost(n)):
		return 0
	return box.fill_free_cells(n)


## Tapes the box shut. False, changing nothing, if already taped or the wallet cannot pay.
static func tape(box: PackedBox, wallet: Object) -> bool:
	if box == null or box.taped or not _pay(wallet, CompanyTuning.TAPE_COST):
		return false
	box.taped = true
	return true


## Sticks the order label. False, changing nothing, with an empty order id or no money.
static func label(box: PackedBox, order_id: StringName, wallet: Object) -> bool:
	if box == null or order_id == &"":
		return false
	var cost: int = 0 if box.label_order_id == order_id else CompanyTuning.LABEL_COST
	if not _pay(wallet, cost):
		return false
	box.label_order_id = order_id
	return true


## Adds a stamp (once per kind). False, changing nothing, if repeated, empty or no money.
static func stamp(box: PackedBox, kind: StringName, wallet: Object) -> bool:
	if box == null or kind == &"" or box.stamps.has(kind):
		return false
	if not _pay(wallet, CompanyTuning.STAMP_COST):
		return false
	box.stamps.append(kind)
	return true


## What the supplies already on the box cost (padding, tape, label if any, stamps). The box
## itself is BoxDispenser.cost_of(). Used by the day summary (D-0508).
static func used_cost(box: PackedBox) -> int:
	if box == null:
		return 0
	var cost: int = 0
	for value: StringName in box.grid.values():
		if value == PackedBox.FILL:
			cost += CompanyTuning.FILL_COST_PER_CELL
	if box.taped:
		cost += CompanyTuning.TAPE_COST
	if box.label_order_id != &"":
		cost += CompanyTuning.LABEL_COST
	return cost + box.stamps.size() * CompanyTuning.STAMP_COST


static func _pay(wallet: Object, cost: int) -> bool:
	if wallet == null or not wallet.can_afford(cost):
		return false
	return cost <= 0 or wallet.spend(cost, REASON)
