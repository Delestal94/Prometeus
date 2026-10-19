class_name BoxDispenser
extends RefCounted
## Box dispenser next to a packing table (expansion D-0702, "Modo Empresa"): picks the size
## and puts an open empty box in the table's hollow, paying CompanyTuning.BOX_COST.
##
## Static and stateless: the table is a PackingStation, the wallet is CompanyState (passed in,
## so a test can use its own). Tape, padding and labels are charged later (D-0706, D-0705).

## What the wallet movement is called in the ledger.
const REASON: StringName = &"boxes"

## Sizes the dispenser offers, small to large.
const SIZES: Array[StringName] = [&"S", &"M", &"L", &"XL"]


## Cost of an empty box of that size; -1 for an unknown size.
static func cost_of(size: StringName) -> int:
	return int(CompanyTuning.BOX_COST.get(size, -1))


## True when the table is free, the size exists, the table has such a box left (D-0718) and the
## wallet covers it.
static func can_dispense(station: PackingStation, size: StringName, wallet: Node) -> bool:
	if station == null or wallet == null or station.has_box():
		return false
	var cost: int = cost_of(size)
	if cost < 0 or not CompanyTuning.BOX_CELLS.has(size) or not wallet.can_afford(cost):
		return false
	return station.supplies.has(StationSupplies.box_kind(size))


## Opens a box of that size on the table and charges for it. False, changing nothing, when
## can_dispense() is false.
static func dispense(station: PackingStation, size: StringName, wallet: Node) -> bool:
	if not can_dispense(station, size, wallet):
		return false
	var cost: int = cost_of(size)
	if cost > 0 and not wallet.spend(cost, REASON):
		return false
	if not station.start_box(size):
		return false
	station.supplies.take(StationSupplies.box_kind(size))
	return true
