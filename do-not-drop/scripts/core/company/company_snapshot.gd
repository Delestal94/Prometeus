class_name CompanySnapshot
extends RefCounted
## How CompanyNet's snapshot travels (D-2004; contract
## docs/expansion-distritos/diseno/red-autoridad.md section 6): packed with var_to_bytes, compressed
## and cut into chunks on the host, joined and unpacked on the client; and the checks of what it
## carries (rule 5): the stock and the packing tables (D-0715).
##
## Static only, no state. Split out of company_net.gd in D-0715 (the file was at gdlint's 1000-line
## edge); CompanyNet keeps pack_snapshot(), unpack_snapshot() and stock_ok() as the same calls. The
## limits are CompanyNet's own constants (SNAPSHOT_*) and CompanyTableNet's (MAX_*), read here. The
## checks of one chunk and the joining (chunk_ok(), join()) came out of CompanyNet._take_chunk() in
## D-0518, for the same reason.


## A snapshot as _snapshot carries it: {size: its var_to_bytes size, chunks: the compressed
## bytes cut every `chunk_bytes` (1 to SNAPSHOT_CHUNK_BYTES)}. {} when it is over
## SNAPSHOT_MAX_BYTES or takes more than SNAPSHOT_MAX_CHUNKS.
static func pack(data: Dictionary, chunk_bytes: int) -> Dictionary:
	var raw: PackedByteArray = var_to_bytes(data)
	if raw.size() > CompanyNet.SNAPSHOT_MAX_BYTES:
		return {}
	var packed: PackedByteArray = raw.compress(CompanyNet.SNAPSHOT_COMPRESSION)
	var step: int = clampi(chunk_bytes, 1, CompanyNet.SNAPSHOT_CHUNK_BYTES)
	var chunks: Array[PackedByteArray] = []
	for start: int in range(0, packed.size(), step):
		chunks.append(packed.slice(start, start + step))
	if chunks.is_empty() or chunks.size() > CompanyNet.SNAPSHOT_MAX_CHUNKS:
		return {}
	return {"size": raw.size(), "chunks": chunks}


## One chunk as _snapshot carries it fits (rule 5): snapshot id and chunk count from 1, the count up to
## SNAPSHOT_MAX_CHUNKS and the chunk inside it, the size uncompressed 1 to SNAPSHOT_MAX_BYTES and 1 to
## SNAPSHOT_CHUNK_BYTES bytes. Whether it belongs to the snapshot being put together is CompanyNet's.
static func chunk_ok(id: int, chunk: int, total: int, size: int, bytes: PackedByteArray) -> bool:
	if id < 1 or total < 1 or total > CompanyNet.SNAPSHOT_MAX_CHUNKS or chunk < 0 or chunk >= total:
		return false
	if size < 1 or size > CompanyNet.SNAPSHOT_MAX_BYTES:
		return false
	return not bytes.is_empty() and bytes.size() <= CompanyNet.SNAPSHOT_CHUNK_BYTES


## The chunks of one snapshot ({index: bytes}, every index from 0 to `total` - 1) joined in order.
static func join(chunks: Dictionary, total: int) -> PackedByteArray:
	var joined := PackedByteArray()
	for index: int in range(total):
		joined.append_array(chunks[index])
	return joined


## The snapshot back from its joined chunks and its uncompressed `size`, or {} when they don't
## make one: a size out of range, bytes that don't decompress to exactly `size`, or anything
## but a Dictionary. Objects never come back (bytes_to_var, not bytes_to_var_with_objects).
static func unpack(packed: PackedByteArray, size: int) -> Dictionary:
	if packed.is_empty() or size < 1 or size > CompanyNet.SNAPSHOT_MAX_BYTES:
		return {}
	var raw: PackedByteArray = packed.decompress(size, CompanyNet.SNAPSHOT_COMPRESSION)
	if raw.size() != size:
		return {}
	var data: Variant = bytes_to_var(raw)
	return data if data is Dictionary else {}


## A stock in Inventory.to_dict() form that came over the network (rule 5): a Dictionary with
## at most `stock` ({product: {location: qty}}) and `reserved` ({order: {product: qty}}), ids
## as text up to SNAPSHOT_MAX_ID_LENGTH, quantities as positive ints.
static func stock_ok(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var stock: Dictionary = value
	for part: Variant in stock:
		if typeof(part) != TYPE_STRING or not ["stock", "reserved"].has(part):
			return false
		if not stock[part] is Dictionary:
			return false
		var outer: Dictionary = stock[part]
		for id: Variant in outer:
			if not name_ok(id) or not outer[id] is Dictionary:
				return false
			var inner: Dictionary = outer[id]
			for sub: Variant in inner:
				if not name_ok(sub) or typeof(inner[sub]) != TYPE_INT or int(inner[sub]) < 1:
					return false
	return true


## An id a snapshot carries: text up to SNAPSHOT_MAX_ID_LENGTH.
static func name_ok(value: Variant) -> bool:
	return CompanyAsk.is_id(value) and String(value).length() <= CompanyNet.SNAPSHOT_MAX_ID_LENGTH


## The packing tables a snapshot carries (CompanyTableNet.to_dict()), checked as data from the
## network and built: {tables: {table: PackingStation}, boxes: {table: box id}, serial}. {} when it
## doesn't fit: not a Dictionary, over CompanyTableNet.MAX_TABLES tables, an id that isn't short
## text, a box PackedBox.from_dict() would not give back the same (a product outside the catalog
## or the box, two on one cell), a box without its id or an id twice, supplies out of capacity.
static func tables_from(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var serial: Variant = (value as Dictionary).get("serial")
	var raw: Variant = (value as Dictionary).get("tables")
	if typeof(serial) != TYPE_INT or int(serial) < 0 or not raw is Dictionary:
		return {}
	if (raw as Dictionary).size() > CompanyTableNet.MAX_TABLES:
		return {}
	var tables: Dictionary = {}
	var boxes: Dictionary = {}
	for table: Variant in raw:
		var desk: PackingStation = _table_from(table, raw[table])
		if desk == null:
			return {}
		tables[StringName(table)] = desk
		var box_id := StringName(str((raw[table] as Dictionary)["box_id"]))
		if desk.has_box() and boxes.values().has(box_id):
			return {}
		if desk.has_box():
			boxes[StringName(table)] = box_id
	return {"tables": tables, "boxes": boxes, "serial": int(serial)}


## One table of tables_from(), or null when it doesn't fit.
static func _table_from(table: Variant, entry: Variant) -> PackingStation:
	if not _short(table, false) or not entry is Dictionary:
		return null
	var box_id: Variant = (entry as Dictionary).get("box_id")
	var box: Variant = (entry as Dictionary).get("box")
	var supplies: Variant = (entry as Dictionary).get("supplies")
	if not (_short(box_id, true) and box is Dictionary and _supplies_ok(supplies)):
		return null
	var desk: PackingStation = PackingStation.make(StringName(table))
	desk.supplies = StationSupplies.from_dict(supplies)
	if (box as Dictionary).is_empty():
		return desk if String(box_id).is_empty() else null
	if not _short(box_id, false) or not _box_ok(box):
		return null
	desk.box = PackedBox.from_dict(box)
	return desk


## Supplies as StationSupplies.to_dict() writes them: every kind, an int within its capacity.
static func _supplies_ok(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var supplies: Dictionary = value
	if supplies.size() != CompanyTuning.SUPPLY_CAPACITY.size():
		return false
	for kind: StringName in CompanyTuning.SUPPLY_CAPACITY:
		var count: Variant = supplies.get(String(kind))
		if typeof(count) != TYPE_INT or int(count) < 0:
			return false
		if int(count) > int(CompanyTuning.SUPPLY_CAPACITY[kind]):
			return false
	return true


## An open box as PackedBox.to_dict() writes it, with its types, no tape (a taped box leaves the
## table), products of the catalog with the catalog's cells, each seal once, and nothing
## PackedBox.from_dict() would drop (a product out of the box or on another): it comes back equal.
static func _box_ok(box: Dictionary) -> bool:
	var size: Variant = box.get("box_size")
	var items: Variant = box.get("items")
	var fill: Variant = box.get("fill")
	var stamps: Variant = box.get("stamps")
	if not (CompanyAsk.is_id(size) and CompanyTuning.BOX_CELLS.has(StringName(size))):
		return false
	if not (items is Array and fill is Array and stamps is Array and box.get("taped") is bool):
		return false
	# An open box is never assisted: only the tape pads it (D-1919).
	var assisted: Variant = box.get("assisted", false)
	if typeof(assisted) != TYPE_BOOL or assisted:
		return false
	if box["taped"] or (items as Array).size() > CompanyTableNet.MAX_ITEMS \
			or (fill as Array).size() > CompanyTableNet.MAX_FILL \
			or (stamps as Array).size() > BoxSeals.KINDS.size():
		return false
	for item: Variant in items:
		var cells: Variant = _catalog_cells(item.get("product")) if item is Dictionary else null
		if cells == null or cells != item.get("cells") or not _triple_ok(item.get("origin")):
			return false
	for cell: Variant in fill:
		if not _triple_ok(cell):
			return false
	var seen: Dictionary = {}
	for stamp: Variant in stamps:
		var kind: bool = _short(stamp, false) and BoxSeals.is_kind(StringName(stamp))
		if not kind or seen.has(String(stamp)):
			return false
		seen[String(stamp)] = true
	return _short(box.get("label_order_id"), true) and PackedBox.from_dict(box).to_dict() == box


## Three ints from 0 to CompanyTableNet.MAX_CELL (a cell or a size in a box's to_dict()).
static func _triple_ok(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for part: Variant in value:
		if typeof(part) != TYPE_INT or int(part) < 0 or int(part) > CompanyTableNet.MAX_CELL:
			return false
	return true


## [x, y, z] of a catalog product's cells (ProductDefinition.cells, as PackedBox.to_dict() writes
## them), null for anything that isn't a product of the catalog.
static func _catalog_cells(product: Variant) -> Variant:
	if not (_short(product, false) and CompanyAsk.product_exists(StringName(product))):
		return null
	var path: String = CompanyAsk.PRODUCTS_DIR + String(product) + ".tres"
	var def: ProductDefinition = load(path) as ProductDefinition
	return [def.cells.x, def.cells.y, def.cells.z] if def != null else null


## Text up to CompanyTableNet.MAX_ID_LENGTH, empty only if `empty_ok`.
static func _short(value: Variant, empty_ok: bool) -> bool:
	if not CompanyAsk.is_id(value) or String(value).length() > CompanyTableNet.MAX_ID_LENGTH:
		return false
	return empty_ok or not String(value).is_empty()
