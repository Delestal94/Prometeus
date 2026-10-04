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


## JSON-friendly copy: travels by network and lives in a save.
func to_dict() -> Dictionary:
	var waiting: Array = []
	for product_id: StringName in staged:
		waiting.append(String(product_id))
	return {
		"id": String(id),
		"box": box.to_dict() if box != null else {},
		"staged": waiting,
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
	return station
