class_name StationSupplies
extends RefCounted
## What one packing table has on hand (expansion D-0718, "Modo Empresa"): empty boxes of each
## size, rolls of tape (one per box) and padding (one per cell). Packing uses them up and
## somebody has to restock the table: the chore of whoever stays in the shed.
##
## Pure data, like PackingStation. The money for each item is still charged when it is used
## (BoxDispenser, PackagingSupplies, D-0504); this is only the physical limit. Restocking costs
## time, not money: the interaction that calls restock() decides how long it takes. Capacities
## live in CompanyTuning.SUPPLY_CAPACITY.

const TAPE: StringName = &"tape"
const FILL: StringName = &"fill"
const BOX_PREFIX: String = "box_"

## kind -> units on hand.
var stock: Dictionary = {}


## A table fully stocked.
static func full() -> StationSupplies:
	var supplies := StationSupplies.new()
	supplies.restock_all()
	return supplies


## The kind that counts empty boxes of `size` (`box_M`).
static func box_kind(size: StringName) -> StringName:
	return StringName(BOX_PREFIX + String(size))


## True for a kind this table tracks.
static func is_kind(kind: StringName) -> bool:
	return CompanyTuning.SUPPLY_CAPACITY.has(kind)


func count(kind: StringName) -> int:
	return int(stock.get(kind, 0))


func has(kind: StringName, n: int = 1) -> bool:
	return is_kind(kind) and count(kind) >= n


## Uses up n units. False, changing nothing, if the kind is unknown or there are fewer than n.
func take(kind: StringName, n: int = 1) -> bool:
	if n <= 0 or not has(kind, n):
		return false
	stock[kind] = count(kind) - n
	return true


## Fills one kind back to its capacity. Returns the units added (0 for an unknown kind).
func restock(kind: StringName) -> int:
	if not is_kind(kind):
		return 0
	var added: int = int(CompanyTuning.SUPPLY_CAPACITY[kind]) - count(kind)
	stock[kind] = int(CompanyTuning.SUPPLY_CAPACITY[kind])
	return maxi(added, 0)


## Fills everything back to capacity. Returns the units added in total.
func restock_all() -> int:
	var added: int = 0
	for kind: StringName in CompanyTuning.SUPPLY_CAPACITY:
		added += restock(kind)
	return added


## True when a kind is at or under CompanyTuning.SUPPLY_LOW_RATIO of its capacity.
func is_low(kind: StringName) -> bool:
	if not is_kind(kind):
		return false
	var capacity: float = float(CompanyTuning.SUPPLY_CAPACITY[kind])
	return float(count(kind)) <= capacity * CompanyTuning.SUPPLY_LOW_RATIO


## The kinds that are low (empty ones included), in the order of SUPPLY_CAPACITY. What the
## table's sign or the HUD shows as "restock".
func low_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: StringName in CompanyTuning.SUPPLY_CAPACITY:
		if is_low(kind):
			out.append(kind)
	return out


## JSON-friendly copy.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for kind: StringName in CompanyTuning.SUPPLY_CAPACITY:
		out[String(kind)] = count(kind)
	return out


## Rebuilds from to_dict() (also after a JSON round trip). A kind that is missing is full; one
## that is out of range is clamped to 0..capacity.
static func from_dict(d: Dictionary) -> StationSupplies:
	var supplies := StationSupplies.new()
	for kind: StringName in CompanyTuning.SUPPLY_CAPACITY:
		var capacity: int = int(CompanyTuning.SUPPLY_CAPACITY[kind])
		supplies.stock[kind] = clampi(int(d.get(String(kind), capacity)), 0, capacity)
	return supplies
