class_name StockView
extends RefCounted
## What the stock list on the clipboard shows (expansion D-0612, "Modo Empresa"): one row per
## product with its units split by where they are, and the low-stock flag of StockAlert (D-0613).
##
## Pure functions over plain data, like StockAlert: no node, no autoload, no tr(). The screen is
## StockPanel; the host calls rows() on every units_moved and a client on its mirror of Inventory.
##
## Locations are bucketed by prefix (Inventory does not interpret them): "shelf:" is shelves,
## "pallet:" and "dock" are reception (units waiting to be put away), "hands:" is hands,
## "box:" is boxes (already packed for an order) and anything else (cart:, floor:...) is other.

const SHELF_PREFIX: String = "shelf:"
const PALLET_PREFIX: String = "pallet:"
const DOCK: String = "dock"
const HANDS_PREFIX: String = "hands:"
const BOX_PREFIX: String = "box:"


## One row per product that has units anywhere or is in `shortages` (StockAlert.shortages()),
## sorted by product id:
## { product, shelves, reception, hands, boxes, other, total, short, missing, incoming, covered }.
## A product that is not short has short = false, missing = 0, incoming = 0, covered = false.
static func rows(inventory: Inventory, shortages: Array = []) -> Array[Dictionary]:
	var by_product: Dictionary = {}
	var stock: Dictionary = inventory.to_dict().get("stock", {})
	for product: StringName in stock:
		by_product[product] = _row(product, stock[product])
	for entry: Dictionary in shortages:
		var product: StringName = StringName(entry.get("product", ""))
		if product == &"":
			continue
		var row: Dictionary = by_product.get(product, _row(product, {}))
		row["short"] = true
		row["missing"] = int(entry.get("missing", 0))
		row["incoming"] = int(entry.get("incoming", 0))
		row["covered"] = bool(entry.get("covered", false))
		by_product[product] = row
	var out: Array[Dictionary] = []
	for row: Dictionary in by_product.values():
		out.append(row)
	out.sort_custom(_by_product)
	return out


## { products, units, short } over rows(): how many rows, all their units and how many are short.
static func totals(list: Array) -> Dictionary:
	var units: int = 0
	var short: int = 0
	for row: Dictionary in list:
		units += int(row.get("total", 0))
		if bool(row.get("short", false)):
			short += 1
	return {"products": list.size(), "units": units, "short": short}


## Name of the bucket a location counts in: shelves, reception, hands, boxes or other.
static func bucket_of(location: StringName) -> StringName:
	var text: String = String(location)
	if text.begins_with(SHELF_PREFIX):
		return &"shelves"
	if text.begins_with(PALLET_PREFIX) or text == DOCK or text.begins_with(DOCK + ":"):
		return &"reception"
	if text.begins_with(HANDS_PREFIX):
		return &"hands"
	if text.begins_with(BOX_PREFIX):
		return &"boxes"
	return &"other"


static func _row(product: StringName, locations: Dictionary) -> Dictionary:
	var row: Dictionary = {
		"product": product, "shelves": 0, "reception": 0, "hands": 0, "boxes": 0, "other": 0,
		"total": 0, "short": false, "missing": 0, "incoming": 0, "covered": false,
	}
	for location: StringName in locations:
		var qty: int = int(locations[location])
		if qty <= 0:
			continue
		var bucket: StringName = bucket_of(location)
		row[bucket] = int(row[bucket]) + qty
		row["total"] = int(row["total"]) + qty
	return row


static func _by_product(a: Dictionary, b: Dictionary) -> bool:
	return String(a["product"]) < String(b["product"])
