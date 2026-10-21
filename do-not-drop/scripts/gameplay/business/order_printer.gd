class_name OrderPrinter
extends RefCounted
## The order printer of the shed (expansion D-0805): it prints one sheet for each new order, the
## sheet waits in the tray, someone takes it and leaves it on a packing table.
##
## Pure state, no nodes and no autoloads: the host owns the one real printer and clients apply the
## same calls from what it sends. A sheet is only the id of its order (what it says is OrderSheet,
## D-0714, built from the order itself). The tray holds CompanyTuning.PRINTER_TRAY_MAX sheets;
## while it is full the printer jams and the next orders wait unprinted until someone empties it.
## Each order prints once, even after its sheet was taken or left on a table.

var _printed: Dictionary = {}
var _tray: Array[StringName] = []
var _carried: Dictionary = {}
var _tables: Dictionary = {}


## Prints a sheet for every order in `orders` (Order dictionaries, arrival order) that is still
## open or late and was never printed, while the tray has room. Returns the ids printed now.
func feed(orders: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for raw: Variant in orders:
		if _tray.size() >= CompanyTuning.PRINTER_TRAY_MAX:
			break
		if not (raw is Dictionary):
			continue
		var order: Dictionary = raw
		var id := StringName(str(order.get("id", "")))
		var state := StringName(str(order.get("state", "")))
		if id == &"" or _printed.has(id):
			continue
		if state != Order.STATE_OPEN and state != Order.STATE_LATE:
			continue
		_printed[id] = true
		_tray.append(id)
		out.append(id)
	return out


## Sheets in the tray, oldest first.
func tray() -> Array[StringName]:
	return _tray.duplicate()


## True when the tray is full: the printer is jammed until someone takes a sheet.
func is_jammed() -> bool:
	return _tray.size() >= CompanyTuning.PRINTER_TRAY_MAX


## Orders that are not printed yet but could be (open or late), so the shed can show "waiting".
func pending(orders: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for raw: Variant in orders:
		if not (raw is Dictionary):
			continue
		var id := StringName(str((raw as Dictionary).get("id", "")))
		var state := StringName(str((raw as Dictionary).get("state", "")))
		if id != &"" and not _printed.has(id) and (state == Order.STATE_OPEN or state == Order.STATE_LATE):
			out.append(id)
	return out


## `holder` (a peer id or any name) takes the sheet of `id` out of the tray. False if it is not in
## the tray or the holder already has CompanyTuning.SHEETS_IN_HAND_MAX sheets.
func take(id: StringName, holder: StringName) -> bool:
	if not _tray.has(id) or sheets_of(holder).size() >= CompanyTuning.SHEETS_IN_HAND_MAX:
		return false
	_tray.erase(id)
	_carried[id] = holder
	return true


## Sheets `holder` carries, in the order they were taken.
func sheets_of(holder: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _carried:
		if _carried[id] == holder:
			out.append(id)
	return out


## `holder` leaves the sheet of `id` on the packing table `station_id`. One sheet per table; False if
## the holder does not carry it or the table already has one.
func put_on_table(id: StringName, holder: StringName, station_id: StringName) -> bool:
	if _carried.get(id, &"") != holder or _tables.has(station_id):
		return false
	_carried.erase(id)
	_tables[station_id] = id
	return true


## The order whose sheet lies on `station_id`, or &"" if the table has none.
func table_order(station_id: StringName) -> StringName:
	return _tables.get(station_id, &"")


## Picks the sheet up from the table (the box was dispatched): it is gone for good.
func clear_table(station_id: StringName) -> bool:
	return _tables.erase(station_id)


func to_dict() -> Dictionary:
	return {
		"printed": _printed.keys().map(func(k: Variant) -> String: return String(k)),
		"tray": _tray.map(func(k: Variant) -> String: return String(k)),
		"carried": _stringify(_carried),
		"tables": _stringify(_tables),
	}


static func from_dict(d: Dictionary) -> OrderPrinter:
	var p := OrderPrinter.new()
	for raw: Variant in d.get("printed", []):
		p._printed[StringName(str(raw))] = true
	for raw: Variant in d.get("tray", []):
		p._tray.append(StringName(str(raw)))
	var carried: Dictionary = d.get("carried", {})
	for k: Variant in carried:
		p._carried[StringName(str(k))] = StringName(str(carried[k]))
	var tables: Dictionary = d.get("tables", {})
	for k: Variant in tables:
		p._tables[StringName(str(k))] = StringName(str(tables[k]))
	return p


static func _stringify(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in src:
		out[String(k)] = String(src[k])
	return out
