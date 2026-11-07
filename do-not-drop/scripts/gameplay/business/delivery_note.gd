class_name DeliveryNote
extends RefCounted
## Goods-received check of a supplier delivery: the "remito" (expansion D-0614, "Modo Empresa").
##
## Compares what was ordered for a day's truck (SupplierSchedule.ordered_for) with
## what actually reached the shed (the units of the pallets that were unloaded), and
## keeps a record of every shortfall and surplus per day. Pure data over product ids
## and counts: no node, no clock, no autoload. Charging only for what arrived is the
## wallet's job (D-0503); the screen that shows the note is a later UI task.
##
## A line is {product, ordered, received, missing, extra}. missing is what the truck
## did not unload (left on the bed, D-0618, or never loaded); extra is a surplus.
##
## Only the last CompanyTuning.DELIVERY_NOTE_DAYS_KEPT days are kept line by line, counted
## back from the newest day on record (D-2026.2): an older day folds into per-product
## missing totals (`older_missing`), so missing_totals() still adds every day while the
## note, which goes in every save and snapshot, stops growing with the days played. The
## trim depends only on the records, so every peer applying the same checks agrees.

## Day -> Array of lines that were not exact (only the discrepancies are kept).
var _records: Dictionary = {}
## Product -> units missing on the days already folded out of _records.
var _older_missing: Dictionary = {}


## Units per product held by the pallets whose id is in received_ids. Pallets that are
## not in the list (left on the truck's bed) do not count.
static func received_units(pallets: Array, received_ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for pallet: Variant in pallets:
		if not pallet is Dictionary:
			continue
		var p: Dictionary = pallet
		if not received_ids.has(p.get("id", &"")) and not received_ids.has(str(p.get("id", ""))):
			continue
		var product := StringName(p.get("product", &""))
		var qty: int = int(p.get("qty", 0))
		if product == &"" or qty < 1:
			continue
		out[product] = int(out.get(product, 0)) + qty
	return out


## One line per product that was ordered or received, in product id order.
## ordered and received are {product -> units}; non-positive counts are ignored.
static func compare(ordered: Dictionary, received: Dictionary) -> Array[Dictionary]:
	var products: Array[String] = []
	for source: Dictionary in [ordered, received]:
		for key: Variant in source:
			if int(source[key]) >= 1 and not products.has(str(key)):
				products.append(str(key))
	products.sort()
	var out: Array[Dictionary] = []
	for id: String in products:
		var want: int = maxi(0, int(ordered.get(StringName(id), ordered.get(id, 0))))
		var got: int = maxi(0, int(received.get(StringName(id), received.get(id, 0))))
		(
			out
			. append(
				{
					"product": StringName(id),
					"ordered": want,
					"received": got,
					"missing": maxi(0, want - got),
					"extra": maxi(0, got - want),
				}
			)
		)
	return out


## True when no line has a shortfall or a surplus.
static func is_exact(lines: Array[Dictionary]) -> bool:
	for line: Dictionary in lines:
		if int(line["missing"]) > 0 or int(line["extra"]) > 0:
			return false
	return true


## Units short across all lines.
static func total_missing(lines: Array[Dictionary]) -> int:
	var total: int = 0
	for line: Dictionary in lines:
		total += int(line["missing"])
	return total


## Checks a day's delivery and records the discrepancies. Returns the full lines.
## Checking the same day again replaces its record (the truck has one note per day).
## A day below 1 records nothing.
func check(day: int, ordered: Dictionary, received: Dictionary) -> Array[Dictionary]:
	var lines: Array[Dictionary] = compare(ordered, received)
	if day < 1:
		return lines
	var off: Array[Dictionary] = []
	for line: Dictionary in lines:
		if int(line["missing"]) > 0 or int(line["extra"]) > 0:
			off.append(line)
	if off.is_empty():
		_records.erase(day)
	else:
		_records[day] = off
	_trim()
	return lines


## Recorded discrepancy lines of that day ({} lines = the delivery was exact or unchecked).
func discrepancies(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: Dictionary in _records.get(day, []):
		out.append(line.duplicate())
	return out


## Days with a recorded discrepancy, ascending (only the days still kept line by line).
func days_with_shortfall() -> Array[int]:
	var out: Array[int] = []
	for day: int in _records:
		for line: Dictionary in _records[day]:
			if int(line["missing"]) > 0:
				out.append(day)
				break
	out.sort()
	return out


## Units still missing from all recorded days, per product (the folded older days too).
func missing_totals() -> Dictionary:
	var out: Dictionary = _older_missing.duplicate()
	for day: int in _records:
		for line: Dictionary in _records[day]:
			if int(line["missing"]) > 0:
				var product: StringName = line["product"]
				out[product] = int(out.get(product, 0)) + int(line["missing"])
	return out


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for day: int in _records:
		var lines: Array = []
		for line: Dictionary in _records[day]:
			(
				lines
				. append(
					{
						"product": String(line["product"]),
						"ordered": int(line["ordered"]),
						"received": int(line["received"]),
					}
				)
			)
		out[str(day)] = lines
	var older: Dictionary = {}
	for product: StringName in _older_missing:
		older[String(product)] = int(_older_missing[product])
	return {"records": out, "older_missing": older}


## How many days are kept line by line (at most CompanyTuning.DELIVERY_NOTE_DAYS_KEPT).
func days_kept() -> int:
	return _records.size()


## Tolerates malformed data: bad days and lines are skipped; missing and extra are
## recomputed from ordered and received. A note from before D-2026.2 (no "older_missing")
## loads with no older totals, and one holding more days than are kept is trimmed.
static func from_dict(data: Dictionary) -> DeliveryNote:
	var note := DeliveryNote.new()
	var older: Variant = data.get("older_missing", {})
	if older is Dictionary:
		for product: Variant in older:
			var units: Variant = (older as Dictionary)[product]
			var is_number: bool = typeof(units) == TYPE_INT or typeof(units) == TYPE_FLOAT
			if str(product) != "" and is_number and float(units) < 1e15 and int(units) >= 1:
				note._older_missing[StringName(str(product))] = int(units)
	var raw: Variant = data.get("records", {})
	if not raw is Dictionary:
		return note
	var records: Dictionary = raw
	for day_key: Variant in records:
		var lines: Variant = records[day_key]
		if not str(day_key).is_valid_int() or not lines is Array:
			continue
		var day: int = int(str(day_key))
		var ordered: Dictionary = {}
		var received: Dictionary = {}
		for line: Variant in lines:
			if not line is Dictionary:
				continue
			var d: Dictionary = line
			var product := String(d.get("product", ""))
			if product == "":
				continue
			ordered[product] = int(d.get("ordered", 0))
			received[product] = int(d.get("received", 0))
		note.check(day, ordered, received)
	return note


## Folds every day more than DELIVERY_NOTE_DAYS_KEPT before the newest recorded one into
## _older_missing and drops its lines (D-2026.2).
func _trim() -> void:
	var newest: int = 0
	for day: int in _records:
		newest = maxi(newest, day)
	var keep_after: int = newest - CompanyTuning.DELIVERY_NOTE_DAYS_KEPT
	for day: int in _records.keys():
		if day > keep_after:
			continue
		for line: Dictionary in _records[day]:
			var missing: int = int(line["missing"])
			if missing > 0:
				var product: StringName = line["product"]
				_older_missing[product] = int(_older_missing.get(product, 0)) + missing
		_records.erase(day)
